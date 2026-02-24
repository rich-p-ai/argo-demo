# Site-to-Site VPN Routing Analysis for windows-non-prod CUDN

## Executive Summary

**PROBLEM**: Server nymsdv301 (10.227.128.11) cannot reach gateway at 10.227.128.1

**ROOT CAUSE IDENTIFIED**: The site-to-site VPN pod is configured with `leftsubnet=0.0.0.0/0` (advertises all traffic), but the **windows-non-prod CUDN (10.227.128.0/21) is an OVN Layer 2 overlay network isolated from the host network** where the VPN pod runs.

**KEY INSIGHT**: The VPN pod runs with `hostNetwork: true` on a worker node, but the OVN overlay network (10.227.128.0/21) doesn't have routing to the worker node's network interface.

---

## Current Configuration Analysis

### Site-to-Site VPN Pod Configuration

```yaml
# deployment.yaml
hostNetwork: true  # Pod runs on host network namespace
dnsPolicy: ClusterFirstWithHostNet

# configmap.yaml - ipsec.conf
leftsubnet=0.0.0.0/0  # Advertises ALL subnets via VPN
rightsubnet=10.63.0.0/16,10.68.0.0/16,...,10.227.112.0/20  # Canon networks
```

**What this means:**
- VPN pod runs directly on worker node's network stack
- VPN tunnel advertises 0.0.0.0/0 (all OpenShift traffic) to on-premise
- Worker node can route: pod network (10.132.0.0/14), service network, etc.
- Worker node **CANNOT** route: OVN overlay networks (CUDNs)

### windows-non-prod CUDN Configuration

```yaml
# cudn-windows-non-prod.yaml
apiVersion: k8s.ovn.org/v1
kind: ClusterUserDefinedNetwork
metadata:
  name: windows-non-prod
spec:
  network:
    topology: Layer2
    layer2:
      role: Secondary
      subnets:
        - "10.227.128.0/21"
      ipamLifecycle: Persistent
```

**What this means:**
- OVN-managed Layer 2 overlay network
- Isolated from host network
- Only accessible within OVN fabric
- No automatic routing to worker node interfaces

---

## The Routing Problem

```
┌──────────────────────────────────────────────────────────────┐
│ On-Premise Networks (10.227.112.0/20, etc.)                  │
└───────────────┬──────────────────────────────────────────────┘
                ↓
┌───────────────────────────────────────────────────────────────┐
│ AWS VPN + Transit Gateway                                     │
└───────────────┬───────────────────────────────────────────────┘
                ↓
┌───────────────────────────────────────────────────────────────┐
│ Worker Node (Physical Host)                                   │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │ strongSwan VPN Pod (hostNetwork: true)                   │ │
│  │ - Routes: Pod network 10.132.0.0/14 ✅                   │ │
│  │ - Routes: Service network ✅                             │ │
│  │ - CANNOT route: OVN overlay 10.227.128.0/21 ❌          │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                                │
│  Worker node routing table:                                   │
│  - 10.132.0.0/14 → ovn-k8s-mp0 interface (pod network)       │
│  - 10.227.128.0/21 → ??? (OVN overlay, no route) ❌          │
└────────────────────────────────────────────────────────────────┘
                      ↓ NO CONNECTION ↓
┌───────────────────────────────────────────────────────────────┐
│ OVN Layer 2 Overlay: windows-non-prod CUDN                    │
│ - 10.227.128.0/21 (isolated overlay)                          │
│ - VMs: 10.227.128.10-14                                       │
│ - NO gateway configured                                       │
│ - NO route to worker node                                     │
└───────────────────────────────────────────────────────────────┘
```

---

## Why 0.0.0.0/0 Doesn't Help

The VPN configuration with `leftsubnet=0.0.0.0/0` means:
- "Route ALL traffic from this OpenShift cluster to on-premise"
- Works for networks **reachable from the worker node**:
  - ✅ Pod network (10.132.0.0/14) - routed via ovn-k8s-mp0
  - ✅ Service network - routed internally
  - ✅ Host network - direct interface
