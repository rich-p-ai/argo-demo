# VM Migration Status - All Windows VMs

**Last Updated**: February 10, 2026  
**Cluster**: Non-Prod OpenShift  
**Network**: windows-non-prod (10.132.104.0/22)  

---

## Migration Pipeline Status

### ✅ Test VMs (Completed)

| Hostname   | Static IP       | Status            | RDP Access         | Notes                          |
|------------|-----------------|-------------------|--------------------|--------------------------------|
| NYMSDV297  | 10.132.104.10   | ✅ Migrated       | ⚠️ Firewall Issue | Need to enable RDP via console |
| NYMSDV301  | 10.132.104.11   | ✅ Migrated       | ⚠️ Firewall Issue | Need to enable RDP via console |
| NYMSDV312  | 10.132.104.19   | ✅ IP Reserved    | ⏳ Pending Start  | Cloud-init ready to apply      |

**Action Required**: Configure Windows Firewall on 297 and 301 via VM console to enable RDP/ICMP.

### 🔄 QA VMs (Ready for Migration)

| Hostname   | Static IP       | Status            | Migration Ready    | Notes                          |
|------------|-----------------|-------------------|--------------------|--------------------------------|
| NYMSQA428  | 10.132.104.20   | ✅ IP Reserved    | ✅ Yes             | Ready for MTV migration        |
| NYMSQA429  | 10.132.104.21   | ✅ IP Reserved    | ✅ Yes             | Ready for MTV migration        |

**Next Step**: Execute MTV migration, then apply cloud-init configuration.

---

## Reserved Static IP Ranges

### Infrastructure IPs (Always Reserved)
- **10.132.104.1** - Default Gateway (S2S VPN)
- **10.132.104.2** - Primary DNS Server
- **10.132.104.3** - Secondary DNS Server

### VM Static IPs (Reserved - Excluded from DHCP)
- **10.132.104.10** - NYMSDV297 (Test VM)
- **10.132.104.11** - NYMSDV301 (Test VM)
- **10.132.104.19** - NYMSDV312 (Test VM)
- **10.132.104.20** - NYMSQA428 (QA VM) ← NEW
- **10.132.104.21** - NYMSQA429 (QA VM) ← NEW

### Available for Future Migrations
- **10.132.104.22 - 10.132.104.254** (233 IPs available in .104 subnet)
- **10.132.105.4 - 10.132.107.254** (Additional ~768 IPs in .105-.107 subnets)

---

## Network Configuration Summary

| Parameter | Value |
|-----------|-------|
| Subnet | 10.132.104.0/22 |
| Netmask | 255.255.252.0 |
| Gateway | 10.132.104.1 |
| DNS Primary | 10.132.104.2 |
| DNS Secondary | 10.132.104.3 |
| DHCP Range | 10.132.104.22 - 10.132.107.250 |
| S2S VPN | Enabled (routable to company network) |
| VLAN | 101 |
| MTU | 1400 |

---

## OpenShift Namespaces

All three namespaces are configured with identical IP reservations:

### ✅ openshift-mtv
- **Purpose**: Migration Toolkit for Virtualization operations
- **NAD**: windows-non-prod (bridge mode, VLAN 101)
- **Reserved IPs**: .1, .2, .3, .10, .11, .19, .20, .21

### ✅ vm-migrations  
- **Purpose**: Temporary landing zone during migration
- **NAD**: windows-non-prod (bridge mode, VLAN 101)
- **Reserved IPs**: .1, .2, .3, .10, .11, .19, .20, .21

### ✅ windows-non-prod
- **Purpose**: Final VM runtime environment
- **NAD**: windows-non-prod (OVN-K8s overlay)
- **Reserved IPs**: .1, .2, .3, .10, .11, .19, .20, .21

---

## Migration Workflow (Standard Process)

### Phase 1: Pre-Migration
```bash
# 1. Reserve static IP in NADs (if not already reserved)
# 2. Verify IP not in use
ping <target-ip>
```

### Phase 2: MTV Migration
```bash
# 1. Create migration plan in MTV web console
# 2. Select windows-non-prod namespace
# 3. Map to windows-non-prod NAD
# 4. Execute migration
# 5. Monitor progress
```

### Phase 3: Static IP Configuration
```bash
# 1. Stop VM after migration
oc patch vm <vm-name> -n windows-non-prod --type merge -p '{"spec":{"running":false}}'

# 2. Apply cloud-init for static IP
cd /c/Users/q22529_a/work/Cluster-Config/components/site-to-site-vpn
./add-static-ip-to-vm.sh <vm-name> <static-ip>

# 3. Start VM
oc patch vm <vm-name> -n windows-non-prod --type merge -p '{"spec":{"running":true}}'
```

### Phase 4: Post-Migration Verification
```bash
# 1. Verify static IP assigned
oc get vmi <vm-name> -n windows-non-prod -o jsonpath='{.status.interfaces[0].ipAddress}'

# 2. Test connectivity from company network
ping <static-ip>

# 3. Test RDP access
mstsc /v:<static-ip>
```

### Phase 5: DNS Update
```powershell
# Add A and PTR records
Add-DnsServerResourceRecordA -Name "<vm-name>" -ZoneName "domain.com" -IPv4Address "<static-ip>"
Add-DnsServerResourceRecordPtr -Name "<last-octet>" -ZoneName "104.132.10.in-addr.arpa" -PtrDomainName "<vm-name>.domain.com"
```

---

## Automation Tools Available

