# VPN Gateway Solution for windows-non-prod CUDN (10.227.128.0/21)

## Executive Summary

**PROBLEM**: VMs on the `windows-non-prod` CUDN network (10.227.128.0/21) cannot reach gateway at 10.227.128.1 because:
- No gateway VM exists at 10.227.128.1
- The CUDN is an isolated Layer 2 overlay network
- Site-to-site VPN does not route 10.227.128.0/21 traffic

**IMPACT**: 
- Server nymsdv301 (10.227.128.11) has no external connectivity
- All VMs on 10.227.128.0/21 network are isolated
- Cannot reach on-premise networks via VPN

**SOLUTION**: Deploy a Linux gateway VM at 10.227.128.1 to route traffic between windows-non-prod CUDN and the VPN infrastructure.

---

## Current Network Analysis

### Windows VMs Network Configuration

| VM Name | IP Address | Gateway (Configured) | Gateway (Actual) | Status |
|---------|-----------|---------------------|------------------|---------|
| nymsdv297 | 10.227.128.10 | 10.227.135.254 | NONE | ❌ No connectivity |
| nymsdv301 | 10.227.128.11 | 10.227.135.254 | NONE | ❌ No connectivity |
| nymsdv312 | 10.227.128.12 | 10.227.135.254 | NONE | ❌ No connectivity |
| nymsqa428 | 10.227.128.13 | 10.227.135.254 | NONE | ❌ No connectivity |
| nymsqa429 | 10.227.128.14 | 10.227.135.254 | NONE | ❌ No connectivity |

### Network Topology Issues

```
┌──────────────────────────────────────────────────────────────────┐
│ windows-non-prod CUDN (10.227.128.0/21 = 10.227.128.0-135.255)  │
│                                                                    │
│  VMs: 10.227.128.10-14                                            │
│  Gateway configured: 10.227.135.254  ← WRONG - Not in same /21! │
│  Gateway needed: 10.227.128.1        ← DOES NOT EXIST           │
│                                                                    │
│  ❌ ISOLATED - No route to outside networks                      │
└──────────────────────────────────────────────────────────────────┘
```

**Subnet Math**:
- CIDR: 10.227.128.0/21
- Subnet mask: 255.255.248.0
- Network: 10.227.128.0
- First usable: 10.227.128.1
- Last usable: 10.227.135.254
- Broadcast: 10.227.135.255

**Gateway 10.227.135.254** is technically in the range but:
- No VM or router exists at this IP
- Cannot be reached from isolated CUDN

---

## Solution Architecture

### Proposed Design: VPN Gateway VM

```
┌─────────────────────────────────────────────────────────────┐
│ On-Premise Network (10.227.112.0/20)                         │
└──────────────────┬──────────────────────────────────────────┘
                   ↕
┌─────────────────────────────────────────────────────────────┐
│ AWS Site-to-Site VPN + Transit Gateway                       │
└──────────────────┬──────────────────────────────────────────┘
                   ↕
┌─────────────────────────────────────────────────────────────┐
│ OpenShift Site-to-Site VPN (strongSwan Pod)                  │
│ - Namespace: site-to-site-vpn                                │
│ - Routes: 10.227.112.0/20 ↔ 10.132.0.0/14 (pod network)     │
│ - NEW: Add route for 10.227.128.0/21                         │
└──────────────────┬──────────────────────────────────────────┘
                   ↕
┌─────────────────────────────────────────────────────────────┐
│ VPN Gateway VM (NEW)                                         │
│ - Namespace: windows-non-prod or vpn-infra                   │
│ - Interface 1: 10.227.128.1/21 (windows-non-prod CUDN)      │
│ - Interface 2: 10.132.x.x/14 (pod network)                   │
│ - IP forwarding: enabled                                     │
│ - Routes: Forward 10.227.128.0/21 ↔ pod network             │
└──────────────────┬──────────────────────────────────────────┘
                   ↕
┌─────────────────────────────────────────────────────────────┐
│ windows-non-prod CUDN (10.227.128.0/21)                      │
│ - nymsdv297: 10.227.128.10                                   │
│ - nymsdv301: 10.227.128.11                                   │
│ - nymsdv312: 10.227.128.12                                   │
│ - nymsqa428: 10.227.128.13                                   │
│ - nymsqa429: 10.227.128.14                                   │
│ - Gateway: 10.227.128.1 ✅ (VPN Gateway VM)                  │
└─────────────────────────────────────────────────────────────┘
```