- Does NOT work for networks **not in worker node routing table**:
  - ❌ OVN overlay networks (CUDNs) - exist only in OVN fabric

---

## Solutions

### Solution 1: Attach VPN Pod to windows-non-prod CUDN (RECOMMENDED)

Make the VPN pod multi-homed so it has an interface on the windows-non-prod network.

#### Implementation

```yaml
---
# Modified VPN deployment with CUDN attachment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: site-to-site-vpn
  namespace: site-to-site-vpn
spec:
  template:
    metadata:
      annotations:
        k8s.v1.cni.cncf.io/networks: |
          [
            {
              "name": "windows-non-prod",
              "namespace": "site-to-site-vpn"
            }
          ]
    spec:
      hostNetwork: false  # ← CHANGE: Disable hostNetwork
      containers:
        - name: strongswan
          # ... rest of config
```

**Changes Required:**
1. Create NAD in site-to-site-vpn namespace:
   ```bash
   # windows-non-prod CUDN must target site-to-site-vpn namespace
   oc edit clusteruserdefinednetwork windows-non-prod
   # Add site-to-site-vpn to namespace selector
   ```

2. Modify deployment to use multus instead of hostNetwork

3. Configure VPN pod to have IP on 10.227.128.0/21 network

**Pros:**
- VPN pod directly connected to windows-non-prod network
- Can route traffic between VPN and Windows VMs
- No additional gateway VM needed

**Cons:**
- VPN pod loses direct host network access
- May need to adjust egress routing
- More complex network configuration

---

### Solution 2: Deploy Gateway VM (Simpler, Previously Proposed)

Deploy a dedicated Linux VM acting as router between OVN overlay and pod network.

**Architecture:**
```
VPN Pod (hostNetwork) ↔ Pod Network ↔ Gateway VM ↔ windows-non-prod CUDN ↔ Windows VMs
```

**Pros:**
- Keeps VPN pod configuration simple
- Clear separation of concerns
- Easy to troubleshoot
- Gateway can be restarted independently

**Cons:**
- Additional VM resource overhead
- Extra hop in routing path

---

### Solution 3: Use OVN EgressIP with Static Routes

Configure OVN to route CUDN traffic to specific worker nodes with static routes.

**Not recommended** - Very complex OVN configuration

---

### Solution 4: Migrate VMs to Bridge-based Network

Use a bridge-based NAD instead of OVN overlay CUDN.

**Pros:**
- Bridge networks integrate with worker node routing
- VPN can route traffic automatically

**Cons:**
- May not support desired static IP configuration
- Requires VM network reconfiguration
- May need VLAN configuration

---

## Recommended Approach: Solution 2 (Gateway VM)

### Why Gateway VM is Best

1. **Least Disruptive**: VPN pod stays as-is, proven working configuration
2. **Clear Architecture**: Gateway VM has single responsibility (routing)
3. **Troubleshooting**: Easy to debug routing issues on dedicated VM
4. **Flexibility**: Can add firewall rules, NAT, monitoring on gateway
5. **Production-Ready**: Standard enterprise pattern for network segmentation

### Implementation Summary

**Step 1: Deploy Gateway VM**
- Namespace: windows-non-prod
- Interface 1: Pod network (masquerade) for VPN connectivity
- Interface 2: windows-non-prod CUDN (10.227.128.1/21) for Windows VMs
- IP forwarding enabled
- NAT/routing configured

**Step 2: Update Windows VMs**
- Change gateway from 10.227.135.254 to 10.227.128.1
- Verify connectivity to gateway

**Step 3: Update VPN Configuration**
- Add static route on VPN pod for 10.227.128.0/21 → Gateway VM pod IP
- OR rely on cluster routing (pod network routes automatically)

**Step 4: Update AWS/On-Premise**
- Add 10.227.128.0/21 routes to TGW
- Add firewall rules for 10.227.128.0/21 on Palo Alto

---

## Quick Diagnosis Commands

### Check VPN Pod Routing

