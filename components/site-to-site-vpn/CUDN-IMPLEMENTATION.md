# ClusterUserDefinedNetwork (CUDN) Implementation for Site-to-Site VPN

Enterprise-grade OpenShift Virtualization networking solution enabling direct, routable access to VMs from VPC networks without NAT, using certificate-based IPSec VPN.

## Architecture Overview

This implementation follows the [Red Hat Cloud Experts documentation](https://cloud.redhat.com/experts/rosa/s2s-vpn/) for establishing direct connectivity between OpenShift Virtualization VMs and AWS VPC networks.

```
VPC Networks (10.132.100.0/22, 10.132.104.0/22, 10.132.108.0/22)
    ↕ AWS Site-to-Site VPN (Certificate-based)
Transit Gateway (TGW)
    ↕
IPSec Gateway VMs (ipsec-a, ipsec-b)
    ├─ Primary Interface: Pod network (egress, management)
    └─ Secondary Interface: CUDN (192.168.1.0/24)
    ↕
VM Network (CUDN: 192.168.1.0/24)
    └─ OpenShift Virtualization VMs with direct routing
```

### Key Components

1. **ClusterUserDefinedNetwork (CUDN)**: Layer 2 overlay network (192.168.1.0/24) for VMs
2. **IPSec Gateway VMs**: Pair of VMs running Libreswan for tunnel termination
3. **Keepalived**: High availability with automatic failover between gateway VMs
4. **Certificate-based IPSec**: Secure authentication via ACM Private CA certificates

## Network Configuration

### CUDN Overlay Network
- **CIDR**: `192.168.1.0/24` (VM overlay network)
- **MTU**: 1400 (accounting for IPSec overhead)
- **IPAM**: Disabled (required for gateway routing and port security bypass)
- **Gateway Virtual IP**: `192.168.1.1` (managed by Keepalived)

### VPC Networks (Destinations)
- **Linux Non-Prod**: `10.132.100.0/22`
- **Windows Non-Prod**: `10.132.104.0/22`
- **Utility**: `10.132.108.0/22`

### IPSec Gateway VM IPs
- **ipsec-a**: `192.168.1.10/24` (Primary, AZ us-east-1a)
- **ipsec-b**: `192.168.1.11/24` (Secondary, AZ us-east-1b)
- **Virtual Gateway IP**: `192.168.1.1` (active VM only)

## Prerequisites

### OpenShift Requirements
- ROSA cluster v4.18+ (Classic or HCP)
- Bare metal worker nodes (`m5.metal` or similar)
- OpenShift Virtualization operator installed
- OVN-Kubernetes networking (default on ROSA)

### AWS Requirements
- AWS VPN Connection with Transit Gateway
- ACM Private CA for certificate generation
- VPN configured with certificate-based authentication
- TGW route table with VPN attachment

### Required Certificates (from ACM PCA)
- `left-cert.p12`: PKCS#12 bundle (leaf + key + chain)
- `certificate_chain.pem`: Full CA chain (subordinate + root)

## Installation Steps

### Step 1: Create VPN Infrastructure Namespace

```bash
oc apply -f vpn-infra-namespace.yaml
```

This creates the `vpn-infra` namespace with:
- Privileged pod security for IPSec VMs
- Cluster monitoring enabled
- Proper labels for CUDN namespace selector

### Step 2: Deploy ClusterUserDefinedNetwork

```bash
oc apply -f cudn-vm-network.yaml
```

This creates:
- **ClusterUserDefinedNetwork**: `vm-network` overlay (192.168.1.0/24)
- **NetworkAttachmentDefinition**: For attaching VMs to the CUDN

**Verification**:
```bash
# Check CUDN status
oc get clusteruserdefinednetwork vm-network -o yaml

# Verify network attachment definition
oc get network-attachment-definitions -n vpn-infra
```

### Step 3: Prepare Cloud-Init Configuration

**CRITICAL**: Edit `ipsec-vm-cloud-init.yaml` before deploying:

```bash
# Edit the Secret to set:
# 1. VM password (change 'changethis')
# 2. SSH authorized keys
# 3. Any additional system configuration

oc apply -f ipsec-vm-cloud-init.yaml
```

### Step 4: Deploy IPSec Gateway VMs

**Before deploying**, review and customize `ipsec-vm-example.yaml`:
- Adjust storage class (`gp3-csi`)
- Configure availability zones
- Verify resource allocations

```bash
oc apply -f ipsec-vm-example.yaml
```

**Wait for VMs to boot**:
```bash
# Monitor VM status
oc get vms -n vpn-infra -w

# Check VM instances
oc get vmis -n vpn-infra
```

Expected output:
```
NAME       AGE   STATUS    READY
ipsec-a    2m    Running   True
ipsec-b    2m    Running   True
```

### Step 5: Configure IPSec VM Network Interfaces

Repeat these steps for **both** `ipsec-a` and `ipsec-b` VMs.

#### 5.1 Access VM Console

```bash
# Option 1: virtctl console
virtctl console -n vpn-infra ipsec-a

# Option 2: Web console
# Navigate to Virtualization → VirtualMachines → ipsec-a → Console
```

Login with credentials from cloud-init configuration.

#### 5.2 Identify Secondary Network Interface

```bash
# Find the interface name (non-primary NIC)
ip link show | grep -E '^[0-9]+: en'

# Example output: enp2s0 (secondary interface on CUDN)
```

#### 5.3 Configure CUDN Interface

**For ipsec-a** (use `192.168.1.10`):
```bash
# Set variables
INTERFACE_NAME=enp2s0  # From previous command
VM_CUDN_IP=192.168.1.10
CUDN_SUBNET_MASK=/24
GATEWAY_VIRTUAL_IP=192.168.1.1
VPC_CIDR_1=10.132.100.0/22
VPC_CIDR_2=10.132.104.0/22
VPC_CIDR_3=10.132.108.0/22

# Configure network interface
sudo nmcli con add type ethernet ifname $INTERFACE_NAME con-name cudn \
  ipv4.addresses ${VM_CUDN_IP}${CUDN_SUBNET_MASK} ipv4.method manual autoconnect yes

# Set MTU for IPSec overhead
sudo nmcli con mod cudn 802-3-ethernet.mtu 1400

# Add routes to VPC networks via virtual gateway IP
sudo nmcli con mod cudn ipv4.routes "$VPC_CIDR_1 $GATEWAY_VIRTUAL_IP"
sudo nmcli con mod cudn +ipv4.routes "$VPC_CIDR_2 $GATEWAY_VIRTUAL_IP"
sudo nmcli con mod cudn +ipv4.routes "$VPC_CIDR_3 $GATEWAY_VIRTUAL_IP"

# Bring up the connection
sudo nmcli con up cudn

# Verify configuration
ip addr show $INTERFACE_NAME
ip route show dev $INTERFACE_NAME
```

**For ipsec-b** (use `192.168.1.11`):
```bash
# Same commands but change VM_CUDN_IP
VM_CUDN_IP=192.168.1.11
# ... rest of commands identical
```

#### 5.4 Configure Kernel Networking

On **both** VMs:
```bash
sudo tee /etc/sysctl.d/99-ipsec.conf <<'EOF'
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0
EOF

sudo sysctl --system
```

#### 5.5 Configure Firewalld

```bash
# Allow IPSec traffic (outbound)
sudo firewall-cmd --permanent --add-service=ipsec
sudo firewall-cmd --permanent --add-port=500/udp
sudo firewall-cmd --permanent --add-port=4500/udp
sudo firewall-cmd --reload

# Verify rules
sudo firewall-cmd --list-all
```

### Step 6: Import VPN Certificates

On **both** VMs, import the certificates generated from ACM Private CA.

#### Method A: Using virtctl (Recommended)

From your workstation:
```bash
# Copy PKCS#12 certificate bundle
virtctl scp -n vpn-infra left-cert.p12 ipsec-a:/tmp/left-cert.p12

# Copy CA certificate chain
virtctl scp -n vpn-infra certificate_chain.pem ipsec-a:/tmp/ca-chain.pem

# Repeat for ipsec-b
virtctl scp -n vpn-infra left-cert.p12 ipsec-b:/tmp/left-cert.p12
virtctl scp -n vpn-infra certificate_chain.pem ipsec-b:/tmp/ca-chain.pem
```

#### Import Certificates into NSS Database

On **each** VM:
```bash
# Switch to root
sudo -i

# Create NSS database directory
mkdir -p /etc/ipsec.d

# Import PKCS#12 (will prompt for passphrase from ACM certificate generation)
pk12util -i /tmp/left-cert.p12 -d sql:/etc/ipsec.d
# Enter passphrase when prompted
# Note the certificate nickname (e.g., "s2s.vpn.test.mobb.cloud")

# Import CA certificate chain
certutil -A -n "vpn-ca-chain" -t "CT,C,C" -d sql:/etc/ipsec.d -a -i /tmp/ca-chain.pem

# Verify certificates
certutil -L -d sql:/etc/ipsec.d
```

Expected output:
```
Certificate Nickname                                         Trust Attributes
                                                             SSL,S/MIME,JAR/XPI

s2s.vpn.test.mobb.cloud                                     u,u,u
vpn-ca-chain                                                CT,C,C
```

**Security**: Remove certificate files after import:
```bash
rm -f /tmp/left-cert.p12 /tmp/ca-chain.pem
```

### Step 7: Configure Libreswan IPSec

On **both** VMs, create the Libreswan configuration.

#### Get AWS VPN Tunnel Information

From AWS Console → VPC → Site-to-Site VPN Connections → Download Configuration:
- Note **Tunnel 1 Outside IP**
- Note **Tunnel 2 Outside IP**
- Note **Certificate FQDN** (e.g., `s2s.vpn.test.mobb.cloud`)

#### Create IPSec Configuration

On **each** VM as root:
```bash
# Set variables from your AWS VPN configuration
CERT_NICKNAME="s2s.vpn.test.mobb.cloud"  # From certutil -L output
TUNNEL1_OUTSIDE_IP="3.232.27.186"        # From AWS VPN config
TUNNEL2_OUTSIDE_IP="98.94.136.2"         # From AWS VPN config
CUDN_CIDR="192.168.1.0/24"
VPC_CIDR_1="10.132.100.0/22"
VPC_CIDR_2="10.132.104.0/22"
VPC_CIDR_3="10.132.108.0/22"

# Create main IPSec configuration
sudo tee /etc/ipsec.conf <<EOF
config setup
    logfile=/var/log/pluto.log
    logappend=yes
    plutodebug=all
    uniqueids=yes

conn %default
    ikelifetime=28800s
    keylife=3600s
    rekeymargin=9m
    keyingtries=%forever
    dpddelay=10s
    dpdtimeout=30s
    dpdaction=restart
    ike=aes128-sha1-modp1024
    esp=aes128-sha1
    authby=rsasig
    leftrsasigkey=%cert
    rightrsasigkey=%cert
    leftcert=$CERT_NICKNAME
    rightid=%fromcert

# Tunnel 1 - AWS VPN Endpoint 1
conn aws-vpn-tunnel1
    left=%defaultroute
    leftid="@$CERT_NICKNAME"
    leftsubnet=$CUDN_CIDR
    right=$TUNNEL1_OUTSIDE_IP
    rightsubnet=$VPC_CIDR_1,$VPC_CIDR_2,$VPC_CIDR_3
    auto=start

# Tunnel 2 - AWS VPN Endpoint 2 (backup)
conn aws-vpn-tunnel2
    left=%defaultroute
    leftid="@$CERT_NICKNAME"
    leftsubnet=$CUDN_CIDR
    right=$TUNNEL2_OUTSIDE_IP
    rightsubnet=$VPC_CIDR_1,$VPC_CIDR_2,$VPC_CIDR_3
    auto=add
EOF

# Set proper permissions
sudo chmod 644 /etc/ipsec.conf
```

#### Test IPSec Connection (Manual)

```bash
# Start IPSec service
sudo systemctl start ipsec

# Check status
sudo ipsec status

# Expected output (should show tunnel established):
# Total IPsec connections: loaded 2, routed 1, active 1
```

**Stop IPSec after testing** (Keepalived will manage it):
```bash
sudo systemctl stop ipsec
```

### Step 8: Configure High Availability (Keepalived)

Configure Keepalived on both VMs for automatic failover.

#### On ipsec-a (Primary):
```bash
sudo tee /etc/keepalived/keepalived.conf <<'EOF'
vrrp_script check_ipsec {
    script "/usr/bin/systemctl is-active ipsec"
    interval 5
    weight -50
    fall 2
    rise 2
}

vrrp_instance IPSEC_HA {
    state MASTER
    interface enp2s0  # CUDN interface
    virtual_router_id 51
    priority 100
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass strongpassword123  # Change this
    }
    virtual_ipaddress {
        192.168.1.1/24
    }
    track_script {
        check_ipsec
    }
    notify_master "/usr/bin/systemctl start ipsec"
    notify_backup "/usr/bin/systemctl stop ipsec"
    notify_fault "/usr/bin/systemctl stop ipsec"
}
EOF
```

#### On ipsec-b (Backup):
```bash
sudo tee /etc/keepalived/keepalived.conf <<'EOF'
vrrp_script check_ipsec {
    script "/usr/bin/systemctl is-active ipsec"
    interval 5
    weight -50
    fall 2
    rise 2
}

vrrp_instance IPSEC_HA {
    state BACKUP
    interface enp2s0  # CUDN interface
    virtual_router_id 51
    priority 50
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass strongpassword123  # Must match ipsec-a
    }
    virtual_ipaddress {
        192.168.1.1/24
    }
    track_script {
        check_ipsec
    }
    notify_master "/usr/bin/systemctl start ipsec"
    notify_backup "/usr/bin/systemctl stop ipsec"
    notify_fault "/usr/bin/systemctl stop ipsec"
}
EOF
```

#### Enable and Start Keepalived

On **both** VMs:
```bash
# Enable services at boot
sudo systemctl enable keepalived
sudo systemctl enable ipsec

# Start keepalived (will manage ipsec)
sudo systemctl start keepalived

# Check status
sudo systemctl status keepalived
sudo systemctl status ipsec

# Verify virtual IP on primary
ip addr show enp2s0 | grep 192.168.1.1
```

### Step 9: AWS Configuration

#### 9.1 Update Transit Gateway Route Table

Ensure TGW routes traffic for CUDN to VPN attachment:

```bash
# AWS CLI: Create static route for CUDN CIDR
aws ec2 create-transit-gateway-route \
  --destination-cidr-block 192.168.1.0/24 \
  --transit-gateway-route-table-id tgw-rtb-XXXXXX \
  --transit-gateway-attachment-id tgw-attach-XXXXXX \
  --region us-east-1
```

Or via AWS Console:
1. Navigate to **VPC → Transit Gateway route tables**
2. Select your TGW route table
3. **Routes → Create static route**
4. **CIDR**: `192.168.1.0/24`
5. **Attachment**: Select VPN attachment

#### 9.2 Update VPC Route Tables

Add routes for CUDN CIDR to all VPC subnets that need VM access:

```bash
# Example: Add route to private subnet route table
aws ec2 create-route \
  --route-table-id rtb-XXXXXX \
  --destination-cidr-block 192.168.1.0/24 \
  --transit-gateway-id tgw-XXXXXX \
  --region us-east-1
```

Or via AWS Console:
1. **VPC → Route tables**
2. Select each private subnet route table
3. **Routes → Edit routes → Add route**
4. **Destination**: `192.168.1.0/24`
5. **Target**: Transit Gateway (select your TGW)

#### 9.3 Security Groups and NACLs

Update security groups on VPC instances to allow traffic from CUDN:

```bash
# Example: Allow ICMP from CUDN
aws ec2 authorize-security-group-ingress \
  --group-id sg-XXXXXX \
  --protocol icmp \
  --port -1 \
  --cidr 192.168.1.0/24 \
  --region us-east-1

# Allow SSH from CUDN
aws ec2 authorize-security-group-ingress \
  --group-id sg-XXXXXX \
  --protocol tcp \
  --port 22 \
  --cidr 192.168.1.0/24 \
  --region us-east-1
```

Check NACLs to ensure bidirectional traffic is allowed.

## Deploy Additional VMs

To add more VMs to the CUDN network with VPN access:

### 1. Create VM with CUDN Interface

Example VM manifest:
```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: my-vm
  namespace: vpn-infra
spec:
  running: true
  template:
    spec:
      domain:
        devices:
          interfaces:
            - name: default
              masquerade: {}
            - name: cudn  # Secondary interface
              bridge: {}
      networks:
        - name: default
          pod: {}
        - name: cudn  # Connect to vm-network
          multus:
            networkName: vm-network-attachment
```

### 2. Configure VM Networking

Log into the VM and configure the CUDN interface:

```bash
# Identify secondary interface
ip link show

# Configure with unique IP
INTERFACE_NAME=enp2s0
VM_CUDN_IP=192.168.1.20  # Must be unique per VM
GATEWAY_VIRTUAL_IP=192.168.1.1
VPC_CIDR_1=10.132.100.0/22
VPC_CIDR_2=10.132.104.0/22
VPC_CIDR_3=10.132.108.0/22

sudo nmcli con add type ethernet ifname $INTERFACE_NAME con-name cudn \
  ipv4.addresses ${VM_CUDN_IP}/24 ipv4.method manual autoconnect yes
sudo nmcli con mod cudn 802-3-ethernet.mtu 1400
sudo nmcli con mod cudn ipv4.routes "$VPC_CIDR_1 $GATEWAY_VIRTUAL_IP"
sudo nmcli con mod cudn +ipv4.routes "$VPC_CIDR_2 $GATEWAY_VIRTUAL_IP"
sudo nmcli con mod cudn +ipv4.routes "$VPC_CIDR_3 $GATEWAY_VIRTUAL_IP"
sudo nmcli con up cudn
```

### 3. Verify Connectivity

```bash
# Test gateway reachability
ping 192.168.1.1

# Test VPC connectivity
ping 10.132.100.10  # Example VPC instance
```

## Verification and Testing

### Check IPSec Tunnel Status

On the active IPSec VM (check which has VIP 192.168.1.1):

```bash
# Check which VM is active
ip addr show enp2s0 | grep 192.168.1.1

# View IPSec status
sudo ipsec status
sudo ipsec statusall

# Check logs
sudo tail -f /var/log/pluto.log
```

### Check AWS VPN Status

AWS Console → VPC → Site-to-Site VPN Connections:
- At least one tunnel should show **UP**
- Note tunnel outside IP and Inside IP addresses

### Test Connectivity

#### From VM to VPC Instance:
```bash
# On any CUDN-connected VM
ping 10.132.100.10  # Replace with actual VPC instance IP
ssh user@10.132.100.10
```

#### From VPC Instance to VM:
```bash
# On EC2 instance in VPC
ping 192.168.1.20  # Replace with actual VM CUDN IP
ssh user@192.168.1.20
```

### Test Failover

```bash
# On primary VM (ipsec-a), stop keepalived
sudo systemctl stop keepalived

# Monitor on ipsec-b - should acquire VIP and start ipsec
watch 'ip addr show enp2s0 | grep 192.168.1.1'
watch 'sudo ipsec status'

# Connectivity should resume within 5-10 seconds
# Test from another VM or VPC
ping 192.168.1.1
```

## Troubleshooting

### IPSec Tunnel Not Establishing

**Check certificates**:
```bash
sudo certutil -L -d sql:/etc/ipsec.d
sudo ipsec showhostkey --left --ckaid $(sudo ipsec showhostkey --list 2>/dev/null | grep CKAID | awk '{print $2}')
```

**Check IPSec logs**:
```bash
sudo tail -100 /var/log/pluto.log | grep -i error
```

**Common issues**:
- Certificate nickname mismatch in `ipsec.conf`
- Wrong tunnel outside IP addresses
- AWS VPN not configured with correct certificate
- Firewall blocking UDP 500/4500

### Keepalived Issues

**Check VRRP communication**:
```bash
sudo tcpdump -i enp2s0 -n vrrp
```

**Check logs**:
```bash
sudo journalctl -u keepalived -f
```

**Common issues**:
- Authentication password mismatch between VMs
- Interface name incorrect
- Virtual router ID conflict

### Routing Issues

**Check routes on VM**:
```bash
ip route show
ip route get 10.132.100.10  # Test route to VPC
```

**Check TGW routes**:
```bash
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id tgw-rtb-XXXXXX \
  --filters "Name=route-search.exact-match,Values=192.168.1.0/24" \
  --region us-east-1
```

**Check VPC routes**:
```bash
aws ec2 describe-route-tables \
  --route-table-ids rtb-XXXXXX \
  --query 'RouteTables[0].Routes[?DestinationCidrBlock==`192.168.1.0/24`]' \
  --region us-east-1
```

### No Connectivity from VPC to VM

**Check security groups**:
```bash
# Verify SG allows traffic from 192.168.1.0/24
aws ec2 describe-security-groups \
  --group-ids sg-XXXXXX \
  --query 'SecurityGroups[0].IpPermissions[?contains(IpRanges[].CidrIp, `192.168.1`)]' \
  --region us-east-1
```

**Check NACLs**:
```bash
# List NACL rules for subnet
aws ec2 describe-network-acls \
  --filters "Name=association.subnet-id,Values=subnet-XXXXXX" \
  --region us-east-1
```

**Test from IPSec VM**:
```bash
# On ipsec-a or ipsec-b
ping -I enp2s0 10.132.100.10
tcpdump -i enp2s0 icmp
```

## Monitoring and Maintenance

### Monitor IPSec Tunnel Health

**Check tunnel status regularly**:
```bash
# Create monitoring script on IPSec VMs
sudo tee /usr/local/bin/check-vpn.sh <<'EOF'
#!/bin/bash
TUNNEL_STATUS=$(sudo ipsec status | grep -c "ESTABLISHED")
VIP_STATUS=$(ip addr show enp2s0 | grep -c "192.168.1.1")

if [ "$VIP_STATUS" -eq 1 ]; then
    if [ "$TUNNEL_STATUS" -eq 0 ]; then
        echo "CRITICAL: IPSec tunnel down on primary"
        sudo systemctl restart ipsec
    else
        echo "OK: IPSec tunnel active"
    fi
else
    echo "Standby mode"
fi
EOF

sudo chmod +x /usr/local/bin/check-vpn.sh

# Add to cron
echo "*/5 * * * * /usr/local/bin/check-vpn.sh >> /var/log/vpn-check.log 2>&1" | sudo crontab -
```

### Certificate Rotation

Certificates expire after 1 year. Plan rotation:

1. Generate new certificates from ACM Private CA
2. Import new certificates to both VMs (keep old certs)
3. Update `ipsec.conf` with new certificate nickname
4. Reload IPSec configuration:
   ```bash
   sudo ipsec reload
   ```
5. Remove old certificates after verification

### Update Libreswan Configuration

```bash
# Edit configuration
sudo vi /etc/ipsec.conf

# Reload configuration (no downtime)
sudo ipsec reload

# Or restart service (brief outage)
sudo systemctl restart ipsec
```

### VM Maintenance

**Before stopping IPSec VM**:
```bash
# Failover to secondary
sudo systemctl stop keepalived

# Verify secondary took over
# On ipsec-b: ip addr show enp2s0 | grep 192.168.1.1
```

## Operational Considerations

### Performance

- **Throughput**: Limited to 1.25 Gbps per AWS VPN tunnel
- **Latency**: Additional ~5-10ms for IPSec encryption/decryption
- **VM CPU**: Monitor IPSec VM CPU during high traffic

### Availability

- **VM Failover**: ~5 seconds with Keepalived
- **Tunnel Failover**: Consider VTI configuration for both tunnels active
- **AZ Resilience**: VMs scheduled in different availability zones

### Security

- **IPAM Disabled**: Port security disabled on vm-network
  - Any VM can use any IP on CUDN
  - Consider network segmentation for untrusted workloads
- **Certificate Security**: Protect private keys
- **VM Access Control**: Secure IPSec VM access via RBAC

### Scalability

- **IP Address Management**: Manual assignment required
  - Consider DHCP server on CUDN for automation
- **Additional VPC CIDRs**: Add to routes on IPSec VMs
- **Multiple VM Networks**: Create additional CUDNs with separate IPSec gateways

## Cost Considerations

- **AWS VPN**: $0.05/hour per connection (~$36/month)
- **Transit Gateway**: $0.05/hour + $0.02/GB processed
- **OpenShift Virtualization**: Included with OpenShift subscription
- **Storage**: PVs for IPSec VMs (~60Gi total)
- **Compute**: 2 CPUs, 4Gi RAM per IPSec VM

## Reference Documentation

- [Red Hat Cloud Experts - ROSA S2S VPN](https://cloud.redhat.com/experts/rosa/s2s-vpn/)
- [OpenShift Virtualization Networking](https://docs.openshift.com/container-platform/latest/virt/vm_networking/virt-connecting-vm-to-ovn-secondary-network.html)
- [AWS VPN Documentation](https://docs.aws.amazon.com/vpn/latest/s2svpn/VPC_VPN.html)
- [Libreswan Documentation](https://libreswan.org/wiki/Main_Page)
- [Keepalived Documentation](https://www.keepalived.org/manpage.html)

---

**Implementation Date**: 2026-02-09  
**Maintained by**: OpenShift Architecture Team  
**Support Contact**: OpenShift Team
