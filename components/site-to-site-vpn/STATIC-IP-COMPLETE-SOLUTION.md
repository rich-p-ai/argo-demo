# Static IP Implementation - Complete Solution

## ✅ What You Have Now

### For Test VMs (NYMSDV297, NYMSDV301, NYMSDV312)

**Status:** ✅ Static IPs Reserved and Working

| Component | Status | Details |
|-----------|--------|---------|
| **IP Reservation** | ✅ Complete | IPs .10, .11, .19 excluded from whereabouts |
| **Network Routing** | ✅ Working | S2S VPN routes 10.132.104.0/22 correctly |
| **VM IPs** | ✅ Assigned | VMs have correct IPs |
| **S2S VPN** | ✅ Working | Gateway 10.132.104.1 responds from company |
| **Firewall** | ⚠️ Needs Config | Must enable RDP in each VM |

---

## 📋 For Your Many VMs - Multiple Solutions

### Option 1: Sysprep with Static IP (NEW VMs) - BEST ⭐

**Use when:** Creating new VMs or can re-sysprep existing ones  
**Configures:** Before first boot automatically  
**Scale:** Unlimited  
**Effort:** 5 min per VM (config file creation)

#### Files Created:
- `windows-sysprep-static-ip.yaml` - Sysprep ConfigMap template
- Edit this file to add your VMs

#### Example: Add 10 VMs

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: windows-sysprep-configs
  namespace: windows-non-prod
data:
  vm1-unattend.xml: |
    <?xml version="1.0"?>
    <unattend xmlns="urn:schemas-microsoft-com:unattend">
      <settings pass="specialize">
        <component name="Microsoft-Windows-TCPIP">
          <Interfaces>
            <Interface>
              <Identifier>Ethernet</Identifier>
              <Ipv4Settings><DhcpEnabled>false</DhcpEnabled></Ipv4Settings>
              <UnicastIpAddresses>
                <IpAddress wcm:keyValue="1">10.132.104.100/22</IpAddress>
              </UnicastIpAddresses>
              <Routes>
                <Route><Prefix>0.0.0.0/0</Prefix><NextHopAddress>10.132.104.1</NextHopAddress></Route>
              </Routes>
            </Interface>
          </Interfaces>
        </component>
        <component name="Microsoft-Windows-Shell-Setup">
          <ComputerName>VM1-HOSTNAME</ComputerName>
        </component>
      </settings>
    </unattend>
  
  vm2-unattend.xml: |
    # ... repeat for each VM with different IP
```

**Then in VM manifest:**

```yaml
volumes:
  - name: sysprep
    sysprep:
      configMap:
        name: windows-sysprep-configs
        key: vm1-unattend.xml
```

---

### Option 2: Cloud-Init Script Generator (NEW VMs)

**Use when:** Windows images have CloudBase-Init  
**Configures:** On first boot  
**Scale:** Unlimited via script  
**Effort:** Automatic from CSV

#### Files Created:
- `generate-vms-with-static-ips.sh` - Batch generator
- `vm-list-example.csv` - CSV template

#### Workflow:

```bash
# 1. Create CSV with all your VMs
cat > my-vms.csv <<EOF
hostname,ip,mac_address,memory,cpu,disk_pvc
nymsdv313,10.132.104.20,00:50:56:xx:xx:xx,8Gi,4,nymsdv313-disk
nymsdv314,10.132.104.21,00:50:56:xx:xx:xx,16Gi,8,nymsdv314-disk
nymsdv315,10.132.104.22,00:50:56:xx:xx:xx,8Gi,4,nymsdv315-disk
EOF

# 2. Generate manifests
./generate-vms-with-static-ips.sh my-vms.csv all-vms.yaml

# 3. Apply to cluster
oc apply -f all-vms.yaml

