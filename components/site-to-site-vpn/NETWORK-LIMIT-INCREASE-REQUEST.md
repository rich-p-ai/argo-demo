# Request: Increase windows-non-prod Network Resource Limit

**Date**: February 10, 2026  
**Requestor**: OpenShift Platform Team  
**Cluster**: Non-Prod OpenShift  
**Priority**: Medium  

---

## Request Summary

Increase the `openshift.io/windows-non-prod` network attachment resource limit to support additional Windows VMs requiring S2S VPN connectivity.

---

## Current Situation

### Issue
Cannot start VM `nymsdv301` with secondary network attachment. Error:
```
0/3 nodes are available: 3 Insufficient openshift.io/windows-non-prod
preemption: 0/3 nodes are available: 3 No preemption victims found for incoming pod
```

### Current Usage
**8 VMs currently using windows-non-prod network:**
- nymsdv217 (10.132.104.17)
- nymsdv282 (10.132.104.16)
- nymsdv303 (10.132.104.14)
- nymsdv317 (10.132.104.15)
- nymsdv351 (10.132.104.12)
- nymsdv352 (10.132.104.13)
- nymsdv296 (pending network configuration)
- nymsdv312 (pending network configuration)

**Additional VMs needing network access:**
- nymsdv297 (needs 10.132.104.10)
- nymsdv301 (needs 10.132.104.11) ← **Currently blocked**
- nymsqa428 (needs 10.132.104.20) ← **Planned**
- nymsqa429 (needs 10.132.104.21) ← **Planned**

---

## Technical Details

### Network Configuration
- **Network**: windows-non-prod
- **Type**: OVN-Kubernetes secondary network (Layer 2)
- **CIDR**: 10.132.104.0/22
- **Available IPs**: ~1,000 IPs (10.132.104.4 - 10.132.107.254)
- **Gateway**: 10.132.104.1
- **DNS**: 10.132.104.2, 10.132.104.3
- **S2S VPN**: Routable to company network

### Current Resource Limit
The `openshift.io/windows-non-prod` resource appears to have a limit preventing more than 8 simultaneous network attachments.

---

## Requested Change

### Increase Network Attachment Limit

**Current**: ~8 attachments (limit reached)  
**Requested**: **20 attachments** (to support current + planned VMs)

### Commands to Check Current Limit

```bash
# Check current allocatable resources per node
oc get nodes -o json | jq '.items[] | {
  name: .metadata.name,
  allocatable: .status.allocatable["openshift.io/windows-non-prod"],
  capacity: .status.capacity["openshift.io/windows-non-prod"]
}'

# Check current usage
oc get pods -A -o json | jq '[.items[] | 
  select(.metadata.annotations["k8s.v1.cni.cncf.io/network-status"] != null) | 
  select(.metadata.annotations["k8s.v1.cni.cncf.io/network-status"] | contains("windows-non-prod"))]
  | length'

# Check NetworkAttachmentDefinition
oc get network-attachment-definitions windows-non-prod -n windows-non-prod -o yaml
```

---

## Implementation Options

### Option 1: Increase Node Resource Capacity (Recommended)

Increase the `openshift.io/windows-non-prod` resource capacity on worker nodes.

**Steps**:
1. Edit MachineConfig or Node configuration
2. Set resource limit to 20 per node
3. Restart affected nodes (if required)

**Example MachineConfig** (if using device plugin):
```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 99-worker-network-resources
spec:
  config:
    ignition:
      version: 3.2.0
    systemd:
      units:
        - name: network-resources.service
          enabled: true
          contents: |
            [Unit]
            Description=Configure Network Resources
            [Service]
            Type=oneshot
            ExecStart=/usr/local/bin/configure-network-resources.sh
            [Install]
            WantedBy=multi-user.target
    storage:
      files:
        - path: /usr/local/bin/configure-network-resources.sh
          mode: 0755
          contents:
            inline: |
              #!/bin/bash
              # Increase windows-non-prod network capacity
              echo "20" > /sys/fs/cgroup/network-resources/windows-non-prod/capacity
```

### Option 2: Remove Resource Limit

If the network has sufficient IP capacity (which it does - ~1,000 IPs available), remove or increase the resource limit altogether.

**Steps**:
1. Check if limit is coming from device plugin configuration
2. Update device plugin ConfigMap or DaemonSet
3. Restart device plugin pods

### Option 3: Use Multiple Network Attachment Definitions

Create additional NADs that reference the same underlying network but with different resource names.

