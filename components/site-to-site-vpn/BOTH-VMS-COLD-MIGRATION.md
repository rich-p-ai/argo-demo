# Both VMs - Cold Migration Status

**Status**: ✅ **BOTH VMs NOW USING COLD MIGRATION**  
**Updated**: February 10, 2026 at ~20:08 UTC  
**Migration Type**: Cold (VMs powered off during migration)  

---

## Active Migrations Summary

| VM | Migration Name | Started | Phase | Progress | Static IP | ETA |
|----|----------------|---------|-------|----------|-----------|-----|
| **NYMSDV297** | nymsdv297-cold-migration-vj5g4 | ~20:08 UTC | ImageConversion | 🔄 Running | 10.132.104.10 | ~20:45 UTC |
| **NYMSDV301** | nymsdv301-cold-migration-5jnzl | ~20:04 UTC | DiskTransferV2v | 🔄 Running | 10.132.104.11 | ~20:45 UTC |

---

## NYMSDV297 Current Status

### Migration Details
- **Migration**: `nymsdv297-cold-migration-vj5g4`
- **Plan**: `nymsdv297-remigration`
- **VM ID**: `vm-10070`
- **Disk Size**: 138,240 MB (~135 GB)
- **Started**: ~20:08 UTC

### Pipeline Progress
```
✅ Initialize            - Completed
✅ DiskAllocation        - Completed (138,240 / 138,240 MB)
🔄 ImageConversion       - Running (Converting to KubeVirt format)
⏳ DiskTransferV2v       - Pending
⏳ VirtualMachineCreation - Pending
```

**Current Phase**: ConvertGuest (ImageConversion)

### Expected Timeline
- **DiskAllocation**: ✅ Completed
- **ImageConversion**: 🔄 In Progress (~10-15 minutes)
- **DiskTransferV2v**: Starting soon (~10-15 minutes)
- **VM Creation**: Final step (~1 minute)
- **ETA**: ~20:35-20:45 UTC

---

## NYMSDV301 Current Status

### Migration Details
- **Migration**: `nymsdv301-cold-migration-5jnzl`
- **Plan**: `nymsdv301-remigration`
- **VM ID**: `vm-5966`
- **Disk Size**: 122,880 MB (~120 GB)
- **Started**: ~20:04 UTC (4 minutes ahead)

### Pipeline Progress
```
✅ Initialize            - Completed
✅ DiskAllocation        - Completed
✅ ImageConversion       - Completed
🔄 DiskTransferV2v       - Running (Transferring disks)
⏳ VirtualMachineCreation - Pending
```

**Current Phase**: DiskTransferV2v

### Expected Timeline
- **DiskAllocation**: ✅ Completed
- **ImageConversion**: ✅ Completed
- **DiskTransferV2v**: 🔄 In Progress (~15-20 minutes remaining)
- **VM Creation**: Final step (~1 minute)
- **ETA**: ~20:35-20:45 UTC

---

## Cold Migration Pipeline Explained

### Cold Migration Phases (Different from Warm)

1. **Initialize**: Set up migration resources
2. **DiskAllocation**: Allocate PVCs for VM disks
3. **ImageConversion**: Convert VMDK to KubeVirt format (runs virt-v2v)
4. **DiskTransferV2v**: Transfer converted disk data
5. **VirtualMachineCreation**: Create VM resource

**Key Differences from Warm Migration:**
- ✅ No snapshot required
- ✅ More reliable
- ⚠️ VM is powered off during entire process
- 🔄 Different phase order (conversion happens earlier)

---

## Why Cold Migration?

### Benefits
1. ✅ **No snapshot dependency** - Eliminates snapshot chain issues
2. ✅ **More reliable** - Simpler workflow with fewer failure points
3. ✅ **Fresh data** - Captures VM state at power-off time
4. ✅ **Better for troubleshooting** - Easier to debug if issues occur

### Trade-off
- ⚠️ **VMs are offline** during migration (~35-40 minutes)
- For dev/test environment, this is acceptable

---

## Monitor Both Migrations

### Quick Status Check
```bash
# Check both migrations
oc get migration -n openshift-mtv | grep cold

# NYMSDV297 status
oc get migration nymsdv297-cold-migration-vj5g4 -n openshift-mtv

# NYMSDV301 status
oc get migration nymsdv301-cold-migration-5jnzl -n openshift-mtv
```

### Detailed Progress
```bash
# NYMSDV297 pipeline
oc get migration nymsdv297-cold-migration-vj5g4 -n openshift-mtv \
  -o jsonpath='{.status.vms[0]}' | jq '{phase, pipeline: [.pipeline[] | {name, phase, progress}]}'

# NYMSDV301 pipeline
oc get migration nymsdv301-cold-migration-5jnzl -n openshift-mtv \
  -o jsonpath='{.status.vms[0]}' | jq '{phase, pipeline: [.pipeline[] | {name, phase, progress}]}'
```

### Check for Completion
```bash
# Check if both are succeeded
oc get migration -n openshift-mtv | grep cold | grep -i succeeded
```

