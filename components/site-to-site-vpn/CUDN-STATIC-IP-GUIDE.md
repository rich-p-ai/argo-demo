# CUDN Static IP Configuration Guide

## Overview

This guide explains how to use the ClusterUserDefinedNetwork (CUDN) `vm-secondary-network` to assign static IP addresses to virtual machines in OpenShift Virtualization.

## What Was Deployed

### ClusterUserDefinedNetwork: `vm-secondary-network`

- **Network CIDR:** `192.168.10.0/24`
- **Topology:** Layer 2 Overlay
- **Role:** Secondary network
- **MTU:** 1500
- **IPAM:** Persistent (allows manual IP assignment)
- **Target Namespaces:** windows-non-prod, vm-migrations, openshift-mtv, vpn-infra

### Key Features

✅ **Static IP Support** - VMs can configure custom IP addresses manually  
✅ **Layer 2 Connectivity** - VMs on this network can communicate directly  
✅ **No DHCP** - Manual IP configuration required (full control)  
✅ **Persistent IPs** - IPs persist across VM restarts  
✅ **Separate from Primary** - Secondary interface doesn't interfere with pod networking  

---

## NetworkAttachmentDefinitions Created

The CUDN automatically created NADs in all target namespaces:

```bash
oc get network-attachment-definitions -n windows-non-prod
# NAME                   AGE
# vm-secondary-network   ...
# windows-non-prod       ...

oc get network-attachment-definitions -n vm-migrations
# NAME                   AGE
# vm-secondary-network   ...
# linux-non-prod         ...
# utility                ...
# windows-non-prod       ...
```

---

## How to Use CUDN with Virtual Machines

### Method 1: Add Secondary Network to Existing VM

#### Step 1: Edit VM to Add Network Interface

Add a secondary network interface to your VM spec:

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: myvm
  namespace: windows-non-prod
spec:
  template:
    spec:
      domain:
        devices:
          interfaces:
            - name: default
              masquerade: {}
            # Add this secondary interface
            - name: secondary-static
              bridge: {}
      networks:
        - name: default
          pod: {}
        # Add this network reference
        - name: secondary-static
          multus:
            networkName: vm-secondary-network
```

#### Step 2: Apply the Changes

```bash
oc apply -f myvm.yaml
```

#### Step 3: Start/Restart the VM

```bash
virtctl start myvm -n windows-non-prod
```

#### Step 4: Configure Static IP Inside the VM

##### For Linux VMs (CentOS/RHEL/Ubuntu):

```bash
# SSH into the VM
virtctl console myvm -n windows-non-prod

# Identify the secondary interface
ip link show
# Look for the new interface (e.g., eth1, ens4, enp2s0)

# Configure static IP using nmcli (RHEL/CentOS)
INTERFACE_NAME="eth1"  # Replace with actual interface name
STATIC_IP="192.168.10.50"
GATEWAY="192.168.10.1"

sudo nmcli con add type ethernet ifname $INTERFACE_NAME con-name static-secondary \
  ipv4.addresses ${STATIC_IP}/24 \
  ipv4.gateway ${GATEWAY} \
  ipv4.method manual \
  autoconnect yes

sudo nmcli con up static-secondary

# Verify
ip addr show $INTERFACE_NAME
ping 192.168.10.1
```

##### For Ubuntu/Debian (using netplan):

```bash
# Create netplan configuration
sudo cat <<EOF > /etc/netplan/60-secondary.yaml
network:
  version: 2
  ethernets:
    eth1:  # Replace with actual interface name
      addresses:
        - 192.168.10.50/24
      routes:
        - to: 192.168.10.0/24
          via: 192.168.10.1
EOF

sudo netplan apply
```

##### For Windows VMs:

1. **Access the VM console** via RDP or virtctl
2. **Open Network Connections** (ncpa.cpl)
3. **Find the new network adapter** (usually "Ethernet 2" or similar)
4. **Configure TCP/IPv4 Properties:**
   - IP Address: `192.168.10.50`
   - Subnet Mask: `255.255.255.0`
   - Default Gateway: `192.168.10.1` (optional)
   - DNS: (leave blank or use existing)
5. **Click OK** and test connectivity

---

### Method 2: Create New VM with CUDN Network

Example VM manifest with CUDN secondary network:

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: myvm-with-static-ip
  namespace: windows-non-prod
  labels:
    app: myapp
    network: static-ip
spec:
  running: false
  template:
    metadata:
      labels:
        kubevirt.io/vm: myvm-with-static-ip
    spec:
      domain:
        devices:
          disks:
            - name: rootdisk
              disk:
                bus: virtio
            - name: cloudinitdisk
              disk:
                bus: virtio
          interfaces:
            # Primary interface - pod network
            - name: default
              masquerade: {}
            # Secondary interface - CUDN with static IP
            - name: secondary-static
              bridge: {}
        resources:
          requests:
            memory: 4Gi
            cpu: 2
      networks:
        # Primary network (pod network)
        - name: default
          pod: {}
        # Secondary network (CUDN - static IP)
        - name: secondary-static
          multus:
            networkName: vm-secondary-network
      volumes:
        - name: rootdisk
          persistentVolumeClaim:
            claimName: myvm-disk
        - name: cloudinitdisk
          cloudInitNoCloud:
            userData: |
              #cloud-config
              password: changeme
              chpasswd: { expire: false }
              ssh_pwauth: true
```