**Example**:
```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: windows-non-prod-extra
  namespace: windows-non-prod
  annotations:
    k8s.v1.cni.cncf.io/resourceName: openshift.io/windows-non-prod-extra
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "type": "ovn-k8s-cni-overlay",
      "name": "windows-non-prod-extra",
      "netAttachDefName": "windows-non-prod/windows-non-prod-extra",
      "subnets": "10.132.104.0/22",
      "mtu": 1400,
      "ipam": {
        "type": "whereabouts",
        "range": "10.132.104.0/22",
        "range_start": "10.132.104.22",
        "range_end": "10.132.107.254",
        "gateway": "10.132.104.1",
        "exclude": [...]
      }
    }
```

---

## Impact Assessment

### Benefits
- ✅ Supports additional Windows VMs with S2S VPN access
- ✅ Enables proper network configuration for migrated VMs
- ✅ Allows RDP access from company network
- ✅ Supports future VM migrations

### Risks
- ⚠️ May require node restart (depending on implementation)
- ⚠️ Need to ensure sufficient network bandwidth
- ℹ️ No impact on existing VMs (they continue running)

### Downtime
- **Option 1**: May require rolling node restart (minimal impact)
- **Option 2**: Device plugin restart only (no downtime)
- **Option 3**: No downtime (immediate)

---

## Validation Steps

After implementing the change:

```bash
# 1. Verify increased capacity
oc get nodes -o json | jq '.items[0].status.allocatable["openshift.io/windows-non-prod"]'
# Expected: "20" (or higher)

# 2. Test with nymsdv301
oc patch vm nymsdv301 -n windows-non-prod --type=json -p='[
  {
    "op": "add",
    "path": "/spec/template/metadata/annotations",
    "value": {
      "k8s.v1.cni.cncf.io/networks": "[{\"name\":\"windows-non-prod\",\"namespace\":\"windows-non-prod\",\"ips\":[\"10.132.104.11\"]}]"
    }
  }
]'

# 3. Restart VM
oc patch vm nymsdv301 -n windows-non-prod --type merge -p '{"spec":{"runStrategy":"Halted"}}'
sleep 10
oc patch vm nymsdv301 -n windows-non-prod --type merge -p '{"spec":{"runStrategy":"Always"}}'

# 4. Verify VM starts successfully
oc get vmi nymsdv301 -n windows-non-prod -o wide
# Should show PHASE=Running with IP 10.132.104.11

# 5. Test connectivity from company network
ping 10.132.104.11
mstsc /v:10.132.104.11
```

---

## IP Capacity Analysis

### Current Reservations
```
Reserved IPs: 8 (including infrastructure)
  - 10.132.104.1/32   (Gateway)
  - 10.132.104.2/32   (DNS Primary)
  - 10.132.104.3/32   (DNS Secondary)
  - 10.132.104.10/32  (nymsdv297)
  - 10.132.104.11/32  (nymsdv301)
  - 10.132.104.12-21  (8 active VMs + 2 planned)
```

### Available Capacity
```
Total IPs in 10.132.104.0/22: 1,024
Usable range (10.132.104.4 - 10.132.107.254): ~1,000 IPs
Currently allocated: ~10 IPs
Remaining capacity: ~990 IPs
```

**Conclusion**: Network has sufficient IP capacity to support 20+ VM attachments.

---

## Recommended Action

**Primary Recommendation**: **Option 2** - Remove or significantly increase the resource limit

**Justification**:
1. Network has ~1,000 available IPs (only 10 currently used)
2. No technical reason to limit to 8 attachments
3. Simplest implementation (no node restart)
4. Supports future growth

**Alternative**: If resource limits are required for other reasons, increase to **20 attachments** minimum (Option 1).

---

## Contact Information

**For questions or approval**:
- OpenShift Platform Team
- Network Team (for S2S VPN routing verification)

**Urgency**: Medium
- **Current Impact**: nymsdv301 cannot be reached from company network
- **Future Impact**: Cannot migrate additional VMs (nymsqa428, nymsqa429)

---

## Related Documentation

- Network Configuration: `windows-non-prod` NAD in `windows-non-prod` namespace
- Static IP Reservations: See `VM-MIGRATION-STATUS.md`
- S2S VPN Configuration: See `README.md` in site-to-site-vpn component

---

**Request Status**: ⏳ Pending Cluster Administrator Action  
**Requested By**: Platform Team  
**Date**: February 10, 2026
