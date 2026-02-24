# VPN Gateway VM Deployment Status and Next Steps

## Deployment Status: ✅ COMPLETE

### Gateway VM Details

- **VM Name**: vpn-gateway
- **Namespace**: windows-non-prod
- **Status**: Running
- **Node**: ip-10-227-100-102.ec2.internal

### Network Configuration

| Interface | Purpose | IP Address | Status |
|-----------|---------|------------|--------|
| eth0 | Pod Network (default) | 10.135.0.23 | ✅ UP |
| eth1 | windows-non-prod CUDN | 10.227.128.15 | ✅ UP |

**NOTE**: The gateway VM received IP **10.227.128.15** from CUDN IPAM instead of the desired **10.227.128.1**. This happened because the windows-non-prod CUDN has `ipamLifecycle: Persistent` which still assigns IPs automatically.

---

## Current Situation

### What's Working ✅
- Gateway VM deployed and running
- Both network interfaces are UP
- VM has connectivity to pod network (10.135.0.23)
- VM has IP on windows-non-prod CUDN (10.227.128.15)

### What Needs Configuration 🔧
1. Change gateway VM IP from 10.227.128.15 to 10.227.128.1 (preferred gateway IP)
2. Verify IP forwarding and NAT rules are active
3. Update Windows VMs to use gateway IP
4. Test end-to-end connectivity

---

## Option 1: Use Current IP (10.227.128.15) - QUICKEST

### Pros
- No VM reconfiguration needed
- Cloud-init already ran successfully
- IP forwarding and NAT likely already configured

### Cons
- Gateway IP is not the "standard" .1 address
- Less intuitive for documentation

### Steps

1. **Verify gateway VM routing is configured**:
   ```bash
   # Check if cloud-init completed
   oc logs -n windows-non-prod \
     $(oc get pod -n windows-non-prod -l kubevirt.io=virt-launcher,vm.kubevirt.io/name=vpn-gateway -o name) \
     -c compute | grep -A 20 "cloud-init"
   ```

2. **Test gateway connectivity from Windows VM**:
   ```powershell
   # From nymsdv301 console
   Test-NetConnection -ComputerName 10.227.128.15 -InformationLevel Detailed
   ping 10.227.128.15
   ```

3. **Configure Windows VMs to use gateway 10.227.128.15**:
   ```powershell
   # On each Windows VM
   $adapter = (Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Sort-Object ifIndex)[1]
   
   Remove-NetIPAddress -InterfaceAlias $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
   Remove-NetRoute -InterfaceAlias $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
   
   New-NetIPAddress -InterfaceAlias $adapter.Name `
                    -IPAddress "10.227.128.11" `
                    -PrefixLength 21 `
                    -DefaultGateway "10.227.128.15"
   
   # Test
   ping 10.227.128.15
   ping 8.8.8.8
   ```

---

## Option 2: Reconfigure to Use 10.227.128.1 - PREFERRED

### Steps

1. **Access gateway VM console**:
   ```bash
   virtctl console vpn-gateway -n windows-non-prod
   # Login with credentials (password: changethis)
   ```

2. **Reconfigure eth1 IP address**:
   ```bash
   # Remove current IP
   sudo ip addr del 10.227.128.15/21 dev eth1
   
   # Add desired IP
   sudo ip addr add 10.227.128.1/21 dev eth1
   
   # Verify
   ip addr show eth1
   
   # Make persistent
   sudo nmcli con mod "System eth1" ipv4.addresses "10.227.128.1/21"
   sudo nmcli con mod "System eth1" ipv4.method manual
   sudo nmcli con up "System eth1"
   ```

3. **Verify cloud-init configuration ran**:
   ```bash
   # Check if IP forwarding is enabled
   sysctl net.ipv4.ip_forward
   # Should return: net.ipv4.ip_forward = 1
   
   # Check iptables NAT rules
   sudo iptables -t nat -L -n -v | grep 10.227.128
   
   # If not configured, run:
   sudo /usr/local/bin/setup-gateway-routing.sh
   ```

4. **Test gateway connectivity**:
   ```bash
   # From gateway VM
   ping 8.8.8.8  # Internet via eth0
   ping 10.135.0.1  # Pod network
   
   # Check if Windows VMs are reachable
   ping 10.227.128.11  # nymsdv301 (if configured)
   ```

5. **Configure Windows VMs to use gateway 10.227.128.1**:
   ```powershell
   # From each Windows VM console
   # See Windows VM configuration script in next section
   ```

---

## Windows VM Network Configuration

### PowerShell Script for Each Windows VM

```powershell
# Run on EACH Windows VM as Administrator
param(
    [Parameter(Mandatory=$true)]
    [string]$IPAddress,
    [string]$Gateway = "10.227.128.1",  # Or "10.227.128.15" if using Option 1
    [int]$PrefixLength = 21
)

$ErrorActionPreference = 'Stop'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Configuring Windows VM Network" -ForegroundColor Cyan
Write-Host "IP: $IPAddress" -ForegroundColor Cyan
Write-Host "Gateway: $Gateway" -ForegroundColor Cyan
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

# Add new configuration
Write-Host "Adding new configuration..."
New-NetIPAddress -InterfaceAlias $adapter.Name `
                 -IPAddress $IPAddress `
                 -PrefixLength $PrefixLength `
                 -DefaultGateway $Gateway -ErrorAction Stop

Write-Host "`n✓ Configuration applied!" -ForegroundColor Green

