# Current Connectivity Status Report

**Date**: 2026-02-12 20:15 UTC  
**Target**: Windows VM (10.227.128.10)  
**Test From**: Your workstation  

---

## ❌ Connectivity Status: NOT WORKING

**Can you reach 10.227.128.10 from your workstation?** ❌ **NO**

---

## Root Cause Analysis

### Current Configuration Status

| Component | Status | Details |
|-----------|--------|---------|
| VPN Tunnel | ✅ ESTABLISHED | Tunnel to AWS is up |
| VPN Pod | ✅ Running | Pod is healthy |
| **VPN Route** | ❌ **MISSING** | Route to 10.227.128.0/21 NOT added yet |
| Gateway VM | ✅ Running | VM deployed and running |
| **Gateway NAT** | ❌ **NOT CONFIGURED** | iptables rules not set |
| Windows VM | ✅ Running | nymsdv297 has CUDN IP |
| **Windows Gateway** | ❌ **NOT CONFIGURED** | VM not using gateway yet |
| AWS TGW Route | ❌ NOT ADDED | 10.227.128.0/21 route missing |
| Firewall Rules | ❌ NOT ADDED | Palo Alto not configured |

---

## Why You Can't Reach the VMs

### The Complete Path (What Should Happen)

```
Your Workstation (10.227.112.x)
    ↓ (1) Route via Palo Alto firewall ❌ NOT CONFIGURED
Palo Alto Firewall
    ↓ (2) Route via VPN tunnel ❌ NO FIREWALL RULE
AWS VPN Connection (vpn-059ee0661e851adf4)
    ↓ (3) Route via Transit Gateway ❌ NO TGW ROUTE
Transit Gateway
    ↓ (4) Route to VPC
ROSA VPC (10.227.96.0/20)
    ↓ (5) Route to OpenShift
VPN Pod (strongSwan)
    ↓ (6) Route to gateway VM ❌ ROUTE NOT ADDED YET
Gateway VM (10.135.0.23)
    ↓ (7) NAT and forward ❌ NAT NOT CONFIGURED
    ↓ (8) Forward to CUDN
Windows VM (10.227.128.x) ❌ NOT USING GATEWAY
```

**Every step marked ❌ needs to be completed for connectivity to work.**

---

## What's Blocking Connectivity

### 1. ❌ VPN ConfigMap Not Applied Yet

**Issue**: Changes are committed to Git but not applied to cluster.

**Why**: 
- Changes committed locally
- Not pushed to Git remote yet
- ArgoCD hasn't detected/synced changes
- VPN pod still using old ConfigMap (no route to gateway VM)

**Evidence**:
```bash
# VPN pod route table (current)
oc exec -n site-to-site-vpn $POD -- ip route show
# OUTPUT: Only shows default route, NO 10.227.128.0/21 route
```

**Fix Required**:
```bash
cd c:\Users\q22529_a\work\Cluster-Config
git push origin main
# Wait 3-5 minutes for ArgoCD sync
# VPN pod will restart with new route
```

### 2. ❌ Gateway VM NAT Not Configured

**Issue**: Gateway VM is running but not routing/NATing traffic.

**Current Status**:
- Gateway VM deployed: ✅
- Pod network IP: 10.135.0.23 ✅
- CUDN IP: 10.227.128.15 ✅
- iptables NAT rules: ❌ NOT CONFIGURED
- IP forwarding: ✅ Enabled

**Fix Required**: Configure NAT inside gateway VM
```bash
virtctl console vpn-gateway -n windows-non-prod
# Then run iptables configuration
```

### 3. ❌ Windows VMs Not Using Gateway

**Issue**: Windows VMs have CUDN IPs but not configured to use gateway.

**Current State** (nymsdv297):
- Has CUDN interface: ✅
- CUDN IP: 10.227.128.13 (not .10 as mentioned)
- Default gateway: ❌ Unknown/not configured
- Can reach gateway VM: ❌ Not tested

**Fix Required**: Configure Windows to use 10.227.128.15 as gateway

### 4. ❌ AWS Transit Gateway Route Missing

**Issue**: AWS doesn't know how to route 10.227.128.0/21 traffic.

**Fix Required**:
```bash
aws ec2 create-transit-gateway-route \
  --destination-cidr-block 10.227.128.0/21 \
  --transit-gateway-route-table-id tgw-rtb-0ff564f70c91bf1d5 \
  --transit-gateway-attachment-id <vpn-attachment-id> \
  --region us-east-1
```

### 5. ❌ Palo Alto Firewall Not Configured

**Issue**: On-premise firewall doesn't know about 10.227.128.0/21.

**Fix Required**: Add Palo Alto rules for this subnet.

---

## Windows VM IP Addresses

**Note**: You mentioned 10.227.128.10, but checking the actual VMs:

| VM Name | Current CUDN IP | Expected IP |
|---------|-----------------|-------------|
| nymsdv297 | 10.227.128.13 | 10.227.128.10 |
| nymsdv301 | ? | 10.227.128.11 |
| nymsdv312 | ? | 10.227.128.12 |
| nymsqa428 | ? | 10.227.128.13 |
| nymsqa429 | ? | 10.227.128.14 |

**Issue**: The CUDN is assigning IPs automatically via IPAM. The VM has 10.227.128.13 instead of the desired 10.227.128.10.

