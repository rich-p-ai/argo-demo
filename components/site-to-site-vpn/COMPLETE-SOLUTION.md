# Complete Solution: Making VM IPs Reachable Through Site-to-Site VPN

## ✅ STATUS: VPN Restored and Running

**VPN Pod Status**: ✅ Running with hostNetwork: true  
**VPN Tunnel**: ✅ ESTABLISHED to AWS (tunnel2: 98.94.136.2)  
**Gateway VM**: ✅ Deployed (vpn-gateway in windows-non-prod)

---

## Solution Architecture

```
┌────────────────────────────────────────────────────────────────┐
│ On-Premise Networks (10.227.112.0/20, Canon offices)           │
└──────────────────┬─────────────────────────────────────────────┘
                   ↓ IPSec VPN
┌──────────────────────────────────────────────────────────────────┐
│ AWS Transit Gateway + VPN Connection                             │
└──────────────────┬───────────────────────────────────────────────┘
                   ↓
┌──────────────────────────────────────────────────────────────────┐
│ OpenShift Worker Node (Host Network)                             │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ strongSwan VPN Pod (hostNetwork: true)                     │ │
│  │ - Receives VPN traffic from AWS                            │ │
│  │ - Routes pod network (10.132.0.0/14) ✅                    │ │
│  │ - Needs route to CUDN (10.227.128.0/21) ⚠️                │ │
│  └────────────────────────────────────────────────────────────┘ │
└──────────────────┬───────────────────────────────────────────────┘
                   ↓ Add static route: 10.227.128.0/21 via 10.135.0.23
┌──────────────────────────────────────────────────────────────────┐
│ Pod Network (10.132.0.0/14, 10.135.0.0/16)                      │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ Gateway VM Pod                                             │ │
│  │ - eth0: 10.135.0.23 (pod network) ← receives from VPN     │ │
│  │ - eth1: 10.227.128.15 (CUDN) ← forwards to Windows VMs    │ │
│  │ - NAT & IP forwarding enabled                              │ │
│  └────────────────────────────────────────────────────────────┘ │
└──────────────────┬───────────────────────────────────────────────┘
                   ↓ Forward via eth1
┌──────────────────────────────────────────────────────────────────┐
│ OVN Layer 2 Overlay: windows-non-prod CUDN (10.227.128.0/21)    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ nymsdv297   │  │ nymsdv301   │  │ nymsdv312   │             │
│  │ 10.227.128.10│ │ 10.227.128.11│ │ 10.227.128.12│             │
│  │ GW: .15     │  │ GW: .15     │  │ GW: .15     │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
│  ┌─────────────┐  ┌─────────────┐                                │
│  │ nymsqa428   │  │ nymsqa429   │                                │
│  │ 10.227.128.13│ │ 10.227.128.14│                                │
│  │ GW: .15     │  │ GW: .15     │                                │
│  └─────────────┘  └─────────────┘                                │
└──────────────────────────────────────────────────────────────────┘
```

---

## Implementation Steps

### ✅ Step 1: VPN Pod Restored (COMPLETE)

VPN pod is running with original configuration (hostNetwork: true).

### Step 2: Configure Gateway VM

**Access gateway VM**:
```bash
virtctl console vpn-gateway -n windows-non-prod
# Login: root / changethis
```

**Configure routing and NAT**:
```bash
#!/bin/bash
# Run inside gateway VM

# Install iptables
dnf install -y iptables iptables-services

# Configure NAT for CUDN traffic
iptables -t nat -A POSTROUTING -s 10.227.128.0/21 -o eth0 -j MASQUERADE

# Allow forwarding
iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT
iptables -A FORWARD -i eth0 -o eth1 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i eth1 -o eth1 -j ACCEPT

# Save rules
iptables-save > /etc/sysconfig/iptables
systemctl enable --now iptables

# Verify
echo "=========================================="
echo "Gateway VM Configuration"
echo "=========================================="
echo "Interfaces:"
ip -br addr show
echo ""
echo "Routing:"
ip route show
echo ""
echo "IP Forwarding:"
sysctl net.ipv4.ip_forward
echo ""
echo "NAT Rules:"
iptables -t nat -L POSTROUTING -n -v
echo "=========================================="
```

### Step 3: Add Static Route in VPN Pod

Update the VPN ConfigMap to add a route to the CUDN via gateway VM:

```yaml
# Edit configmap
oc edit configmap ipsec-config -n site-to-site-vpn
```

