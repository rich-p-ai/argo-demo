# Quick Reference: CUDN Configuration Variables

This quick reference provides the key configuration values for your CUDN implementation.

## Network CIDRs

### CUDN Overlay Network
```
CUDN_CIDR=192.168.1.0/24
CUDN_SUBNET_MASK=/24
MTU=1400
```

### VPC Destination Networks
```
VPC_CIDR_1=10.132.100.0/22  # linux-non-prod
VPC_CIDR_2=10.132.104.0/22  # windows-non-prod
VPC_CIDR_3=10.132.108.0/22  # utility
```

## IPSec Gateway VMs

### IP Assignments
```
GATEWAY_VIRTUAL_IP=192.168.1.1    # Keepalived VIP (active VM only)
IPSEC_A_IP=192.168.1.10/24        # ipsec-a primary
IPSEC_B_IP=192.168.1.11/24        # ipsec-b secondary
```

### VM Resources
```
CPU: 2 cores per VM
Memory: 4Gi per VM
Storage: 30Gi per VM
```

### Availability Zones
```
ipsec-a: us-east-1a
ipsec-b: us-east-1b
```

## CUDN Interface Configuration Template

### For ipsec-a VM:
```bash
INTERFACE_NAME=enp2s0              # Identify via: ip link show
VM_CUDN_IP=192.168.1.10
CUDN_SUBNET_MASK=/24
GATEWAY_VIRTUAL_IP=192.168.1.1
VPC_CIDR_1=10.132.100.0/22
VPC_CIDR_2=10.132.104.0/22
VPC_CIDR_3=10.132.108.0/22

sudo nmcli con add type ethernet ifname $INTERFACE_NAME con-name cudn \
  ipv4.addresses ${VM_CUDN_IP}${CUDN_SUBNET_MASK} ipv4.method manual autoconnect yes
sudo nmcli con mod cudn 802-3-ethernet.mtu 1400
sudo nmcli con mod cudn ipv4.routes "$VPC_CIDR_1 $GATEWAY_VIRTUAL_IP"
sudo nmcli con mod cudn +ipv4.routes "$VPC_CIDR_2 $GATEWAY_VIRTUAL_IP"
sudo nmcli con mod cudn +ipv4.routes "$VPC_CIDR_3 $GATEWAY_VIRTUAL_IP"
sudo nmcli con up cudn
```

### For ipsec-b VM:
```bash
# Same as above but change:
VM_CUDN_IP=192.168.1.11
```

### For additional VMs:
```bash
# Use unique IP for each VM
VM_CUDN_IP=192.168.1.20  # Increment for each VM
# Gateway IP remains 192.168.1.1
```

## Libreswan Configuration Template

```bash
CERT_NICKNAME="s2s.vpn.test.mobb.cloud"  # From: certutil -L -d sql:/etc/ipsec.d
TUNNEL1_OUTSIDE_IP="3.232.27.186"        # From AWS VPN configuration
TUNNEL2_OUTSIDE_IP="98.94.136.2"         # From AWS VPN configuration
CUDN_CIDR="192.168.1.0/24"
VPC_CIDR_1="10.132.100.0/22"
VPC_CIDR_2="10.132.104.0/22"
VPC_CIDR_3="10.132.108.0/22"
```

## Keepalived Configuration

### Priority Settings
```
ipsec-a (MASTER): priority 100
ipsec-b (BACKUP): priority 50
```

### Authentication
```
auth_type: PASS
auth_pass: strongpassword123  # MUST match on both VMs
virtual_router_id: 51
```

## Deployment Commands

### Deploy CUDN Infrastructure
```bash
# Deploy namespace, CUDN, and cloud-init
oc apply -k components/site-to-site-vpn/ -f kustomization-cudn.yaml

# Deploy IPSec VMs separately (after customizing)
oc apply -f components/site-to-site-vpn/ipsec-vm-example.yaml
```

### Verification Commands
```bash
# Check CUDN
oc get clusteruserdefinednetwork vm-network -o yaml

# Check NetworkAttachmentDefinition
oc get network-attachment-definitions -n vpn-infra

# Check VMs
oc get vms -n vpn-infra
oc get vmis -n vpn-infra

# Access VM console
virtctl console -n vpn-infra ipsec-a
```

## IP Address Allocation

Reserve IPs in the 192.168.1.0/24 range:

```
192.168.1.1     - Gateway Virtual IP (Keepalived)
192.168.1.10    - ipsec-a
192.168.1.11    - ipsec-b
192.168.1.20+   - Additional VMs (manually assigned)
```

## AWS Configuration Checklist

- [ ] TGW route: 192.168.1.0/24 → VPN attachment
- [ ] VPC route tables: 192.168.1.0/24 → TGW
- [ ] Security groups: Allow ICMP, SSH (22), RDP (3389) from 192.168.1.0/24
- [ ] NACLs: Bidirectional traffic allowed for 192.168.1.0/24
- [ ] VPN connection: Certificate-based authentication configured
- [ ] VPN status: At least one tunnel UP

## Certificate Requirements

Required files from ACM Private CA:
- `left-cert.p12` - PKCS#12 bundle with passphrase
- `certificate_chain.pem` - Full CA chain (subordinate + root)

Certificate FQDN must match:
- AWS VPN Customer Gateway certificate
- Libreswan `leftcert` and `leftid` parameters

## Common IP Ranges Reference

| Network | CIDR | Purpose | Gateway |
|---------|------|---------|---------|
| CUDN Overlay | 192.168.1.0/24 | VM network | 192.168.1.1 |
| Linux Non-Prod | 10.132.100.0/22 | VPC destination | via TGW |
| Windows Non-Prod | 10.132.104.0/22 | VPC destination | via TGW |
| Utility | 10.132.108.0/22 | VPC destination | via TGW |
| Pod Network | 10.132.0.0/14 | Existing ROSA pods | N/A |
| VPC | 10.227.96.0/20 | Worker nodes | N/A |

## Testing Commands

### From VM to VPC:
```bash
ping 10.132.100.10  # Replace with actual VPC instance IP
ssh user@10.132.100.10
```

### From VPC to VM:
```bash
ping 192.168.1.20  # Replace with actual VM IP
ssh user@192.168.1.20
```

### Check IPSec Status:
```bash
# On active IPSec VM
sudo ipsec status
sudo ipsec statusall
tail -50 /var/log/pluto.log
```

### Check Keepalived Status:
```bash
# Check which VM has the VIP
ip addr show enp2s0 | grep 192.168.1.1

# Check keepalived logs
sudo journalctl -u keepalived -f
```

## Troubleshooting Quick Checks

```bash
# On IPSec VM - verify interface config
ip addr show enp2s0
ip route show dev enp2s0

# Verify kernel settings
sysctl net.ipv4.ip_forward
sysctl net.ipv4.conf.all.rp_filter

# Check certificates
sudo certutil -L -d sql:/etc/ipsec.d

# Test IPSec connectivity
sudo ipsec trafficstatus

# Monitor IPSec traffic
sudo tcpdump -i enp2s0 -n icmp

# Check AWS VPN status (from AWS CLI)
aws ec2 describe-vpn-connections \
  --vpn-connection-ids vpn-059ee0661e851adf4 \
  --region us-east-1 \
  --query 'VpnConnections[0].VgwTelemetry'
```
