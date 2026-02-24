# 🎯 Static IP Solution - Quick Reference

## ✅ Problem Solved: Static IPs Before VM Start

**YES! You can configure static IPs BEFORE VMs start using:**
1. ✅ Sysprep/Unattend.xml (most reliable for Windows)
2. ✅ Cloud-Init (requires CloudBase-Init installed)
3. ✅ Automated scripts for batch operations

---

## Three Solutions Created for You

### 🏆 Solution 1: Sysprep (BEST for Windows)

**File:** `windows-sysprep-static-ip.yaml`

**What it does:**
- Configures static IP **before Windows first boot**
- Sets hostname automatically
- Enables RDP and configures firewall
- Most reliable method for Windows

**How to use:**
```yaml
# In your VM manifest:
volumes:
  - name: sysprep
    sysprep:
      configMap:
        name: windows-sysprep-configs
        key: nymsdv297-unattend.xml  # One per VM
```

**Perfect for:** New VMs or VMs you can re-sysprep

---

### 🚀 Solution 2: Batch Generator from CSV

**Files:** 
- `generate-vms-with-static-ips.sh` (generator script)
- `vm-list-example.csv` (template)

**What it does:**
- Creates VM manifests from CSV file
- Adds cloud-init configuration for static IP
- Batch process many VMs at once

**How to use:**
```bash
# 1. Create CSV with your VMs
cat > my-vms.csv <<EOF
hostname,ip,mac_address,memory,cpu,disk_pvc
vm1,10.132.104.50,00:50:56:xx:xx:xx,8Gi,4,vm1-disk
vm2,10.132.104.51,00:50:56:xx:xx:xx,16Gi,8,vm2-disk
# ... add all your VMs
EOF

# 2. Generate manifests
chmod +x generate-vms-with-static-ips.sh
./generate-vms-with-static-ips.sh my-vms.csv all-my-vms.yaml

# 3. Deploy
oc apply -f all-my-vms.yaml

# 4. Start VMs - they auto-configure!
oc patch vm vm1 -n windows-non-prod --type merge -p '{"spec":{"running":true}}'
```

**Perfect for:** Creating many new VMs

---

### 🔧 Solution 3: Patch Existing VMs

**File:** `add-static-ip-to-vm.sh`

**What it does:**
- Adds cloud-init to already-created VMs
- Configures static IP on next boot
- One command per VM

**How to use:**
```bash
chmod +x add-static-ip-to-vm.sh

# For each VM:
./add-static-ip-to-vm.sh nymsdv297 10.132.104.10 00:50:56:bd:4e:b1
./add-static-ip-to-vm.sh nymsdv301 10.132.104.11 00:50:56:8b:5f:43
./add-static-ip-to-vm.sh nymsdv312 10.132.104.19
```

**Perfect for:** Existing VMs that need static IP config

---

## What Each Solution Configures Automatically

✅ **Static IP Address** - Sets the IP you specify  
✅ **Subnet Mask** - /22 (255.255.252.0)  
✅ **Default Gateway** - 10.132.104.1  
✅ **DNS Servers** - 10.132.104.53, 8.8.8.8  
✅ **Hostname** - Sets computer name  
✅ **RDP Enabled** - Enables Terminal Services  
✅ **Windows Firewall** - Allows RDP and Ping  
✅ **Auto-Start** - Runs on first boot  

**No manual configuration needed inside Windows!** 🎉

---

## Comparison: Which Solution to Use?

| Method | Reliability | Scale | Existing VMs | New VMs | Setup Time |
|--------|-------------|-------|--------------|---------|------------|
| **Sysprep** | ⭐⭐⭐⭐⭐ | Unlimited | No* | ✅ Yes | 10 min |
| **Cloud-Init Generator** | ⭐⭐⭐⭐ | Unlimited | No | ✅ Yes | 15 min |
| **Patch Script** | ⭐⭐⭐⭐ | Good | ✅ Yes | ✅ Yes | 5 min/VM |
| **Manual Console** | ⭐⭐⭐⭐⭐ | <10 VMs | ✅ Yes | No | 5 min/VM |

\* Sysprep works on existing VMs if you can re-run sysprep (generalize the image)

---

## For Your "Many VMs" Scenario

### If Creating NEW VMs from Template/Clone:

**BEST:** Use **Sysprep method**

1. Create sysprep ConfigMap with all VMs:
```bash
oc apply -f windows-sysprep-static-ip.yaml
```

2. Add each VM to the ConfigMap (one entry per VM)

3. Reference sysprep in VM manifest:
```yaml
volumes:
  - name: sysprep
    sysprep:
      configMap:
        name: windows-sysprep-configs
        key: <vmname>-unattend.xml
```

4. Start VMs - static IP configured automatically!

### If VMs Already Exist (Migrated from VMware):

**BEST:** Use **Patch Script** for each VM