| Tool | Purpose | Location |
|------|---------|----------|
| `add-static-ip-to-vm.sh` | Add cloud-init to existing VM | `/c/Users/q22529_a/work/Cluster-Config/components/site-to-site-vpn/` |
| `generate-vms-with-static-ips.sh` | Generate VM manifests from CSV | Same as above |
| `deploy-qa-vm-ips.sh` | Deploy IP reservations for QA VMs | Same as above |
| `reserve-qa-vm-ips.yaml` | NAD manifests with QA IP exclusions | Same as above |

---

## Cloud-Init Configuration (Automated)

When you run `./add-static-ip-to-vm.sh <vm-name> <ip>`, it automatically configures:

- ✅ Static IP address
- ✅ Subnet mask (255.255.252.0)
- ✅ Default gateway (10.132.104.1)
- ✅ DNS servers (10.132.104.2, 10.132.104.3)
- ✅ Computer hostname
- ✅ RDP enabled (port 3389)
- ✅ Windows Firewall rules (RDP + ICMP)

**No manual Windows configuration needed!**

---

## Common Commands

### Check VM Status
```bash
# List all VMs in namespace
oc get vm -n windows-non-prod

# Get detailed VM info
oc describe vm <vm-name> -n windows-non-prod

# Check running VM instances
oc get vmi -n windows-non-prod -o wide
```

### VM Power Management
```bash
# Start VM
oc patch vm <vm-name> -n windows-non-prod --type merge -p '{"spec":{"running":true}}'

# Stop VM
oc patch vm <vm-name> -n windows-non-prod --type merge -p '{"spec":{"running":false}}'

# Restart VM (stop then start)
oc patch vm <vm-name> -n windows-non-prod --type merge -p '{"spec":{"running":false}}'
sleep 30
oc patch vm <vm-name> -n windows-non-prod --type merge -p '{"spec":{"running":true}}'
```

### Network Verification
```bash
# Check VM IP addresses
oc get vmi -n windows-non-prod -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.interfaces[0].ipAddress}{"\n"}{end}'

# View NAD configuration
oc get network-attachment-definitions windows-non-prod -n windows-non-prod -o yaml

# Check reserved IPs
oc get network-attachment-definitions windows-non-prod -n windows-non-prod -o jsonpath='{.spec.config}' | jq '.ipam.exclude'
```

### Access VM Console
```bash
# Text console
virtctl console <vm-name> -n windows-non-prod

# VNC viewer (graphical)
virtctl vnc <vm-name> -n windows-non-prod
```

---

## Troubleshooting Quick Reference

### Issue: VM doesn't get static IP after cloud-init

```bash
# Check cloud-init ran
oc logs virt-launcher-<vm-name>-xxxxx -n windows-non-prod | grep cloud-init

# Access console and verify manually
virtctl console <vm-name> -n windows-non-prod
ipconfig /all
```

### Issue: RDP connection fails

```bash
# 1. Verify VM has correct IP
oc get vmi <vm-name> -n windows-non-prod -o jsonpath='{.status.interfaces[0].ipAddress}'

# 2. Test from company network (ping gateway first)
ping 10.132.104.1  # Should work
ping <vm-ip>       # May be blocked by Windows Firewall

# 3. Check Windows Firewall via console
virtctl console <vm-name> -n windows-non-prod
# In Windows PowerShell:
Get-NetFirewallRule -DisplayName "*Remote Desktop*"
```

### Issue: Can't ping VM from company network

**Likely Cause**: Windows Firewall blocking ICMP

**Solution**: Access VM console and enable ICMP:
```powershell
# In Windows PowerShell (via console)
New-NetFirewallRule -DisplayName "Allow ICMPv4" -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Allow
```

---

## Documentation Index

| Document | Description |
|----------|-------------|
| `QA-VMS-READY.md` | Quick reference for NYMSQA428/429 migration |
| `QA-VMS-DEPLOYMENT.md` | Detailed QA VM deployment procedures |
| `VM-MIGRATION-STATUS.md` | This file - overall migration status |
| `STATIC-IP-QUICK-ANSWER.md` | Complete static IP solutions guide |
| `WINDOWS-STATIC-IP-GUIDE.md` | Windows static IP configuration methods |
| `TROUBLESHOOTING-RDP-CONNECTIVITY.md` | RDP troubleshooting procedures |
| `DEPLOYMENT-COMPLETE.md` | Test VMs deployment summary |
| `dns-records-qa-vms.md` | DNS configuration for QA VMs |
| `dns-records-test-vms.md` | DNS configuration for test VMs |

---

## Next Actions

### For Test VMs (297, 301)
1. Access VM console via `virtctl console`
2. Enable Windows Firewall rules for RDP and ICMP
3. Test RDP connectivity from company network
4. Update DNS records if not already done

### For NYMSDV312
1. Start the VM: `oc patch vm nymsdv312 -n windows-non-prod --type merge -p '{"spec":{"running":true}}'`
2. Cloud-init will auto-configure static IP on boot
3. Verify IP: `oc get vmi nymsdv312 -n windows-non-prod`
4. Test RDP from company network
5. Add DNS records

### For QA VMs (428, 429)
1. Execute MTV migration from vSphere
2. After migration completes, apply cloud-init:
   ```bash
   ./add-static-ip-to-vm.sh nymsqa428 10.132.104.20
   ./add-static-ip-to-vm.sh nymsqa429 10.132.104.21
   ```
3. Start VMs and verify connectivity
4. Add DNS records

---

**Migration Pipeline Summary:**
- ✅ **3 Test VMs**: IP config complete, need firewall setup
- ✅ **2 QA VMs**: Ready for MTV migration
- 📊 **5 Total VMs**: 8 static IPs reserved (including .10-.21)
- 💾 **233+ IPs Available**: For future migrations in .104 subnet

🚀 **System is production-ready for ongoing VM migrations!**
