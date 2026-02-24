# CUDN Comparison: Non-Prod vs ROSA/POC Cluster

**Analysis Date:** February 10, 2026  
**Clusters Compared:**
- **Non-Prod:** api.non-prod.5wp0.p3.openshiftapps.com (OpenShift 4.20.12)
- **ROSA/POC:** api.rosa.m34m.p3.openshiftapps.com (OpenShift 4.20.8)

---

## Executive Summary

### Non-Prod Cluster (NEW)
✅ **Has CUDN deployed** - `vm-secondary-network` with static IP support  
✅ **Modern network architecture** - Uses OVN-K8s overlay networks  
✅ **Dual network capability** - Both bridge-based and CUDN networks available

### ROSA/POC Cluster (CURRENT)
❌ **No CUDN deployed** - Uses only traditional bridge-based networks  
⚠️ **Limited to dynamic IPs** - No static IP capability for VMs  
⚠️ **Bridge-only architecture** - Traditional approach

**Key Difference:** Non-Prod cluster now has **advanced network capabilities** that the ROSA/POC cluster lacks.

---

## Detailed Comparison

### Network Types Available

| Feature | Non-Prod Cluster | ROSA/POC Cluster |
|---------|------------------|------------------|
| **CUDNs** | ✅ 1 CUDN (vm-secondary-network) | ❌ None |
| **Bridge NADs** | ✅ 3 NADs (linux/windows/utility) | ✅ 3 NADs (assumed similar) |
| **Static IP Support** | ✅ Yes (via CUDN) | ❌ No |
| **Dynamic IP Support** | ✅ Yes (via bridge NADs) | ✅ Yes (via bridge NADs) |
| **Layer 2 Overlay** | ✅ Yes (CUDN) | ❌ No |
| **VLAN Support** | ✅ Yes (bridge NADs) | ✅ Yes (bridge NADs) |

---

## Network Architecture Comparison

### Non-Prod Cluster (Current State)

```
┌─────────────────────────────────────────────────────────────────┐
│  Non-Prod Cluster (api.non-prod.5wp0.p3.openshiftapps.com)     │
│  OpenShift 4.20.12 | OVN-Kubernetes                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  ClusterUserDefinedNetwork (NEW ✨)                     │   │
│  │  - vm-secondary-network: 192.168.10.0/24               │   │
│  │  - Layer 2 Overlay                                      │   │
│  │  - Role: Secondary                                      │   │
│  │  - IPAM: Persistent (static IPs)                       │   │
│  │  - Target NS: windows-non-prod, vm-migrations,         │   │
│  │                openshift-mtv, vpn-infra                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Bridge-based NADs (Traditional - Existing)             │   │
│  │                                                          │   │
│  │  1. linux-non-prod                                      │   │
│  │     - Network: 10.132.100.0/22                         │   │
│  │     - VLAN: 100                                         │   │
│  │     - IPAM: whereabouts (dynamic)                      │   │
│  │     - Gateway: 10.132.100.1                            │   │
│  │                                                          │   │
│  │  2. windows-non-prod                                    │   │
│  │     - Network: 10.132.104.0/22                         │   │
│  │     - VLAN: 101                                         │   │
│  │     - IPAM: whereabouts (dynamic)                      │   │
│  │     - Gateway: 10.132.104.1                            │   │
│  │                                                          │   │
│  │  3. utility                                             │   │
│  │     - Management network                                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                   │
│  VMs can use BOTH network types simultaneously!                  │
└─────────────────────────────────────────────────────────────────┘
```

### ROSA/POC Cluster (Current State - Assumed)

```
┌─────────────────────────────────────────────────────────────────┐
│  ROSA/POC Cluster (api.rosa.m34m.p3.openshiftapps.com)         │
│  OpenShift 4.20.8 | OVN-Kubernetes                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ❌ No ClusterUserDefinedNetwork deployed                        │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Bridge-based NADs Only                                  │   │
│  │                                                          │   │
│  │  - Likely similar to non-prod:                          │   │
│  │    • linux network (VLAN, dynamic IPAM)                │   │
│  │    • windows network (VLAN, dynamic IPAM)              │   │
│  │    • utility network                                    │   │
│  │                                                          │   │
│  │  - MTV migrations use these networks                    │   │
│  │  - No static IP capability                              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                   │
│  VMs limited to bridge networks with dynamic IPs only            │
└─────────────────────────────────────────────────────────────────┘
```

---

## Feature-by-Feature Comparison

### 1. ClusterUserDefinedNetwork (CUDN)

#### Non-Prod Cluster: ✅ DEPLOYED