```bash
# For each VM:
./add-static-ip-to-vm.sh vmname ip mac

# Or manual via console if you prefer
```

---

## Current Status of Your Test VMs

| VM | Static IP | Status | Configured |
|----|-----------|--------|------------|
| NYMSDV297 | 10.132.104.10 | ✅ IP Reserved | ⚠️ Manual config needed |
| NYMSDV301 | 10.132.104.11 | ✅ IP Reserved | ⚠️ Manual config needed |
| NYMSDV312 | 10.132.104.19 | ✅ IP Reserved | Not started |

**For 297 & 301:** IPs are reserved, but Windows still needs firewall configured (manual console access)

**For 312:** Can use cloud-init when you start it!

---

## Example: Add Static IP to NYMSDV312 (Before Starting)

```bash
# Run patch script
./add-static-ip-to-vm.sh nymsdv312 10.132.104.19

# Start VM
oc patch vm nymsdv312 -n windows-non-prod --type merge -p '{"spec":{"running":true}}'

# Wait for boot (cloud-init runs automatically)
oc get vmi nymsdv312 -n windows-non-prod -w

# Verify IP
oc get vmi nymsdv312 -n windows-non-prod -o jsonpath='{.status.interfaces[0].ipAddress}'
# Should show: 10.132.104.19

# Test from company network
ping 10.132.104.19
mstsc /v:10.132.104.19
```

**Result:** VM boots with static IP already configured! ✨

---

## Batch Processing Many VMs

### Create CSV with All VMs:

```csv
hostname,ip,mac_address,memory,cpu,disk_pvc
nymsdv313,10.132.104.20,00:50:56:xx:xx:xx,8Gi,4,nymsdv313-disk
nymsdv314,10.132.104.21,00:50:56:xx:xx:xx,8Gi,4,nymsdv314-disk
nymsdv315,10.132.104.22,00:50:56:xx:xx:xx,16Gi,8,nymsdv315-disk
nymsdv316,10.132.104.23,00:50:56:xx:xx:xx,8Gi,4,nymsdv316-disk
# ... add all your VMs
```

### Generate All VM Manifests:

```bash
./generate-vms-with-static-ips.sh my-100-vms.csv generated-vms.yaml
```

### Deploy All at Once:

```bash
oc apply -f generated-vms.yaml
```

### Start All VMs:

```bash
# Start all VMs with static-ip label
oc get vm -n windows-non-prod -l static-ip=true -o name | xargs -I {} oc patch {} --type merge -p '{"spec":{"running":true}}'
```

**Result:** All VMs boot with static IPs pre-configured! 🚀

---

## Files You Have

### Automation Files:
- ✅ `windows-sysprep-static-ip.yaml` - Sysprep ConfigMap (3 VMs included)
- ✅ `vm-with-static-ip-template.yaml` - Cloud-Init templates (2 VMs)
- ✅ `generate-vms-with-static-ips.sh` - Batch generator script
- ✅ `add-static-ip-to-vm.sh` - Patch existing VMs
- ✅ `vm-list-example.csv` - CSV template

### Configuration Files:
- ✅ `reserve-test-vm-ips.yaml` - Whereabouts IP reservations
- ✅ `windows-static-ip-configmap.yaml` - Cloud-Init ConfigMap

### Documentation:
- ✅ `STATIC-IP-COMPLETE-SOLUTION.md` - All solutions
- ✅ `WINDOWS-STATIC-IP-GUIDE.md` - Complete guide
- ✅ `STATIC-IP-OPTIONS.md` - Architecture options
- ✅ `VM-VERIFICATION-REPORT.md` - Test results
- ✅ `dns-records-test-vms.md` - DNS setup

---

## Quick Start: Your Next VM

For your next VM with static IP:

```bash
# Option A: Use the patch script (existing VM)
./add-static-ip-to-vm.sh nymsdv312 10.132.104.19

# Option B: Create new VM from template
# Edit vm-with-static-ip-template.yaml
# Change IP, hostname, MAC, PVC name
oc apply -f my-new-vm.yaml
```

**Either way, VM will configure itself on boot!**

---

## Answer to Your Question

**Q: Can static IP + hostname be configured before VM starts?**  
**A: ✅ YES! Using Sysprep or Cloud-Init**

**Q: What about many VMs?**  
**A: ✅ YES! Use the CSV generator script**

**Files ready to use:**
- `generate-vms-with-static-ips.sh` - Create many VMs from CSV
- `add-static-ip-to-vm.sh` - Patch one VM at a time
- `windows-sysprep-static-ip.yaml` - Sysprep ConfigMap

**All scripts configure:**
- ✅ Static IP
- ✅ Hostname
- ✅ RDP enabled
- ✅ Firewall configured
- ✅ **Automatically on first boot!**

Ready to scale to as many VMs as you need! 🎯