---

## Implementation Steps

### Step 1: Deploy VPN Gateway VM

#### 1.1 Create Gateway VM Manifest

Create file: `vpn-gateway-vm.yaml`

```yaml
---
# VPN Gateway VM for windows-non-prod CUDN
# Acts as router between 10.227.128.0/21 and pod network/VPN
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: vpn-gateway
  namespace: windows-non-prod
  labels:
    app: vpn-gateway
    role: router
  annotations:
    description: "Gateway VM routing windows-non-prod CUDN to VPN"
spec:
  running: true
  dataVolumeTemplates:
    - metadata:
        name: vpn-gateway-root
      spec:
        pvc:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 30Gi
          storageClassName: gp3-csi
        source:
          registry:
            url: docker://quay.io/containerdisks/centos-stream:9
  template:
    metadata:
      labels:
        app: vpn-gateway
        role: router
    spec:
      domain:
        cpu:
          cores: 2
          sockets: 1
          threads: 1
        memory:
          guest: 4Gi
        devices:
          disks:
            - name: root
              disk:
                bus: virtio
            - name: cloudinit
              disk:
                bus: virtio
          interfaces:
            # Primary interface - pod network (for VPN connectivity)
            - name: default
              masquerade: {}
            # Secondary interface - windows-non-prod CUDN
            - name: cudn
              bridge: {}
        resources:
          requests:
            memory: 4Gi
            cpu: 2
          limits:
            memory: 4Gi
            cpu: 2
      networks:
        - name: default
          pod: {}
        - name: cudn
          multus:
            networkName: windows-non-prod
      volumes:
        - name: root
          dataVolume:
            name: vpn-gateway-root
        - name: cloudinit
          cloudInitNoCloud:
            secretRef:
              name: vpn-gateway-cloudinit
---
# Cloud-init configuration for gateway VM
apiVersion: v1
kind: Secret
metadata:
  name: vpn-gateway-cloudinit
  namespace: windows-non-prod
type: Opaque
stringData:
  userdata: |
    #cloud-config
    password: changethis
    chpasswd:
      expire: false
    ssh_pwauth: true
    
    # Add your SSH public keys
    ssh_authorized_keys:
      - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQD... your-key-here
    
    # Install required packages
    packages:
      - iptables
      - iptables-services
      - firewalld
      - tcpdump
      - net-tools
      - bind-utils
      - traceroute
    
    # Enable IP forwarding
    bootcmd:
      - echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/99-gateway.conf
      - echo "net.ipv4.conf.all.rp_filter=0" >> /etc/sysctl.d/99-gateway.conf
      - echo "net.ipv4.conf.default.rp_filter=0" >> /etc/sysctl.d/99-gateway.conf
      - sysctl --system
    
    runcmd:
      # Configure secondary interface with static IP 10.227.128.1
      - |
        cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-eth1
        DEVICE=eth1
        BOOTPROTO=none
        ONBOOT=yes
        IPADDR=10.227.128.1
        PREFIX=21
        EOF
      - ifup eth1
      
      # Disable firewalld (or configure to allow forwarding)
      - systemctl stop firewalld
      - systemctl disable firewalld
      
      # Enable IP forwarding at runtime
      - sysctl -w net.ipv4.ip_forward=1
      
      # Configure iptables for NAT/forwarding
      - iptables -t nat -A POSTROUTING -s 10.227.128.0/21 -o eth0 -j MASQUERADE
      - iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT
      - iptables -A FORWARD -i eth0 -o eth1 -m state --state RELATED,ESTABLISHED -j ACCEPT
      
      # Save iptables rules
      - iptables-save > /etc/sysconfig/iptables
      - systemctl enable iptables
      - systemctl start iptables
    
    final_message: "VPN Gateway VM initialized successfully"
```

#### 1.2 Deploy the Gateway VM

```bash
# Deploy gateway VM
oc apply -f vpn-gateway-vm.yaml

# Wait for VM to start
oc wait --for=condition=Ready vmi/vpn-gateway -n windows-non-prod --timeout=300s

# Check VM status
oc get vm vpn-gateway -n windows-non-prod
oc get vmi vpn-gateway -n windows-non-prod
```

#### 1.3 Verify Gateway VM Configuration