---

## Network Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  OpenShift Non-Prod Cluster                                     │
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Namespace: windows-non-prod                              │  │
│  │                                                             │  │
│  │  ┌──────────────────────────────────────────────────┐     │  │
│  │  │  VM: myvm                                        │     │  │
│  │  │                                                    │     │  │
│  │  │  eth0 (masquerade): 10.132.x.x  ← Pod Network   │     │  │
│  │  │    - Default route                               │     │  │
│  │  │    - Internet access                             │     │  │
│  │  │    - Service access                              │     │  │
│  │  │                                                    │     │  │
│  │  │  eth1 (bridge): 192.168.10.50  ← CUDN           │     │  │
│  │  │    - Static IP                                   │     │  │
│  │  │    - VM-to-VM communication                      │     │  │
│  │  │    - Custom routing                              │     │  │
│  │  └──────────────────────────────────────────────────┘     │  │
│  │                                                             │  │
│  │  ┌──────────────────────────────────────────────────┐     │  │
│  │  │  VM: another-vm                                  │     │  │
│  │  │                                                    │     │  │
│  │  │  eth0 (masquerade): 10.132.x.x                   │     │  │
│  │  │  eth1 (bridge): 192.168.10.51  ← CUDN           │     │  │
│  │  └──────────────────────────────────────────────────┘     │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                   │
│  CUDN: vm-secondary-network (192.168.10.0/24)                   │
│  - Layer 2 overlay                                              │
│  - Direct VM-to-VM connectivity                                 │
│  - Manual IP assignment                                         │
└─────────────────────────────────────────────────────────────────┘
```

---

## IP Address Management

### Recommended IP Allocation Strategy

| Range | Purpose | Example |
|-------|---------|---------|
| 192.168.10.1 | Gateway/Router (reserved) | Gateway VM |
| 192.168.10.2-10 | Infrastructure | VPN gateways, DNS, etc. |
| 192.168.10.11-50 | Windows VMs | Application servers |
| 192.168.10.51-100 | Linux VMs | Application servers |
| 192.168.10.101-200 | Development/Test | Temporary VMs |
| 192.168.10.201-254 | Reserved | Future use |

### IP Assignment Tracking

Create a spreadsheet or ConfigMap to track IP assignments:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: vm-static-ip-registry
  namespace: windows-non-prod
data:
  assignments: |
    192.168.10.50 - myvm - Windows Server 2019 - App Server
    192.168.10.51 - another-vm - RHEL 9 - Database
    192.168.10.52 - testvm - Ubuntu 22.04 - Dev Environment
```

---

## Verification and Troubleshooting

### Verify CUDN Status

```bash
# Check CUDN exists
oc get clusteruserdefinednetwork vm-secondary-network

# View CUDN details
oc get clusteruserdefinednetwork vm-secondary-network -o yaml

# Check NAD in target namespace
oc get network-attachment-definitions -n windows-non-prod
```

### Verify VM Network Configuration

```bash
# Check VM spec for network interfaces
oc get vm myvm -n windows-non-prod -o yaml | grep -A 20 networks

# Check VMI interfaces
oc get vmi myvm -n windows-non-prod -o jsonpath='{.spec.networks}' | jq

# View VMI interface status
oc get vmi myvm -n windows-non-prod -o jsonpath='{.status.interfaces}' | jq
```

### Test Connectivity Between VMs

From one VM, test connectivity to another:

```bash
# Ping another VM on the CUDN
ping 192.168.10.51

# Check routing table
ip route show
# or on Windows: route print

# Check interface status
ip addr show eth1
# or on Windows: ipconfig /all
```

### Common Issues and Solutions

#### Issue: Secondary interface not appearing in VM

**Solution:**
1. Verify NAD exists: `oc get net-attach-def vm-secondary-network -n windows-non-prod`
2. Check VM spec includes network reference
3. Restart VM: `virtctl restart myvm -n windows-non-prod`

