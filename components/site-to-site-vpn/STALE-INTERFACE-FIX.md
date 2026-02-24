# NYMSDV301 & NYMSDV312 - Stale Interface Resolution

## Problem

Both NYMSDV301 and NYMSDV312 cannot start with the secondary network attached due to a persistent stale network interface error:

```
failed to configure pod interface: container veth name provided (pod17d5a8f04ff) already exists
```

This interface appears to be stuck in the CNI/Multus configuration and is affecting VMs across multiple nodes.

## Immediate Solution: Start VMs Without Secondary Network

### Step 1: Stop Both VMs

```bash
# Stop NYMSDV301
virtctl stop nymsdv301 -n windows-non-prod --force --grace-period=0

# Stop NYMSDV312  
virtctl stop nymsdv312 -n windows-non-prod --force --grace-period=0

# Wait for them to stop
sleep 15
```

### Step 2: Remove Secondary Network Temporarily

```bash
# Remove secondary network from NYMSDV301
oc patch vm nymsdv301 -n windows-non-prod --type='json' \
  -p='[
    {"op": "remove", "path": "/spec/template/spec/domain/devices/interfaces/2"},
    {"op": "remove", "path": "/spec/template/spec/networks/2"}
  ]'

# Remove secondary network from NYMSDV312
oc patch vm nymsdv312 -n windows-non-prod --type='json' \
  -p='[
    {"op": "remove", "path": "/spec/template/spec/domain/devices/interfaces/1"},
    {"op": "remove", "path": "/spec/template/spec/networks/1"}
  ]'
```

### Step 3: Start VMs (Pod Network Only)

```bash
# Start NYMSDV301
virtctl start nymsdv301 -n windows-non-prod

# Start NYMSDV312
virtctl start nymsdv312 -n windows-non-prod

# Monitor startup
watch "oc get vmi -n windows-non-prod"
```

**Result**: VMs will start successfully with only the pod network (10.132.0.x/23 range).

## Root Cause Analysis

The stale interface `pod17d5a8f04ff` is likely from a previous VM (possibly an old NYMSDV301 migration attempt) that didn't clean up properly. This interface name is being reused or referenced in the CNI configuration.

## Permanent Fix Options

### Option 1: Clean Up Stale Interface Across All Nodes (Requires Cluster Admin)

Run on **each worker node** that might have the stale interface:

```bash
# For each worker node
for NODE in $(oc get nodes -l node-role.kubernetes.io/worker= -o name | cut -d/ -f2); do
  echo "=== Cleaning node: $NODE ==="
  oc debug node/$NODE -- chroot /host /bin/bash -c \
    "ip link show | grep -q pod17d5a8f04ff && ip link delete pod17d5a8f04ff || echo 'Interface not found on this node'"
done
```

### Option 2: Restart Multus/CNI on All Nodes

```bash
# Restart Multus pods on all nodes
oc delete pods -n openshift-multus --all

# Wait for them to come back
sleep 60
oc get pods -n openshift-multus
```

### Option 3: Use Different MAC Addresses

When re-adding the secondary network, specify explicit MAC addresses to avoid conflicts:

```bash
# For NYMSDV301 - with specific MAC
oc patch vm nymsdv301 -n windows-non-prod --type='json' \
  -p='[
    {
      "op": "add",
      "path": "/spec/template/spec/domain/devices/interfaces/-",
      "value": {
        "name": "nic-2",
        "bridge": {},
        "macAddress": "02:00:00:10:41:01"
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

# For NYMSDV312 - with specific MAC  
oc patch vm nymsdv312 -n windows-non-prod --type='json' \
  -p='[
    {
      "op": "add",
      "path": "/spec/template/spec/domain/devices/interfaces/-",
      "value": {
        "name": "nic-2",
        "bridge": {},
        "macAddress": "02:00:00:10:41:02"
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

## Recommended Action Plan

1. **Immediate (5 minutes)**: 
   - Remove secondary networks from both VMs
   - Start VMs with pod network only
   - Verify VMs are accessible via pod network IPs

2. **Short-term (30 minutes)**:
   - Contact cluster admin to clean up `pod17d5a8f04ff` interface across all nodes
   - OR restart all Multus pods cluster-wide

3. **Re-enable Secondary Networks (after cleanup)**:
   - Stop VMs
   - Add secondary networks back (with explicit MAC addresses)
   - Start VMs
   - Configure static IPs inside VMs

## Current Status

- ✅ Secondary network added to NYMSDV301 spec
- ✅ Secondary network added to NYMSDV312 spec
- ❌ VMs cannot start due to stale CNI interface
- 🔧 Need to temporarily remove secondary networks to unblock

## Alternative: Use Pod Network IPs Temporarily

If you need immediate access to the VMs:

1. Start VMs without secondary network (pod network only)
2. Use pod network IPs for RDP access temporarily:
   - These IPs are routable within the OpenShift cluster
   - May not be directly accessible from Canon network depending on VPN routing
3. Add secondary networks back once CNI issue is resolved

## Files for Reference

- `NYMSDV301-ATTACH-NETWORK-QUICK.md` - Full troubleshooting guide
- `NYMSDV301-NETWORK-ATTACHMENT-GUIDE.md` - Detailed network attachment guide