```bash
# Get VPN pod
POD=$(oc get pods -n site-to-site-vpn -l app=site-to-site-vpn -o jsonpath='{.items[0].metadata.name}')

# Check VPN pod IP and node
oc get pod $POD -n site-to-site-vpn -o wide

# Check routing table on VPN pod (same as worker node)
oc exec -n site-to-site-vpn $POD -- ip route show

# Check if 10.227.128.0/21 is routable
oc exec -n site-to-site-vpn $POD -- ip route get 10.227.128.11
# Expected: No route found ❌
```

### Check Worker Node Routing

```bash
# Find worker node running VPN pod
NODE=$(oc get pod $POD -n site-to-site-vpn -o jsonpath='{.spec.nodeName}')

# Debug on worker node (requires cluster-admin)
oc debug node/$NODE

# In debug shell:
chroot /host
ip route show | grep 10.227.128
# Expected: No route ❌

ip route show | grep 10.132
# Expected: Route via ovn-k8s-mp0 ✅
```

### Check OVN Overlay Network

```bash
# Check CUDN status
oc get clusteruserdefinednetwork windows-non-prod -o yaml

# Check which namespaces have NADs
oc get network-attachment-definitions --all-namespaces | grep windows-non-prod

# Check if site-to-site-vpn namespace has NAD
oc get network-attachment-definitions -n site-to-site-vpn
# If windows-non-prod NAD not present → Solution 1 won't work without config change
```

### Test Connectivity from Windows VM

```powershell
# From nymsdv301 console
# Check interface
ipconfig /all

# Check routing table
route print

# Try to ping gateway
ping 10.227.128.1
# Expected: Destination host unreachable ❌

# Try to ping pod network (won't work either)
ping 10.132.0.1
# Expected: Destination host unreachable ❌
```

---

## Immediate Action: Verify Current State

### Verification Script

```bash
#!/bin/bash
echo "=== VPN Pod Status ==="
POD=$(oc get pods -n site-to-site-vpn -l app=site-to-site-vpn -o jsonpath='{.items[0].metadata.name}')
echo "VPN Pod: $POD"
oc get pod $POD -n site-to-site-vpn -o wide

echo -e "\n=== VPN Pod Routing Table ==="
oc exec -n site-to-site-vpn $POD -- ip route show

echo -e "\n=== Check if 10.227.128.0/21 is routable from VPN pod ==="
oc exec -n site-to-site-vpn $POD -- ip route get 10.227.128.11 2>&1 || echo "❌ No route to 10.227.128.11"

echo -e "\n=== Check windows-non-prod CUDN ==="
oc get clusteruserdefinednetwork windows-non-prod -o jsonpath='{.spec.namespaceSelector}'
echo ""

echo -e "\n=== Check if site-to-site-vpn namespace has windows-non-prod NAD ==="
oc get network-attachment-definitions -n site-to-site-vpn | grep windows-non-prod || echo "❌ No windows-non-prod NAD in site-to-site-vpn namespace"

echo -e "\n=== Check Windows VMs network attachment ==="
oc get vm -n windows-non-prod -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.networks[*].multus.networkName}{"\n"}{end}'

echo -e "\n=== CONCLUSION ==="
echo "If 'No route to 10.227.128.11' appears above, the VPN pod cannot reach the windows-non-prod CUDN."
echo "Solution: Deploy gateway VM as described in VPN-GATEWAY-SOLUTION.md"
```

---

## Conclusion

**YES**, the site-to-site VPN pod *should* be able to connect the two networks **IF** they were both reachable from the worker node's routing table. However:

- The VPN pod (with hostNetwork: true) can route **pod network (10.132.0.0/14)** ✅
- The VPN pod **CANNOT** route **OVN overlay (10.227.128.0/21)** ❌

**The OVN Layer 2 overlay network is isolated from the host network.**

**Best Solution**: Deploy a gateway VM (as detailed in VPN-GATEWAY-SOLUTION.md) to bridge the OVN overlay to the pod network, allowing the VPN pod to route traffic for the Windows VMs.

---

**Document Version**: 1.0  
**Created**: 2026-02-12  
**Status**: Analysis Complete - Recommend Gateway VM Solution