---

## Immediate Next Steps (In Order)

### Step 1: Push Git Changes (5 minutes)

```bash
cd c:\Users\q22529_a\work\Cluster-Config
git push origin main
```

Wait for ArgoCD to sync (auto, ~3-5 minutes) or force:
```bash
argocd app sync site-to-site-vpn
```

Verify route added:
```bash
POD=$(oc get pods -n site-to-site-vpn -l app=site-to-site-vpn -o jsonpath='{.items[0].metadata.name}')
oc exec -n site-to-site-vpn $POD -- ip route show | grep 10.227.128
# Should show: 10.227.128.0/21 via 10.135.0.23 dev eth0
```

### Step 2: Configure Gateway VM NAT (10 minutes)

```bash
virtctl console vpn-gateway -n windows-non-prod
# Login: root / changethis
```

Inside gateway VM:
```bash
# Install iptables
dnf install -y iptables iptables-services

# Configure NAT
iptables -t nat -A POSTROUTING -s 10.227.128.0/21 -o eth0 -j MASQUERADE
iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT
iptables -A FORWARD -i eth0 -o eth1 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Save and enable
iptables-save > /etc/sysconfig/iptables
systemctl enable --now iptables

# Verify
iptables -t nat -L -n -v
ip addr show
```

### Step 3: Test VPN to Gateway VM (2 minutes)

```bash
# From VPN pod, test gateway VM
POD=$(oc get pods -n site-to-site-vpn -l app=site-to-site-vpn -o jsonpath='{.items[0].metadata.name}')
oc exec -n site-to-site-vpn $POD -- ping -c 3 10.135.0.23

# Should get replies
```

### Step 4: Configure One Windows VM (10 minutes)

Test with nymsdv297 first:
```bash
virtctl console nymsdv297 -n windows-non-prod
```

In Windows (PowerShell as Administrator):
```powershell
# Find second NIC
$adapter = (Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Sort-Object ifIndex)[1]

# Remove old config
Remove-NetIPAddress -InterfaceAlias $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
Remove-NetRoute -InterfaceAlias $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue

# Add config with gateway
New-NetIPAddress -InterfaceAlias $adapter.Name `
                 -IPAddress "10.227.128.10" `
                 -PrefixLength 21 `
                 -DefaultGateway "10.227.128.15"

# Test gateway
ping 10.227.128.15

# Test internet
ping 8.8.8.8
```

### Step 5: Add AWS TGW Route (5 minutes)

```bash
# Get VPN attachment ID
aws ec2 describe-transit-gateway-attachments \
  --filters "Name=resource-id,Values=vpn-059ee0661e851adf4" \
  --region us-east-1 \
  --query 'TransitGatewayAttachments[0].TransitGatewayAttachmentId' \
  --output text

# Add route
aws ec2 create-transit-gateway-route \
  --destination-cidr-block 10.227.128.0/21 \
  --transit-gateway-route-table-id tgw-rtb-0ff564f70c91bf1d5 \
  --transit-gateway-attachment-id <attachment-id-from-above> \
  --region us-east-1
```

### Step 6: Add Firewall Rules (Time varies)

Contact network team or add Palo Alto rules for 10.227.128.0/21.

### Step 7: Test from Your Workstation

```bash
# Test ping
ping 10.227.128.10

# Test RDP
mstsc /v:10.227.128.10
```

---

## Estimated Time to Completion

| Step | Time | Cumulative |
|------|------|------------|
| 1. Push Git & ArgoCD sync | 5 min | 5 min |
| 2. Configure Gateway VM NAT | 10 min | 15 min |
| 3. Test VPN to Gateway | 2 min | 17 min |
| 4. Configure Windows VM | 10 min | 27 min |
| 5. Add AWS TGW route | 5 min | 32 min |
| 6. Add Firewall rules | ? | ? |
| 7. Test connectivity | 5 min | ~40 min |

**Estimated Total**: ~40 minutes (excluding firewall approval time)

---

## Quick Test (Without Completing Everything)

You can test partial connectivity without completing all steps:

### Test 1: VPN to Gateway VM
```bash
# After Step 1+2, from VPN pod
oc exec -n site-to-site-vpn $POD -- ping 10.135.0.23
```

### Test 2: Gateway to Windows VM (Layer 2)
```bash
# After Step 2, from gateway VM
virtctl console vpn-gateway -n windows-non-prod
ping 10.227.128.13  # Current IP of nymsdv297
```

### Test 3: Windows VM to Gateway
```powershell
# After Step 4, from Windows VM
ping 10.227.128.15
```

---

## Summary

**Current Status**: ❌ **NOT CONNECTED**

**Why**: Configuration is incomplete:
1. ❌ VPN route not applied (Git not pushed)
2. ❌ Gateway NAT not configured
3. ❌ Windows VMs not using gateway
4. ❌ AWS routes not added
5. ❌ Firewall rules not added

**Next Action**: Start with **Step 1** (Push Git changes) and proceed through the steps.

**Documentation**: See `COMPLETE-SOLUTION.md` for full details.

---

**Report Generated**: 2026-02-12 20:15 UTC  
**Connectivity**: ❌ NOT WORKING  
**Estimated Time to Fix**: ~40 minutes + firewall approval