---

## Post-Migration Actions (Both VMs)

Once both migrations complete successfully:

### 1. Configure Static IPs

```bash
cd /c/Users/q22529_a/work/Cluster-Config/components/site-to-site-vpn

# NYMSDV297 - 10.132.104.10
./add-static-ip-to-vm.sh nymsdv297 10.132.104.10
oc patch vm nymsdv297 -n windows-non-prod --type merge -p '{"spec":{"runStrategy":"Always"}}'

# NYMSDV301 - 10.132.104.11
./add-static-ip-to-vm.sh nymsdv301 10.132.104.11
oc patch vm nymsdv301 -n windows-non-prod --type merge -p '{"spec":{"runStrategy":"Always"}}'
```

### 2. Wait for VMs to Boot

```bash
# Monitor boot
oc get vmi -n windows-non-prod -w

# Check when ready (Ctrl+C to exit watch)
```

### 3. Verify Static IPs

```bash
# Check both IPs
oc get vmi -n windows-non-prod -o wide

# Individual checks
oc get vmi nymsdv297 -n windows-non-prod -o jsonpath='{.status.interfaces[0].ipAddress}'
# Expected: 10.132.104.10

oc get vmi nymsdv301 -n windows-non-prod -o jsonpath='{.status.interfaces[0].ipAddress}'
# Expected: 10.132.104.11
```

### 4. Test Connectivity from Company Network

```bash
# Ping both VMs
ping 10.132.104.10
ping 10.132.104.11

# RDP to both VMs
mstsc /v:10.132.104.10
mstsc /v:10.132.104.11
```

### 5. Configure Windows Firewall (if RDP fails)

Access VM consoles:
```bash
# NYMSDV297
virtctl console nymsdv297 -n windows-non-prod

# NYMSDV301
virtctl console nymsdv301 -n windows-non-prod
```

In each Windows PowerShell:
```powershell
# Enable RDP
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

# Enable ICMP (ping)
New-NetFirewallRule -DisplayName "Allow ICMPv4" `
  -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Allow
```

---

## Timeline Comparison

### NYMSDV301 (Started First)
- **Started**: 20:04 UTC
- **Current**: DiskTransferV2v phase
- **Expected Completion**: ~20:35-20:45 UTC
- **Total Duration**: ~40-45 minutes

### NYMSDV297 (Started Later)
- **Started**: 20:08 UTC
- **Current**: ImageConversion phase
- **Expected Completion**: ~20:35-20:45 UTC
- **Total Duration**: ~35-40 minutes

**Both Expected Complete By**: ~20:45 UTC

---

## Static IP Reservations (Ready)

Both static IPs are already reserved in all namespaces:

### NYMSDV297 - 10.132.104.10
```
✅ openshift-mtv: 10.132.104.10/32 excluded
✅ vm-migrations: 10.132.104.10/32 excluded  
✅ windows-non-prod: 10.132.104.10/32 excluded
```

### NYMSDV301 - 10.132.104.11
```
✅ openshift-mtv: 10.132.104.11/32 excluded
✅ vm-migrations: 10.132.104.11/32 excluded  
✅ windows-non-prod: 10.132.104.11/32 excluded
```

---

## Troubleshooting

### If Migration Stalls or Fails

```bash
# Check error for specific VM
oc get migration <migration-name> -n openshift-mtv \
  -o jsonpath='{.status.vms[0].pipeline[]}' | jq 'select(.error != null)'

# Check PVC status
oc get pvc -n windows-non-prod | grep -E "(nymsdv297|nymsdv301)"

# Check virt-v2v pod logs (if ImageConversion fails)
oc get pods -n openshift-mtv | grep v2v
oc logs <v2v-pod-name> -n openshift-mtv
```

---

## Files and Documentation

| File | Description |
|------|-------------|
| `BOTH-VMS-COLD-MIGRATION.md` | This summary document |
| `NYMSDV297-COLD-MIGRATION.md` | NYMSDV297 detailed status |
| `NYMSDV301-COLD-MIGRATION.md` | NYMSDV301 detailed status |
| `nymsdv297-remigration-plan.yaml` | NYMSDV297 plan (cold migration) |
| `nymsdv301-remigration-plan.yaml` | NYMSDV301 plan (cold migration) |
| `add-static-ip-to-vm.sh` | Static IP automation script |

---

## Summary

| Item | Status |
|------|--------|
| **NYMSDV297 Migration** | 🔄 Running (ImageConversion) |
| **NYMSDV301 Migration** | 🔄 Running (DiskTransferV2v) |
| **Migration Type** | ✅ Cold (both VMs) |
| **VMs Powered** | ⚠️ Offline (will auto-start after config) |
| **Static IPs** | ✅ Reserved (both) |
| **ETA** | ~20:35-20:45 UTC |

---

**Last Updated**: February 10, 2026 at 20:10 UTC  
**Status**: ✅ Both cold migrations running successfully  
**Next Action**: Wait for completion, then configure static IPs

🔄 **Both VMs are being migrated with cold migration for maximum reliability!**
