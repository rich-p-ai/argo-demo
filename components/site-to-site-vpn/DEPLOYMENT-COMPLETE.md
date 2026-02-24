# Gateway VM Deployment - COMPLETE ✅

## Deployment Summary

**Status**: ✅ **SUCCESSFULLY DEPLOYED AND RUNNING**

### VM Details
- **Name**: vpn-gateway
- **Namespace**: windows-non-prod  
- **Status**: Running
- **Guest OS**: CentOS Stream 9
- **Guest Agent**: Connected ✅

### Network Configuration
| Interface | Network | IP Address | Status |
|-----------|---------|------------|--------|
| eth0 | Pod Network (masquerade) | 10.135.0.23 | ✅ UP |
| eth1 | windows-non-prod CUDN | 10.227.128.15 | ✅ UP |

### System Status
- **IP Forwarding**: ✅ Enabled (`net.ipv4.ip_forward = 1`)
- **iptables**: ⚠️ Not configured yet (packages may still be installing)
- **Cloud-init**: Running/Complete

---

## Next Steps: Complete Gateway Configuration

### Step 1: Access Gateway VM Console

```bash
virtctl console vpn-gateway -n windows-non-prod
```

**Default Credentials**:
- Username: `root`
- Password: `changethis`

### Step 2: Verify Cloud-Init Completion

Once logged into the gateway VM:

```bash
# Check if packages are installed
rpm -qa | grep iptables

# Check if setup script exists
ls -la /usr/local/bin/setup-gateway-routing.sh

# If script exists, run it
/usr/local/bin/setup-gateway-routing.sh

# If script doesn't exist, packages might still be installing
# Check cloud-init status
tail -f /var/log/messages | grep cloud-init
```

### Step 3: Manual Configuration (if cloud-init hasn't completed)

If packages aren't installed yet, run these commands in the guest VM:

```bash
# Install required packages
dnf install -y iptables iptables-services

# Configure iptables NAT
iptables -t nat -A POSTROUTING -s 10.227.128.0/21 -o eth0 -j MASQUERADE

# Allow forwarding
iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT
iptables -A FORWARD -i eth0 -o eth1 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i eth1 -o eth1 -j ACCEPT

# Save rules
iptables-save > /etc/sysconfig/iptables
systemctl enable iptables
systemctl start iptables
```

### Step 4: Verify Gateway Configuration

```bash
# Check interfaces
ip addr show

# Check routing
ip route show

# Check IP forwarding
sysctl net.ipv4.ip_forward

# Check iptables
iptables -t nat -L -n -v
iptables -L FORWARD -n -v

# Test internet connectivity
ping 8.8.8.8
```

### Step 5: Test from Windows VM (nymsdv301)

Access Windows VM console:
```bash
virtctl console nymsdv301 -n windows-non-prod
```

Test connectivity to gateway:
```powershell
# Test ping to gateway
ping 10.227.128.15

# If gateway responds, configure network
$adapter = (Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Sort-Object ifIndex)[1]

# Remove old config
Remove-NetIPAddress -InterfaceAlias $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
Remove-NetRoute -InterfaceAlias $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue

# Add new config with gateway
New-NetIPAddress -InterfaceAlias $adapter.Name `
                 -IPAddress "10.227.128.11" `
                 -PrefixLength 21 `
                 -DefaultGateway "10.227.128.15"

# Test
ping 10.227.128.15
ping 8.8.8.8
```

---

## Configuration Files Created

1. **vpn-gateway-vm.yaml** - VM and cloud-init configuration
2. **configure-gateway.sh** - Manual configuration script
3. **GATEWAY-VM-STATUS.md** - Complete status and procedures
4. **VPN-GATEWAY-SOLUTION.md** - Full architecture and solution
5. **VPN-ROUTING-ANALYSIS.md** - Technical analysis of the routing issue

---

## Quick Status Check Commands

```bash
# Check VM status
oc get vm,vmi -n windows-non-prod | grep vpn-gateway

# Get VM IPs
oc get vmi vpn-gateway -n windows-non-prod -o jsonpath='{.status.interfaces[*].ipAddress}'

# Check if guest agent is connected
oc get vmi vpn-gateway -n windows-non-prod -o jsonpath='{.status.conditions}' | jq '.[] | select(.type=="AgentConnected")'

# Access console
virtctl console vpn-gateway -n windows-non-prod
```

---

## Troubleshooting

### If cloud-init is still running
```bash
# Inside VM, check cloud-init progress
tail -f /var/log/messages

# Or check cloud-init status (if cloud-init package is installed)
cloud-init status --wait
```

### If iptables not installed
```bash
# Inside VM
dnf install -y iptables iptables-services tcpdump net-tools bind-utils
```

### If gateway not responding
```bash
# Check VM is running
oc get vmi vpn-gateway -n windows-non-prod

# Restart VM if needed
virtctl restart vpn-gateway -n windows-non-prod
```

---

## Summary

✅ Gateway VM is **deployed and running**  
✅ IP forwarding is **enabled**  
✅ Network interfaces are **UP and configured**  
⚠️ iptables NAT rules need to be **verified/configured manually**  

**Next Action**: Access the gateway VM console and complete Step 2-4 above to finish configuration.

**After Gateway Configuration**: Configure Windows VMs (starting with nymsdv301) to use gateway IP 10.227.128.15

---

**Document Created**: 2026-02-12 19:42 UTC  
**Gateway VM**: vpn-gateway  
**Status**: Awaiting final configuration
