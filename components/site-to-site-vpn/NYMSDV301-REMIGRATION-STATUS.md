# NYMSDV301 Re-Migration Status

**Status**: ✅ **RUNNING SUCCESSFULLY**  
**Started**: February 10, 2026 at 19:49:19 UTC  
**Migration Type**: Warm migration with VDDK (Preflight Inspection Disabled)  
**Reason**: Capture most current data from source VM  

---

## Migration Details

| Parameter | Value |
|-----------|-------|
| **Migration Name** | `nymsdv301-remigration-4gtpl` |
| **Plan Name** | `nymsdv301-remigration` |
| **Namespace** | `openshift-mtv` |
| **Source VM ID** | `vm-5966` |
| **Target VM Name** | `nymsdv301` |
| **Target Namespace** | `windows-non-prod` |
| **Static IP** | **10.132.104.11** (reserved) |

---

## Current Status

### Migration Pipeline

```
🔄 Initialize           - Running
⏳ DiskTransfer         - Pending (0 / 122,880 MB)
⏳ Cutover              - Pending
⏳ ImageConversion      - Pending
⏳ VirtualMachineCreation - Pending
```

**Current Phase**: StoreInitialSnapshotDeltas

### Warm Migration Details

| Metric | Value |
|--------|-------|
| **Snapshot ID** | `snapshot-766777` (**LATEST**) |
| **Precopy Count** | 1 (initial) |
| **Delta IDs** | **6270** (Latest - Feb 10) |
| **Successes** | 0 (in progress) |
| **Failures** | 0 |
| **Started** | 19:49:19 UTC |

**Disk Delta Information:**
- **NYMSDV301_2.vmdk**: Delta ID `52 d9 2e d8 d0 da 6b 57-55 60 1c 43 c9 fb 2f 8c/6270` ✅
- **NYMSDV301.vmdk**: Delta ID `52 49 5f 56 e8 15 34 41-63 34 e4 f2 b9 be 6b 21/6270` ✅

**Delta Evolution:**
- Original (Feb 8): 6254
- Current (Feb 10): **6270** ← **MOST CURRENT DATA** ✅

---

## Disk Transfer Plan

| Disk | Size (MB) | Location |
|------|-----------|----------|
| **NYMSDV301_2.vmdk** | 81,920 | [WorkloadDatastore (1)] |
| **NYMSDV301.vmdk** | 40,960 | [WorkloadDatastore (1)] |
| **Total** | **122,880 MB** (~120 GB) | |

**Expected Transfer Time**: ~18-25 minutes

---

## Static IP Configuration

The static IP **10.132.104.11** is already reserved in all necessary namespaces:

```
✅ openshift-mtv: 10.132.104.11/32 excluded
✅ vm-migrations: 10.132.104.11/32 excluded  
✅ windows-non-prod: 10.132.104.11/32 excluded
```

**Post-Migration Steps:**
1. Stop VM after migration completes
2. Apply cloud-init configuration for static IP
3. Start VM - static IP will be configured automatically
4. Verify connectivity via RDP

---

## Monitoring Commands

### Check Current Progress
```bash
# Overall migration status
oc get migration nymsdv301-remigration-4gtpl -n openshift-mtv

# Detailed progress with phases
oc get migration nymsdv301-remigration-4gtpl -n openshift-mtv \
  -o jsonpath='{.status.vms[0]}' | jq '{phase, pipeline: [.pipeline[] | {name, phase, progress}]}'

# Disk transfer progress (once started)
oc get migration nymsdv301-remigration-4gtpl -n openshift-mtv \
  -o jsonpath='{.status.vms[0].pipeline[1]}' | jq .

# Warm migration snapshot info
oc get migration nymsdv301-remigration-4gtpl -n openshift-mtv \
  -o jsonpath='{.status.vms[0].warm}' | jq .
```

---

## Expected Timeline

### Phase 1: Initialize 🔄
- **Started**: 19:49:19 UTC
- **Duration**: ~1-2 minutes

