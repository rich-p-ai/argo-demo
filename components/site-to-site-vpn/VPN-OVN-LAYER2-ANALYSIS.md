# Site-to-Site VPN with OVN Layer 2 - Analysis and Recommendations

## Problem Statement

**Goal**: Make Windows VMs on windows-non-prod CUDN (10.227.128.0/21) reachable through the site-to-site VPN.

**Challenge**: The VPN pod runs with `hostNetwork: true` and cannot see/route the OVN Layer 2 overlay network.

---

## Attempted Solution: Attach VPN Pod to CUDN

### What We Tried
- Remove `hostNetwork: true` from VPN deployment
- Add Multus annotation to attach VPN pod to windows-non-prod CUDN
- Configure VPN pod as gateway at 10.227.128.1

### Why It Failed
**OVN-Kubernetes ClusterUserDefinedNetworks (CUDNs) are NOT compatible with regular pods using Multus annotations.**

**Technical Details:**
1. CUDNs automatically create NetworkAttachmentDefinitions (NADs)
2. These NADs are specifically designed for **KubeVirt VirtualMachineInstances**
3. Regular pods cannot attach to CUDN networks via Multus
4. Multus network-status shows `null` - network not attached
5. No `net1` interface created in the pod

**Evidence:**
```bash
# Pod has Multus annotation but no network attached
oc get pod -n site-to-site-vpn -o jsonpath='{.metadata.annotations}' | jq '."k8s.v1.cni.cncf.io/network-status"'
# Returns: null
```

---

## Root Cause Analysis

### The Fundamental Issue

```
┌──────────────────────────────────────────────────────────────┐
│ Worker Node / Host Network                                    │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐│
│  │ VPN Pod (hostNetwork: true)                              ││
│  │ - Can route: Pod network (10.132.0.0/14) ✅              ││
│  │ - Can route: Service network ✅                          ││
│  │ - Cannot route: OVN Overlay (10.227.128.0/21) ❌        ││
│  └──────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────┘
                         ↕ NO ROUTING ↕
┌──────────────────────────────────────────────────────────────┐
│ OVN Layer 2 Overlay (isolated network fabric)                 │
│ - CUDN: windows-non-prod (10.227.128.0/21)                   │
│ - Only accessible to: VirtualMachineInstances                │
│ - NOT accessible to: Regular pods, worker nodes              │
└──────────────────────────────────────────────────────────────┘
```

**Key Insight**: OVN Layer 2 overlay networks are **isolated from the host network**. They exist only within the OVN fabric and are designed specifically for VM-to-VM communication, not pod-to-VM or host-to-VM.

---

## Recommended Solutions

### ✅ Solution 1: Gateway VM (Already Deployed - RECOMMENDED)

**Status**: Gateway VM already deployed and running

**Architecture**:
```
VPN Pod (hostNetwork) ↔ Pod Network ↔ Gateway VM ↔ CUDN ↔ Windows VMs
  10.132.x.x              10.132.x.x     10.135.0.23   10.227.128.15
                                         (pod network) (CUDN)
```

**Gateway VM**:
- Name: `vpn-gateway`
- Namespace: `windows-non-prod`
- Pod Network IP: 10.135.0.23
- CUDN IP: 10.227.128.15

**What Needs to Be Done**:
1. ✅ Gateway VM deployed
2. ⚠️ Configure NAT/routing in gateway VM
3. ⚠️ Configure Windows VMs to use 10.227.128.15 as gateway
4. ⚠️ Update VPN/AWS/firewall routing

**Advantages**:
- ✅ Works with current VPN configuration (`hostNetwork: true`)
- ✅ Clear separation of concerns (VPN vs routing)
- ✅ Easy to troubleshoot and manage
- ✅ Standard enterprise pattern

**Next Steps**: See "Gateway VM Configuration" section below

---

### ✅ Solution 2: Static Routes in Worker Nodes

Add static routes on OpenShift worker nodes to route CUDN traffic through OVN.

**Implementation**:
```bash
# On each worker node
ip route add 10.227.128.0/21 via <ovn-gateway-ip> dev ovn-k8s-mp0
```

**Challenges**:
- Requires MachineConfig to persist routes
- Complex OVN routing configuration
- May not work depending on OVN configuration
- Not officially supported pattern

**Not Recommended** - Too complex and fragile

---

### ✅ Solution 3: Bridge-based Network Instead of CUDN

Replace OVN Layer 2 CUDN with a traditional bridge-based NetworkAttachmentDefinition.

**Advantages**:
- Bridge networks integrate with worker node routing
- VPN can route traffic automatically

**Disadvantages**:
- Requires VM network reconfiguration
- VMs need to be restarted
- May not support desired static IP configuration
- Requires VLAN configuration

**Not Recommended** - Too disruptive for existing VMs

---

## ✅ RECOMMENDED: Complete Gateway VM Configuration

