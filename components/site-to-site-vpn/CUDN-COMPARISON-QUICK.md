# CUDN Comparison Summary - Quick View

## Cluster Network Capabilities

### Non-Prod Cluster ✅ (ADVANCED)
```
┌─────────────────────────────────────────┐
│  Non-Prod Cluster                       │
│  OpenShift 4.20.12                      │
├─────────────────────────────────────────┤
│  ✅ CUDN: vm-secondary-network         │
│     • Network: 192.168.10.0/24         │
│     • Static IPs supported             │
│     • Layer 2 overlay                   │
│                                          │
│  ✅ Bridge NADs (3):                   │
│     • linux-non-prod (10.132.100.0/22) │
│     • windows-non-prod (10.132.104.0/22)│
│     • utility                           │
│     • Dynamic IPs (whereabouts)        │
│                                          │
│  Capabilities:                          │
│  ✅ Static IP VMs                      │
│  ✅ Dynamic IP VMs                     │
│  ✅ VPN Gateways                       │
│  ✅ VM-to-VM Private Networks          │
│  ✅ Custom Routing                     │
│  ✅ MTV Migrations                     │
└─────────────────────────────────────────┘
```

### ROSA/POC Cluster ⚠️ (TRADITIONAL)
```
┌─────────────────────────────────────────┐
│  ROSA/POC Cluster                       │
│  OpenShift 4.20.8                       │
├─────────────────────────────────────────┤
│  ❌ No CUDN deployed                   │
│                                          │
│  ✅ Bridge NADs only (assumed):        │
│     • Similar network layout            │
│     • Dynamic IPs only                  │
│     • VLAN-based                        │
│                                          │
│  Capabilities:                          │
│  ❌ Static IP VMs                      │
│  ✅ Dynamic IP VMs                     │
│  ❌ VPN Gateways                       │
│  ⚠️ VM-to-VM Limited                  │
│  ⚠️ Custom Routing Limited            │
│  ✅ MTV Migrations                     │
└─────────────────────────────────────────┘
```

---

## Head-to-Head Comparison

| Feature | Non-Prod | ROSA/POC |
|---------|:--------:|:--------:|
| **CUDN Deployed** | ✅ | ❌ |
| **Static IP Support** | ✅ | ❌ |
| **Dynamic IP Support** | ✅ | ✅ |
| **Layer 2 Overlay** | ✅ | ❌ |
| **VPN Gateway Capable** | ✅ | ❌ |
| **Bridge Networks** | ✅ | ✅ |
| **Multi-network VMs** | ✅ Both | ⚠️ Bridge only |
| **IP Control** | ✅ Full | ⚠️ Limited |

---

## Key Differences

### What Non-Prod Has (that ROSA/POC doesn't):

1. **ClusterUserDefinedNetwork** - `vm-secondary-network`
   - 192.168.10.0/24 network
   - Static IP capability
   - 4 namespaces covered

2. **vpn-infra Namespace**
   - Dedicated for VPN infrastructure
   - CUDN network access

3. **Advanced Use Cases**
   - IPSec/VPN gateways
   - Static IP VMs
   - Custom network topologies

### What Both Have:

1. **Bridge-based NADs**
   - MTV migration support
   - Dynamic IPAM (whereabouts)
   - VLAN integration

2. **OVN-Kubernetes**
   - Both capable of CUDNs
   - Modern network plugin

---

## Network Count

### Non-Prod: 12 NADs Total
- 4 CUDN-based (vm-secondary-network in 4 namespaces)
- 7 Bridge-based (linux, windows, utility across namespaces)
- 1 Default (pod network)

### ROSA/POC: ~4 NADs (estimated)
- 0 CUDN-based
- ~3 Bridge-based
- 1 Default (pod network)

---

## IP Assignment Methods

### Non-Prod (Dual Mode)

**Static IPs (CUDN):**
```bash
# Manual configuration inside VM
nmcli con add type ethernet ifname eth1 con-name static \
  ipv4.addresses 192.168.10.50/24 ipv4.method manual
```

**Dynamic IPs (Bridge):**
```yaml
# Automatic via whereabouts IPAM
ipam:
  type: whereabouts
  range: 10.132.100.0/22
```

### ROSA/POC (Dynamic Only)

**Dynamic IPs Only:**
```yaml
# All IPs assigned automatically
# No static IP option
```

---

## To Add CUDN to ROSA/POC

**One command deployment:**

```bash
cat <<'EOF' | oc apply -f -
apiVersion: k8s.ovn.org/v1
kind: ClusterUserDefinedNetwork
metadata:
  name: vm-secondary-network
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
EOF
```

**Result:** ROSA/POC would match non-prod capabilities

---

## Bottom Line

**Non-Prod Cluster: Enterprise-Ready Network Architecture**
- ✅ Modern CUDN overlay networks
- ✅ Traditional bridge networks
- ✅ Static AND dynamic IP support
- ✅ Ready for advanced use cases

**ROSA/POC Cluster: Traditional Network Architecture**
- ⚠️ Bridge networks only
- ⚠️ Dynamic IPs only
- ⚠️ Limited flexibility
- ✅ Stable and proven

**Gap:** Non-prod is significantly more advanced in networking capabilities.

**Effort to Close Gap:** ~5 minutes (apply CUDN manifest to ROSA/POC)

---

## Quick Reference

**Non-Prod CUDN Details:**
- Name: `vm-secondary-network`
- Network: `192.168.10.0/24`
- Type: Layer2, Secondary
- IPAM: Persistent (manual)
- Namespaces: 4 (windows-non-prod, vm-migrations, openshift-mtv, vpn-infra)
- NADs Created: 4 (auto-generated)
- Status: ✅ Ready

**Documentation:**
- Full Guide: `CUDN-STATIC-IP-GUIDE.md`
- Deployment Summary: `CUDN-DEPLOYMENT-SUMMARY.md`
- Comparison: `CUDN-CLUSTER-COMPARISON.md`
- Quick Ref: `CUDN-QUICK-REF.md`
