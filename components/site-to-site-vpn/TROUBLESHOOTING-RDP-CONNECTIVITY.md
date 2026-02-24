# Troubleshooting: RDP Connectivity to VMs

## Issue
Cannot ping or RDP to VMs at 10.132.104.10 and 10.132.104.11 from company network.

## VM Configuration Verified ✅

```
NYMSDV297: 10.132.104.10 - Running, interface UP
NYMSDV301: 10.132.104.11 - Running, interface UP
Network: windows-non-prod (VLAN 101, bridge mode)
Gateway: 10.132.104.1
```

## Root Cause Analysis

The VMs are configured correctly, but there are several possible reasons why connectivity isn't working:

### 1. Site-to-Site VPN Routing Issue (Most Likely)

**Problem:** The 10.132.104.0/22 subnet might not be properly routed through the S2S VPN.

**Check these:**

#### A. VPN Transit Gateway Routes

The S2S VPN needs a route for 10.132.104.0/22:

```bash
# Check VPN TGW routes
aws ec2 describe-transit-gateway-route-tables \
  --transit-gateway-route-table-ids tgw-rtb-XXXXX \
  --region us-east-1
```

**Expected route:** `10.132.104.0/22` → Non-Prod VPC attachment

#### B. Palo Alto Firewall Configuration

The firewall needs to know about this subnet:

```
# On Palo Alto CLI
show routing route
show vpn flow name <vpn-tunnel-name>
```

**Expected:** Route for 10.132.104.0/22 via VPN tunnel

#### C. VPC Route Table

Non-Prod VPC needs route back to company network:

```bash
aws ec2 describe-route-tables \
  --route-table-ids rtb-0467d201a9cbdb89c \
  --region us-east-1
```

**Expected:** Return route to company network (10.222.155.0/24 or similar)

---

### 2. OpenShift Network Configuration

**Problem:** VMs might not have proper default route or gateway configured.

#### Check VM Routing (from inside VM)

```bash
# Login to VM console
virtctl console nymsdv297 -n windows-non-prod

# Windows - Check routing
route print

# Expected output should show:
# Network         Netmask         Gateway        Interface
# 0.0.0.0         0.0.0.0         10.132.104.1   10.132.104.10
# 10.132.104.0    255.255.252.0   On-link        10.132.104.10
```

**If gateway is missing:**
```powershell
# Add default route (inside Windows VM)
route add 0.0.0.0 mask 0.0.0.0 10.132.104.1 -p
```

---

### 3. Gateway Not Responding

**Problem:** The gateway 10.132.104.1 might not exist or isn't routing traffic.

#### Test from VM Console

```bash
# Login to VM
virtctl console nymsdv297 -n windows-non-prod

# Test gateway
ping 10.132.104.1

# Test external connectivity
ping 8.8.8.8
ping 10.222.155.1  # Company network
```

**If gateway doesn't respond:** This is a network configuration issue. The gateway should be provided by the VPC networking.

---

### 4. Windows Firewall Blocking RDP

**Problem:** Windows Firewall might be blocking RDP connections.

#### Check from VM Console

```powershell
# Check if RDP is enabled
Get-NetFirewallRule -DisplayName "*Remote Desktop*" | Select DisplayName, Enabled

# Enable RDP through firewall
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

# Or disable firewall entirely (testing only!)
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
```

---

### 5. Network Attachment Not Working

**Problem:** Bridge network might not be functioning properly.

#### Verify Bridge on Node

```bash
# Find which node the VM is on
oc get vmi nymsdv297 -n windows-non-prod -o jsonpath='{.status.nodeName}'

# Debug the node (requires node access)
oc debug node/<node-name>

# Check bridge exists
chroot /host
bridge link show br-windows
```

---

## Diagnostic Steps

### Step 1: Test from Within OpenShift

```bash
# Create test pod on same network
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: network-test
  namespace: windows-non-prod
  annotations:
    k8s.v1.cni.cncf.io/networks: windows-non-prod
spec:
  containers:
  - name: test
    image: nicolaka/netshoot
    command: ["sleep", "3600"]
EOF

# Wait for pod to start
oc wait --for=condition=Ready pod/network-test -n windows-non-prod --timeout=60s

# Test connectivity to VMs
oc exec -it network-test -n windows-non-prod -- ping 10.132.104.10
oc exec -it network-test -n windows-non-prod -- ping 10.132.104.11
oc exec -it network-test -n windows-non-prod -- ping 10.132.104.1  # Gateway

# Test RDP port
oc exec -it network-test -n windows-non-prod -- nc -zv 10.132.104.10 3389
```

