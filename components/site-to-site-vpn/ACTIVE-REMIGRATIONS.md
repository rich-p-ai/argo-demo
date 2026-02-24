# Active VM Re-Migrations Summary

**Date**: February 10, 2026  
**Status**: ✅ **BOTH MIGRATIONS RUNNING SUCCESSFULLY**  

---

## Overview

Two Windows VMs are being re-migrated to capture the most current data from vSphere:

| VM | Migration Name | Started | Status | Static IP | ETA |
|----|---------------|---------|--------|-----------|-----|
| **NYMSDV297** | nymsdv297-remigration-r8xn8 | 19:40:26 UTC | 🔄 Running | 10.132.104.10 | ~20:10-20:20 |
| **NYMSDV301** | nymsdv301-remigration-4gtpl | 19:49:19 UTC | 🔄 Running | 10.132.104.11 | ~20:20-20:35 |

---

## NYMSDV297 Migration Details

### Current Status
```
✅ Initialize           - Completed
🔄 DiskTransfer         - In Progress (~10 minutes elapsed)
⏳ Cutover              - Pending
⏳ ImageConversion      - Pending
⏳ VirtualMachineCreation - Pending
```

### Key Information
- **VM ID**: vm-10070
- **Snapshot**: snapshot-766776
- **Delta ID**: 2252 (vs original 2238)
- **Disk Size**: 138,240 MB (~135 GB)
- **Expected Completion**: ~20:10-20:20 UTC
- **Static IP**: 10.132.104.10 (already reserved)

### Data Currency
✅ Capturing **LATEST** data from vSphere (delta 2252 vs old 2238)

---

## NYMSDV301 Migration Details

### Current Status
```
🔄 Initialize           - Running
⏳ DiskTransfer         - Pending (0 / 122,880 MB)
⏳ Cutover              - Pending
⏳ ImageConversion      - Pending
⏳ VirtualMachineCreation - Pending
```

### Key Information
- **VM ID**: vm-5966
- **Snapshot**: snapshot-766777
- **Delta ID**: 6270 (vs original 6254)
- **Disk Size**: 122,880 MB (~120 GB)
- **Expected Completion**: ~20:20-20:35 UTC
- **Static IP**: 10.132.104.11 (already reserved)

### Data Currency
✅ Capturing **LATEST** data from vSphere (delta 6270 vs old 6254)

---

## Migration Configuration

Both migrations use the same configuration:
- **Type**: Warm migration (minimal downtime)
- **Transfer Method**: VDDK (VMware Data Recovery)
- **Guest Conversion**: Enabled (virtio drivers)
- **Preflight Inspection**: **Disabled** (to avoid guest inspection failures)
- **Compatibility Mode**: Enabled

---

## Why Re-Migrate?

**Reason**: To capture the most current data from the source VMs in vSphere.

**Evidence of New Data**:
- NYMSDV297: Delta ID changed from 2238 → **2252**
- NYMSDV301: Delta ID changed from 6254 → **6270**

This confirms both migrations are capturing **NEW snapshots** with the **latest changes** from vSphere.

---

## Static IP Reservations

Both static IPs are already reserved in all necessary namespaces:

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

## Monitoring Both Migrations

### Quick Status Check
```bash
# Check both migrations
oc get migration -n openshift-mtv | grep remigration

# NYMSDV297 progress
oc get migration nymsdv297-remigration-r8xn8 -n openshift-mtv

# NYMSDV301 progress
oc get migration nymsdv301-remigration-4gtpl -n openshift-mtv
```

### Detailed Progress
```bash
# NYMSDV297 detailed status
oc get migration nymsdv297-remigration-r8xn8 -n openshift-mtv \
  -o jsonpath='{.status.vms[0]}' | jq '{phase, pipeline: [.pipeline[] | {name, phase, progress}]}'

# NYMSDV301 detailed status
oc get migration nymsdv301-remigration-4gtpl -n openshift-mtv \
  -o jsonpath='{.status.vms[0]}' | jq '{phase, pipeline: [.pipeline[] | {name, phase, progress}]}'
```

