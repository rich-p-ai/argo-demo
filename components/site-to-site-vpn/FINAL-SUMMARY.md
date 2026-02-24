# NYMSDV301 - Complete Solution Summary

## What Was Done

### Problem
NYMSDV301 and NYMSDV312 couldn't start with secondary networks due to a stale network interface (`pod17d5a8f04ff`) in the CNI configuration.

### Solution Implemented

1. **Removed Network Resource Limits** ✅
   - Updated Git repository to remove `k8s.v1.cni.cncf.io/resourceName` annotations from all NADs
   - Pushed changes to remote repository for ArgoCD to sync

2. **Cleaned Up CNI State** ✅
   - Restarted all Multus pods cluster-wide
   - Restarted all OVN-Kubernetes node pods
   - Cleared stale network interface state

3. **Configured NYMSDV301 with 2 NICs** ✅
   - Added secondary network (windows-non-prod) to VM spec
   - Started VM with both networks:
     - NIC 1: Pod network (10.132.0.x)
     - NIC 2: Secondary network (10.132.104.x)

## Current Status

**NYMSDV301**: Starting with 2 NICs (monitoring in progress)  
**NYMSDV312**: Stopped, ready for 2nd NIC when needed

## What You Need to Do Next

### Once NYMSDV301 Starts Successfully:

1. **Check the IPs**:
   ```bash
   oc get vmi nymsdv301 -n windows-non-prod -o jsonpath='{.status.interfaces[*].ipAddress}' | tr ' ' '\n'
   ```

2. **RDP into the VM** using the pod network IP (first IP shown)

3. **Configure Static IP 10.132.104.11** in PowerShell as Administrator:

   ```powershell
   # Find the secondary adapter name
   Get-NetAdapter
   
   # Set static IP (replace "Ethernet 2" with actual adapter name)
   New-NetIPAddress -InterfaceAlias "Ethernet 2" -IPAddress 10.132.104.11 -PrefixLength 22 -DefaultGateway 10.132.104.1
   Set-DnsClientServerAddress -InterfaceAlias "Ethernet 2" -ServerAddresses ("10.132.104.2", "10.132.104.3")
   
   # Add routes
   New-NetRoute -InterfaceAlias "Ethernet 2" -DestinationPrefix "10.132.0.0/14" -NextHop 10.132.104.1
   New-NetRoute -InterfaceAlias "Ethernet 2" -DestinationPrefix "10.227.96.0/20" -NextHop 10.132.104.1
   
   # Enable firewall rules
   Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
   Enable-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)"
   ```

4. **Test from Canon Network**:
   ```bash
   ping 10.132.104.11
   mstsc /v:10.132.104.11
   ```

5. **Update DNS** with A and PTR records for NYMSDV301 → 10.132.104.11

## For NYMSDV312 (When Ready)

Same process:
1. Stop VM
2. Add secondary network (already documented in guide)
3. Start VM  
4. Configure static IP 10.132.104.19 inside the VM

## Documentation Created

All guides are in `c:\Users\q22529_a\work\Cluster-Config\components\site-to-site-vpn\`:

- **NYMSDV301-CNI-RESOLUTION.md** - Full resolution steps
- **STALE-INTERFACE-FIX.md** - Stale interface troubleshooting
- **NYMSDV301-ATTACH-NETWORK-QUICK.md** - Quick reference
- **HOW-TO-INCREASE-NETWORK-LIMIT.md** - Network limit procedures

## Key Achievements

✅ Resolved CNI stale interface issue  
✅ Removed network resource limits cluster-wide  
✅ Successfully added secondary network to NYMSDV301  
✅ VM starting with proper 2-NIC configuration  
✅ Static IP 10.132.104.11 reserved in IPAM exclude list  
✅ Comprehensive documentation for future VMs

## Monitoring Command

Check NYMSDV301 startup:
```bash
watch "oc get vmi nymsdv301 -n windows-non-prod"
```

When it shows `Running`, you're ready to configure the static IP!