**If this works:** Problem is with VPN/firewall routing  
**If this fails:** Problem is with VM or OpenShift networking

### Step 2: Test Gateway Accessibility

```bash
# From test pod, check if gateway responds
oc exec -it network-test -n windows-non-prod -- ping 10.132.104.1

# Check ARP table
oc exec -it network-test -n windows-non-prod -- arp -n

# Try to trace route
oc exec -it network-test -n windows-non-prod -- traceroute 10.222.155.1
```

### Step 3: Check VM Guest Agent

```bash
# Verify guest agent is running (provides IP info)
oc get vmi nymsdv297 -n windows-non-prod -o jsonpath='{.status.guestOSInfo}'

# If empty, guest agent might not be installed/running in Windows
```

---

## Quick Fixes

### Fix 1: Configure Static Routes in VM

If VMs can't reach company network, add static routes:

```powershell
# Inside Windows VM
# Add route to company network via gateway
route add 10.222.155.0 mask 255.255.255.0 10.132.104.1 -p
route add 10.0.0.0 mask 255.0.0.0 10.132.104.1 -p

# Verify
route print
```

### Fix 2: Enable RDP in Windows

```powershell
# Enable RDP
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -value 0

# Enable firewall rule
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

# Restart service
Restart-Service TermService -Force
```

### Fix 3: Add Missing VPN Route (AWS Side)

If 10.132.104.0/22 isn't routed through VPN:

```bash
# Add route to VPN TGW route table
aws ec2 create-transit-gateway-route \
  --transit-gateway-route-table-id tgw-rtb-XXXXX \
  --destination-cidr-block 10.132.104.0/22 \
  --transit-gateway-attachment-id tgw-attach-XXXXX \
  --region us-east-1
```

### Fix 4: Update Palo Alto Firewall

Add 10.132.104.0/22 to VPN policy:

```
# Palo Alto CLI
configure
set address VM-Network-NonProd ip-netmask 10.132.104.0/22
set rulebase pbf rules pbf-vpn-tunnel destination VM-Network-NonProd
set rulebase nat rules No_NAT_LAN_VPC destination VM-Network-NonProd
commit
```

---

## Most Likely Issue: VPN Routing

Based on the VPN-ROUTING-FIX-ACTION-PLAN.md documentation, the most likely issue is that **10.132.104.0/22** is not properly routed through the S2S VPN.

### Check Current VPN Configuration

**Question 1:** Is 10.132.104.0/22 included in the VPN tunnel configuration?

Check on Palo Alto:
```
show vpn ipsec-sa
show routing route | match 10.132.104
```

**Question 2:** Does the VPN Transit Gateway have a route for this subnet?

```bash
aws ec2 describe-transit-gateway-route-tables \
  --filters "Name=transit-gateway-id,Values=tgw-00279fe0ab1ac255c" \
  --region us-east-1
```

**Question 3:** Can you reach other IPs in the 10.132.104.0/22 range from company network?

Test from company workstation:
```powershell
ping 10.132.104.1  # Gateway
ping 10.132.104.5  # Infrastructure IP
```

---

## Recommended Action Plan

1. **First:** Test from within OpenShift (Step 1 above) to isolate if it's VM or network issue
2. **Second:** Check if gateway 10.132.104.1 is reachable from company network
3. **Third:** Review VPN configuration for 10.132.104.0/22 routing
4. **Fourth:** Configure Windows Firewall/RDP if connectivity works

---

## Need More Information

To help diagnose further, please provide:

1. **Can you ping 10.132.104.1 from company network?**
2. **What do you see when testing from the test pod (Step 1)?**
3. **Are there any other VMs/IPs in 10.132.104.0/22 you CAN reach?**
4. **What error do you get when trying to RDP?** (timeout, refused, etc.)

Based on your answers, I can provide more specific fixes.

---

## Summary

The VMs are configured correctly with IPs 10.132.104.10 and .11. The most likely issue is:

**VPN routing is not configured for 10.132.104.0/22 subnet**

This would require:
- AWS VPN Transit Gateway route update
- Palo Alto Firewall policy update
- Possible VPC route table update

Let's diagnose which component is missing the route configuration.