#### Issue: Cannot ping other VMs on CUDN

**Solution:**
1. Verify both VMs have IPs in 192.168.10.0/24 range
2. Check VM firewalls (iptables, Windows Firewall)
3. Verify MTU settings match (1500)
4. Check interface is UP: `ip link show eth1`

#### Issue: VM has no IP on secondary interface

**Solution:**
- **Expected behavior** - CUDN has no DHCP
- Must manually configure IP inside the VM
- Follow "Configure Static IP Inside the VM" steps above

---

## Advanced Configuration

### Adding Static Routes via CUDN

If you need VMs to route to other networks via the CUDN:

```bash
# Linux - Add route to VPC networks via CUDN gateway
sudo nmcli con mod static-secondary +ipv4.routes "10.132.100.0/22 192.168.10.1"
sudo nmcli con mod static-secondary +ipv4.routes "10.132.104.0/22 192.168.10.1"
sudo nmcli con up static-secondary

# Windows - Add static route
route add 10.132.100.0 mask 255.255.252.0 192.168.10.1 -p
route add 10.132.104.0 mask 255.255.252.0 192.168.10.1 -p
```

### Configuring Multiple Static IPs on Same Interface

```bash
# Linux - Add additional IP addresses
sudo ip addr add 192.168.10.60/24 dev eth1
sudo ip addr add 192.168.10.61/24 dev eth1

# Make persistent with nmcli
sudo nmcli con mod static-secondary +ipv4.addresses "192.168.10.60/24"
sudo nmcli con mod static-secondary +ipv4.addresses "192.168.10.61/24"
```

### Setting Interface MTU

```bash
# Linux - Set MTU
sudo nmcli con mod static-secondary 802-3-ethernet.mtu 1500
sudo nmcli con up static-secondary

# Windows - Set MTU
netsh interface ipv4 set subinterface "Ethernet 2" mtu=1500 store=persistent
```

---

## Comparison: CUDN vs Bridge-based NADs

| Feature | CUDN (vm-secondary-network) | Bridge NAD (windows-non-prod) |
|---------|------------------------------|-------------------------------|
| Network Type | OVN Layer 2 Overlay | Bridge with VLAN |
| IP Assignment | Manual (Static) | Whereabouts IPAM (Dynamic) |
| DHCP | No | Yes |
| VLAN Tagging | No | Yes (VLAN 101) |
| Gateway | Manual configuration | Automatic (10.132.104.1) |
| Use Case | Static IPs, VM-to-VM | Migration from VMware |
| External Routing | Requires gateway VM | Built-in via TGW |

**When to use CUDN:**
- Need static/custom IP addresses
- VM-to-VM direct communication
- Custom routing requirements
- IPSec/VPN gateways

**When to use Bridge NAD:**
- Migration from VMware (MTV)
- Need external VPC connectivity
- Want automatic IP assignment
- Require VLAN integration

---

## Adding More Namespaces

To extend the CUDN to additional namespaces:

```bash
# Edit the CUDN
oc edit clusteruserdefinednetwork vm-secondary-network

# Add namespace to the values list:
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
          - my-new-namespace  # Add this
```

The NAD will be automatically created in the new namespace.

---

## Cleanup (If Needed)

To remove the CUDN and all associated NADs:

```bash
# This will remove the CUDN and all auto-created NADs
oc delete clusteruserdefinednetwork vm-secondary-network

# NADs in all namespaces will be automatically removed
```

---

## Quick Reference Commands

```bash
# List all CUDNs
oc get clusteruserdefinednetwork

# View CUDN details
oc get clusteruserdefinednetwork vm-secondary-network -o yaml

# Check NADs in namespace
oc get network-attachment-definitions -n windows-non-prod

# View VM networks
oc get vm myvm -n windows-non-prod -o jsonpath='{.spec.template.spec.networks}' | jq

# View VMI interface status
oc get vmi myvm -n windows-non-prod -o jsonpath='{.status.interfaces}' | jq

# Console into VM
virtctl console myvm -n windows-non-prod

# Test from one VM to another
ping 192.168.10.51
```

---

## Summary

✅ **CUDN Deployed:** `vm-secondary-network` with 192.168.10.0/24  
✅ **NADs Created:** Automatically in windows-non-prod, vm-migrations, openshift-mtv, vpn-infra  
✅ **Static IP Support:** VMs can manually configure IPs on secondary interface  
✅ **Layer 2 Connectivity:** Direct VM-to-VM communication on the overlay network  

**Next Steps:**
1. Add secondary network to your VMs (see examples above)
2. Configure static IPs inside VMs
3. Test connectivity between VMs
4. Implement IP address tracking strategy
