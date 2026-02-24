# QA VM Migration - NYMSQA428 & NYMSQA429

## Summary

**Status**: ✅ IP Reservations Deployed Successfully  
**Date**: February 10, 2026  
**Cluster**: Non-Prod OpenShift

## VMs Prepared for Migration

| Hostname   | Static IP       | Network               | Status                  |
|------------|-----------------|------------------------|-------------------------|
| NYMSQA428  | 10.132.104.20   | windows-non-prod      | Ready for migration     |
| NYMSQA429  | 10.132.104.21   | windows-non-prod      | Ready for migration     |

## Network Configuration

**Subnet**: 10.132.104.0/22 (windows-non-prod)  
**Gateway**: 10.132.104.1  
**DNS**: 10.132.104.2, 10.132.104.3  
**S2S VPN**: Routable from company network  

**Reserved IPs** (excluded from DHCP):
- 10.132.104.1/32 (Gateway)
- 10.132.104.2/32 (DNS Primary)
- 10.132.104.3/32 (DNS Secondary)
- 10.132.104.10/32 (NYMSDV297 - test VM)
- 10.132.104.11/32 (NYMSDV301 - test VM)
- 10.132.104.19/32 (NYMSDV312 - test VM)
- **10.132.104.20/32 (NYMSQA428 - NEW)**
- **10.132.104.21/32 (NYMSQA429 - NEW)**

## Migration Workflow

### 1. Perform MTV Migration
```bash
# Use Migration Toolkit for Virtualization (MTV) to migrate:
# - NYMSQA428 from vSphere
# - NYMSQA429 from vSphere
# 
# Post-migration VMs will be created in windows-non-prod namespace
# with dynamic IPs initially
```

### 2. Configure Static IPs (After Migration)

**For NYMSQA428:**
```bash
cd /c/Users/q22529_a/work/Cluster-Config/components/site-to-site-vpn

# Stop VM if running
oc patch vm nymsqa428 -n windows-non-prod --type merge -p '{"spec":{"running":false}}'

# Apply cloud-init configuration
./add-static-ip-to-vm.sh nymsqa428 10.132.104.20

# Start VM (cloud-init runs automatically on boot)
oc patch vm nymsqa428 -n windows-non-prod --type merge -p '{"spec":{"running":true}}'

# Monitor boot
oc get vmi nymsqa428 -n windows-non-prod -w
```

**For NYMSQA429:**
```bash
# Stop VM if running
oc patch vm nymsqa429 -n windows-non-prod --type merge -p '{"spec":{"running":false}}'

# Apply cloud-init configuration
./add-static-ip-to-vm.sh nymsqa429 10.132.104.21

# Start VM (cloud-init runs automatically on boot)
oc patch vm nymsqa429 -n windows-non-prod --type merge -p '{"spec":{"running":true}}'

# Monitor boot
oc get vmi nymsqa429 -n windows-non-prod -w
```

### 3. Verify Configuration

```bash
# Check VM IP addresses
oc get vmi nymsqa428 -n windows-non-prod -o jsonpath='{.status.interfaces[0].ipAddress}'
# Expected: 10.132.104.20

oc get vmi nymsqa429 -n windows-non-prod -o jsonpath='{.status.interfaces[0].ipAddress}'
# Expected: 10.132.104.21

# Test network connectivity from company network
ping 10.132.104.20
ping 10.132.104.21

# Test RDP access
mstsc /v:10.132.104.20
mstsc /v:10.132.104.21
```

### 4. Update DNS Records

Add A and PTR records to company DNS server:

**A Records (Forward DNS):**
```
NYMSQA428.domain.com.    IN  A  10.132.104.20
NYMSQA429.domain.com.    IN  A  10.132.104.21
```

**PTR Records (Reverse DNS):**
```
20.104.132.10.in-addr.arpa.  IN  PTR  NYMSQA428.domain.com.
21.104.132.10.in-addr.arpa.  IN  PTR  NYMSQA429.domain.com.
```

## What Cloud-Init Configures Automatically

The `add-static-ip-to-vm.sh` script embeds a cloud-init configuration that automatically configures on first boot:

1. **Static IP Assignment**: Sets the static IP (10.132.104.20 or .21)
2. **Default Gateway**: 10.132.104.1
3. **DNS Servers**: 10.132.104.2, 10.132.104.3
4. **Hostname**: Sets computer name to NYMSQA428 or NYMSQA429
5. **RDP**: Enables Remote Desktop Protocol
6. **Windows Firewall**: 
   - Allows RDP (port 3389)
   - Allows ICMP (ping)
   - Blocks all other inbound traffic

## Troubleshooting

### VM doesn't get static IP
```bash
# Check cloud-init ran successfully
oc logs virt-launcher-nymsqa428-xxxxx -n windows-non-prod

# Access VM console
virtctl console nymsqa428 -n windows-non-prod

# Verify IP manually in Windows
ipconfig /all
```

### RDP not working
```bash
# Verify Windows Firewall rules inside VM via console
# Check RDP service is running
# Confirm S2S VPN routing (test gateway ping)
ping 10.132.104.1
```

### DNS not resolving
- Verify DNS records added to company DNS server
- Test `nslookup NYMSQA428` from company network
- Check reverse DNS: `nslookup 10.132.104.20`

## Files Generated

- `reserve-qa-vm-ips.yaml` - NAD manifests with .20/.21 exclusions
- `deploy-qa-vm-ips.sh` - Deployment script
- `dns-records-qa-vms.md` - DNS configuration guide
- `QA-VMS-DEPLOYMENT.md` - This file

## Backups

NAD backups stored in:
```
nad-backups/qa-20260210-141353/
├── openshift-mtv.yaml
├── vm-migrations.yaml
└── windows-non-prod.yaml
```

## References

- Static IP automation: `STATIC-IP-QUICK-ANSWER.md`
- Windows setup guide: `WINDOWS-STATIC-IP-GUIDE.md`
- Troubleshooting: `TROUBLESHOOTING-RDP-CONNECTIVITY.md`
- Original test VMs: `DEPLOYMENT-COMPLETE.md`

---

**Ready for migration!** 🚀 Proceed with MTV migration, then apply cloud-init configs.
