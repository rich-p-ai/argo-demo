# NYMSDV301 - How to Attach Second Network

## Quick Answer

**The secondary network has already been added to NYMSDV301**, but there's a persistent stale network interface issue on node `ip-10-227-100-102.ec2.internal` preventing the VM from starting.

## What's Been Done

### 1. Network Limits Removed ✅
Successfully removed `k8s.v1.cni.cncf.io/resourceName` annotations from all NetworkAttachmentDefinitions to lift the resource limit.

### 2. Secondary Network Added to VM ✅
The VM configuration has been successfully updated with:

```bash
oc patch vm nymsdv301 -n windows-non-prod --type='json' \
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
```

**Result**: The VM now has the secondary network configured and should get IP 10.132.104.11.

### 3. Current Blocker: Stale Network Interface

The VM is stuck in "Scheduling" state because of a stale veth interface (`pod17d5a8f04ff`) on the worker node from previous failed start attempts.

**Error**: 
```
failed to configure pod interface: container veth name provided (pod17d5a8f04ff) already exists
```

## Solutions (Try in Order)

###  **OPTION 1: Schedule VM on Different Node** (RECOMMENDED)

Force the VM to a different worker node to avoid the stale interface:

```bash
# Stop the VM first
virtctl stop nymsdv301 -n windows-non-prod --force --grace-period=0

# Wait for it to fully stop
sleep 15

# Get list of available nodes (excluding the problematic one)
oc get nodes -l node-role.kubernetes.io/worker= | grep -v ip-10-227-100-102

# Add node anti-affinity to avoid the problematic node
oc patch vm nymsdv301 -n windows-non-prod --type='json' \
  -p='[{
    "op": "add",
    "path": "/spec/template/spec/affinity",
    "value": {
      "nodeAffinity": {
        "requiredDuringSchedulingIgnoredDuringExecution": {
          "nodeSelectorTerms": [{
            "matchExpressions": [{
              "key": "kubernetes.io/hostname",
              "operator": "NotIn",
              "values": ["ip-10-227-100-102.ec2.internal"]
            }]
          }]
        }
      }
    }
  }]'

# Start the VM
virtctl start nymsdv301 -n windows-non-prod

# Monitor startup
watch "oc get vmi nymsdv301 -n windows-non-prod"
```

### **OPTION 2: Clean Stale Interface via Debug Pod**

If you have PowerShell or Linux terminal (not Git Bash):

```bash
# Create a debug pod on the node
oc debug node/ip-10-227-100-102.ec2.internal

# Inside the debug pod, run:
chroot /host

# Check for the stale interface
ip link show | grep pod17d5a8f04ff

# Delete it
ip link delete pod17d5a8f04ff

# Exit
exit
exit

# Now start the VM
virtctl start nymsdv301 -n windows-non-prod
```

### **OPTION 3: Wait for Automatic Cleanup**

CNI may automatically clean up stale interfaces. We've already restarted the Multus pods. Wait 10-15 minutes:

```bash
# Stop the VM
virtctl stop nymsdv301 -n windows-non-prod --force --grace-period=0

# Wait 15 minutes
# (Go get coffee)

# Try starting again
virtctl start nymsdv301 -n windows-non-prod
```

### **OPTION 4: Temporary - Remove Secondary Network**

If you need NYMSDV301 running immediately for testing (pod network only):

```bash
# Remove secondary network temporarily
oc patch vm nymsdv301 -n windows-non-prod --type='json' \
  -p='[
    {"op": "remove", "path": "/spec/template/spec/domain/devices/interfaces/2"},
    {"op": "remove", "path": "/spec/template/spec/networks/2"}
  ]'

# Start VM (will only have pod network IP)
virtctl start nymsdv301 -n windows-non-prod
```

**Note**: You'll need to add the secondary network back later when the node issue is resolved.

## After VM Starts Successfully

Once NYMSDV301 is running with the secondary network:

### 1. Verify Network Attachment

```bash
# Check VM has two IPs
oc get vmi nymsdv301 -n windows-non-prod -o jsonpath='{.status.interfaces[*].ipAddress}' | tr ' ' '\n'
```

Expected output:
- `10.132.0.xxx` (pod network)
- `10.132.104.xxx` (secondary network - dynamic IP from Whereabouts)

### 2. Configure Static IP 10.132.104.11

RDP into the VM using the pod network IP, then run PowerShell as Administrator:

```powershell
# Identify adapters
Get-NetAdapter

# The secondary network will be "Ethernet 2" or similar
# Set static IP
New-NetIPAddress -InterfaceAlias "Ethernet 2" `
  -IPAddress 10.132.104.11 `
  -PrefixLength 22 `
  -DefaultGateway 10.132.104.1

# Set DNS
Set-DnsClientServerAddress -InterfaceAlias "Ethernet 2" `
  -ServerAddresses ("10.132.104.2", "10.132.104.3")

# Add routes
New-NetRoute -InterfaceAlias "Ethernet 2" `
  -DestinationPrefix "10.132.0.0/14" `
  -NextHop 10.132.104.1

New-NetRoute -InterfaceAlias "Ethernet 2" `
  -DestinationPrefix "10.227.96.0/20" `
  -NextHop 10.132.104.1

# Enable RDP firewall rule
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

# Enable ping
Enable-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)"
```

### 3. Test from Canon Network

```bash
# Test ping
ping 10.132.104.11

# Test RDP
mstsc /v:10.132.104.11
```

## Current Status

- ✅ Network resource limits removed
- ✅ Secondary network added to VM spec
- ⚠️  VM cannot start due to stale interface on node `ip-10-227-100-102.ec2.internal`
- 🔄 Multus CNI pods restarted (may take time to clean up)
- 📋 Need to try Option 1 (move to different node) or Option 2 (manual cleanup)

## Monitoring Commands

```bash
# VM status
oc get vm nymsdv301 -n windows-non-prod

# VMI status
oc get vmi nymsdv301 -n windows-non-prod

# Pod status
oc get pods -n windows-non-prod | grep nymsdv301

# Check for errors
oc describe vmi nymsdv301 -n windows-non-prod | tail -30

# Pod events
POD=$(oc get pods -n windows-non-prod | grep virt-launcher-nymsdv301 | awk '{print $1}')
oc get events -n windows-non-prod --field-selector involvedObject.name=$POD --sort-by='.lastTimestamp' | tail -10
```

## Recommended Next Step

**Try OPTION 1** - Schedule VM on a different node. This is the quickest solution that doesn't require debugging node networking issues.

```bash
# Stop current attempt
virtctl stop nymsdv301 -n windows-non-prod --force --grace-period=0

# Add node anti-affinity
oc patch vm nymsdv301 -n windows-non-prod --type='json' \
  -p='[{
    "op": "add",
    "path": "/spec/template/spec/affinity",
    "value": {
      "nodeAffinity": {
        "requiredDuringSchedulingIgnoredDuringExecution": {
          "nodeSelectorTerms": [{
            "matchExpressions": [{
              "key": "kubernetes.io/hostname",
              "operator": "NotIn",
              "values": ["ip-10-227-100-102.ec2.internal"]
            }]
          }]
        }
      }
    }
  }]'

# Start on different node
virtctl start nymsdv301 -n windows-non-prod
```

This should allow the VM to start successfully on a different node without the stale interface issue.