# Verify
Write-Host "`nCurrent configuration:" -ForegroundColor Cyan
Get-NetIPAddress -InterfaceAlias $adapter.Name | Format-Table
Get-NetRoute -InterfaceAlias $adapter.Name | Select-Object DestinationPrefix, NextHop | Format-Table

# Test gateway
Write-Host "Testing gateway $Gateway..." -ForegroundColor Cyan
$result = Test-NetConnection -ComputerName $Gateway -InformationLevel Quiet
if ($result) {
    Write-Host "✓ Gateway is reachable!" -ForegroundColor Green
} else {
    Write-Host "✗ Cannot reach gateway" -ForegroundColor Red
}

Write-Host "`nTest external connectivity:" -ForegroundColor Cyan
Write-Host "  ping 8.8.8.8" -ForegroundColor Yellow
Write-Host "========================================`n" -ForegroundColor Cyan
```

### VM-Specific Commands

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

---

## Verification Checklist

### Gateway VM Checks

- [ ] Gateway VM is running
- [ ] eth0 has pod network IP (10.135.0.23)
- [ ] eth1 has CUDN IP (10.227.128.1 or 10.227.128.15)
- [ ] IP forwarding is enabled (`sysctl net.ipv4.ip_forward = 1`)
- [ ] iptables NAT rules are configured
- [ ] Gateway can ping internet (8.8.8.8)
- [ ] Gateway can ping pod network (10.135.0.1)

### Windows VM Checks

- [ ] Windows VM has IP on eth1 (10.227.128.10-14)
- [ ] Windows VM can ping gateway (10.227.128.1 or .15)
- [ ] Windows VM can ping internet (8.8.8.8)
- [ ] Windows VM can ping other Windows VMs
- [ ] Routing table shows default gateway correctly

### End-to-End Checks

- [ ] On-premise can ping Windows VMs (requires VPN routing updates)
- [ ] Windows VMs can reach on-premise resources (requires VPN routing updates)

---

## Quick Verification Commands

```bash
# Check gateway VM status
oc get vm,vmi -n windows-non-prod | grep vpn-gateway

# Get gateway VM IPs
oc get vmi vpn-gateway -n windows-non-prod -o jsonpath='{.status.interfaces[*].ipAddress}'

# Access gateway VM console
virtctl console vpn-gateway -n windows-non-prod

# Inside gateway VM - check status
hostname
ip addr show
ip route show
sysctl net.ipv4.ip_forward
iptables -t nat -L -n -v
ping 8.8.8.8

# From Windows VM (PowerShell)
ipconfig /all
route print
ping 10.227.128.1  # or .15
ping 8.8.8.8
```

---

## Next Steps After Gateway Configuration

1. **Update VPN Configuration** (if using 10.227.128.1):
   - Verify VPN pod can reach gateway pod IP (10.135.0.23)
   - VPN routing should work automatically via pod network

2. **Update AWS Transit Gateway Routes**:
   ```bash
   aws ec2 create-transit-gateway-route \
     --destination-cidr-block 10.227.128.0/21 \
     --transit-gateway-route-table-id tgw-rtb-0ff564f70c91bf1d5 \
     --transit-gateway-attachment-id <vpn-attachment-id> \
     --region us-east-1
   ```

3. **Update Palo Alto Firewall** (on-premise):
   - Add route for 10.227.128.0/21 via VPN tunnel
   - Add firewall policy allowing 10.227.128.0/21 traffic

4. **Test End-to-End Connectivity**:
   - From on-premise: `ping 10.227.128.11`
   - From Windows VM: `ping <on-premise-ip>`

---

## Troubleshooting

### Gateway VM not responding
```bash
# Check if VM is running
oc get vmi vpn-gateway -n windows-non-prod

# Check VM logs
oc logs -n windows-non-prod \
  $(oc get pod -n windows-non-prod -l vm.kubevirt.io/name=vpn-gateway -o name) \
  -c compute

# Restart VM if needed
virtctl restart vpn-gateway -n windows-non-prod
```

### Windows VM cannot reach gateway
```powershell
# Verify adapter is UP
Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }

# Check routing table
route print | findstr 10.227.128

# Verify IP configuration
ipconfig /all

# Test ARP (checks Layer 2 connectivity)
arp -a | findstr 10.227.128
```

### Gateway VM not forwarding packets
```bash
# On gateway VM
# Check forwarding counters
iptables -t nat -L POSTROUTING -n -v
iptables -L FORWARD -n -v

# If counters not increasing, check:
sysctl net.ipv4.ip_forward  # Must be 1
sysctl net.ipv4.conf.all.rp_filter  # Should be 0

# Re-run setup script
/usr/local/bin/setup-gateway-routing.sh
```

---

## Summary

✅ **Gateway VM Successfully Deployed**

**Current Configuration**:
- Gateway VM: vpn-gateway
- Pod Network IP: 10.135.0.23
- CUDN Network IP: 10.227.128.15

**Recommended Next Step**:
Use **Option 1** (10.227.128.15) for quickest deployment, or **Option 2** (10.227.128.1) for standard gateway addressing.

**Priority Tasks**:
1. Verify gateway VM routing configuration
2. Configure one Windows VM as test (nymsdv301)
3. Test connectivity
4. Configure remaining Windows VMs
5. Update VPN/TGW/firewall routing

---

**Document Updated**: 2026-02-12  
**Gateway VM Status**: ✅ Running  
**Next Action**: Configure Windows VM network settings