Since the gateway VM is already deployed, let's complete its configuration.

### Step 1: Configure Gateway VM Routing

Access the gateway VM console:
```bash
virtctl console vpn-gateway -n windows-non-prod
# Login: root / changethis
```

Inside the gateway VM, run:
```bash
# Install iptables if not present
dnf install -y iptables iptables-services

# Configure NAT for CUDN traffic
iptables -t nat -A POSTROUTING -s 10.227.128.0/21 -o eth0 -j MASQUERADE

# Allow forwarding
iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT
iptables -A FORWARD -i eth0 -o eth1 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i eth1 -o eth1 -j ACCEPT

# Save rules
iptables-save > /etc/sysconfig/iptables
systemctl enable --now iptables

# Verify
ip addr show
ip route show
iptables -t nat -L -n -v
```

### Step 2: Add Static Route in VPN Pod

The VPN pod needs to know how to reach the CUDN network via the gateway VM's pod IP.

**Option A: Add route in VPN startup script**

Update the VPN configmap to add a route:
```bash
# In start-vpn.sh, after enabling IP forwarding:
ip route add 10.227.128.0/21 via 10.135.0.23
```

Where `10.135.0.23` is the gateway VM's pod network IP.

**Option B: Use Kubernetes NetworkPolicy or CNI routing**

Configure OVN to route CUDN traffic to gateway VM (complex).

### Step 3: Configure Windows VMs

From each Windows VM console:
```powershell
$adapter = (Get-NetAdapter | Where-Object { $_.Status -eq 'Up' })[1]

Remove-NetIPAddress -InterfaceAlias $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
Remove-NetRoute -InterfaceAlias $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue

# Use gateway VM's CUDN IP
New-NetIPAddress -InterfaceAlias $adapter.Name `
                 -IPAddress "10.227.128.11" `
                 -PrefixLength 21 `
                 -DefaultGateway "10.227.128.15"

# Test
ping 10.227.128.15
ping 8.8.8.8
```

### Step 4: Update AWS Transit Gateway

Add route for 10.227.128.0/21:
```bash
aws ec2 create-transit-gateway-route \
  --destination-cidr-block 10.227.128.0/21 \
  --transit-gateway-route-table-id tgw-rtb-0ff564f70c91bf1d5 \
  --transit-gateway-attachment-id <vpn-attachment-id> \
  --region us-east-1
```

### Step 5: Update On-Premise Firewall

Add Palo Alto firewall rules for 10.227.128.0/21 traffic.

---

## Alternative: Simplified Static Route Approach

If configuring the gateway VM is complex, we can add a static route directly in the VPN pod:

### Update VPN ConfigMap

```yaml
# Add to start-vpn.sh after IP forwarding is enabled:
echo "Adding route to CUDN via gateway VM..."
ip route add 10.227.128.0/21 via 10.135.0.23 dev eth0

# Where 10.135.0.23 is the gateway VM's pod IP
```

This tells the VPN pod: "To reach 10.227.128.0/21, send traffic to 10.135.0.23 (gateway VM)".

The gateway VM then forwards this traffic to the CUDN network.

---

## Cleanup: Remove Failed VPN Deployment

```bash
# Restore original VPN deployment
oc apply -f deployment-backup-*.yaml

# Or manually patch to remove Multus annotation
oc patch deployment site-to-site-vpn -n site-to-site-vpn --type=json -p='[
  {"op": "remove", "path": "/spec/template/metadata/annotations/k8s.v1.cni.cncf.io~1networks"}
]'

# Ensure hostNetwork is enabled
oc patch deployment site-to-site-vpn -n site-to-site-vpn --type=json -p='[
  {"op": "add", "path": "/spec/template/spec/hostNetwork", "value": true}
]'
```

---

## Summary

### What We Learned
1. ❌ OVN Layer 2 CUDNs do NOT support Multus attachment for regular pods
2. ✅ CUDNs are designed specifically for VirtualMachineInstances
3. ✅ Gateway VM approach is the correct solution
4. ✅ VPN pod stays on host network with simple routing to gateway VM

### Next Actions
1. **Immediate**: Restore VPN deployment to working state (hostNetwork: true)
2. **Complete Gateway VM**: Configure NAT/routing in gateway VM
3. **Add Static Route**: Add route in VPN pod to gateway VM
4. **Configure Windows VMs**: Point to gateway VM as default gateway
5. **Update AWS/Firewall**: Add 10.227.128.0/21 routes

### Expected Result
```
On-Premise ↔ AWS VPN ↔ VPN Pod ↔ Gateway VM ↔ Windows VMs
            (IPSec)  (hostNet)  (10.135.0.23) (10.227.128.15)
                                 Pod Net | CUDN
```

---

**Document Created**: 2026-02-12  
**Status**: Gateway VM deployed, needs final configuration  
**Recommendation**: Complete Gateway VM solution (Solution 1)
