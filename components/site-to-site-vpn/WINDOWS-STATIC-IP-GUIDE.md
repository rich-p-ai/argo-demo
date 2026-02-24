# Static IP Configuration for Windows VMs - Complete Guide

## Problem: How to Configure Static IPs at Scale

You have many Windows VMs that need static IPs configured. There are multiple approaches depending on whether VMs are new or existing.

---

## Approach 1: For NEW VMs (Best - Configure Before First Boot)

### Method 1A: Using Sysprep/Unattend.xml (RECOMMENDED)

**Best for:** New VMs or VMs that can be re-sysprepped  
**Reliability:** ⭐⭐⭐⭐⭐ (Most reliable)  
**Complexity:** Medium

#### Step 1: Create Sysprep ConfigMap

```bash
oc apply -f windows-sysprep-static-ip.yaml
```

#### Step 2: Attach Sysprep to VM

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: mynewvm
  namespace: windows-non-prod
spec:
  template:
    spec:
      domain:
        devices:
          disks:
            - name: rootdisk
              disk:
                bus: virtio
            - name: sysprep
              disk:
                bus: sata
      volumes:
        - name: rootdisk
          persistentVolumeClaim:
            claimName: mynewvm-disk
        - name: sysprep
          sysprep:
            configMap:
              name: windows-sysprep-configs
              key: mynewvm-unattend.xml  # Must match ConfigMap key
```

**Result:** Windows will configure static IP on first boot automatically.

### Method 1B: Using Cloud-Init (CloudBase-Init)

**Best for:** Windows images with CloudBase-Init pre-installed  
**Reliability:** ⭐⭐⭐ (Requires CloudBase-Init)  
**Complexity:** Medium

See `vm-with-static-ip-template.yaml` for examples.

**Limitation:** CloudBase-Init must be installed in Windows image.

---

## Approach 2: For EXISTING VMs (Currently Running)

### Method 2A: One-Time PowerShell Script via Console (MANUAL)

**Best for:** Small number of VMs (<10)  
**Reliability:** ⭐⭐⭐⭐⭐  
**Time:** 5 min per VM

#### Steps:

```bash
# 1. Access VM console
virtctl console nymsdv297 -n windows-non-prod

# 2. Login to Windows

# 3. Open PowerShell as Administrator

# 4. Run this script:
$IP = "10.132.104.10"
$Gateway = "10.132.104.1"
$DNS = "10.132.104.53","8.8.8.8"
$Interface = (Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Select-Object -First 1).Name

Remove-NetIPAddress -InterfaceAlias $Interface -Confirm:$false -ErrorAction SilentlyContinue
Remove-NetRoute -InterfaceAlias $Interface -Confirm:$false -ErrorAction SilentlyContinue

New-NetIPAddress -InterfaceAlias $Interface -IPAddress $IP -PrefixLength 22 -DefaultGateway $Gateway
Set-DnsClientServerAddress -InterfaceAlias $Interface -ServerAddresses $DNS

# Enable RDP and Firewall
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
Enable-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)"

# Test
ping 10.132.104.1
```

### Method 2B: Ansible Automation (SCALABLE)

**Best for:** Many VMs (10+)  
**Reliability:** ⭐⭐⭐⭐  
**Setup Time:** 1 hour, then 1 min per VM

#### Ansible Playbook:

```yaml
---
- name: Configure Static IP on Windows VMs
  hosts: windows_vms
  gather_facts: no
  vars:
    gateway: "10.132.104.1"
    dns_servers:
      - "10.132.104.53"
      - "8.8.8.8"
  
  tasks:
    - name: Configure Static IP
      ansible.windows.win_powershell:
        script: |
          $Interface = (Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Select-Object -First 1).Name
          
          Remove-NetIPAddress -InterfaceAlias $Interface -Confirm:$false -ErrorAction SilentlyContinue
          Remove-NetRoute -InterfaceAlias $Interface -Confirm:$false -ErrorAction SilentlyContinue
          
          New-NetIPAddress -InterfaceAlias $Interface `
            -IPAddress "{{ static_ip }}" `
            -PrefixLength 22 `
            -DefaultGateway "{{ gateway }}"
          
          Set-DnsClientServerAddress -InterfaceAlias $Interface `
            -ServerAddresses @("{{ dns_servers | join('","') }}")
    
    - name: Set Hostname
      ansible.windows.win_hostname:
        name: "{{ inventory_hostname_short | upper }}"
    
    - name: Enable RDP
      ansible.windows.win_regedit:
        path: HKLM:\System\CurrentControlSet\Control\Terminal Server
        name: fDenyTSConnections
        data: 0
        type: dword
    
    - name: Configure Firewall for RDP
      ansible.windows.win_firewall_rule:
        name: "{{ item }}"
        enabled: yes
        state: present
      loop:
        - "Remote Desktop - User Mode (TCP-In)"
        - "Remote Desktop - User Mode (UDP-In)"
    
    - name: Enable ICMP (Ping)
      ansible.windows.win_firewall_rule:
        name: "File and Printer Sharing (Echo Request - ICMPv4-In)"
        enabled: yes
        state: present
