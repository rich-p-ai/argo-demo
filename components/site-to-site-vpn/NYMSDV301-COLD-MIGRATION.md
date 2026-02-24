# NYMSDV301 Migration Issue & Resolution

**Status**: ⚠️ **WARM MIGRATION FAILED - SWITCHED TO COLD MIGRATION**  
**Issue Occurred**: February 10, 2026 at ~19:57 UTC  
**Current Solution**: Cold migration in progress  

---

## Issue Summary

### Original Error
```
Phase: DiskTransfer
Error: Unable to connect to vddk data source: no snapshots for this VM
```

### Root Cause
The warm migration failed because VMware snapshot operations encountered an issue. This typically happens when:
1. The VM was powered on/off in vSphere during migration setup
2. VMware snapshot consolidation occurred
3. Snapshot chain became invalid

---

## Resolution Applied

### Solution: Switch to Cold Migration

**What Changed:**
- Changed from `warm: true` to `warm: false` in migration plan
- Cold migration will power off the VM in vSphere
- No snapshot required - direct disk transfer
- More reliable but VM will be offline during migration

### Actions Taken
1. Deleted failed warm migration: `nymsdv301-remigration-4gtpl`
2. Deleted and recreated plan with `warm: false`
3. Started new migration: `nymsdv301-cold-migration-5jnzl`

---

## Current Migration Status

| Parameter | Value |
|-----------|-------|
| **Migration Name** | `nymsdv301-cold-migration-5jnzl` |
| **Plan Name** | `nymsdv301-remigration` |
| **Migration Type** | **Cold (VM will be powered off)** |
| **Source VM ID** | `vm-5966` |
| **Target VM Name** | `nymsdv301` |
| **Target Namespace** | `windows-non-prod` |
| **Static IP** | **10.132.104.11** (reserved) |
| **Status** | 🔄 Running (Initialize/DiskTransfer phase) |

---

## Cold Migration vs Warm Migration

| Aspect | Warm Migration | Cold Migration |
|--------|----------------|----------------|
| **Downtime** | Minimal (~2-5 min cutover) | Full migration time (~30-45 min) |
| **VM Power State** | Stays powered on | **Powered off during migration** |
| **Snapshots** | Required | **Not required** ✅ |
| **Reliability** | More complex | **More reliable** ✅ |
| **Use Case** | Production VMs | Dev/Test VMs ✅ |

**For NYMSDV301**: Cold migration is acceptable since this is a dev/test environment.

---

## Monitor Cold Migration Progress

### Quick Status Check
```bash
# Check overall status
oc get migration nymsdv301-cold-migration-5jnzl -n openshift-mtv

# Detailed pipeline view
oc get migration nymsdv301-cold-migration-5jnzl -n openshift-mtv \
  -o jsonpath='{.status.vms[0]}' | jq '{phase, pipeline: [.pipeline[] | {name, phase, progress}]}'

# Check for completion
oc get migration nymsdv301-cold-migration-5jnzl -n openshift-mtv \
  -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}'
```

### Expected Pipeline (Cold Migration)
```
✅ Initialize
🔄 DiskTransfer (0 → 122,880 MB) - ~20-25 minutes
✅ ImageConversion - ~10-15 minutes  
✅ VirtualMachineCreation - ~1 minute
```

**Note**: No "Cutover" phase in cold migration (only used in warm migrations)

---

## Expected Timeline

- **Started**: ~20:04 UTC
- **DiskTransfer**: ~20:05-20:30 UTC (25 minutes)
- **ImageConversion**: ~20:30-20:45 UTC (15 minutes)
- **Completion**: ~20:45-20:50 UTC

**Total Duration**: ~40-45 minutes

---

## NYMSDV297 Status (For Comparison)

The NYMSDV297 warm migration is still running successfully:

```bash
# Check NYMSDV297 status
oc get migration nymsdv297-remigration-r8xn8 -n openshift-mtv
```

NYMSDV297 should complete around 20:10-20:20 UTC (warm migration works for that VM).

---

## Post-Migration Steps (Same as Before)

Once NYMSDV301 migration completes:

### 1. Configure Static IP

```bash
cd /c/Users/q22529_a/work/Cluster-Config/components/site-to-site-vpn

# Apply cloud-init for static IP 10.132.104.11
./add-static-ip-to-vm.sh nymsdv301 10.132.104.11

# Start VM
oc patch vm nymsdv301 -n windows-non-prod --type merge \
  -p '{"spec":{"runStrategy":"Always"}}'
```

### 2. Verify IP

```bash
# Check IP assignment (should show 10.132.104.11)
oc get vmi nymsdv301 -n windows-non-prod \
  -o jsonpath='{.status.interfaces[0].ipAddress}'
```

### 3. Test Connectivity

```bash
# From company network
ping 10.132.104.11
mstsc /v:10.132.104.11
```

---

## Troubleshooting

### If Cold Migration Also Fails

Check error details:
```bash
oc get migration nymsdv301-cold-migration-5jnzl -n openshift-mtv \
  -o jsonpath='{.status.vms[0].pipeline[]}' | jq 'select(.error != null)'
```

### Common Cold Migration Issues

1. **Disk transfer timeout**: Increase timeout or retry
2. **Storage provisioning failure**: Check PVC status
3. **Image conversion failure**: Check virt-v2v logs

### Check PVCs
```bash
# List PVCs for NYMSDV301
oc get pvc -n windows-non-prod | grep -i nymsdv301
```

---

## Why Cold Migration Works Better Here

### Advantages for This Scenario:
1. ✅ **No snapshot dependency** - Avoids snapshot chain issues
2. ✅ **Simpler workflow** - Fewer moving parts
3. ✅ **More reliable** - Direct disk copy without delta tracking
4. ✅ **Fresh data capture** - Gets latest data at power-off time

### Trade-off:
- ⚠️ **VM will be offline** during migration (~40-45 minutes)
- For dev/test environment, this is acceptable

---

## Updated Plan File

The plan file has been updated:
```
File: nymsdv301-remigration-plan.yaml
Change: warm: true → warm: false
```

This ensures future migrations of NYMSDV301 use cold migration by default.

---

## Summary

| Item | Status |
|------|--------|
| **Issue** | ✅ Identified (snapshot failure) |
| **Solution** | ✅ Applied (cold migration) |
| **Migration** | 🔄 In Progress |
| **Static IP** | ✅ Reserved (10.132.104.11) |
| **ETA** | ~20:45-20:50 UTC |

---

## Next Steps

1. **Wait for migration to complete** (~40-45 minutes from 20:04 UTC)
2. **Monitor progress** using commands above
3. **Configure static IP** once complete
4. **Start VM and test RDP** from company network

---

**Last Updated**: February 10, 2026 at 20:05 UTC  
**Current Phase**: DiskTransfer (cold migration)  
**Action Required**: None - migration is progressing automatically

🔄 **Cold migration in progress - VM will be offline until complete**
