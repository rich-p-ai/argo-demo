# CUDN Quick Reference Card

## ✅ Deployed CUDN: vm-secondary-network

**Network:** 192.168.10.0/24 | **Type:** Layer2 Overlay | **Role:** Secondary

---

## Quick Commands

### View CUDN
```bash
oc get clusteruserdefinednetwork vm-secondary-network
```

### Check NADs in Your Namespace
```bash
oc get network-attachment-definitions -n windows-non-prod
```

### Add to VM (YAML snippet)
```yaml
spec:
  template:
    spec:
      domain:
        devices:
          interfaces:
            - name: default
              masquerade: {}
            - name: static-ip      # Add this
              bridge: {}
      networks:
        - name: default
          pod: {}
        - name: static-ip          # Add this
          multus:
            networkName: vm-secondary-network
```

### Configure Static IP in Linux VM
```bash
# Find interface name
ip link show

# Configure static IP (replace eth1 and IP)
sudo nmcli con add type ethernet ifname eth1 con-name static-secondary \
  ipv4.addresses 192.168.10.50/24 ipv4.method manual autoconnect yes

sudo nmcli con up static-secondary
```

### Configure Static IP in Windows VM
1. Open Network Connections (ncpa.cpl)
2. Right-click new adapter → Properties → TCP/IPv4
3. Set IP: `192.168.10.X`, Mask: `255.255.255.0`

---

## IP Allocation Guide

| Range | Purpose |
|-------|---------|
| .1 | Gateway (reserved) |
| .2-10 | Infrastructure VMs |
| .11-50 | Windows VMs |
| .51-100 | Linux VMs |
| .101-200 | Dev/Test |

---

## Available Namespaces
- ✅ windows-non-prod
- ✅ vm-migrations
- ✅ openshift-mtv
- ✅ vpn-infra

---

## Documentation
- **Full Guide:** `CUDN-STATIC-IP-GUIDE.md`
- **Deployment Summary:** `CUDN-DEPLOYMENT-SUMMARY.md`
- **Manifest:** `cudn-vm-secondary-network.yaml`
