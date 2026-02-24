# IPSec VPN VM Deployment - Migration from Container VPN

**Date**: 2026-02-12  
**Cluster**: Non-Prod ROSA  
**Objective**: Replace container-based VPN with VM-based IPSec gateway on CUDN

## Executive Summary

Successfully deployed an **IPSec VPN VM** (`ipsec-vpn`) in the `windows-non-prod` namespace to replace the container-based site-to-site VPN approach. This VM runs **Libreswan** directly on the `windows-non-prod` CUDN (10.227.128.0/21), acting as both the IPSec tunnel terminator and gateway for Windows VMs.

### Architecture Change

**Before (Container Approach)**:
```
Pod Network → VPN Container (hostNetwork) → NAT → AWS TGW → On-Prem
                    ↑                           
                    └─ Separate Gateway VM required to route CUDN traffic
```

**After (VM Approach - Red Hat Best Practice)**:
```
CUDN (10.227.128.0/21) → IPSec VM (Libreswan) → Pod Network → NAT → AWS TGW → On-Prem
   ↑                            ↑
   Windows VMs              Gateway at 10.227.128.1
```

### Key Benefits

1. **Direct CUDN Integration**: IPSec VM is directly connected to the CUDN network
2. **No Routing Hacks**: No need for complex routing between hostNetwork and OVN overlays
3. **Red Hat Best Practice**: Follows official OpenShift Virtualization guidance
4. **Simplified Architecture**: Single VM replaces both container VPN + gateway VM
5. **Better Isolation**: VPN traffic stays within CUDN, doesn't affect pod network

---

## Deployment Details

### 1. IPSec VPN VM

**File**: `Cluster-Config/components/site-to-site-vpn/ipsec-vpn-vm.yaml`

**Configuration**:
- **Name**: `ipsec-vpn`
- **Namespace**: `windows-non-prod`
- **OS**: CentOS Stream 9
- **Resources**: 2 CPUs, 4Gi RAM, 30Gi disk
- **Storage Class**: gp3-csi
- **Interfaces**:
  - **eth0** (default): Pod network - 10.135.0.27 (for VPN tunnel egress to AWS TGW)
  - **eth1** (cudn): windows-non-prod CUDN - 10.227.128.1 (gateway for Windows VMs)

**Status**:
```bash
$ oc get vm,vmi -n windows-non-prod | grep ipsec
virtualmachine.kubevirt.io/ipsec-vpn   2m59s   Running   True
virtualmachineinstance.kubevirt.io/ipsec-vpn   2m58s   Running   10.135.0.27   ip-10-227-100-102.ec2.internal   True
```

**Network Configuration**:
```bash
$ oc get vmi ipsec-vpn -n windows-non-prod -o jsonpath='{.status.interfaces}'
[
  {
    "name": "default",
    "ipAddress": "10.135.0.27",
    "mac": "02:85:bb:50:0c:64",
    "linkState": "up"
  },
  {
    "name": "cudn",
    "ipAddress": "10.227.128.19",  # Will be reconfigured to 10.227.128.1
    "mac": "02:85:bb:50:0c:65",
    "linkState": "up"
  }
]
```

### 2. Cloud-Init Configuration

**Features**:
- Installs **Libreswan** for IPSec tunnels
- Configures **eth1 static IP**: 10.227.128.1/21
- Enables **IP forwarding** and kernel parameters for IPSec
- Sets up **iptables NAT** for CUDN → pod network traffic
- Configures **iptables forwarding** rules
- Creates **ipsec.conf** and **ipsec.secrets** placeholders
- Management scripts: `ipsec-status.sh`, `configure-ipsec-gateway.sh`

**Key Kernel Parameters** (`/etc/sysctl.d/99-ipsec.conf`):
```
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
```