```bash
# Console into gateway VM
virtctl console vpn-gateway -n windows-non-prod

# Check interfaces
ip addr show

# Expected output:
# eth0: 10.132.x.x (pod network)
# eth1: 10.227.128.1/21 (windows-non-prod CUDN)

# Verify IP forwarding
sysctl net.ipv4.ip_forward
# Should return: net.ipv4.ip_forward = 1

# Check routing table
ip route show

# Test connectivity from gateway to pod network
ping 8.8.8.8  # Should work via eth0

# Check iptables rules
iptables -t nat -L -n -v
iptables -L FORWARD -n -v
```

---

### Step 2: Update Windows VMs to Use New Gateway

#### 2.1 Update PowerShell Configuration Script

Update the network configuration to use **10.227.128.1** as gateway:

```powershell
# Run on EACH Windows VM
param(
    [Parameter(Mandatory=$true)]
    [string]$IPAddress,
    [string]$Gateway = "10.227.128.1",  # ← CHANGED from 10.227.135.254
    [int]$PrefixLength = 21,
    [string]$DNS1 = "10.0.0.10",
    [string]$DNS2 = "10.0.0.11"
)

$ErrorActionPreference = 'Stop'
Write-Host "Configuring network with gateway: $Gateway" -ForegroundColor Cyan

# Find second NIC
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Sort-Object ifIndex
if ($adapters.Count -lt 2) {
    Write-Host "ERROR: Less than 2 network adapters found" -ForegroundColor Red
    exit 1
}

$adapter = $adapters[1]
Write-Host "Configuring adapter: $($adapter.Name)" -ForegroundColor Green

# Remove existing IP configuration
Remove-NetIPAddress -InterfaceAlias $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
Remove-NetRoute -InterfaceAlias $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# Add new IP configuration with correct gateway
New-NetIPAddress -InterfaceAlias $adapter.Name `
                 -IPAddress $IPAddress `
                 -PrefixLength $PrefixLength `
                 -DefaultGateway $Gateway -ErrorAction Stop

# Set DNS servers
Set-DnsClientServerAddress -InterfaceAlias $adapter.Name `
                           -ServerAddresses ($DNS1,$DNS2)

# Verify
Write-Host "`nConfiguration applied:" -ForegroundColor Green
Get-NetIPAddress -InterfaceAlias $adapter.Name | Format-Table
Get-NetRoute -InterfaceAlias $adapter.Name | Format-Table

# Test gateway connectivity
Write-Host "`nTesting gateway $Gateway..." -ForegroundColor Cyan
if (Test-NetConnection -ComputerName $Gateway -InformationLevel Quiet) {
    Write-Host "✓ Gateway is reachable!" -ForegroundColor Green
} else {
    Write-Host "✗ Cannot reach gateway" -ForegroundColor Red
}

Write-Host "`nNetwork configuration complete!" -ForegroundColor Green
```

#### 2.2 Apply Configuration to Each VM

```bash
# Access nymsdv301
virtctl console nymsdv301 -n windows-non-prod

# In Windows PowerShell (as Administrator):
# Copy the script above, save as C:\configure-network.ps1
# Then run:
C:\configure-network.ps1 -IPAddress "10.227.128.11"

# Verify connectivity
Test-NetConnection -ComputerName 10.227.128.1 -InformationLevel Detailed
ping 10.227.128.1

# Test external connectivity via gateway
ping 8.8.8.8
```

Repeat for all VMs:
- nymsdv297: `10.227.128.10`
- nymsdv301: `10.227.128.11`
- nymsdv312: `10.227.128.12`
- nymsqa428: `10.227.128.13`
- nymsqa429: `10.227.128.14`

---

### Step 3: Configure VPN Routing for 10.227.128.0/21

#### 3.1 Update strongSwan VPN Configuration

The site-to-site VPN needs to know about the 10.227.128.0/21 network.

```bash
# Edit the strongSwan configmap
oc edit configmap ipsec-config -n site-to-site-vpn

# Add 10.227.128.0/21 to leftsubnet:
# OLD: leftsubnet=10.132.0.0/14
# NEW: leftsubnet=10.132.0.0/14,10.227.128.0/21
```

**Complete ipsec.conf section:**

```ini
conn aws-vpn-tunnel2
    left=%defaultroute
    leftid="CN=vpn-059ee0661e851adf4.endpoint-1"
    leftcert=client-cert.pem
    leftsubnet=10.132.0.0/14,10.227.128.0/21
    right=98.94.136.2
    rightid="CN=vpn-059ee0661e851adf4.endpoint-1"
    rightsubnet=10.227.112.0/20
    ike=aes128-sha1-modp1024!
    esp=aes128-sha1-modp1024!
    ikelifetime=28800s
    lifetime=3600s
    keyexchange=ikev1
    dpdaction=restart
    dpddelay=10s
    dpdtimeout=30s
    auto=start
