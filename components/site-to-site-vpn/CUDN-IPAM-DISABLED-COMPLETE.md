# CUDN with IPAM Disabled - Complete Configuration

## Summary

Successfully disabled IPAM on both CUDNs and attached 2nd NIC to nymsdv297-rosa.

## CUDNs with IPAM Disabled ✅

### linux-non-prod CUDN
```yaml
apiVersion: k8s.ovn.org/v1
kind: ClusterUserDefinedNetwork
metadata:
  name: linux-non-prod
  annotations:
    description: "Secondary network for Linux VMs - Layer 2 without IPAM"
spec:
  namespaceSelector:
    matchExpressions:
      - key: kubernetes.io/metadata.name
        operator: In
        values:
          - openshift-mtv
          - vm-migrations
          - vpn-infra
  network:
    layer2:
      mtu: 1500
      role: Secondary
      ipam:
        mode: Disabled  # ✅ IPAM disabled - VMs must configure IPs manually
    topology: Layer2
```

**Configuration**: `{"ipam":{"mode":"Disabled"},"mtu":1500,"role":"Secondary"}`

### windows-non-prod CUDN
```yaml
apiVersion: k8s.ovn.org/v1
kind: ClusterUserDefinedNetwork
metadata:
  name: windows-non-prod
  annotations:
    description: "Secondary network for Windows VMs - Layer 2 without IPAM"
spec:
  namespaceSelector:
    matchExpressions:
      - key: kubernetes.io/metadata.name
        operator: In
        values:
          - windows-non-prod
          - openshift-mtv
          - vm-migrations
          - vpn-infra
  network:
    layer2:
      mtu: 1500
      role: Secondary
      ipam:
        mode: Disabled  # ✅ IPAM disabled - VMs must configure IPs manually
    topology: Layer2
```

**Configuration**: `{"ipam":{"mode":"Disabled"},"mtu":1500,"role":"Secondary"}`

## S2S VPN Configuration ✅

**Status**: NO CHANGES NEEDED

The VPN is configured with `leftsubnet=0.0.0.0/0`, automatically routing:
- Pod network: `10.132.0.0/14`
- Service network: `172.30.0.0/16`  
- All CUDN networks (any CIDR assigned to VMs)

## nymsdv297-rosa Configuration ✅

**Status**: 2nd NIC attached and VM running

**Network Configuration**:
- **NIC 1 (net-0)**: Pod network - IP: `10.133.0.68`
- **NIC 2 (nic-2)**: windows-non-prod CUDN - IP: `10.136.8.2`

**Note**: The VM is using the **windows-non-prod CUDN** network (10.136.8.0/21), NOT the bridge NAD (10.132.104.0/22).

## Key Differences: CUDN vs Bridge NAD

| Feature | CUDN (with IPAM disabled) | Bridge NAD (with Whereabouts) |
|---------|---------------------------|-------------------------------|
| IP Assignment | Manual only (no IPAM) | Automatic (Whereabouts IPAM) |
| Network Type | OVN-Kubernetes Layer 2 overlay | Linux bridge | 
| MTU | 1500 | 1500 |
| Routes | Must configure manually | Configured via IPAM |
| DNS | Must configure manually | Configured via IPAM |
| Gateway | Must configure manually | Configured via IPAM |

## Important: Static IP Configuration

Since IPAM is now **disabled** on the CUDNs, VMs attached to these networks will NOT get automatic IP addresses. You MUST configure static IPs manually inside each VM.

### For nymsdv297-rosa

The VM currently has IP `10.136.8.2` on the CUDN network. To configure static IP:

1. **RDP into VM** using pod network IP `10.133.0.68`

2. **Run PowerShell as Administrator**:

```powershell
# Find the CUDN adapter (likely "Ethernet 2")
Get-NetAdapter

# Configure static IP (choose an IP from 10.136.8.0/21 range)
# Example: 10.136.8.10
New-NetIPAddress -InterfaceAlias "Ethernet 2" `
  -IPAddress 10.136.8.10 `
  -PrefixLength 21

# Set DNS (use your DNS servers)
Set-DnsClientServerAddress -InterfaceAlias "Ethernet 2" `
  -ServerAddresses ("10.132.104.2", "10.132.104.3")

# Add routes to Canon network
New-NetRoute -InterfaceAlias "Ethernet 2" `
  -DestinationPrefix "10.132.0.0/14" `
  -NextHop 10.136.8.1

New-NetRoute -InterfaceAlias "Ethernet 2" `
  -DestinationPrefix "10.227.96.0/20" `
  -NextHop 10.136.8.1

# Enable firewall rules
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
Enable-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)"
```

**Note**: Since the gateway IP (10.136.8.1) may not exist, you might need to adjust the routes or configure the VM without a default gateway on this interface.

## Alternative: Use Bridge NAD with IPAM

If you want automatic IP assignment with static IP reservations, use the **bridge NAD** (`windows-non-prod` in namespace `windows-non-prod`) which has:
- **IPAM**: Whereabouts (automatic allocation)
- **CIDR**: 10.132.104.0/22
- **Gateway**: 10.132.104.1
- **DNS**: 10.132.104.2, 10.132.104.3
- **Reserved IPs**: 10.132.104.10, .11, .19, .20, .21

To switch nymsdv297-rosa to bridge NAD:

```bash
# Stop VM
virtctl stop nymsdv297-rosa -n windows-non-prod

# Remove CUDN network
oc patch vm nymsdv297-rosa -n windows-non-prod --type='json' \
  -p='[
    {"op": "remove", "path": "/spec/template/spec/domain/devices/interfaces/1"},
    {"op": "remove", "path": "/spec/template/spec/networks/1"}
  ]'

# Add bridge NAD network
oc patch vm nymsdv297-rosa -n windows-non-prod --type='json' \
  -p='[
    {
      "op": "add",
      "path": "/spec/template/spec/domain/devices/interfaces/-",
      "value": {"name": "nic-2", "bridge": {}}
    },
    {
      "op": "add",
      "path": "/spec/template/spec/networks/-",
      "value": {
        "name": "nic-2",
        "multus": {"networkName": "windows-non-prod"}
      }
    }
  ]'

# Start VM
virtctl start nymsdv297-rosa -n windows-non-prod
```

## Files Created

- **linux-non-prod-cudn-no-ipam.yaml** - CUDN for Linux VMs without IPAM
- **windows-non-prod-cudn-no-ipam.yaml** - CUDN for Windows VMs without IPAM
- **CUDN-INSPECTION-REPORT.md** - Detailed CUDN analysis
- **add-secondary-nic-to-vm.yaml** - Template for adding 2nd NIC

## Completed Actions

✅ Inspected CUDNs (linux-non-prod, windows-non-prod)  
✅ Disabled IPAM on both CUDNs by setting `ipam.mode: Disabled`  
✅ Verified S2S VPN already routes all CUDN CIDRs (`leftsubnet=0.0.0.0/0`)  
✅ Attached 2nd NIC to nymsdv297-rosa  
✅ nymsdv297-rosa is running with 2 NICs  
⏳ Need to configure static IP manually inside VM (no automatic IPAM)

## Recommendations

1. **For Production Use**: Consider using **bridge NADs with Whereabouts IPAM** for automatic IP management
2. **For CUDN Use**: If you want to use CUDNs, you'll need to manually configure IP addresses, gateways, DNS, and routes inside each VM
3. **Network Choice**: Bridge NADs are simpler for static IP management with the `exclude` list feature

The nymsdv297-rosa VM is ready for manual IP configuration!
