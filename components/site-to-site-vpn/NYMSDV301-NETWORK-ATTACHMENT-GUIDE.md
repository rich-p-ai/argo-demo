# NYMSDV301 Secondary Network Attachment Guide

## Current Status

**VM**: NYMSDV301  
**Namespace**: windows-non-prod  
**Target IP**: 10.132.104.11  
**Secondary Network**: windows-non-prod NAD

## Problem

NYMSDV301 completed cold migration successfully but is experiencing network interface conflicts when trying to attach the secondary network (`windows-non-prod`). The error indicates a stale veth interface on the node.

## What We've Done

### 1. Removed Network Resource Limits ✅

Successfully removed the `k8s.v1.cni.cncf.io/resourceName` annotations from all NADs:
- ✅ `openshift-mtv` namespace
- ✅ `vm-migrations` namespace  
- ✅ `windows-non-prod` namespace

This lifted the network attachment limit that was preventing VMs from getting secondary networks.

### 2. Added Secondary Network to VM Spec ✅

Successfully patched the VM to include the secondary network:

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

### 3. Current Issue: Stale Network Interface ⚠️

When the VM tries to start, it fails with:

```
Failed to create pod sandbox: error adding pod to CNI network: 
container veth name provided (pod17d5a8f04ff) already exists
```

This indicates a stale network interface on the worker node from a previous failed start attempt.

## Solutions to Try

### Option 1: Node-Level Cleanup (Requires Node Access)

If you have SSH access to the node `ip-10-227-100-102.ec2.internal`:

```bash
# SSH to the node
oc debug node/ip-10-227-100-102.ec2.internal

# Once in the debug pod
chroot /host

# List network interfaces
ip link show | grep pod17d5a8f04ff

# Delete the stale interface
ip link delete pod17d5a8f04ff

# Exit the debug pod
exit
exit
```

Then restart the VM:

```bash
virtctl stop nymsdv301 -n windows-non-prod --force --grace-period=0
sleep 10
virtctl start nymsdv301 -n windows-non-prod
```

### Option 2: Force VM to Different Node

Modify the VM to schedule on a different node to avoid the stale interface:

```bash
# Get available nodes
oc get nodes -l node-role.kubernetes.io/worker=

# Add node affinity to VM
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

# Restart the VM
virtctl stop nymsdv301 -n windows-non-prod --force --grace-period=0
sleep 10
virtctl start nymsdv301 -n windows-non-prod
```

### Option 3: Wait for Node CNI Cleanup

The Multus CNI may automatically clean up stale interfaces. Wait 5-10 minutes and retry:

```bash
# Stop the VM
virtctl stop nymsdv301 -n windows-non-prod --force --grace-period=0

# Wait 10 minutes for CNI cleanup
sleep 600

# Start the VM
virtctl start nymsdv301 -n windows-non-prod
```

### Option 4: Restart Node CNI (Requires Cluster Admin)

Restart the Multus and OVN-Kubernetes pods on the affected node:

```bash
# Get Multus pod on the node
MULTUS_POD=$(oc get pod -n openshift-multus -o wide | grep ip-10-227-100-102 | awk '{print $1}')

# Delete it (will restart automatically)
oc delete pod $MULTUS_POD -n openshift-multus

# Wait for it to restart
sleep 30

# Try starting the VM again
virtctl start nymsdv301 -n windows-non-prod
```

### Option 5: Temporary Workaround - Use Pod Network Only

If you need the VM running immediately, start it without the secondary network:

```bash
# Remove the secondary network temporarily
oc patch vm nymsdv301 -n windows-non-prod --type='json' \
  -p='[
    {"op": "remove", "path": "/spec/template/spec/domain/devices/interfaces/2"},
    {"op": "remove", "path": "/spec/template/spec/networks/2"}
  ]'

# Start the VM (will only have pod network)
virtctl start nymsdv301 -n windows-non-prod
```

Then add the secondary network back later after node cleanup.

## Monitoring Commands

```bash
# Check VM status
oc get vm nymsdv301 -n windows-non-prod

# Check VMI status and IPs
oc get vmi nymsdv301 -n windows-non-prod -o wide

# Check pod status
oc get pods -n windows-non-prod | grep nymsdv301

# Check for errors
oc describe vmi nymsdv301 -n windows-non-prod | tail -50

# Check pod events
POD_NAME=$(oc get pods -n windows-non-prod | grep "virt-launcher-nymsdv301" | awk '{print $1}')
oc describe pod $POD_NAME -n windows-non-prod | grep -A20 "Events:"
```

## After Successful Start

Once the VM starts successfully with the secondary network attached, configure the static IP:

### 1. Get the Assigned IP

```bash
oc get vmi nymsdv301 -n windows-non-prod -o jsonpath='{.status.interfaces[*].ipAddress}' | tr ' ' '\n'
```

You should see two IPs:
- Pod network IP (10.132.x.x)
- Secondary network IP (10.132.104.x - dynamic from Whereabouts)

### 2. Configure Static IP 10.132.104.11

RDP into the VM and run PowerShell as Administrator:

```powershell
# Identify the secondary network adapter (usually "Ethernet 2" or similar)
Get-NetAdapter

# Set static IP on the secondary adapter
# Replace "Ethernet 2" with actual adapter name
New-NetIPAddress -InterfaceAlias "Ethernet 2" `
  -IPAddress 10.132.104.11 `
  -PrefixLength 22 `
  -DefaultGateway 10.132.104.1

# Set DNS servers
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

### 3. Test Connectivity

From your workstation on the Canon network:

```bash
# Test ping
ping 10.132.104.11

# Test RDP
mstsc /v:10.132.104.11
```

## Next Steps

1. Resolve the network interface conflict using one of the options above
2. Start NYMSDV301 successfully with secondary network
3. Configure static IP 10.132.104.11 inside the VM
4. Enable Windows Firewall rules for RDP and ping
5. Update DNS records for NYMSDV301.corp.example.com → 10.132.104.11
6. Perform end-to-end RDP testing

## Files Created

- `c:\Users\q22529_a\work\Cluster-Config\components\mtv-target-network\nad-vm-migration-bridge.yaml` - Updated to remove resource limits
- `c:\Users\q22529_a\work\Cluster-Config\components\site-to-site-vpn\HOW-TO-INCREASE-NETWORK-LIMIT.md` - Detailed guide
- `c:\Users\q22529_a\work\Cluster-Config\components\site-to-site-vpn\NETWORK-LIMIT-FINAL-SUMMARY.md` - Summary