```

#### 3.2 Restart VPN Pod

```bash
# Delete pod to apply new configuration
oc delete pod -n site-to-site-vpn -l app=site-to-site-vpn

# Wait for pod to restart
oc wait --for=condition=Ready pod -n site-to-site-vpn -l app=site-to-site-vpn --timeout=120s

# Verify VPN tunnel re-established
POD=$(oc get pods -n site-to-site-vpn -l app=site-to-site-vpn -o jsonpath='{.items[0].metadata.name}')
oc logs -n site-to-site-vpn $POD | grep -E "ESTABLISHED|IKE_SA"
```

---

### Step 4: Update AWS and On-Premise Routing

#### 4.1 Add Route to Transit Gateway

```bash
# Add route for 10.227.128.0/21 to TGW route table
aws ec2 create-transit-gateway-route \
  --destination-cidr-block 10.227.128.0/21 \
  --transit-gateway-route-table-id tgw-rtb-0ff564f70c91bf1d5 \
  --transit-gateway-attachment-id tgw-attach-XXXXX \
  --region us-east-1

# Verify route
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id tgw-rtb-0ff564f70c91bf1d5 \
  --filters "Name=route-search.exact-match,Values=10.227.128.0/21" \
  --region us-east-1
```

#### 4.2 Update Palo Alto Firewall (On-Premise)

Add route for 10.227.128.0/21 to VPN connection:

```
# Add to address objects
set address POD-CIDR-NONPROD-WINDOWS 10.227.128.0/21

# Add to VPN routing
set routing route add 10.227.128.0/21 via vpn-tunnel interface

# Add to firewall policy
set rulebase security rules allow rule-name "VPN-to-Windows-VMs" \
  source any destination POD-CIDR-NONPROD-WINDOWS action allow
```

---

## Verification and Testing

### Test 1: Gateway VM Connectivity

```bash
# From gateway VM console
virtctl console vpn-gateway -n windows-non-prod

# Test pod network connectivity
ping 8.8.8.8

# Test VPN pod connectivity
ping <site-to-site-vpn-pod-ip>

# Check forwarding
iptables -t nat -L -n -v
iptables -L FORWARD -n -v
```

### Test 2: Windows VM to Gateway

```powershell
# From nymsdv301 Windows console
# Test gateway
Test-NetConnection -ComputerName 10.227.128.1 -InformationLevel Detailed
ping 10.227.128.1

# Check routing table
route print

# Should see default route via 10.227.128.1
```

### Test 3: Windows VM to External

```powershell
# From nymsdv301 Windows console
# Test internet connectivity
ping 8.8.8.8
nslookup google.com

# Test on-premise network (adjust IP)
ping 10.227.112.10
```

### Test 4: On-Premise to Windows VM

```bash
# From on-premise workstation
ping 10.227.128.11  # nymsdv301
ssh administrator@10.227.128.11  # If SSH enabled
```

### Test 5: End-to-End Verification

```bash
# Check VPN tunnel status
oc logs -n site-to-site-vpn $POD | grep "10.227.128.0/21"

# Check routing on gateway VM
oc exec -n windows-non-prod vpn-gateway -- ip route

# Verify packet forwarding statistics
oc exec -n windows-non-prod vpn-gateway -- iptables -t nat -L -n -v | grep 10.227.128.0
```

---

## Troubleshooting

### Issue: Gateway VM not reachable from Windows VMs

**Check:**
1. Gateway VM is running: `oc get vmi vpn-gateway -n windows-non-prod`
2. Gateway has IP 10.227.128.1: `oc exec vpn-gateway -n windows-non-prod -- ip addr show eth1`
3. Both VMs are on same CUDN: `oc get vm -n windows-non-prod -o yaml | grep -A 5 "multus"`

**Solution:**
```bash
# Verify CUDN connectivity
virtctl console vpn-gateway -n windows-non-prod
ping 10.227.128.11  # Try to reach nymsdv301 from gateway
```

### Issue: Gateway VM can't forward packets

**Check:**
1. IP forwarding enabled: `sysctl net.ipv4.ip_forward` (should be 1)
2. iptables rules configured: `iptables -L -n -v`
3. No firewall blocking: `systemctl status firewalld` (should be stopped)

**Solution:**
```bash
# Re-enable forwarding
oc exec vpn-gateway -n windows-non-prod -- sysctl -w net.ipv4.ip_forward=1

