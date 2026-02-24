# ✅ QA VMs Ready for Migration

**Status**: COMPLETE - Static IPs Reserved  
**Date**: February 10, 2026  
**Cluster**: Non-Prod OpenShift  

---

## Next VMs to Migrate

| Hostname   | Static IP       | MAC Address        | Status              |
|------------|-----------------|-------------------|---------------------|
| NYMSQA428  | 10.132.104.20   | (assign in vSphere)| ✅ IP Reserved      |
| NYMSQA429  | 10.132.104.21   | (assign in vSphere)| ✅ IP Reserved      |

## Network Configuration

**Subnet**: 10.132.104.0/22 (windows-non-prod)  
**Gateway**: 10.132.104.1  
**DNS Servers**: 10.132.104.2, 10.132.104.3  
**S2S VPN**: Routable from company network  

## All Reserved IPs (Complete List)

The following IPs are now reserved across all three namespaces:

```
✓ openshift-mtv namespace:
  - 10.132.104.1/32   (Gateway)
  - 10.132.104.2/32   (DNS Primary)
  - 10.132.104.3/32   (DNS Secondary)
  - 10.132.104.10/32  (NYMSDV297)
  - 10.132.104.11/32  (NYMSDV301)
  - 10.132.104.19/32  (NYMSDV312)
  - 10.132.104.20/32  (NYMSQA428) ← NEW
  - 10.132.104.21/32  (NYMSQA429) ← NEW

✓ vm-migrations namespace:
  - 10.132.104.1/32   (Gateway)
  - 10.132.104.2/32   (DNS Primary)
  - 10.132.104.3/32   (DNS Secondary)
  - 10.132.104.10/32  (NYMSDV297)
  - 10.132.104.11/32  (NYMSDV301)
  - 10.132.104.19/32  (NYMSDV312)
  - 10.132.104.20/32  (NYMSQA428) ← NEW
  - 10.132.104.21/32  (NYMSQA429) ← NEW

✓ windows-non-prod namespace:
  - 10.132.104.1/32   (Gateway)
  - 10.132.104.2/32   (DNS Primary)
  - 10.132.104.3/32   (DNS Secondary)
  - 10.132.104.10/32  (NYMSDV297)
  - 10.132.104.11/32  (NYMSDV301)
  - 10.132.104.19/32  (NYMSDV312)
  - 10.132.104.20/32  (NYMSQA428) ← NEW
  - 10.132.104.21/32  (NYMSQA429) ← NEW
```

---

## Migration Steps

### Phase 1: Perform MTV Migration

Use the Migration Toolkit for Virtualization (MTV) to migrate VMs from vSphere:

1. Create migration plan in MTV for NYMSQA428 and NYMSQA429
2. Select `windows-non-prod` namespace as destination
3. Map networks to `windows-non-prod` NAD
4. Execute migration
5. Wait for migration to complete

**Post-Migration State**: VMs will initially boot with dynamic IPs from the DHCP range.

### Phase 2: Configure Static IPs

After migration completes, configure static IPs using cloud-init automation:

#### NYMSQA428 - 10.132.104.20

```bash
# Navigate to scripts directory
cd /c/Users/q22529_a/work/Cluster-Config/components/site-to-site-vpn

# Stop VM
oc patch vm nymsqa428 -n windows-non-prod --type merge -p '{"spec":{"running":false}}'

# Wait for VM to stop
oc get vm nymsqa428 -n windows-non-prod -w

# Apply cloud-init configuration for static IP
./add-static-ip-to-vm.sh nymsqa428 10.132.104.20

# Start VM - cloud-init will auto-configure on boot
oc patch vm nymsqa428 -n windows-non-prod --type merge -p '{"spec":{"running":true}}'

# Monitor boot process
oc get vmi nymsqa428 -n windows-non-prod -w
```

#### NYMSQA429 - 10.132.104.21

```bash
# Stop VM
oc patch vm nymsqa429 -n windows-non-prod --type merge -p '{"spec":{"running":false}}'

# Wait for VM to stop
oc get vm nymsqa429 -n windows-non-prod -w

# Apply cloud-init configuration for static IP
./add-static-ip-to-vm.sh nymsqa429 10.132.104.21

# Start VM - cloud-init will auto-configure on boot
oc patch vm nymsqa429 -n windows-non-prod --type merge -p '{"spec":{"running":true}}'

# Monitor boot process
oc get vmi nymsqa429 -n windows-non-prod -w
```

### Phase 3: Verify Configuration

```bash
# Verify NYMSQA428 IP
oc get vmi nymsqa428 -n windows-non-prod -o jsonpath='{.status.interfaces[0].ipAddress}'
# Expected output: 10.132.104.20

# Verify NYMSQA429 IP
oc get vmi nymsqa429 -n windows-non-prod -o jsonpath='{.status.interfaces[0].ipAddress}'
# Expected output: 10.132.104.21

# Test ping from company network
ping 10.132.104.20
ping 10.132.104.21

# Test RDP access from company network
mstsc /v:10.132.104.20
mstsc /v:10.132.104.21
```

### Phase 4: DNS Configuration

Add DNS records to your company DNS server:

