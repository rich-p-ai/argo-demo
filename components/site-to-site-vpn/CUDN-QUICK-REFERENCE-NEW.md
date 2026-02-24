# CUDN Quick Reference - Updated Feb 11, 2026

## ✅ Active CUDNs on Non-Prod Cluster

### 1. linux-non-prod
**Network:** `10.136.0.0/21` | **Type:** OVN Layer2 | **Role:** Secondary  
**Capacity:** 2,048 IPs

### 2. windows-non-prod  
**Network:** `10.136.8.0/21` | **Type:** OVN Layer2 | **Role:** Secondary  
**Capacity:** 2,048 IPs

---

## 📊 Cluster Network Layout

```
Pod Network:     10.132.0.0/14  (Primary - all pods)
Service Network: 172.30.0.0/16  (ClusterIP services)

Secondary Networks (CUDNs):
├── Linux VMs:   10.136.0.0/21  (2,048 IPs)
└── Windows VMs: 10.136.8.0/21  (2,048 IPs)
```

---

## Quick Commands

### View CUDNs
```bash
oc get clusteruserdefinednetworks
```

### Check NADs in Your Namespace
```bash
oc get network-attachment-definitions -n <namespace>
```

### View CUDN Details
```bash
oc get clusteruserdefinednetwork linux-non-prod -o yaml
oc get clusteruserdefinednetwork windows-non-prod -o yaml
```

---

## Add CUDN to VM

### Linux VM
```yaml
spec:
  template:
    spec:
      domain:
        devices:
          interfaces:
            - name: default
              masquerade: {}
            - name: linux-net      # Add this
              bridge: {}
      networks:
        - name: default
          pod: {}
        - name: linux-net          # Add this
          multus:
            networkName: linux-non-prod
```

### Windows VM
```yaml
spec:
  template:
    spec:
      domain:
        devices:
          interfaces:
            - name: default
              masquerade: {}
            - name: windows-net    # Add this
              bridge: {}
      networks:
        - name: default
          pod: {}
        - name: windows-net        # Add this
          multus:
            networkName: windows-non-prod
```

---

## Configure Static IP

### Linux VM
```bash
# Find interface name
ip link show

# Configure static IP (replace eth1 and IP)
sudo nmcli con add type ethernet ifname eth1 con-name static-net \
  ipv4.addresses 10.136.0.100/21 ipv4.method manual autoconnect yes

sudo nmcli con up static-net
```

### Windows VM
1. Open Network Connections (ncpa.cpl)
2. Right-click new adapter → Properties → TCP/IPv4
3. Set IP: `10.136.8.100`, Mask: `255.255.248.0` (/21)

---

## IP Allocation Guide

### Linux Network: 10.136.0.0/21

| Range | Purpose |
|-------|---------|
| .0.1 | Gateway (reserved) |
| .0.2-.0.10 | Infrastructure |
| .0.11-.3.255 | Production Linux VMs |
| .4.0-.5.255 | Dev/Test Linux VMs |
| .6.0-.7.255 | Reserved |

### Windows Network: 10.136.8.0/21

| Range | Purpose |
|-------|---------|
| .8.1 | Gateway (reserved) |
| .8.2-.8.10 | Infrastructure |
| .8.11-.11.255 | Production Windows VMs |
| .12.0-.13.255 | Dev/Test Windows VMs |
| .14.0-.15.255 | Reserved |

---

## Available Namespaces

### linux-non-prod CUDN
- ✅ openshift-mtv
- ✅ vm-migrations
- ✅ vpn-infra

### windows-non-prod CUDN
- ✅ windows-non-prod
- ✅ openshift-mtv
- ✅ vm-migrations
- ✅ vpn-infra

---

## Troubleshooting

### VM Not Getting Secondary Network
```bash
# Check NAD exists
oc get net-attach-def -n <namespace>

# Check VM network spec
oc get vm <vm-name> -n <namespace> -o yaml | grep -A 20 networks

# Check VMI interfaces
oc get vmi <vm-name> -n <namespace> -o jsonpath='{.status.interfaces}' | jq

# Restart VM
virtctl restart <vm-name> -n <namespace>
```

### Check OVN Health
```bash
oc get pods -n openshift-ovn-kubernetes -l app=ovnkube-node
```

---

## Documentation

- **Full Migration Guide:** `CUDN-MIGRATION-SUMMARY.md`
- **Static IP Guide:** `CUDN-STATIC-IP-GUIDE.md`
- **Manifests:** 
  - `cudn-linux-non-prod.yaml`
  - `cudn-windows-non-prod.yaml`

---

**Last Updated:** February 11, 2026  
**Cluster:** non-prod.5wp0.p3.openshiftapps.com