# Verify iptables
oc exec vpn-gateway -n windows-non-prod -- iptables -t nat -A POSTROUTING -s 10.227.128.0/21 -o eth0 -j MASQUERADE
```

### Issue: Windows VMs configured but no external connectivity

**Check:**
1. Windows default route: `route print` (should show 10.227.128.1)
2. Windows can ping gateway: `ping 10.227.128.1`
3. Gateway can forward: Check iptables counters

**Solution:**
```powershell
# On Windows VM - verify route
route print | findstr 10.227.128.1

# If missing, re-add gateway
Remove-NetRoute -InterfaceAlias "Ethernet 1" -Confirm:$false
New-NetIPAddress -InterfaceAlias "Ethernet 1" -IPAddress 10.227.128.11 -PrefixLength 21 -DefaultGateway 10.227.128.1
```

### Issue: VPN tunnel not routing 10.227.128.0/21

**Check:**
1. VPN configuration includes subnet: `oc get configmap ipsec-config -n site-to-site-vpn -o yaml | grep leftsubnet`
2. VPN tunnel established: `oc logs $POD -n site-to-site-vpn | grep ESTABLISHED`
3. AWS TGW has route: AWS console or CLI

**Solution:**
```bash
# Update VPN config
oc edit configmap ipsec-config -n site-to-site-vpn
# Add: leftsubnet=10.132.0.0/14,10.227.128.0/21

# Restart VPN pod
oc delete pod -n site-to-site-vpn -l app=site-to-site-vpn
```

---

## Alternative Solutions

### Alternative 1: Use Existing Bridge-based Network

**If you already have a bridge-based NAD with external routing:**

```yaml
# Change VMs to use bridge-based NAD instead of windows-non-prod CUDN
networks:
  - name: default
    pod: {}
  - name: external
    multus:
      networkName: linux-non-prod  # Or another bridge NAD with routing
```

**Pros:**
- No need for gateway VM
- Direct VPC/TGW routing

**Cons:**
- May not support static IPs as desired
- Requires VM recreation or network changes

### Alternative 2: Move VMs to vpn-infra Namespace with vm-network CUDN

**Use the vm-network CUDN (192.168.1.0/24) which is designed for VPN connectivity:**

```yaml
# Migrate VMs to vpn-infra namespace
# Use vm-network-attachment NAD
networks:
  - name: default
    pod: {}
  - name: vpn
    multus:
      networkName: vm-network-attachment
```

**Pros:**
- Network already designed for VPN routing
- Smaller IP changes (192.168.1.x instead of 10.227.128.x)

**Cons:**
- Requires VM migration to different namespace
- IP addressing scheme change

---

## Post-Implementation Checklist

- [ ] Gateway VM deployed and running
- [ ] Gateway VM has IP 10.227.128.1 on eth1
- [ ] Gateway VM IP forwarding enabled
- [ ] Gateway VM iptables rules configured
- [ ] All Windows VMs updated to use gateway 10.227.128.1
- [ ] Windows VMs can ping 10.227.128.1
- [ ] Windows VMs can ping external IPs (8.8.8.8)
- [ ] strongSwan VPN config updated with 10.227.128.0/21
- [ ] VPN tunnel re-established successfully
- [ ] AWS TGW route added for 10.227.128.0/21
- [ ] Palo Alto firewall configured for 10.227.128.0/21
- [ ] On-premise can reach Windows VMs (10.227.128.x)
- [ ] End-to-end connectivity verified

---

## Summary

### Root Cause
The `windows-non-prod` CUDN (10.227.128.0/21) is an isolated Layer 2 overlay network with no gateway configured, preventing VMs from routing traffic externally.

### Solution
Deploy a Linux gateway VM at 10.227.128.1 with:
- Interface on windows-non-prod CUDN (10.227.128.1/21)
- Interface on pod network (10.132.x.x/14)
- IP forwarding and NAT enabled
- Routes to/from VPN infrastructure

### Next Steps
1. Deploy gateway VM
2. Update Windows VM network configurations
3. Configure VPN routing
4. Update AWS and on-premise routing
5. Test end-to-end connectivity

---

**Document Version**: 1.0  
**Created**: 2026-02-12  
**Status**: Ready for Implementation