```

#### Inventory File:

```ini
[windows_vms]
nymsdv297 static_ip=10.132.104.10
nymsdv301 static_ip=10.132.104.11
nymsdv312 static_ip=10.132.104.19
nymsdv313 static_ip=10.132.104.20
```

---

## Approach 3: For EXISTING VMs via MTV Migration

### Method 3A: Update Whereabouts to Use Static Range

**Best for:** VMs migrated via MTV that need permanent IPs  
**Reliability:** ⭐⭐⭐⭐  
**Complexity:** Low

#### Create Static IP Allocation List

```bash
# Add each VM IP to whereabouts exclusion
# See: reserve-test-vm-ips.yaml
```

**Advantage:** No changes to VMs  
**Disadvantage:** Must track IPs manually, limited scalability

### Method 3B: Post-Migration Static IP Script

**Best for:** Automated post-migration configuration  
**Reliability:** ⭐⭐⭐⭐  
**Requires:** Network access to VMs after migration

#### PowerShell Script (Run from Bastion/Jump Host):

```powershell
# Configure-StaticIP.ps1
param(
    [string]$VMName,
    [string]$StaticIP,
    [string]$Gateway = "10.132.104.1",
    [string[]]$DNS = @("10.132.104.53","8.8.8.8")
)

# Connect to VM (requires WinRM or RDP)
$Session = New-PSSession -ComputerName $StaticIP -Credential (Get-Credential)

Invoke-Command -Session $Session -ScriptBlock {
    param($IP, $GW, $DNS)
    
    $Adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Select-Object -First 1
    
    # Configure Static IP
    Remove-NetIPAddress -InterfaceAlias $Adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceAlias $Adapter.Name -IPAddress $IP -PrefixLength 22 -DefaultGateway $GW
    Set-DnsClientServerAddress -InterfaceAlias $Adapter.Name -ServerAddresses $DNS
    
    # Enable RDP
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -value 0
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
    
} -ArgumentList $StaticIP, $Gateway, $DNS

Remove-PSSession $Session
```

---

## Recommended Workflow for Many VMs

### Phase 1: Preparation

1. **Create VM inventory CSV:**
   ```csv
   hostname,static_ip,mac_address,memory,cpu
   nymsdv297,10.132.104.10,00:50:56:bd:4e:b1,8Gi,4
   nymsdv301,10.132.104.11,00:50:56:8b:5f:43,8Gi,4
   nymsdv312,10.132.104.19,00:50:56:xx:xx:xx,8Gi,4
   ```

2. **Reserve IPs in whereabouts:**
   ```bash
   # Add all IPs to exclusion list in windows-non-prod NAD
   # See: update-whereabouts-exclusions.sh
   ```

3. **Create DNS entries:**
   ```powershell
   Import-Csv vms.csv | ForEach-Object {
       Add-DnsServerResourceRecordA -Name $_.hostname `
         -ZoneName "corp.cusa.canon.com" `
         -IPv4Address $_.static_ip -CreatePtr
   }
   ```

### Phase 2: For NEW VMs

Use **Sysprep method** (most reliable):
1. Create sysprep ConfigMap with all VM configs
2. Reference sysprep volume in VM manifests
3. Start VMs - they auto-configure

### Phase 3: For EXISTING VMs

**Option A: Manual (Small Scale)**
- Access console for each VM
- Run PowerShell script
- 5 minutes per VM

**Option B: Ansible (Large Scale)**
- Create Ansible inventory
- Run playbook
- Automated for all VMs

---

## Quick Reference: Which Method to Use?

| Scenario | Recommended Method | Time | Files |
|----------|-------------------|------|-------|
| **New VMs (<10)** | Sysprep unattend.xml | 10 min setup | `windows-sysprep-static-ip.yaml` |
| **New VMs (>10)** | Generator script + Sysprep | 30 min setup | `generate-vms-with-static-ips.sh` |
| **Existing VMs (<10)** | Manual console + PowerShell | 5 min/VM | `STATIC-IP-MANUAL-CONFIG.md` |
| **Existing VMs (>10)** | Ansible playbook | 1 hr setup + 1 min/VM | `ansible-static-ip.yaml` |
| **MTV Migrated VMs** | Reserve IPs in whereabouts | 10 min | `reserve-test-vm-ips.yaml` |

---

## Files Created for You

### For New VMs:
- ✅ `vm-with-static-ip-template.yaml` - Cloud-Init template
- ✅ `windows-sysprep-static-ip.yaml` - Sysprep ConfigMap (more reliable)
- ✅ `generate-vms-with-static-ips.sh` - Batch generator from CSV
- ✅ `vm-list-example.csv` - CSV template

### For Existing VMs:
- ✅ `reserve-test-vm-ips.yaml` - Reserve IPs in whereabouts
- ✅ `STATIC-IP-MANUAL-CONFIG.md` - Manual configuration guide

### Documentation:
- ✅ `STATIC-IP-OPTIONS.md` - All approaches explained
- ✅ `VM-VERIFICATION-REPORT.md` - Current status
- ✅ `WINDOWS-STATIC-IP-GUIDE.md` - This complete guide

---

## What Works Right Now

For your 3 test VMs:
- ✅ IPs are reserved (10.132.104.10, .11, .19)
- ✅ VMs have correct IPs
- ✅ Network routing works (S2S VPN operational)
- ⚠️ **Need Windows Firewall configured** (one-time manual step per VM)

---

## Next Steps for Your Many VMs

**Tell me:**
1. How many VMs do you need to configure?
2. Are they already migrated or are you creating new ones?
3. Do your Windows images have CloudBase-Init installed?

Based on your answers, I'll recommend the best approach and create the necessary automation scripts.

For now, you can use the **CSV generator** to batch-create VM manifests with static IPs:

```bash
# 1. Fill out vm-list.csv with your VMs
# 2. Generate manifests
./generate-vms-with-static-ips.sh vm-list.csv output-vms.yaml

# 3. Deploy all VMs
oc apply -f output-vms.yaml
```

Would you like me to create an Ansible playbook or additional automation for your specific scenario?