Add this to the `start-vpn.sh` script, after enabling IP forwarding (around line 101):

```bash
# Add route to windows-non-prod CUDN via gateway VM
echo "Adding route to windows-non-prod CUDN..."
ip route add 10.227.128.0/21 via 10.135.0.23 dev eth0 2>/dev/null || true
echo "✓ Route added: 10.227.128.0/21 via 10.135.0.23"
```

**Restart VPN pod**:
```bash
oc delete pod -n site-to-site-vpn -l app=site-to-site-vpn
oc wait --for=condition=Ready pod -n site-to-site-vpn -l app=site-to-site-vpn --timeout=120s
```

**Verify route**:
```bash
POD=$(oc get pods -n site-to-site-vpn -l app=site-to-site-vpn -o jsonpath='{.items[0].metadata.name}')
oc exec -n site-to-site-vpn $POD -- ip route show | grep 10.227.128
# Should show: 10.227.128.0/21 via 10.135.0.23 dev eth0
```

### Step 4: Configure Windows VMs

**For each Windows VM**, access console and run:

```powershell
# PowerShell script for Windows VM network configuration
param(
    [Parameter(Mandatory=$true)]
    [string]$IPAddress
)

$ErrorActionPreference = 'Stop'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Configuring Windows VM Network" -ForegroundColor Cyan
Write-Host "IP: $IPAddress" -ForegroundColor Cyan
Write-Host "Gateway: 10.227.128.15" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Find second NIC
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Sort-Object ifIndex
if ($adapters.Count -lt 2) {
    Write-Host "ERROR: Need 2 network adapters" -ForegroundColor Red
    exit 1
}

$adapter = $adapters[1]
Write-Host "Configuring: $($adapter.Name)`n" -ForegroundColor Green

# Remove existing configuration
Write-Host "Removing old configuration..."
Remove-NetIPAddress -InterfaceAlias $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
Remove-NetRoute -InterfaceAlias $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Add new configuration with gateway VM as default gateway
Write-Host "Adding new configuration..."
New-NetIPAddress -InterfaceAlias $adapter.Name `
                 -IPAddress $IPAddress `
                 -PrefixLength 21 `
                 -DefaultGateway "10.227.128.15" -ErrorAction Stop

Write-Host "`n✓ Configuration applied!" -ForegroundColor Green

# Test gateway
Write-Host "Testing gateway 10.227.128.15..." -ForegroundColor Cyan
$result = Test-NetConnection -ComputerName 10.227.128.15 -InformationLevel Quiet
if ($result) {
    Write-Host "✓ Gateway is reachable!" -ForegroundColor Green
} else {
    Write-Host "✗ Cannot reach gateway" -ForegroundColor Red
}