**Forward DNS (A Records):**
```dns
NYMSQA428.domain.com.    IN  A  10.132.104.20
NYMSQA429.domain.com.    IN  A  10.132.104.21
```

**Reverse DNS (PTR Records):**
```dns
20.104.132.10.in-addr.arpa.  IN  PTR  NYMSQA428.domain.com.
21.104.132.10.in-addr.arpa.  IN  PTR  NYMSQA429.domain.com.
```

**PowerShell (Windows DNS):**
```powershell
Add-DnsServerResourceRecordA -Name "NYMSQA428" -ZoneName "domain.com" -IPv4Address "10.132.104.20"
Add-DnsServerResourceRecordA -Name "NYMSQA429" -ZoneName "domain.com" -IPv4Address "10.132.104.21"
Add-DnsServerResourceRecordPtr -Name "20" -ZoneName "104.132.10.in-addr.arpa" -PtrDomainName "NYMSQA428.domain.com"
Add-DnsServerResourceRecordPtr -Name "21" -ZoneName "104.132.10.in-addr.arpa" -PtrDomainName "NYMSQA429.domain.com"
```

---

## Cloud-Init Automation

The `add-static-ip-to-vm.sh` script automatically configures:

| Setting | Value |
|---------|-------|
| Static IP | 10.132.104.20 or .21 |
| Subnet Mask | 255.255.252.0 (/22) |
| Gateway | 10.132.104.1 |
| DNS Primary | 10.132.104.2 |
| DNS Secondary | 10.132.104.3 |
| Hostname | NYMSQA428 or NYMSQA429 |
| RDP | Enabled (port 3389) |
| Windows Firewall | RDP + ICMP allowed |

**No manual Windows configuration required!** Everything is automated via cloud-init on first boot.

---

## Troubleshooting

### VM doesn't get static IP after reboot

```bash
# Check cloud-init logs
oc logs virt-launcher-nymsqa428-xxxxx -n windows-non-prod | grep -i cloud-init

# Access VM console to verify manually
virtctl console nymsqa428 -n windows-non-prod

# Inside Windows, check IP configuration
ipconfig /all
```

### RDP connection refused

1. **Verify Windows Firewall** (via VM console):
   ```powershell
   Get-NetFirewallRule -DisplayName "*Remote Desktop*" | Select-Object DisplayName, Enabled
   ```

2. **Test network connectivity from company network**:
   ```bash
   # Test gateway (should work)
   ping 10.132.104.1
   
   # Test VM (may be blocked by Windows Firewall)
   ping 10.132.104.20
   ```

3. **Check RDP service**:
   ```powershell
   Get-Service TermService
   ```

### DNS not resolving

```bash
# From company network
nslookup NYMSQA428.domain.com
nslookup 10.132.104.20

# Flush DNS cache if needed
ipconfig /flushdns
```

---

## Files and Documentation

| File | Purpose |
|------|---------|
| `reserve-qa-vm-ips.yaml` | NAD manifests with .20/.21 exclusions |
| `deploy-qa-vm-ips.sh` | Deployment script for IP reservations |
| `add-static-ip-to-vm.sh` | Cloud-init automation script |
| `dns-records-qa-vms.md` | DNS configuration guide |
| `QA-VMS-DEPLOYMENT.md` | Detailed deployment procedures |
| `QA-VMS-READY.md` | This quick reference (you are here) |

### Related Documentation
- `STATIC-IP-QUICK-ANSWER.md` - Complete static IP solutions reference
- `WINDOWS-STATIC-IP-GUIDE.md` - Windows static IP configuration methods
- `TROUBLESHOOTING-RDP-CONNECTIVITY.md` - RDP troubleshooting procedures
- `DEPLOYMENT-COMPLETE.md` - Previous test VMs documentation

---

## Backup Information

NAD backups created during deployment:
```
nad-backups/qa-20260210-141353/
├── openshift-mtv.yaml
├── vm-migrations.yaml
└── windows-non-prod.yaml
```

To restore a NAD backup:
```bash
oc apply -f nad-backups/qa-20260210-141353/openshift-mtv.yaml
```

---

## Summary

✅ **Static IPs Reserved**: 10.132.104.20 and 10.132.104.21  
✅ **All Namespaces Updated**: openshift-mtv, vm-migrations, windows-non-prod  
✅ **Automation Ready**: Cloud-init scripts prepared  
✅ **Documentation Complete**: Migration and DNS guides ready  

**You're ready to proceed with MTV migration!** After migration, run the cloud-init scripts to auto-configure static IPs, then update DNS records and test RDP connectivity.

---

**Quick Commands Reference:**

```bash
# After migration, configure NYMSQA428
./add-static-ip-to-vm.sh nymsqa428 10.132.104.20
oc patch vm nymsqa428 -n windows-non-prod --type merge -p '{"spec":{"running":true}}'

# After migration, configure NYMSQA429
./add-static-ip-to-vm.sh nymsqa429 10.132.104.21
oc patch vm nymsqa429 -n windows-non-prod --type merge -p '{"spec":{"running":true}}'

# Verify IPs
oc get vmi -n windows-non-prod -o wide

# Test from company network
ping 10.132.104.20 && ping 10.132.104.21
mstsc /v:10.132.104.20
```

🚀 **Ready for migration!**
