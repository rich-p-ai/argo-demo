# Network Limit Investigation - Final Summary

**Date**: February 10, 2026  
**Issue**: Cannot add secondary network to NYMSDV301  
**Root Cause**: Multiple factors - resource limits + network configuration issues  

---

## What We Discovered

### 1. Resource Limit Exists
The `k8s.v1.cni.cncf.io/resourceName` annotations on NADs create countable Kubernetes resources that limit network attachments.

**Found on NADs**:
- `openshift-mtv`: `bridge.network.kubevirt.io/br-windows` 
- `vm-migrations`: `bridge.network.kubevirt.io/br-windows`
- `windows-non-prod`: `openshift.io/windows-non-prod` (removed)

### 2. Annotations Keep Coming Back
The NADs in `openshift-mtv` and `vm-migrations` namespaces appear to be managed by ArgoCD or another controller, causing the resourceName annotation to be re-applied after removal.

### 3. Network Configuration Conflict
When trying to add the secondary network, encountered:
```
failed to configure pod interface: container veth name provided (pod17d5a8f04ff) already exists
```

This indicates a deeper networking issue with interface creation.

---

## Attempted Solutions

### ✅ Removed Resource Limit (Partially)
```bash
# Successfully removed from windows-non-prod namespace
oc annotate network-attachment-definitions windows-non-prod \
  -n windows-non-prod \
  k8s.v1.cni.cncf.io/resourceName-
```

### ⚠️ Resource Limits in Other Namespaces Persist
The `openshift-mtv` and `vm-migrations` NADs are being managed by a controller (likely ArgoCD) and the annotation keeps being re-applied.

### ❌ Network Sandbox Creation Fails
Even after removing limits, the pod fails to create network sandbox due to veth interface conflicts.

---

## Actual Root Cause

The issue is **NOT just the resource limit**. There are two problems:

1. **Resource Exhaustion**: Too many VMs using the `bridge.network.kubevirt.io/br-windows` resource
2. **Network Configuration**: The bridge-based network configuration has hit a limit or has conflicts

---

## Working Solutions

### Solution 1: Use Pod Network Only (Current State)

NYMSDV301 is running successfully with pod network:
- ✅ VM is functional
- ✅ Can access via console
- ✅ Migration data intact
- ❌ Not reachable from company network

```bash
# VM is already running this way
oc get vmi nymsdv301 -n windows-non-prod
# IP: 10.132.0.204 (pod network)
```

**Access Methods**:
```bash
# Console access
virtctl console nymsdv301 -n windows-non-prod

# Port-forward RDP (from bastion/jumpbox with oc access)
virtctl port-forward vm/nymsdv301 -n windows-non-prod 3389:3389
# Then: mstsc /v:localhost:3389
```

### Solution 2: Stop Another VM Temporarily

Free up a network resource slot by stopping a less critical VM:

```bash
# Example: Stop nymsdv217 temporarily
oc patch vm nymsdv217 -n windows-non-prod --type merge -p '{"spec":{"runStrategy":"Halted"}}'

# Wait for it to stop
sleep 30

# Then try adding network to nymsdv301
./add-network-nymsdv301.sh
```

### Solution 3: Modify ArgoCD/GitOps Configuration

The proper long-term fix is to modify the source of truth for the NADs:

1. **Find the GitOps repo** that manages these NADs
2. **Edit the NAD manifests** to remove `k8s.v1.cni.cncf.io/resourceName` annotations
3. **Commit and sync** via ArgoCD

**Check ArgoCD apps**:
```bash
# Find which ArgoCD app manages these NADs
oc get applications -n openshift-gitops | grep -i network

# Get the app details
oc get application <app-name> -n openshift-gitops -o yaml
```

### Solution 4: Use OVN-Kubernetes Network Instead of Bridge

The current NADs use bridge mode which has resource limits. Consider switching to OVN-K8s overlay:

