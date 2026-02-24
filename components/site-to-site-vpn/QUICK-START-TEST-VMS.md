# Quick Start: Static IPs for Test VMs

## Summary

**Test VMs with Reserved IPs:**
- **NYMSDV297:** 10.132.104.10
- **NYMSDV301:** 10.132.104.11  
- **NYMSDV312:** 10.132.104.19

**Goal:** Make these IPs static/reserved so they can be used for DNS entries and RDP access from company network.

**Solution:** Reserve these IPs in whereabouts to prevent conflicts.

---

## Quick Deploy (5 minutes)

### Step 1: Apply IP Reservations

```bash
cd Cluster-Config/components/site-to-site-vpn

# Deploy
oc apply -f reserve-test-vm-ips.yaml
```

**What it does:**
- Updates windows-non-prod NAD in 3 namespaces
- Adds .10, .11, .19 to exclusion list
- Prevents whereabouts from assigning these IPs to other VMs

### Step 2: Verify

```bash
# Check VMs still have their IPs
oc get vmi nymsdv297 nymsdv301 -n windows-non-prod -o custom-columns=NAME:.metadata.name,IP:.status.interfaces[0].ipAddress

# Expected output:
# NAME       IP
# nymsdv297  10.132.104.10
# nymsdv301  10.132.104.11
```

### Step 3: Add DNS Records

See `dns-records-test-vms.md` for details.

**Quick add (Windows DNS):**
```powershell
Add-DnsServerResourceRecordA -Name "nymsdv297" -ZoneName "corp.cusa.canon.com" -IPv4Address "10.132.104.10" -CreatePtr
Add-DnsServerResourceRecordA -Name "nymsdv301" -ZoneName "corp.cusa.canon.com" -IPv4Address "10.132.104.11" -CreatePtr
Add-DnsServerResourceRecordA -Name "nymsdv312" -ZoneName "corp.cusa.canon.com" -IPv4Address "10.132.104.19" -CreatePtr
```

### Step 4: Test RDP

From company network workstation:

```powershell
# Test connectivity
ping 10.132.104.10
ping nymsdv297.corp.cusa.canon.com

# RDP
mstsc /v:10.132.104.10
mstsc /v:nymsdv297.corp.cusa.canon.com
```

---

## Files Created

| File | Purpose |
|------|---------|
| `reserve-test-vm-ips.yaml` | NAD updates with IP exclusions |
| `deploy-test-vm-ips.sh` | Deployment script with backup |
| `dns-records-test-vms.md` | DNS configuration guide |
| `STATIC-IP-TEST-PLAN.md` | Complete implementation plan |
| `STATIC-IP-OPTIONS.md` | All available options explained |

---

## What Changed

**Before:**
```json
"exclude": [
  "10.132.104.1/32",
  "10.132.104.2/32",
  "10.132.104.3/32"
]
```

**After:**
```json
"exclude": [
  "10.132.104.1/32",
  "10.132.104.2/32",
  "10.132.104.3/32",
  "10.132.104.10/32",  ← NYMSDV297
  "10.132.104.11/32",  ← NYMSDV301
  "10.132.104.19/32"   ← NYMSDV312
]
```

---

## Benefits

✅ IPs are now reserved (won't be reassigned)  
✅ Can create DNS entries pointing to these IPs  
✅ RDP works from company network via S2S VPN  
✅ No changes to VMs required  
✅ No downtime  
✅ Easy to rollback  

---

## Rollback

If needed:

```bash
# Restore original NADs
oc apply -f backups/windows-non-prod-openshift-mtv-backup.yaml
oc apply -f backups/windows-non-prod-vm-migrations-backup.yaml
oc apply -f backups/windows-non-prod-windows-non-prod-backup.yaml
```

---

## Troubleshooting

### Issue: VMs lost their IPs

**Should not happen** - exclusions only prevent future assignments.

**Fix:**
1. Restart VMs
2. They should get same IPs back (whereabouts tracks assignments)

### Issue: Other VMs can't get IPs

**Check:**
- Whereabouts range still has available IPs (.10-.199 = 190 IPs)
- Check current allocations: `oc get ippools -n kube-system`

### Issue: DNS not resolving

**Check:**
1. DNS records added
2. DNS cache cleared
3. Using correct DNS server

---

## Next Steps

After successful testing with these 3 VMs:

1. **Document process** for adding more static IPs
2. **Create IP tracking spreadsheet** to manage assignments
3. **Consider migrating to static IP range** (.200-.249) for production

See `STATIC-IP-OPTIONS.md` for production approach.