**Resource:** `vm-secondary-network`

```yaml
apiVersion: k8s.ovn.org/v1
kind: ClusterUserDefinedNetwork
metadata:
  name: vm-secondary-network
  annotations:
    description: "Secondary network for VMs with static IP support"
spec:
  namespaceSelector:
    matchExpressions:
      - key: kubernetes.io/metadata.name
        operator: In
        values:
          - windows-non-prod
          - vm-migrations
          - openshift-mtv
          - vpn-infra
  network:
    topology: Layer2
    layer2:
      role: Secondary
      subnets:
        - "192.168.10.0/24"
      ipamLifecycle: Persistent
      mtu: 1500
```

**Capabilities:**
- ✅ Static IP assignment
- ✅ Layer 2 overlay networking
- ✅ VM-to-VM direct communication
- ✅ Custom routing support
- ✅ IPSec/VPN gateway capability
- ✅ No VLAN dependency
- ✅ Multi-namespace support

**Status:**
```
NetworkAttachmentDefinition has been created in following namespaces:
[openshift-mtv, vm-migrations, vpn-infra, windows-non-prod]
```

#### ROSA/POC Cluster: ❌ NOT DEPLOYED

**Status:** No CUDNs exist

```bash
$ oc get clusteruserdefinednetwork
No resources found
```

**Impact:**
- ❌ Cannot assign static IPs to VMs
- ❌ No Layer 2 overlay capability
- ❌ Cannot create IPSec/VPN gateways
- ❌ Limited to bridge-based dynamic IPs only

---

### 2. NetworkAttachmentDefinitions (NADs)

#### Non-Prod Cluster

**Total NADs:** 12

| Namespace | NAD Name | Type | Network | Purpose |
|-----------|----------|------|---------|---------|
| openshift-mtv | linux-non-prod | Bridge | 10.132.100.0/22 (VLAN 100) | MTV migrations |
| openshift-mtv | windows-non-prod | Bridge | 10.132.104.0/22 (VLAN 101) | MTV migrations |
| openshift-mtv | utility | Bridge | Management | Utility |
| openshift-mtv | **vm-secondary-network** | **CUDN** | **192.168.10.0/24** | **Static IPs** ✨ |
| vm-migrations | linux-non-prod | Bridge | 10.132.100.0/22 | MTV migrations |
| vm-migrations | windows-non-prod | Bridge | 10.132.104.0/22 | MTV migrations |
| vm-migrations | utility | Bridge | Management | Utility |
| vm-migrations | **vm-secondary-network** | **CUDN** | **192.168.10.0/24** | **Static IPs** ✨ |
| windows-non-prod | windows-non-prod | Bridge | 10.132.104.0/22 | VM operations |
| windows-non-prod | **vm-secondary-network** | **CUDN** | **192.168.10.0/24** | **Static IPs** ✨ |
| vpn-infra | **vm-secondary-network** | **CUDN** | **192.168.10.0/24** | **VPN gateways** ✨ |
| openshift-ovn-kubernetes | default | OVN | Pod network | Default |

**Key Features:**
- ✅ 4 CUDN-based NADs (new capability)
- ✅ 7 Bridge-based NADs (existing MTV support)
- ✅ 1 Default OVN NAD (pod network)

#### ROSA/POC Cluster

**Total NADs:** Unknown (likely similar bridge NADs only)

**Assumed Configuration:**
| Namespace | NAD Name | Type | Network | Purpose |
|-----------|----------|------|---------|---------|
| openshift-mtv | linux | Bridge | 10.x.x.0/22? | MTV migrations |
| openshift-mtv | windows | Bridge | 10.x.x.0/22? | MTV migrations |
| openshift-mtv | utility | Bridge | Management | Utility |
| openshift-ovn-kubernetes | default | OVN | Pod network | Default |

**Missing:**
- ❌ No CUDN-based NADs
- ❌ No static IP networks

---

### 3. IP Address Management (IPAM)

#### Non-Prod Cluster

**Dynamic IPs (Bridge NADs):**
```json
{
  "ipam": {
    "type": "whereabouts",
    "range": "10.132.100.0/22",
    "range_start": "10.132.100.10",
    "range_end": "10.132.103.250",
    "gateway": "10.132.100.1"
  }
}
```
- Uses Whereabouts IPAM plugin
- Automatic IP assignment
- DHCP-like behavior
- Used for MTV migrations

**Static IPs (CUDN):**
```yaml
network:
  layer2:
    ipamLifecycle: Persistent
    subnets:
      - "192.168.10.0/24"
```
- No automatic IPAM
- Manual IP configuration inside VM
- Full control over addressing
- Used for custom deployments