**Create a new NAD without bridge resource**:
```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: windows-non-prod-overlay
  namespace: windows-non-prod
  # NO resourceName annotation
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "type": "ovn-k8s-cni-overlay",
      "name": "windows-non-prod-overlay",
      "netAttachDefName": "windows-non-prod/windows-non-prod-overlay",
      "subnets": "10.132.104.0/22",
      "mtu": 1400,
      "ipam": {
        "type": "whereabouts",
        "range": "10.132.104.0/22",
        "range_start": "10.132.104.50",
        "range_end": "10.132.107.254",
        "gateway": "10.132.104.1",
        "exclude": ["10.132.104.1/32", "10.132.104.2/32", "10.132.104.3/32"]
      }
    }
```

Then use this NAD for new VMs.

---

## Recommended Path Forward

### Short Term (Immediate)

**Option A**: Keep nymsdv301 on pod network only
- ✅ VM is working
- ✅ Can verify functionality via console
- ❌ Cannot test from company network

**Option B**: Stop nymsdv217 or another non-critical VM
- Free up network resource slot
- Add network to nymsdv301
- Test from company network
- Restart the stopped VM later

### Long Term (Proper Fix)

1. **Work with Platform/GitOps team** to:
   - Remove resourceName annotations from NAD source definitions
   - OR increase the bridge resource capacity
   - OR migrate to OVN-K8s overlay networks (no resource limits)

2. **Investigate bridge network limits**:
   ```bash
   # Check bridge configuration
   oc get network.operator.openshift.io cluster -o yaml
   
   # Check CNV/OpenShift Virtualization config
   oc get hyperconverged -n openshift-cnv -o yaml
   ```

3. **Consider network architecture changes**:
   - Move from bridge-based to overlay-based networking
   - Use ClusterUserDefinedNetwork (CUDN) for better scalability
   - Implement network segmentation differently

---

## Current VM Status Summary

| VM | Network | IP | Company Access | Status |
|----|---------|----|--------------| -------|
| **nymsdv297** | Cold migration running | TBD | ⏳ Pending | Migrating |
| **nymsdv301** | Pod only | 10.132.0.204 | ❌ No | ✅ Running |
| **nymsdv312** | Pod only | 10.132.0.178 | ❌ No | ✅ Running |
| **Others** | Bridge network | 10.132.104.x | ✅ Yes | ✅ Running |

---

## Next Steps

### Immediate Action Needed

**Decision Point**: Choose one:

1. **Accept pod network for now**
   - nymsdv301 works via console/port-forward
   - No company network access
   - No changes needed

2. **Stop another VM temporarily**
   - Free up network resource
   - Add network to nymsdv301
   - Test company access
   - Restart stopped VM

3. **Escalate to platform team**
   - Request proper fix to resource limits
   - Modify GitOps/ArgoCD configurations
   - Long-term solution

### Commands for Option 2

```bash
# Stop nymsdv217 (or choose another)
oc patch vm nymsdv217 -n windows-non-prod --type merge -p '{"spec":{"runStrategy":"Halted"}}'

# Wait
sleep 60

# Add network to nymsdv301
cd /c/Users/q22529_a/work/Cluster-Config/components/site-to-site-vpn
./add-network-nymsdv301.sh

# Test from company network
ping 10.132.104.11
mstsc /v:10.132.104.11

# Later, restart nymsdv217
oc patch vm nymsdv217 -n windows-non-prod --type merge -p '{"spec":{"runStrategy":"Always"}}'
```

---

## Files Created

| File | Purpose |
|------|---------|
| `HOW-TO-INCREASE-NETWORK-LIMIT.md` | Detailed guide on limit increases |
| `NETWORK-LIMIT-FINAL-SUMMARY.md` | This document |
| `remove-network-limits.sh` | Script to remove resourceName annotations |
| `add-network-nymsdv301.sh` | Script to configure network |

---

**Status**: Blocked by network resource limits + configuration issues  
**VM Functional**: ✅ Yes (pod network)  
**Company Access**: ❌ Not yet (requires network resource slot)  
**Workaround Available**: ✅ Yes (stop another VM or use port-forward)