### Check for Completion
```bash
# Check if NYMSDV297 is complete
oc get migration nymsdv297-remigration-r8xn8 -n openshift-mtv \
  -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}'

# Check if NYMSDV301 is complete
oc get migration nymsdv301-remigration-4gtpl -n openshift-mtv \
  -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}'
```

---

## Post-Migration Actions (For Both VMs)

### When NYMSDV297 Completes

```bash
cd /c/Users/q22529_a/work/Cluster-Config/components/site-to-site-vpn

# Configure static IP 10.132.104.10
./add-static-ip-to-vm.sh nymsdv297 10.132.104.10

# Start VM
oc patch vm nymsdv297 -n windows-non-prod --type merge -p '{"spec":{"runStrategy":"Always"}}'

# Verify IP
oc get vmi nymsdv297 -n windows-non-prod -o jsonpath='{.status.interfaces[0].ipAddress}'

# Test connectivity
ping 10.132.104.10
mstsc /v:10.132.104.10
```

### When NYMSDV301 Completes

```bash
cd /c/Users/q22529_a/work/Cluster-Config/components/site-to-site-vpn

# Configure static IP 10.132.104.11
./add-static-ip-to-vm.sh nymsdv301 10.132.104.11

# Start VM
oc patch vm nymsdv301 -n windows-non-prod --type merge -p '{"spec":{"runStrategy":"Always"}}'

# Verify IP
oc get vmi nymsdv301 -n windows-non-prod -o jsonpath='{.status.interfaces[0].ipAddress}'

# Test connectivity
ping 10.132.104.11
mstsc /v:10.132.104.11
```

---

## Timeline Summary

### NYMSDV297
- **Started**: 19:40:26 UTC
- **DiskTransfer ETA**: ~19:55-20:00 UTC
- **Completion ETA**: ~20:10-20:20 UTC
- **Total Duration**: ~30-40 minutes

### NYMSDV301
- **Started**: 19:49:19 UTC
- **DiskTransfer ETA**: ~19:50-19:51 UTC
- **Completion ETA**: ~20:20-20:35 UTC
- **Total Duration**: ~30-45 minutes

**Both VMs Expected Complete By**: ~20:35 UTC

---

## Troubleshooting

### If Migration Fails
```bash
# Check error message
oc get migration <migration-name> -n openshift-mtv \
  -o jsonpath='{.status.conditions[?(@.type=="Failed")].message}'

# Check detailed VM error
oc get migration <migration-name> -n openshift-mtv \
  -o jsonpath='{.status.vms[0].pipeline[]}' | jq 'select(.error != null)'
```

### If RDP Fails Post-Migration
1. Access VM console: `virtctl console <vm-name> -n windows-non-prod`
2. Enable Windows Firewall rules for RDP
3. Verify static IP configuration inside Windows

---

## Documentation Files

| File | Description |
|------|-------------|
| `ACTIVE-REMIGRATIONS.md` | This summary document |
| `NYMSDV297-REMIGRATION-STATUS.md` | NYMSDV297 detailed status |
| `NYMSDV301-REMIGRATION-STATUS.md` | NYMSDV301 detailed status |
| `nymsdv297-remigration-plan.yaml` | NYMSDV297 MTV plan |
| `nymsdv301-remigration-plan.yaml` | NYMSDV301 MTV plan |
| `add-static-ip-to-vm.sh` | Static IP automation script |

---

## Next Steps

1. **Monitor Progress**: Check migrations periodically using commands above
2. **Wait for Completion**: Both should complete by ~20:35 UTC
3. **Configure Static IPs**: Run cloud-init scripts for both VMs
4. **Start VMs**: Boot VMs with static IP configuration
5. **Test Connectivity**: Verify RDP access from company network
6. **Configure Firewall**: If needed, enable RDP/ICMP via VM console
7. **Verify Data**: Login and confirm latest data is present

---

**Last Updated**: February 10, 2026 at 19:50 UTC  
**Status**: ✅ Both migrations running successfully  
**Next Check**: Monitor disk transfer progress in ~10 minutes

🚀 **Both re-migrations are capturing the latest data from vSphere!**