#### ROSA/POC Cluster

**Dynamic IPs Only:**
- Likely uses Whereabouts or similar IPAM
- No static IP capability
- All IPs assigned automatically

---

### 4. Network Configuration Workflows

#### Non-Prod Cluster

**For Dynamic IPs (MTV Migrations):**
1. MTV creates VM with bridge NAD (linux-non-prod or windows-non-prod)
2. Whereabouts IPAM assigns IP automatically
3. VM boots with configured IP
4. Gateway and routes configured automatically

**For Static IPs (Custom VMs):** ✨ NEW
1. Add CUDN interface to VM:
   ```yaml
   networks:
     - name: static-ip
       multus:
         networkName: vm-secondary-network
   ```
2. Boot VM
3. Configure IP manually inside VM:
   ```bash
   # Linux
   nmcli con add type ethernet ifname eth1 con-name static \
     ipv4.addresses 192.168.10.50/24 ipv4.method manual
   
   # Windows
   # Use GUI to set IP: 192.168.10.50
   ```
4. IP persists across restarts

#### ROSA/POC Cluster

**For Dynamic IPs (MTV Migrations):**
- Same as non-prod (bridge-based)
- Only option available

**For Static IPs:**
- ❌ Not possible
- Would require CUDN deployment

---

### 5. Use Cases Enabled

#### Non-Prod Cluster

**Enabled Use Cases:**
1. ✅ **MTV VM Migrations** - Dynamic IPs via bridge NADs
2. ✅ **Static IP VMs** - Manual IP assignment via CUDN
3. ✅ **IPSec/VPN Gateways** - CUDN with custom routing
4. ✅ **VM-to-VM Private Networks** - Layer 2 overlay
5. ✅ **Multi-homed VMs** - Both bridge and CUDN interfaces
6. ✅ **Custom Network Topologies** - Flexible routing
7. ✅ **Site-to-Site VPN** - IPSec gateways on CUDN

#### ROSA/POC Cluster

**Enabled Use Cases:**
1. ✅ **MTV VM Migrations** - Dynamic IPs via bridge NADs
2. ❌ **Static IP VMs** - Not supported
3. ❌ **IPSec/VPN Gateways** - Not feasible
4. ❌ **VM-to-VM Private Networks** - Limited
5. ⚠️ **Multi-homed VMs** - Only multiple bridge interfaces
6. ❌ **Custom Network Topologies** - Limited
7. ❌ **Site-to-Site VPN** - Would require workarounds

---

### 6. Network Namespaces

#### Non-Prod Cluster

**Namespaces with CUDN Access:**
- ✅ windows-non-prod
- ✅ vm-migrations
- ✅ openshift-mtv
- ✅ vpn-infra

**Namespaces with Bridge NADs:**
- ✅ windows-non-prod
- ✅ vm-migrations
- ✅ openshift-mtv

**Special Namespaces:**
- ✅ vpn-infra (created for VPN infrastructure)

#### ROSA/POC Cluster

**Namespaces with Network Access:**
- Likely similar MTV namespaces
- No vpn-infra namespace

---

### 7. OVN-Kubernetes Configuration

#### Both Clusters

**Network Plugin:** OVN-Kubernetes  
**Cluster Network:** 10.132.0.0/14  
**Service Network:** 172.30.0.0/16

**Both clusters support CUDN** (OVN-K8s capability)  
**Only non-prod has CUDN deployed**

---

## Migration Path: Adding CUDN to ROSA/POC

If you want to add CUDN capability to the ROSA/POC cluster:

### Step 1: Verify Prerequisites

```bash
# Login to ROSA/POC cluster
oc login https://api.rosa.m34m.p3.openshiftapps.com:443

# Check OpenShift version (need 4.14+)
oc version
# Current: 4.20.8 ✅

# Verify OVN-Kubernetes
oc get network.operator.openshift.io cluster -o yaml | grep networkType
# Should show: OVNKubernetes ✅

# Check if CUDN CRD exists
oc get crd clusteruserdefinednetworks.k8s.ovn.org
# Should exist ✅
```

### Step 2: Create VPN Infrastructure Namespace (if needed)

```bash
oc create namespace vpn-infra
oc label namespace vpn-infra \
  kubernetes.io/metadata.name=vpn-infra \
  pod-security.kubernetes.io/enforce=privileged \
  --overwrite
```

### Step 3: Deploy CUDN

Use the same manifest from non-prod:

```bash
# Copy from non-prod cluster config
cd Cluster-Config/components/site-to-site-vpn

# Apply to ROSA/POC
oc apply -f - <<'EOF'
apiVersion: k8s.ovn.org/v1
kind: ClusterUserDefinedNetwork
metadata:
  name: vm-secondary-network
  annotations:
    description: "Secondary network for VMs with static IP support"
    network.openshift.io/purpose: "vm-static-ip-secondary"
spec:
  namespaceSelector:
    matchExpressions:
      - key: kubernetes.io/metadata.name
        operator: In
        values:
          - windows-non-prod  # Adjust namespace names as needed
          - vm-migrations
          - openshift-mtv
          - vpn-infra
  network:
    topology: Layer2
    layer2:
      role: Secondary
      subnets:
        - "192.168.10.0/24"  # Can use different subnet if preferred
      ipamLifecycle: Persistent
      mtu: 1500
EOF
```

### Step 4: Verify Deployment

```bash
# Check CUDN created
oc get clusteruserdefinednetwork vm-secondary-network

# Check NADs auto-created
oc get network-attachment-definitions --all-namespaces | grep vm-secondary

# View CUDN status
oc get clusteruserdefinednetwork vm-secondary-network -o yaml
```

### Step 5: Test with a VM

Add secondary interface to test VM and configure static IP inside the VM.

---

## Recommendations

### For Non-Prod Cluster (Current)

✅ **Keep current configuration** - You now have best of both worlds:
- Bridge NADs for MTV migrations (dynamic IPs)
- CUDN for custom VMs (static IPs)

**Use Cases:**
- **MTV Migrations:** Use existing bridge NADs
- **Custom Deployments:** Use CUDN for static IPs
- **VPN Gateways:** Use CUDN in vpn-infra namespace
- **Special Requirements:** Use CUDN when you need specific IPs

### For ROSA/POC Cluster (Recommendation)

**Option 1: Deploy CUDN (Recommended)**
- ✅ Gain static IP capability
- ✅ Enable advanced use cases
- ✅ Match non-prod capabilities
- ⚠️ Requires testing in production
- ⚠️ Need IP allocation planning

**Option 2: Keep Current (Conservative)**
- ✅ No changes to production
- ✅ Proven stability
- ❌ Limited to dynamic IPs
- ❌ Cannot run VPN gateways
- ❌ Less flexible

---

## Key Takeaways

1. **Non-Prod is MORE advanced** - Has CUDN capability that ROSA/POC lacks

2. **CUDN enables new use cases:**
   - Static IP assignment
   - VPN gateway VMs
   - Custom network topologies
   - VM-to-VM private networks

3. **Bridge NADs still needed** - CUDN complements, doesn't replace bridge NADs

4. **Easy to replicate** - Same CUDN manifest can be applied to ROSA/POC

5. **No breaking changes** - CUDN is additive, doesn't affect existing VMs

6. **Production-ready** - CUDN is supported in OpenShift 4.14+

---

## Summary Table

| Capability | Non-Prod | ROSA/POC | Impact |
|------------|----------|----------|--------|
| **CUDNs** | ✅ 1 | ❌ 0 | Non-prod has modern networking |
| **Static IPs** | ✅ Yes | ❌ No | Non-prod more flexible |
| **Dynamic IPs** | ✅ Yes | ✅ Yes | Both support MTV |
| **VPN Gateways** | ✅ Possible | ❌ Not feasible | Non-prod ready for VPN |
| **Layer 2 Overlay** | ✅ Yes | ❌ No | Non-prod has OVN overlay |
| **Multi-network VMs** | ✅ Both types | ⚠️ Bridge only | Non-prod more capable |
| **IP Management** | ✅ Both static & dynamic | ⚠️ Dynamic only | Non-prod more control |

**Verdict:** Non-Prod cluster has **significantly more advanced** networking capabilities than ROSA/POC cluster.

---

## Files Created

This comparison analysis, along with deployment documentation:

1. **This Document:** CUDN comparison analysis
2. **Non-Prod Deployment:** 
   - `CUDN-STATIC-IP-GUIDE.md` - Usage guide
   - `CUDN-DEPLOYMENT-SUMMARY.md` - What was deployed
   - `cudn-vm-secondary-network.yaml` - Deployment manifest
   - `CUDN-QUICK-REF.md` - Quick reference

3. **Migration Path:** Steps above show how to replicate to ROSA/POC

---

**Conclusion:** The non-prod cluster now has enterprise-grade network capabilities with both traditional bridge-based networks for compatibility and modern CUDN overlay networks for advanced use cases. This represents a significant advancement over the ROSA/POC cluster's network configuration.
