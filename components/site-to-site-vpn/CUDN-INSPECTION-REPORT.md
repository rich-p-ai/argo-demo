# New CUDN Inspection and S2S VPN Configuration

## Date: 2026-02-11

## CUDNs Discovered

### 1. linux-non-prod CUDN
```yaml
apiVersion: k8s.ovn.org/v1
kind: ClusterUserDefinedNetwork
metadata:
  name: linux-non-prod
  annotations:
    description: "Secondary network for Linux VMs - 10.136.0.0/21"
    network.openshift.io/purpose: vm-migration-linux
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
      subnets:
        - 10.136.0.0/21
    topology: Layer2
```

**CIDR**: `10.136.0.0/21` (10.136.0.0 - 10.136.7.255)  
**Usable IPs**: 2,046 addresses  
**Purpose**: Linux VM migrations

### 2. windows-non-prod CUDN
```yaml
apiVersion: k8s.ovn.org/v1
kind: ClusterUserDefinedNetwork
metadata:
  name: windows-non-prod
  annotations:
    description: "Secondary network for Windows VMs - 10.136.8.0/21"
    network.openshift.io/purpose: vm-migration-windows
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
      subnets:
        - 10.136.8.0/21
    topology: Layer2
```

**CIDR**: `10.136.8.0/21` (10.136.8.0 - 10.136.15.255)  
**Usable IPs**: 2,046 addresses  
**Purpose**: Windows VM migrations

## S2S VPN Configuration Review

### Current Configuration

**Location**: ConfigMap `ipsec-config` in namespace `site-to-site-vpn`

**Key Settings**:
```conf
conn %default
    leftsubnet=0.0.0.0/0  # ✅ Advertises ALL OpenShift networks
    
    # Canon corporate networks
    rightsubnet=10.63.0.0/16,10.68.0.0/16,10.99.0.0/16,10.110.0.0/16,\
                10.140.0.0/16,10.141.0.0/16,10.158.0.0/16,10.227.112.0/20
```

### Analysis

✅ **NO UPDATE NEEDED** - The S2S VPN is configured with `leftsubnet=0.0.0.0/0`, which means:

1. **All OpenShift networks are advertised** automatically, including:
   - Pod network: `10.132.0.0/14`
   - Service network: `172.30.0.0/16`
   - **New CUDN networks**:
     - Linux CUDN: `10.136.0.0/21`
     - Windows CUDN: `10.136.8.0/21`

2. **Routing is automatic** - The VPN gateway will route traffic to any IP in these ranges

3. **Canon networks** can access VMs on the new CUDNs immediately

### Network Summary

| Network Type | CIDR | Purpose | VPN Accessible |
|--------------|------|---------|----------------|
| Pod Network | 10.132.0.0/14 | OpenShift pods/containers | ✅ Yes |
| Service Network | 172.30.0.0/16 | Kubernetes services | ✅ Yes |
| Linux CUDN | 10.136.0.0/21 | Linux VM secondary network | ✅ Yes |
| Windows CUDN | 10.136.8.0/21 | Windows VM secondary network | ✅ Yes |
| Old Bridge NADs | 10.132.100.0/22, 10.132.104.0/22, 10.132.108.0/22 | Legacy VM networks | ✅ Yes |

## CUDN Status

Both CUDNs show an error in their status:

```
Status: False
Type: NetworkCreated
Message: foreign NetworkAttachmentDefinition with the desired name already exist
```

**Cause**: The old bridge-based NADs (`linux-non-prod`, `windows-non-prod`) already exist in `openshift-mtv` and `vm-migrations` namespaces.

**Impact**: 
- ⚠️  The CUDNs cannot create Layer 2 NADs with the same names
- ✅ The existing bridge-based NADs are still functional
- ✅ VMs can still attach to these networks

**Resolution Options**:
1. **Rename the CUDNs** to avoid conflicts (e.g., `linux-cudn`, `windows-cudn`)
2. **Delete old NADs** and let CUDNs recreate them (requires VM downtime)
3. **Use existing bridge NADs** and delete the CUDNs

## Recommendation for nymsdv297-rosa

**Current State**: nymsdv297-rosa is running with only pod network (net-0)

**Recommended Action**: Attach to **windows-non-prod bridge NAD** (10.132.104.0/22), NOT the CUDN

**Reason**:
- The bridge NAD is proven to work (NYMSDV301, NYMSDV312 use it)
- The CUDN has creation errors
- The bridge NAD CIDR (10.132.104.0/22) is already routed through the S2S VPN
- Static IP 10.132.104.10 is already reserved for NYMSDV297

**Steps**:
1. Stop nymsdv297-rosa
2. Add secondary NIC attached to `windows-non-prod` bridge NAD
3. Start VM
4. Configure static IP 10.132.104.10 inside the VM

## Next Actions

1. ✅ S2S VPN - No changes needed (already routes new CUDNs)
2. 🔄 Attach 2nd NIC to nymsdv297-rosa using bridge NAD
3. ⏳ Decision needed: Rename/fix CUDNs or continue using bridge NADs
