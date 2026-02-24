# NYMSDV301 Network Configuration Issue & Workaround

**Status**: ⚠️ **BLOCKED - Network Resource Exhaustion**  
**Issue**: Cannot attach secondary network due to resource limits  
**Workaround**: Manual network configuration required  

---

## Current Situation

### Migration Status
✅ **Cold migration completed successfully**  
✅ **VM created**: `nymsdv301` in `windows-non-prod` namespace  
✅ **Static IP reserved**: `10.132.104.11/32` in all NADs  
❌ **Cannot start VM**: Insufficient network resources  

### Error Message
```
0/3 nodes are available: 3 Insufficient openshift.io/windows-non-prod
preemption: 0/3 nodes are available: 3 No preemption victims found for incoming pod
```

### Root Cause
The `windows-non-prod` network has a resource limit and there are already **8 VMs** using this network:
- nymsdv217 (10.132.104.17)
- nymsdv282 (10.132.104.16)  
- nymsdv296 (pod network only)
- nymsdv303 (10.132.104.14)
- nymsdv312 (pod network only)
- nymsdv317 (10.132.104.15)
- nymsdv351 (10.132.104.12)
- nymsdv352 (10.132.104.13)

**Problem**: The cluster has hit the maximum number of `openshift.io/windows-non-prod` network attachments allowed per node or globally.

---

## Workaround Options

### Option 1: Start VM with Pod Network Only (Quick Test)

This allows you to start the VM and verify it's working, but it won't be reachable from company network via S2S VPN.

```bash
# VM is already configured with only pod network
# Start the VM
oc patch vm nymsdv301 -n windows-non-prod --type merge -p '{"spec":{"runStrategy":"Always"}}'

# Wait for it to boot
oc get vmi nymsdv301 -n windows-non-prod -w

# Access via console
virtctl console nymsdv301 -n windows-non-prod

# Or RDP via port-forward (from bastion/jumpbox)
virtctl port-forward vm/nymsdv301 -n windows-non-prod 3389:3389
# Then: mstsc /v:localhost:3389
```

**Pros**: 
- VM starts immediately
- Can verify Windows is working
- Can access via console/port-forward

**Cons**:
- Not reachable from company network via RDP
- No static IP on S2S VPN network

---

### Option 2: Stop Another VM to Free Network Resources

Temporarily stop one of the other VMs to free up a network attachment slot:

```bash
# Stop a VM you don't need right now (example: nymsdv217)
oc patch vm nymsdv217 -n windows-non-prod --type merge -p '{"spec":{"runStrategy":"Halted"}}'

# Wait for it to stop
oc get vmi nymsdv217 -n windows-non-prod

# Now try to start nymsdv301 with secondary network
# (Would need to re-add secondary network configuration)
```

**Pros**:
- NYMSDV301 gets proper network access
- Reachable from company network

**Cons**:
- Another VM becomes unavailable
- Temporary solution

---

### Option 3: Increase Network Resource Limits (Requires Admin)

Contact cluster administrator to increase the `openshift.io/windows-non-prod` resource limit.

```bash
# Check current limits (requires cluster-admin)
oc get nodes -o json | jq '.items[].status.allocatable | .["openshift.io/windows-non-prod"]'

# This might require:
# - Increasing NetworkAttachmentDefinition resource limits
# - Modifying node configuration
# - Adjusting whereabouts IPAM pool size
```

---

### Option 4: Manual Network Configuration Inside Windows

Start VM with pod network, then manually configure secondary network inside Windows:

1. **Start VM with pod network only** (current state)
2. **Access VM console**: `virtctl console nymsdv301 -n windows-non-prod`
3. **Inside Windows, manually configure network**:
   ```powershell
   # Find network adapter
   Get-NetAdapter
   
   # Configure static IP on adapter
   New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 10.132.104.11 `
     -PrefixLength 22 -DefaultGateway 10.132.104.1
   
   # Set DNS
   Set-DnsClientServerAddress -InterfaceAlias "Ethernet" `
     -ServerAddresses ("10.132.104.2","10.132.104.3")
   
   # Enable RDP
   Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
     -Name "fDenyTSConnections" -Value 0
   
   # Enable firewall rules
   Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
   New-NetFirewallRule -DisplayName "Allow ICMPv4" `
     -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Allow
   ```

**Note**: This won't work because the VM only has pod network interface, not the secondary network hardware.

---

## Recommended Immediate Action

**Use Option 1** to verify the VM is functional:

```bash
# Start VM (already configured with pod network only)
oc patch vm nymsdv301 -n windows-non-prod --type merge -p '{"spec":{"runStrategy":"Always"}}'

# Wait 2-3 minutes for boot
sleep 120

# Check status
oc get vmi nymsdv301 -n windows-non-prod

# Access console to verify Windows is working
virtctl console nymsdv301 -n windows-non-prod
```

### Test Checklist
- [ ] VM starts successfully
- [ ] Windows boots to login screen
- [ ] Can login via console
- [ ] Guest agent connects
- [ ] Applications are intact
- [ ] Data is present from vSphere

Once verified, we can decide on the best approach for network configuration.

---

## For Company Network Access

To make NYMSDV301 reachable from company network with static IP 10.132.104.11, you'll need to:

1. **Either**: Stop another VM temporarily (Option 2)
2. **Or**: Request increased network resource limits from cluster admin (Option 3)

Then:
```bash
# Re-add secondary network to VM
oc patch vm nymsdv301 -n windows-non-prod --type=json -p='[
  {
    "op": "add",
    "path": "/spec/template/metadata/annotations",
    "value": {
      "k8s.v1.cni.cncf.io/networks": "[{\"name\":\"windows-non-prod\",\"namespace\":\"windows-non-prod\",\"ips\":[\"10.132.104.11\"]}]"
    }
  }
]'

# Restart VM
oc patch vm nymsdv301 -n windows-non-prod --type merge -p '{"spec":{"runStrategy":"Halted"}}'
sleep 10
oc patch vm nymsdv301 -n windows-non-prod --type merge -p '{"spec":{"runStrategy":"Always"}}'
```

---

## Summary

| Item | Status |
|------|--------|
| **Migration** | ✅ Complete |
| **VM Created** | ✅ Yes |
| **Static IP Reserved** | ✅ 10.132.104.11 |
| **VM Running** | ❌ Blocked by network limit |
| **Company Network Access** | ❌ Not yet configured |
| **Workaround Available** | ✅ Pod network only |

---

**Next Step**: Start VM with pod network to verify it's functional, then determine best approach for network access.

```bash
# Quick start command
oc patch vm nymsdv301 -n windows-non-prod --type merge -p '{"spec":{"runStrategy":"Always"}}'
```

---

**Last Updated**: February 10, 2026 at 20:52 UTC  
**Issue**: Network resource exhaustion  
**Impact**: Cannot attach secondary network for S2S VPN access
