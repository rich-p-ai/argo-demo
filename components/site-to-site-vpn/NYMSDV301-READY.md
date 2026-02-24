# NYMSDV301 - Ready for Network Configuration

**Status**: ⏳ **Awaiting Network Resource Limit Increase**  
**Date**: February 10, 2026  

---

## Current Status

✅ **VM Migration**: Complete  
✅ **VM Running**: Yes (with pod network only)  
✅ **VM Functional**: Ready to test via console  
✅ **Static IP Reserved**: 10.132.104.11  
✅ **Cloud-init Configured**: Will auto-configure on next boot  
⏳ **Secondary Network**: Pending resource limit increase  

---

## What Has Been Done

1. ✅ Cold migration completed successfully
2. ✅ VM created and started with pod network
3. ✅ Static IP 10.132.104.11 reserved in all NADs
4. ✅ Cloud-init configuration created for automatic network setup
5. ✅ Request document prepared for cluster administrator
6. ✅ Automation script ready to apply network configuration

---

## What's Needed

### Cluster Administrator Action Required

The cluster has reached the maximum number of `openshift.io/windows-non-prod` network attachments (currently 8 VMs using this network).

**Request Document**: `NETWORK-LIMIT-INCREASE-REQUEST.md`

**Summary of Request**:
- Current Limit: ~8 network attachments
- Requested Limit: 20 network attachments
- Reason: Support additional Windows VMs with S2S VPN access
- Network Capacity: ~1,000 IPs available (only ~10 currently used)

---

## Once Limit is Increased

### Automated Configuration

Simply run the prepared script:

```bash
cd /c/Users/q22529_a/work/Cluster-Config/components/site-to-site-vpn

# Make script executable
chmod +x add-network-nymsdv301.sh

# Run the script
./add-network-nymsdv301.sh
```

**The script will**:
1. Stop the VM
2. Add secondary network interface
3. Configure static IP annotation (10.132.104.11)
4. Restart the VM
5. Verify the configuration
6. Display next steps

### Expected Results

After running the script and waiting 2-3 minutes for Windows to boot:

| Item | Expected Value |
|------|----------------|
| **VM Status** | Running |
| **Pod Network IP** | 10.132.0.x (automatic) |
| **Secondary Network IP** | 10.132.104.11 (static) |
| **Reachable from Company** | Yes (via S2S VPN) |
| **RDP Access** | `mstsc /v:10.132.104.11` |

---

## Manual Configuration Steps

If you prefer to configure manually after limit increase:

```bash
# 1. Stop VM
oc patch vm nymsdv301 -n windows-non-prod --type merge -p '{"spec":{"runStrategy":"Halted"}}'
sleep 15

# 2. Add network annotation
oc patch vm nymsdv301 -n windows-non-prod --type=json -p='[
  {
    "op": "add",
    "path": "/spec/template/metadata/annotations",
    "value": {
      "k8s.v1.cni.cncf.io/networks": "[{\"name\":\"windows-non-prod\",\"namespace\":\"windows-non-prod\",\"ips\":[\"10.132.104.11\"]}]"
    }
  }
]'

# 3. Add network interface
oc patch vm nymsdv301 -n windows-non-prod --type=json -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/domain/devices/interfaces/-",
    "value": {"name": "net-1", "bridge": {}, "model": "virtio"}
  },
  {
    "op": "add",
    "path": "/spec/template/spec/networks/-",
    "value": {"name": "net-1", "multus": {"networkName": "windows-non-prod"}}
  }
]'

# 4. Start VM
oc patch vm nymsdv301 -n windows-non-prod --type merge -p '{"spec":{"runStrategy":"Always"}}'

# 5. Wait and verify
sleep 120
oc get vmi nymsdv301 -n windows-non-prod -o wide
```

---

## Testing the VM Now (Without Network)

You can verify the VM is functional right now using console access:

```bash
# Access VM console
virtctl console nymsdv301 -n windows-non-prod

# Inside Windows, verify:
# - VM boots correctly
# - Can login
# - Applications are intact
# - Data from vSphere is present
```

---

## Testing After Network Configuration

Once the network is configured:

### 1. Verify IP Assignment
```bash
oc get vmi nymsdv301 -n windows-non-prod -o jsonpath='{.status.interfaces}' | jq .
# Should show both pod network and 10.132.104.11
```

### 2. Test from Company Network
```bash
# Ping test
ping 10.132.104.11

# RDP test
mstsc /v:10.132.104.11
```

### 3. If RDP Fails
Access console and check Windows Firewall:
```powershell
# Via console
virtctl console nymsdv301 -n windows-non-prod

# Inside Windows
Get-NetFirewallRule -DisplayName "*Remote Desktop*"
ipconfig /all
```

---

## Troubleshooting

### If VM Still Won't Schedule After Limit Increase

```bash
# Check node resources
oc get nodes -o json | jq '.items[] | {
  name: .metadata.name,
  windows_np: .status.allocatable["openshift.io/windows-non-prod"]
}'

# Check for other issues
oc describe vmi nymsdv301 -n windows-non-prod
```

### If IP Doesn't Assign

```bash
# Check cloud-init logs in VM console
# Check whereabouts IPAM
oc get ippools.whereabouts.cni.cncf.io -n windows-non-prod

# Verify NAD configuration
oc get network-attachment-definitions windows-non-prod -n windows-non-prod -o yaml
```

---

## Summary for Cluster Admin

**What's Needed**:
- Increase `openshift.io/windows-non-prod` resource limit from ~8 to 20

**Why**:
- Current: 8 VMs using the network (limit reached)
- Need: Support for 4 additional VMs (12 total active)
- Future: Room for growth (20 total capacity)

**Network Capacity**: 
- Available IPs: ~1,000 (10.132.104.0/22)
- Currently used: ~10 IPs
- No technical constraint on increased limit

**Request Document**: See `NETWORK-LIMIT-INCREASE-REQUEST.md`

**Validation Commands**: All provided in request document

---

## Files Created

| File | Purpose |
|------|---------|
| `NETWORK-LIMIT-INCREASE-REQUEST.md` | Formal request for cluster administrator |
| `add-network-nymsdv301.sh` | Automated script to configure network |
| `NYMSDV301-READY.md` | This summary document |
| `NYMSDV301-NETWORK-ISSUE.md` | Detailed problem analysis |

---

**Status**: Ready to proceed as soon as network limit is increased  
**Next Action**: Submit `NETWORK-LIMIT-INCREASE-REQUEST.md` to cluster administrator  
**ETA**: Once approved, network configuration takes ~5 minutes + 2-3 min boot time

🚀 **VM is ready - just waiting for network resource availability!**