### Phase 2: DiskTransfer ⏳
- **Expected Start**: ~19:50-19:51 UTC
- **Expected Duration**: 18-25 minutes
- **Progress**: 0 → 122,880 MB
- **ETA Complete**: ~20:08-20:16 UTC

### Phase 3: Cutover ⏳
- **Expected Start**: ~20:08-20:16 UTC
- **Duration**: 1-2 minutes
- **Purpose**: Sync final delta changes

### Phase 4: ImageConversion ⏳
- **Expected Start**: ~20:09-20:18 UTC
- **Duration**: 10-15 minutes
- **Purpose**: Convert VMDK to KubeVirt format + virtio drivers

### Phase 5: VirtualMachineCreation ⏳
- **Expected Start**: ~20:19-20:33 UTC
- **Duration**: 1 minute

**Expected Completion**: ~20:20-20:35 UTC (~30-45 minutes total)

---

## Post-Migration Actions

### 1. Configure Static IP (10.132.104.11)

```bash
cd /c/Users/q22529_a/work/Cluster-Config/components/site-to-site-vpn

# Wait for VM to be created but not started
oc get vm nymsdv301 -n windows-non-prod -w

# Apply cloud-init configuration
./add-static-ip-to-vm.sh nymsdv301 10.132.104.11

# Start VM
oc patch vm nymsdv301 -n windows-non-prod --type merge \
  -p '{"spec":{"runStrategy":"Always"}}'

# Monitor boot
oc get vmi nymsdv301 -n windows-non-prod -w
```

### 2. Verify Static IP Assignment

```bash
# Check IP (should show 10.132.104.11)
oc get vmi nymsdv301 -n windows-non-prod \
  -o jsonpath='{.status.interfaces[0].ipAddress}'

# Check guest agent connection
oc get vmi nymsdv301 -n windows-non-prod \
  -o jsonpath='{.status.conditions[?(@.type=="AgentConnected")].status}'
```

### 3. Test Connectivity from Company Network

```bash
# Test ping
ping 10.132.104.11

# Test RDP
mstsc /v:10.132.104.11
```

### 4. Configure Windows Firewall (if RDP fails)

Access VM console:
```bash
virtctl console nymsdv301 -n windows-non-prod
```

In Windows PowerShell:
```powershell
# Enable RDP firewall rule
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

# Enable ICMP (ping)
New-NetFirewallRule -DisplayName "Allow ICMPv4" `
  -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Allow

# Verify firewall rules
Get-NetFirewallRule -DisplayName "*Remote Desktop*" | Select DisplayName, Enabled
```

---

## Comparison: Old vs New Migration

| Aspect | Original (Feb 8) | New (Feb 10) |
|--------|------------------|--------------|
| **Snapshot ID** | snapshot-765857 | **snapshot-766777** |
| **Delta ID** | 6254 | **6270** |
| **Preflight** | Enabled (succeeded) | **Skipped** |
| **Static IP** | Not configured | **10.132.104.11 ready** |
| **Data Currency** | 2 days old | **Latest** ✅ |

---

## Files

- `nymsdv301-remigration-plan.yaml` - MTV plan (preflight disabled)
- `NYMSDV301-REMIGRATION-STATUS.md` - This status document
- `add-static-ip-to-vm.sh` - Cloud-init automation for static IP

---

## Quick Commands Reference

```bash
# Check if migration complete
oc get migration nymsdv301-remigration-4gtpl -n openshift-mtv | grep -i succeeded

# Once complete, configure static IP
./add-static-ip-to-vm.sh nymsdv301 10.132.104.11
oc patch vm nymsdv301 -n windows-non-prod --type merge -p '{"spec":{"runStrategy":"Always"}}'

# Verify IP
oc get vmi nymsdv301 -n windows-non-prod -o jsonpath='{.status.interfaces[0].ipAddress}'

# Test from company network
ping 10.132.104.11
mstsc /v:10.132.104.11
```

---

**Last Updated**: February 10, 2026 at 19:49 UTC  
**Status**: ✅ Initialize phase running  
**Next Milestone**: DiskTransfer phase start (~19:50-19:51 UTC)

🚀 **Migration is progressing successfully with the latest data from vSphere!**