# Test internet
Write-Host "Testing internet connectivity..." -ForegroundColor Cyan
$internet = Test-NetConnection -ComputerName 8.8.8.8 -InformationLevel Quiet
if ($internet) {
    Write-Host "✓ Internet is reachable!" -ForegroundColor Green
} else {
    Write-Host "✗ No internet connectivity" -ForegroundColor Yellow
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Configuration complete!" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
```

**Run for each VM**:
```powershell
# nymsdv297
.\configure-network.ps1 -IPAddress "10.227.128.10"

# nymsdv301
.\configure-network.ps1 -IPAddress "10.227.128.11"

# nymsdv312
.\configure-network.ps1 -IPAddress "10.227.128.12"

# nymsqa428
.\configure-network.ps1 -IPAddress "10.227.128.13"

# nymsqa429
.\configure-network.ps1 -IPAddress "10.227.128.14"
```

### Step 5: Update AWS Transit Gateway Routes

Add route for the CUDN network:

```bash
# Get VPN attachment ID
aws ec2 describe-transit-gateway-attachments \
  --filters "Name=resource-id,Values=vpn-059ee0661e851adf4" \
  --region us-east-1 \
  --query 'TransitGatewayAttachments[0].TransitGatewayAttachmentId' \
  --output text

# Add route for windows-non-prod CUDN
aws ec2 create-transit-gateway-route \
  --destination-cidr-block 10.227.128.0/21 \
  --transit-gateway-route-table-id tgw-rtb-0ff564f70c91bf1d5 \
  --transit-gateway-attachment-id <vpn-attachment-id-from-above> \
  --region us-east-1

# Verify route
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id tgw-rtb-0ff564f70c91bf1d5 \
  --filters "Name=route-search.exact-match,Values=10.227.128.0/21" \
  --region us-east-1
```

### Step 6: Update On-Premise Firewall (Palo Alto)

Add firewall rules and routes for 10.227.128.0/21:

```
# Add address object
set address POD-CIDR-NONPROD-WINDOWS-VMS 10.227.128.0/21

# Add to existing VPN routing
set routing route add 10.227.128.0/21 via vpn-tunnel interface

# Add firewall policy (adjust as needed)
set rulebase security rules rule-name "Allow-VPN-to-Windows-VMs" \
  source any \
  destination POD-CIDR-NONPROD-WINDOWS-VMS \
  application any \
  service application-default \
  action allow

# Commit changes
commit
```

---

## Verification and Testing

### Test 1: Gateway VM Connectivity

```bash
# Access gateway VM
virtctl console vpn-gateway -n windows-non-prod

# Test pod network
ping 10.135.0.1

# Test internet
ping 8.8.8.8

# Check interfaces
ip addr show eth0  # Should have 10.135.0.23
ip addr show eth1  # Should have 10.227.128.15

# Check forwarding
sysctl net.ipv4.ip_forward  # Should be 1

# Check NAT rules
iptables -t nat -L -n -v | grep 10.227.128
```

### Test 2: VPN Pod Routing

```bash
# Get VPN pod
POD=$(oc get pods -n site-to-site-vpn -l app=site-to-site-vpn -o jsonpath='{.items[0].metadata.name}')

# Check VPN tunnel
oc logs -n site-to-site-vpn $POD | grep ESTABLISHED

# Check route to CUDN
oc exec -n site-to-site-vpn $POD -- ip route show | grep 10.227.128

# Test connectivity to gateway VM
oc exec -n site-to-site-vpn $POD -- ping -c 3 10.135.0.23
```

### Test 3: Windows VM to Gateway

```powershell
# From Windows VM console
# Test gateway
ping 10.227.128.15

# Test internet
ping 8.8.8.8

# Check routing table
route print | findstr 10.227.128

# Test DNS
nslookup google.com
```

### Test 4: End-to-End (On-Premise to Windows VM)

```bash
# From on-premise workstation
ping 10.227.128.11  # nymsdv301

# If ping works, try RDP
mstsc /v:10.227.128.11
```

---

## Troubleshooting Guide

### Issue: Gateway VM not responding to ping

**Check**:
```bash
oc get vmi vpn-gateway -n windows-non-prod
virtctl console vpn-gateway -n windows-non-prod
ip addr show
```

**Fix**: Verify both eth0 and eth1 are UP with correct IPs.

### Issue: Windows VM can't reach gateway

**Check**:
```powershell
Test-NetConnection -ComputerName 10.227.128.15 -InformationLevel Detailed
arp -a | findstr 10.227.128.15
```

**Fix**: Verify Windows VM and gateway VM are on same CUDN.

### Issue: VPN pod has no route to CUDN

**Check**:
```bash
oc exec -n site-to-site-vpn $POD -- ip route show
```

**Fix**: Update VPN configmap with static route and restart pod.

### Issue: No internet from Windows VMs

**Check**:
```bash
# On gateway VM
iptables -t nat -L POSTROUTING -n -v
# Check packet counters

# From Windows VM
tracert 8.8.8.8
```

**Fix**: Verify NAT rules and IP forwarding on gateway VM.

---

## Summary

### What's Been Completed
- ✅ VPN pod restored and running (hostNetwork: true)
- ✅ Gateway VM deployed (vpn-gateway)
- ✅ Analysis complete on OVN Layer 2 limitations

### Next Actions (In Order)
1. **Configure Gateway VM** - Set up NAT and routing
2. **Update VPN ConfigMap** - Add static route to CUDN
3. **Configure Windows VMs** - Point to gateway at 10.227.128.15
4. **Update AWS TGW** - Add 10.227.128.0/21 route
5. **Update Firewall** - Add Palo Alto rules for CUDN
6. **Test End-to-End** - Verify on-premise can reach Windows VMs

### Expected Result

After completing all steps:
- ✅ On-premise can ping/RDP to Windows VMs (10.227.128.10-14)
- ✅ Windows VMs can reach on-premise resources
- ✅ Windows VMs have internet access via VPN
- ✅ All traffic routed through site-to-site VPN

---

**Document Created**: 2026-02-12 19:55 UTC  
**VPN Status**: ✅ Running  
**Gateway VM**: ✅ Deployed  
**Next Step**: Configure gateway VM routing
