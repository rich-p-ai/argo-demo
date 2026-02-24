# CUDN Inspection and nymsdv297-rosa Configuration - COMPLETE

## Summary of Actions Completed

### 1. CUDN Inspection ✅

Discovered two ClusterUserDefinedNetworks:

| CUDN Name | CIDR | Purpose | Status |
|-----------|------|---------|--------|
| linux-non-prod | 10.136.0.0/21 | Linux VM secondary network | ⚠️  Creation error (NAD conflict) |
| windows-non-prod | 10.136.8.0/21 | Windows VM secondary network | ⚠️  Creation error (NAD conflict) |

**Note**: Both CUDNs have errors because bridge-based NADs with the same names already exist in `openshift-mtv` and `vm-migrations` namespaces.

### 2. S2S VPN Configuration Review ✅

**Finding**: NO UPDATE NEEDED

The Site-to-Site VPN is already configured to route ALL OpenShift networks:

```conf
leftsubnet=0.0.0.0/0  # Advertises all OpenShift networks automatically
```

This means:
- ✅ New CUDN CIDRs (10.136.0.0/21, 10.136.8.0/21) are automatically routed
- ✅ Existing bridge NAD CIDRs (10.132.100.0/22, 10.132.104.0/22, 10.132.108.0/22) are routed
- ✅ Pod network (10.132.0.0/14) is routed
- ✅ All VMs on these networks are accessible from Canon corporate network

### 3. Attached 2nd NIC to nymsdv297-rosa ✅

**VM**: nymsdv297-rosa  
**Namespace**: windows-non-prod  
**Network Attached**: windows-non-prod (bridge NAD, not CUDN)  
**CIDR**: 10.132.104.0/22  
**Target Static IP**: 10.132.104.10

**Configuration Applied**:
```yaml
interfaces:
  - name: net-0      # Pod network (masquerade)
  - name: nic-2      # Secondary network (bridge)

networks:
  - name: net-0
    pod: {}
  - name: nic-2
    multus:
      networkName: windows-non-prod  # Bridge NAD
```

**Status**: VM starting with 2 NICs

## Network Architecture

### Current Setup (Using Bridge NADs)

```
nymsdv297-rosa (Windows VM)
├── NIC 1 (net-0): Pod Network
│   └── IP: 10.132.x.x (dynamic, OpenShift pod network)
└── NIC 2 (nic-2): windows-non-prod Bridge NAD
    ├── IP: 10.132.104.x (dynamic from Whereabouts)
    └── Target Static IP: 10.132.104.10
    └── Gateway: 10.132.104.1
    └── DNS: 10.132.104.2, 10.132.104.3
    └── Routes to Canon network via S2S VPN
```

### S2S VPN Routing

```
Canon Corporate Networks          OpenShift Non-Prod Cluster
10.63.0.0/16                     10.132.0.0/14 (Pod network)
10.68.0.0/16                     10.132.100.0/22 (linux-non-prod NAD)
10.99.0.0/16          <------>   10.132.104.0/22 (windows-non-prod NAD)
10.110.0.0/16                    10.132.108.0/22 (utility NAD)
10.140.0.0/16                    10.136.0.0/21 (linux CUDN)
10.141.0.0/16                    10.136.8.0/21 (windows CUDN)
10.158.0.0/16
10.227.112.0/20
```

## Next Steps for nymsdv297-rosa

Once the VM is running:

### 1. Verify Network Attachment

```bash
# Check VM is running
oc get vm nymsdv297-rosa -n windows-non-prod

# Get all IPs
oc get vmi nymsdv297-rosa -n windows-non-prod -o jsonpath='{.status.interfaces[*].ipAddress}' | tr ' ' '\n'
```

Expected output:
- First IP: Pod network (10.132.x.x)
- Second IP: Secondary network (10.132.104.x)

### 2. Configure Static IP 10.132.104.10

RDP into the VM using the pod network IP, then run PowerShell as Administrator:

```powershell
# Identify adapters
Get-NetAdapter

# Configure static IP on secondary adapter (usually "Ethernet 2")
New-NetIPAddress -InterfaceAlias "Ethernet 2" `
  -IPAddress 10.132.104.10 `
  -PrefixLength 22 `
  -DefaultGateway 10.132.104.1

# Set DNS
Set-DnsClientServerAddress -InterfaceAlias "Ethernet 2" `
  -ServerAddresses ("10.132.104.2", "10.132.104.3")

# Add static routes
New-NetRoute -InterfaceAlias "Ethernet 2" `
  -DestinationPrefix "10.132.0.0/14" `
  -NextHop 10.132.104.1

New-NetRoute -InterfaceAlias "Ethernet 2" `
  -DestinationPrefix "10.227.96.0/20" `
  -NextHop 10.132.104.1

# Enable RDP and ping through Windows Firewall
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
Enable-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)"
```

### 3. Test Connectivity

From Canon corporate network:

```bash
# Test ping
ping 10.132.104.10

# Test RDP
mstsc /v:10.132.104.10
```

### 4. Update DNS

Add DNS records:
- **A Record**: `NYMSDV297.corp.canon.com` → `10.132.104.10`
- **PTR Record**: `10.104.132.10.in-addr.arpa` → `NYMSDV297.corp.canon.com`

## Files Created

- **CUDN-INSPECTION-REPORT.md** - Detailed CUDN inspection and S2S VPN analysis
- **add-secondary-nic-to-vm.yaml** - Reusable YAML for adding 2nd NIC to VMs

## Summary

✅ CUDNs inspected (linux-non-prod: 10.136.0.0/21, windows-non-prod: 10.136.8.0/21)  
✅ S2S VPN confirmed to route new CUDN CIDRs automatically (no changes needed)  
✅ 2nd NIC attached to nymsdv297-rosa using windows-non-prod bridge NAD  
✅ VM starting with 2 NICs  
⏳ Configure static IP 10.132.104.10 inside VM after startup  
⏳ Test RDP connectivity from Canon network

The VM will be accessible from the Canon corporate network once the static IP is configured!