# 4. Start VMs - they auto-configure
oc patch vm nymsdv313 -n windows-non-prod --type merge -p '{"spec":{"running":true}}'
```

---

### Option 3: Manual Console Configuration (EXISTING VMs)

**Use when:** VMs already running, small number  
**Configures:** Now  
**Scale:** <10 VMs  
**Effort:** 5 min per VM

#### Quick Script for Each VM:

```powershell
# Replace IP for each VM
$IP = "10.132.104.10"  # CHANGE THIS
$Adapter = (Get-NetAdapter | Where-Object {$_.Status -eq "Up"})[0].Name

Remove-NetIPAddress -InterfaceAlias $Adapter -Confirm:$false -ErrorAction SilentlyContinue
Remove-NetRoute -InterfaceAlias $Adapter -Confirm:$false -ErrorAction SilentlyContinue

New-NetIPAddress -InterfaceAlias $Adapter -IPAddress $IP -PrefixLength 22 -DefaultGateway "10.132.104.1"
Set-DnsClientServerAddress -InterfaceAlias $Adapter -ServerAddresses "10.132.104.53","8.8.8.8"

Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
Enable-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)"
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -value 0

ping 10.132.104.1
```

---

### Option 4: Batch Update Script (EXISTING VMs)

**Use when:** Many existing VMs, can access via console or WinRM  
**Configures:** Via automation  
**Scale:** Unlimited  
**Effort:** 1 hour setup

See Ansible playbook in `WINDOWS-STATIC-IP-GUIDE.md`

---

## Recommended Approach for Your Situation

**If you have MANY VMs to configure:**

### For NEW VMs (Not yet created):
✅ **Use Sysprep method** - Most reliable, configures before first boot

**Steps:**
1. Create sysprep ConfigMap with all VMs
2. Use generator script or template
3. Deploy VMs with sysprep volume
4. Start VMs - auto-configure

### For EXISTING VMs (Already running):
✅ **Reserve IPs in whereabouts** (what we just did)

**Then choose:**
- **Manual (<10 VMs):** Console + PowerShell script
- **Automated (>10 VMs):** Ansible playbook

---

## What Needs to Happen for RDP to Work

**Current Situation:**
- ✅ VMs have static IPs
- ✅ IPs are reserved
- ✅ Network routing works
- ❌ Windows Firewall blocking RDP

**Required Action:**

For **each existing VM** (NYMSDV297, NYMSDV301), you must:

1. Access console: `virtctl console <vmname> -n windows-non-prod`
2. Login to Windows
3. Run PowerShell script to enable RDP
4. Test from company network

**For future VMs**, use the Sysprep or Cloud-Init methods so this happens automatically.

---

## Files Summary

### Automated Solutions:
| File | Purpose | Use Case |
|------|---------|----------|
| `windows-sysprep-static-ip.yaml` | Sysprep ConfigMap | NEW VMs (best) |
| `vm-with-static-ip-template.yaml` | Cloud-Init template | NEW VMs (CloudBase-Init) |
| `generate-vms-with-static-ips.sh` | Batch generator | NEW VMs from CSV |
| `vm-list-example.csv` | CSV template | Input for generator |

### Manual Solutions:
| File | Purpose | Use Case |
|------|---------|----------|
| `reserve-test-vm-ips.yaml` | Reserve IPs | EXISTING VMs |
| `WINDOWS-STATIC-IP-GUIDE.md` | Complete guide | All scenarios |
| `STATIC-IP-MANUAL-CONFIG.md` | Manual steps | Small scale |

### Verification:
| File | Purpose |
|------|---------|
| `VM-VERIFICATION-REPORT.md` | Test results |
| `TROUBLESHOOTING-RDP-CONNECTIVITY.md` | Diagnostics |
| `dns-records-test-vms.md` | DNS setup |

---

## Next Steps

**Tell me:**
1. **How many VMs** do you need to configure?
2. **Are they migrated already** or creating new?
3. **Preferred method:**
   - Sysprep (new VMs, most reliable)
   - Cloud-Init (requires CloudBase-Init)
   - Manual (small number)
   - Ansible (large number, existing VMs)

I can then create the exact files/scripts you need for your specific scenario.

**For now:** Your test VMs (297, 301, 312) are ready - just need Windows Firewall enabled to allow RDP.
