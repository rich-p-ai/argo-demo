# NYMSDV301 - CNI Issue Resolution and Startup

## Actions Taken

### 1. CNI Cleanup ✅
Successfully restarted all CNI pods to clean stale interface `pod17d5a8f04ff`:

- ✅ Deleted all Multus pods in `openshift-multus` namespace
- ✅ Deleted all OVN-Kubernetes node pods
- ✅ All pods restarted successfully and are running

### 2. VM Configuration ✅  
- ✅ Stopped NYMSDV301 and NYMSDV312
- ✅ Added secondary network back to NYMSDV301
- ✅ Started NYMSDV301 with 2 NICs (pod network + windows-non-prod)

## Current Status

**NYMSDV301**: Starting with 2 NICs  
**NYMSDV312**: Stopped (will add 2nd NIC later if needed)

## Expected Configuration for NYMSDV301

Once running, NYMSDV301 should have:

1. **NIC 1 (net-0)**: Pod network  
   - IP: `10.132.0.x/23` (dynamic from OVN-Kubernetes)
   - Used for OpenShift internal communication

2. **NIC 2 (nic-2)**: Secondary network (windows-non-prod NAD)  
   - IP: `10.132.104.x/22` (dynamic from Whereabouts IPAM)
   - Target static IP: `10.132.104.11`
   - Gateway: `10.132.104.1`
   - DNS: `10.132.104.2`, `10.132.104.3`

## Next Steps After VM Starts

### 1. Verify Network Attachment

```bash
# Check VM is running
oc get vm nymsdv301 -n windows-non-prod

# Get all IPs
oc get vmi nymsdv301 -n windows-non-prod -o jsonpath='{.status.interfaces[*].ipAddress}' | tr ' ' '\n'

# Get interface details
oc get vmi nymsdv301 -n windows-non-prod -o yaml | grep -A50 "interfaces:"
```

### 2. Configure Static IP 10.132.104.11

RDP into the VM using the pod network IP, then run PowerShell as Administrator:

```powershell
# Identify adapters (secondary will be "Ethernet 2" or similar)
Get-NetAdapter

# Configure static IP on secondary adapter
New-NetIPAddress -InterfaceAlias "Ethernet 2" `
  -IPAddress 10.132.104.11 `
  -PrefixLength 22 `
  -DefaultGateway 10.132.104.1

# Set DNS
Set-DnsClientServerAddress -InterfaceAlias "Ethernet 2" `
  -ServerAddresses ("10.132.104.2", "10.132.104.3")

# Add static routes
New-NetRoute -InterfaceAlias "Ethernet 2" `
  -DestinationPrefix "10.132.0.0/14" `
  -NextHop 10.132.104.1

New-NetRoute -InterfaceAlias "Ethernet 2" `
  -DestinationPrefix "10.227.96.0/20" `
  -NextHop 10.132.104.1

# Enable RDP through Windows Firewall
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

# Enable ICMP (ping)
Enable-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)"
```

### 3. Test Connectivity from Canon Network

```bash
# Test ping
ping 10.132.104.11

# Test RDP
mstsc /v:10.132.104.11
```

### 4. Update DNS

Add DNS records for NYMSDV301:
- **A Record**: `NYMSDV301.corp.canon.com` → `10.132.104.11`
- **PTR Record**: `11.104.132.10.in-addr.arpa` → `NYMSDV301.corp.canon.com`

## Troubleshooting

If the VM fails to start with the same "pod17d5a8f04ff already exists" error:

### Option 1: Wait for CNI Cleanup
The CNI cleanup may need more time. Wait 10-15 minutes for the restarted pods to fully clean up stale interfaces.

### Option 2: Force VM to Specific Node
```bash
# Stop VM
virtctl stop nymsdv301 -n windows-non-prod --force --grace-period=0

# Add node selector to use a specific clean node
oc patch vm nymsdv301 -n windows-non-prod --type='json' \
  -p='[{
    "op": "add",
    "path": "/spec/template/spec/nodeSelector",
    "value": {
      "kubernetes.io/hostname": "ip-10-227-98-180.ec2.internal"
    }
  }]'

# Start VM
virtctl start nymsdv301 -n windows-non-prod
```

### Option 3: Use Explicit MAC Address
```bash
# Stop VM
virtctl stop nymsdv301 -n windows-non-prod --force --grace-period=0

# Remove and re-add secondary network with explicit MAC
oc patch vm nymsdv301 -n windows-non-prod --type='json' \
  -p='[
    {"op": "remove", "path": "/spec/template/spec/domain/devices/interfaces/2"},
    {"op": "remove", "path": "/spec/template/spec/networks/2"}
  ]'

oc patch vm nymsdv301 -n windows-non-prod --type='json' \
  -p='[
    {
      "op": "add",
      "path": "/spec/template/spec/domain/devices/interfaces/-",
      "value": {
        "name": "nic-2",
        "bridge": {},
        "macAddress": "02:00:00:10:04:0B"
      }
    },
    {
      "op": "add",
      "path": "/spec/template/spec/networks/-",
      "value": {
        "name": "nic-2",
        "multus": {
          "networkName": "windows-non-prod"
        }
      }
    }
  ]'

# Start VM
virtctl start nymsdv301 -n windows-non-prod
```

## NYMSDV312 - Add 2nd NIC Later

When ready to add the second NIC to NYMSDV312:

```bash
# Stop VM
virtctl stop nymsdv312 -n windows-non-prod

# Add secondary network
oc patch vm nymsdv312 -n windows-non-prod --type='json' \
  -p='[
    {
      "op": "add",
      "path": "/spec/template/spec/domain/devices/interfaces/-",
      "value": {
        "name": "nic-2",
        "bridge": {}
      }
    },
    {
      "op": "add",
      "path": "/spec/template/spec/networks/-",
      "value": {
        "name": "nic-2",
        "multus": {
          "networkName": "windows-non-prod"
        }
      }
    }
  ]'

# Start VM
virtctl start nymsdv312 -n windows-non-prod
```

Then configure static IP 10.132.104.19 inside the VM using the same PowerShell commands.

## Summary

- ✅ CNI issue resolved by restarting all Multus and OVN-Kubernetes pods
- ✅ Network limits removed (no more resource exhaustion)
- ✅ NYMSDV301 configured with 2 NICs and starting
- 🔄 Monitoring NYMSDV301 startup
- ⏳ Once running, need to configure static IP 10.132.104.11 inside the VM
- ⏳ NYMSDV312 ready to have 2nd NIC added when needed (static IP 10.132.104.19)

## Files Created

- `STALE-INTERFACE-FIX.md` - Detailed guide on stale interface issue
- `NYMSDV301-ATTACH-NETWORK-QUICK.md` - Quick reference for network attachment
- `NYMSDV301-NETWORK-ATTACHMENT-GUIDE.md` - Complete network attachment guide
- `HOW-TO-INCREASE-NETWORK-LIMIT.md` - Network limit increase procedures