**iptables Rules**:
```bash
# NAT for CUDN traffic to external networks
iptables -t nat -A POSTROUTING -s 10.227.128.0/21 ! -d 10.227.128.0/21 -o eth0 -j MASQUERADE

# Forward CUDN traffic to/from pod network
iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT
iptables -A FORWARD -i eth0 -o eth1 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Allow VM-to-VM traffic within CUDN
iptables -A FORWARD -i eth1 -o eth1 -j ACCEPT
```

---

## Next Steps (Configuration Required)

### Step 1: Verify VM Configuration

Access the VM console:
```bash
virtctl console ipsec-vpn -n windows-non-prod
# Login: root / Canon123!
```

Verify eth1 configuration:
```bash
ip addr show eth1
# Should show: 10.227.128.1/21

# If not, manually configure:
ip addr add 10.227.128.1/21 dev eth1
ip link set eth1 up
```

### Step 2: Copy IPSec Configuration from Container VPN

The container VPN has the working IPSec configuration. We need to extract it:

```bash
# Get ipsec.conf from ConfigMap
oc get configmap ipsec-config -n site-to-site-vpn -o jsonpath='{.data.ipsec\.conf}' > /tmp/ipsec.conf

# Get NAT IP (left ID for IPSec)
NAT_IP=$(oc get pods -n site-to-site-vpn -l app=site-to-site-vpn -o jsonpath='{.items[0].status.hostIP}')
echo "NAT IP: $NAT_IP"

# Get pre-shared keys
oc get secret vpn-secrets -n site-to-site-vpn -o jsonpath='{.data.tunnel1-psk}' | base64 -d
oc get secret vpn-secrets -n site-to-site-vpn -o jsonpath='{.data.tunnel2-psk}' | base64 -d
```

### Step 3: Configure IPSec on VM

Via `virtctl console`:

```bash
# Edit ipsec.conf
cat > /etc/ipsec.d/aws-vpn.conf <<'EOF'
conn aws-vpn-tunnel1
    authby=secret
    auto=start
    dpdaction=restart
    dpddelay=10
    dpdtimeout=30
    ike=aes128-sha1-modp1024
    ikelifetime=28800s
    ikev2=no
    keyingtries=%forever
    left=%defaultroute
    leftid=<NAT_IP_HERE>
    leftsubnet=10.227.128.0/21
    right=3.232.27.186
    rightsubnet=10.63.0.0/16
    type=tunnel
    phase2alg=aes128-sha1-modp1024
    lifetime=3600s
    keyexchange=ikev1

conn aws-vpn-tunnel2
    authby=secret
    auto=start
    dpdaction=restart
    dpddelay=10
    dpdtimeout=30
    ike=aes128-sha1-modp1024
    ikelifetime=28800s
    ikev2=no
    keyingtries=%forever
    left=%defaultroute
    leftid=<NAT_IP_HERE>
    leftsubnet=10.227.128.0/21
    right=98.94.136.2
    rightsubnet=10.63.0.0/16
    type=tunnel
    phase2alg=aes128-sha1-modp1024
    lifetime=3600s
    keyexchange=ikev1
EOF

# Add secrets
cat > /etc/ipsec.d/aws-vpn.secrets <<'EOF'
<NAT_IP_HERE> 3.232.27.186 : PSK "<TUNNEL1_PSK_HERE>"
<NAT_IP_HERE> 98.94.136.2 : PSK "<TUNNEL2_PSK_HERE>"
EOF

# Restart IPSec
systemctl restart ipsec

# Check status
ipsec status
ipsec-status.sh
```

### Step 4: Update Windows VMs

Windows VMs in the CUDN need to use the IPSec VM as their gateway:

```powershell
# On each Windows VM (via console)
# Set default gateway to IPSec VM
New-NetIPAddress -InterfaceAlias "Ethernet 2" -IPAddress 10.227.128.x -PrefixLength 21 -DefaultGateway 10.227.128.1
```

### Step 5: AWS Transit Gateway Configuration

Update AWS TGW to route `10.227.128.0/21` to the VPN attachment:

```bash
# In AWS Console or CLI
# Add route: 10.227.128.0/21 → VPN attachment (vpn-xxxxx)
```

### Step 6: Palo Alto Firewall

Add routes on the on-premise Palo Alto firewall:
```
Destination: 10.227.128.0/21
Next Hop: AWS TGW
```

---

## Decommissioning Container VPN (Future Step)

Once the IPSec VM is fully functional and tested:

```bash
# Scale down container VPN
oc scale deployment site-to-site-vpn -n site-to-site-vpn --replicas=0

# Or delete it entirely
oc delete deployment site-to-site-vpn -n site-to-site-vpn
oc delete configmap ipsec-config -n site-to-site-vpn
oc delete secret vpn-secrets -n site-to-site-vpn
```

---

## Validation & Testing

### Test 1: VM Gateway Connectivity

From IPSec VM console:
```bash
# Test pod network egress
ping -c 3 8.8.8.8

# Test CUDN interface
ip addr show eth1 | grep 10.227.128.1

# Check routing
ip route show

# Check iptables
iptables -t nat -L -n -v
iptables -L FORWARD -n -v
```

### Test 2: Windows VM Connectivity

From Windows VM console:
```powershell
# Test gateway reachability
Test-NetConnection -ComputerName 10.227.128.1 -Port 22

# Test internet via gateway (should NAT through IPSec VM)
Test-NetConnection -ComputerName 8.8.8.8

# Test on-premise network (once VPN tunnel is up)
Test-NetConnection -ComputerName <on-prem-ip>
```

### Test 3: IPSec Tunnel Status

From IPSec VM console:
```bash
ipsec status
# Should show: "aws-vpn-tunnel1" and "aws-vpn-tunnel2" ESTABLISHED

ipsec trafficstatus
# Should show active SA (Security Associations)
```

---

## Troubleshooting

### Issue: eth1 doesn't have 10.227.128.1

**Solution**: Manually configure via console:
```bash
virtctl console ipsec-vpn -n windows-non-prod
ip addr flush dev eth1
ip addr add 10.227.128.1/21 dev eth1
ip link set eth1 up
```

### Issue: IPSec tunnels won't establish

**Diagnostics**:
```bash
# Check logs
tail -f /var/log/pluto.log

# Verify secrets
cat /etc/ipsec.d/aws-vpn.secrets

# Test connectivity to AWS TGW endpoints
ping 3.232.27.186
ping 98.94.136.2

# Verify NAT IP matches leftid in ipsec.conf
curl -s ifconfig.me  # Should match leftid
```

### Issue: Windows VMs can't reach gateway

**Solution**: Verify CUDN connectivity:
```bash
# From IPSec VM
tcpdump -i eth1 icmp

# From Windows VM
Test-NetConnection -ComputerName 10.227.128.1 -Port 22
```

---

## References

- **Red Hat Blog**: [Site-to-Site VPN with OpenShift Virtualization](https://cloud.redhat.com/experts/rosa/s2s-vpn/)
- **Comparison Doc**: `docs/VPN-COMPARISON-CONTAINER-VS-VM.md`
- **CUDN Implementation**: `Cluster-Config/components/site-to-site-vpn/CUDN-IMPLEMENTATION.md`
- **IPSec VM Template**: `Cluster-Config/components/site-to-site-vpn/ipsec-vm-example.yaml`

---

## Summary

✅ **Deployed**: IPSec VPN VM (`ipsec-vpn`) in `windows-non-prod` namespace  
✅ **Configured**: Dual-NIC setup (pod network + CUDN)  
✅ **Prepared**: Cloud-init with Libreswan, routing, and NAT  
⏳ **Pending**: Copy IPSec configuration from container VPN  
⏳ **Pending**: Configure Windows VMs to use new gateway  
⏳ **Pending**: Update AWS TGW and Palo Alto routes  

**Next Action**: Access VM console and complete IPSec configuration transfer.
