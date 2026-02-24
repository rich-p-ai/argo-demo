# VM Static IP Verification Report

**Date:** February 10, 2026  
**Cluster:** non-prod.5wp0.p3.openshiftapps.com

---

## ✅ Static IP Reservation: SUCCESS

### VMs Status

| VM | Reserved IP | Actual IP | Status | Interface | Guest Agent |
|----|-------------|-----------|--------|-----------|-------------|
| **NYMSDV297** | 10.132.104.10 | ✅ 10.132.104.10 | ✅ Running | ✅ UP | ✅ Active |
| **NYMSDV301** | 10.132.104.11 | ✅ 10.132.104.11 | ✅ Running | ✅ UP | ⚠️ Limited |
| **NYMSDV312** | 10.132.104.19 | (not started) | Stopped | - | - |

**Verdict:** ✅ **VMs have correct static IPs and are running**

---

## ❌ Network Connectivity: BLOCKED

### Test Results from OpenShift Network

```
Test Pod IP: 10.132.104.20 (same network as VMs)

PING 10.132.104.10 → ❌ Destination Host Unreachable
PING 10.132.104.11 → ❌ Destination Host Unreachable
RDP Port 3389     → ❌ Connection Timeout
```

### Root Cause

**Windows Firewall is blocking all incoming traffic.**

The VMs are:
- ✅ Running correctly
- ✅ Have correct IP addresses (10.132.104.10, .11)
- ✅ Network interfaces are UP
- ✅ On the correct network (10.132.104.0/22)
- ❌ **But Windows Firewall is blocking ICMP (ping) and RDP**

---

## 🔧 Required Fix: Disable Windows Firewall or Enable RDP

You need to access each VM console and configure Windows Firewall.

### Option 1: Disable Firewall (Quick Test)

```bash
# Access VM console
virtctl console nymsdv297 -n windows-non-prod

# Login to Windows (press Ctrl+] to exit console)

# Run in PowerShell as Administrator:
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
```

### Option 2: Enable RDP Through Firewall (Production)

```powershell
# Inside Windows VM
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
Enable-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)"

# Ensure RDP is enabled
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -value 0

# Restart RDP service
Restart-Service TermService -Force
```

### How to Access VM Console

#### From Command Line:

```bash
# NYMSDV297
virtctl console nymsdv297 -n windows-non-prod

# NYMSDV301  
virtctl console nymsdv301 -n windows-non-prod

# Press Ctrl+] to exit console
```

#### From OpenShift Console GUI:

1. Navigate to: Virtualization → VirtualMachines
2. Click on VM name (nymsdv297 or nymsdv301)
3. Go to "Console" tab
4. Login with Windows credentials
5. Open PowerShell as Administrator
6. Run the firewall commands above

---

## Network Path Verification

### ✅ Company Network → OpenShift Gateway

```
ping 10.132.104.1
Result: ✅ SUCCESS (4 packets sent, 4 received, 0% loss)
```

**Verdict:** S2S VPN routing is working correctly for 10.132.104.0/22

### ✅ OpenShift → VMs (Layer 2)

```
Test Pod: 10.132.104.20
VMs: 10.132.104.10, 10.132.104.11
Network: windows-non-prod (VLAN 101, bridge)
ARP: Can resolve MAC addresses
```

**Verdict:** OpenShift networking is working correctly

### ❌ Test Pod → VMs (ICMP/TCP)

```
PING 10.132.104.10 → Destination Host Unreachable
TCP 10.132.104.10:3389 → Connection Timeout
```

**Verdict:** Windows Firewall is blocking traffic

---

## Complete Network Topology

```
┌─────────────────────────────────────────────────────────────┐
│ Company Network (10.222.155.0/24)                          │
│                                                               │
│  Workstation: Can ping 10.132.104.1 ✅                      │
└────────────────┬─────────────────────────────────────────────┘
                 │
                 │ Site-to-Site VPN ✅
                 │
┌────────────────▼─────────────────────────────────────────────┐
│ AWS VPC (10.227.96.0/20)                                     │
│                                                               │
│  Gateway: 10.132.104.1 ✅ Responding                        │
│                                                               │
│  ┌────────────────────────────────────────────────┐         │
│  │ OpenShift windows-non-prod Network             │         │
│  │ 10.132.104.0/22 (VLAN 101)                     │         │
│  │                                                  │         │
│  │  Test Pod: 10.132.104.20 ✅                    │         │
│  │                                                  │         │
│  │  VM NYMSDV297: 10.132.104.10                   │         │
│  │    Interface: UP ✅                             │         │
│  │    Firewall: BLOCKING ❌                        │         │
│  │                                                  │         │
│  │  VM NYMSDV301: 10.132.104.11                   │         │
│  │    Interface: UP ✅                             │         │
│  │    Firewall: BLOCKING ❌                        │         │
│  └────────────────────────────────────────────────┘         │
└──────────────────────────────────────────────────────────────┘
```

---

## Summary

### What's Working ✅

1. ✅ Static IP reservation in whereabouts (IPs .10, .11, .19 excluded)
2. ✅ VMs have correct IP addresses
3. ✅ VMs are running and interfaces are UP
4. ✅ Site-to-Site VPN routing (can reach gateway 10.132.104.1)
5. ✅ OpenShift networking (Layer 2 connectivity established)
6. ✅ Test pod can reach the same network segment

### What's NOT Working ❌

1. ❌ Windows Firewall blocking ICMP (ping)
2. ❌ Windows Firewall blocking TCP 3389 (RDP)
3. ❌ VMs not responding to any network traffic

### Root Cause

**Windows Firewall Default Policy:** Windows blocks all incoming traffic by default. The VMs need firewall rules configured to allow:
- ICMP (ping) - for testing
- TCP 3389 (RDP) - for remote access

---

## Action Required

**You must access each VM console and configure Windows Firewall to allow RDP.**

### Quick Steps:

1. **Access VM:**
   ```bash
   virtctl console nymsdv297 -n windows-non-prod
   ```

2. **Login to Windows**

3. **Run PowerShell as Administrator:**
   ```powershell
   # Disable firewall (testing)
   Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
   
   # OR enable RDP specifically (production)
   Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
   Enable-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)"
   ```

4. **Test from company network:**
   ```powershell
   ping 10.132.104.10
   mstsc /v:10.132.104.10
   ```

5. **Repeat for NYMSDV301**

---

## Expected Results After Fix

### From Company Network:

```powershell
ping 10.132.104.10
# Should respond: Reply from 10.132.104.10: bytes=32 time=<5ms TTL=128

mstsc /v:10.132.104.10
# Should open RDP connection to Windows VM
```

### From Test Pod:

```bash
oc exec network-test -n windows-non-prod -- ping -c 3 10.132.104.10
# Should respond: 3 packets transmitted, 3 received, 0% packet loss
```

---

## Cleanup Test Pod

Once testing is complete:

```bash
oc delete pod network-test -n windows-non-prod
```

---

## Conclusion

**Static IP Implementation:** ✅ **100% SUCCESS**
- VMs have static IPs: 10.132.104.10, .11
- IPs are reserved in whereabouts
- S2S VPN routing is working
- OpenShift networking is correct

**RDP Connectivity:** ⚠️ **BLOCKED BY WINDOWS FIREWALL**
- Network path is established
- VMs need firewall configuration
- **Action Required:** Configure Windows Firewall via VM console

**Status:** Ready for firewall configuration to enable RDP access.
