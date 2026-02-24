# Static IP Options for S2S VPN Routable Networks

## Problem Statement

**Requirement:** VMs need static IP addresses that are:
1. ✅ Routable through the site-to-site VPN
2. ✅ Accessible from company network for RDP
3. ✅ Have DNS entries pointing to specific IPs
4. ✅ Within existing S2S VPN subnets

**Current Routable Subnets (S2S VPN Configured):**
- `10.132.100.0/22` - linux-non-prod (VLAN 100)
- `10.132.104.0/22` - windows-non-prod (VLAN 101)
- `10.132.108.0/22` - utility (VLAN 102)

**Current Issue:**
- Existing NADs use **whereabouts IPAM** (dynamic allocation)
- IPs assigned automatically from ranges (.10 to .250)
- Cannot assign specific IPs for DNS/RDP requirements
- CUDN (192.168.10.0/24) is NOT routable via S2S VPN ❌

---

## Current IP Allocation

### Linux Network (10.132.100.0/22)
- **Total IPs:** 1,024 (.0 to .255 on 10.132.100-103)
- **Gateway:** 10.132.100.1
- **Reserved:** 10.132.100.1, .2, .3
- **Whereabouts Range:** 10.132.100.10 to 10.132.103.250
- **Available for Static:** 10.132.100.4 to .9, 10.132.103.251 to .254

### Windows Network (10.132.104.0/22)
- **Total IPs:** 1,024 (.0 to .255 on 10.132.104-107)
- **Gateway:** 10.132.104.1
- **Reserved:** 10.132.104.1, .2, .3
- **Whereabouts Range:** 10.132.104.10 to 10.132.107.250
- **Available for Static:** 10.132.104.4 to .9, 10.132.107.251 to .254

### Utility Network (10.132.108.0/22)
- **Total IPs:** 1,024 (.0 to .255 on 10.132.108-111)
- **Gateway:** 10.132.108.1
- **Reserved:** 10.132.108.1, .2, .3
- **Whereabouts Range:** 10.132.108.10 to 10.132.111.250
- **Available for Static:** 10.132.108.4 to .9, 10.132.111.251 to .254

---

## Option 1: Reserve Static IP Ranges (RECOMMENDED)

### Approach
Carve out dedicated static IP ranges from each subnet and adjust whereabouts to exclude them.

### Proposed IP Allocation

#### Windows Network (10.132.104.0/22) - For RDP VMs
```
10.132.104.1         - Gateway
10.132.104.2-3       - Reserved
10.132.104.4-9       - INFRASTRUCTURE (VPN gateways, DNS, etc.)
10.132.104.10-199    - WHEREABOUTS DYNAMIC (existing)
10.132.104.200-249   - STATIC IP POOL (50 IPs) ✨ NEW
10.132.104.250-254   - Reserved for future
```

#### Linux Network (10.132.100.0/22)
```
10.132.100.1         - Gateway
10.132.100.2-3       - Reserved
10.132.100.4-9       - INFRASTRUCTURE
10.132.100.10-199    - WHEREABOUTS DYNAMIC (existing)
10.132.100.200-249   - STATIC IP POOL (50 IPs) ✨ NEW
10.132.100.250-254   - Reserved
```

#### Utility Network (10.132.108.0/22)
```
10.132.108.1         - Gateway
10.132.108.2-3       - Reserved
10.132.108.4-9       - INFRASTRUCTURE
10.132.108.10-199    - WHEREABOUTS DYNAMIC (existing)
10.132.108.200-249   - STATIC IP POOL (50 IPs) ✨ NEW
10.132.108.250-254   - Reserved
```

### Implementation Steps

#### Step 1: Create Static-IP NADs

Create new NADs without IPAM for static IP assignment:

```yaml
---
# windows-non-prod-static NAD
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: windows-non-prod-static
  namespace: windows-non-prod
  annotations:
    description: "Static IP network for Windows VMs (10.132.104.200-249)"
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "name": "windows-non-prod-static",
      "type": "bridge",
      "bridge": "br-windows",
      "vlan": 101,
      "preserveDefaultVlan": false,
      "macspoofchk": false,
      "ipam": {}
    }
---
# linux-non-prod-static NAD
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: linux-non-prod-static
  namespace: windows-non-prod
  annotations:
    description: "Static IP network for Linux VMs (10.132.100.200-249)"
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "name": "linux-non-prod-static",
      "type": "bridge",
      "bridge": "br-linux",
      "vlan": 100,
      "preserveDefaultVlan": false,
      "macspoofchk": false,
      "ipam": {}
    }
---
# utility-static NAD
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: utility-static
  namespace: windows-non-prod
  annotations:
    description: "Static IP network for utility VMs (10.132.108.200-249)"
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "name": "utility-static",
      "type": "bridge",
      "bridge": "br-utility",
      "vlan": 102,
      "preserveDefaultVlan": false,
      "macspoofchk": false,
      "ipam": {}
    }
```

#### Step 2: Update Existing Dynamic NADs

Modify whereabouts ranges to exclude static pool (10.132.x.200-249):

```yaml
# Update windows-non-prod NAD
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "name": "windows-non-prod",
      "type": "bridge",
      "bridge": "br-windows",
      "vlan": 101,
      "ipam": {
        "type": "whereabouts",
        "range": "10.132.104.0/22",
        "range_start": "10.132.104.10",
        "range_end": "10.132.104.199",    # Changed from .250 to .199
        "gateway": "10.132.104.1",
        "exclude": [
          "10.132.104.1/32",
          "10.132.104.2/32",
          "10.132.104.3/32",
          "10.132.104.200/29",             # Exclude static pool
          "10.132.104.208/28",
          "10.132.104.224/27"
        ]
      }
    }
```

Similar updates for linux-non-prod and utility NADs.

#### Step 3: VM Configuration for Static IPs

**Example: Windows VM with Static IP**

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: myapp-server
  namespace: windows-non-prod
  labels:
    app: myapp
    static-ip: "10.132.104.200"
spec:
  running: true
  template:
    metadata:
      labels:
        kubevirt.io/vm: myapp-server
    spec:
      domain:
        devices:
          interfaces:
            - name: default
              masquerade: {}
            - name: windows-static-ip    # Static IP interface
              bridge: {}
      networks:
        - name: default
          pod: {}
        - name: windows-static-ip        # Use static NAD
          multus:
            networkName: windows-non-prod-static
      # ... rest of VM spec
```

**Configure IP inside Windows VM:**
1. Login via console
2. Open Network Connections (ncpa.cpl)
3. Configure "Ethernet 2":
   - IP: `10.132.104.200`
   - Subnet: `255.255.252.0` (/22)
   - Gateway: `10.132.104.1`
   - DNS: Your DNS servers

**Configure IP inside Linux VM:**
```bash
sudo nmcli con add type ethernet ifname eth1 con-name static-ip \
  ipv4.addresses 10.132.100.200/22 \
  ipv4.gateway 10.132.100.1 \
  ipv4.dns "10.132.104.53" \
  ipv4.method manual \
  autoconnect yes

sudo nmcli con up static-ip
```

### Advantages
✅ Uses existing routable subnets (S2S VPN already configured)  
✅ RDP directly from company network  
✅ Predictable IPs for DNS entries  
✅ No conflicts with whereabouts  
✅ Simple to manage  

### Disadvantages
⚠️ Requires manual IP configuration inside VM  
⚠️ Need to track IP assignments manually  

---

## Option 2: Use Utility Subnet for All Static IPs

### Approach
Dedicate the utility subnet (10.132.108.0/22) entirely for static IP VMs.

### Proposed Allocation

```
10.132.108.1         - Gateway
10.132.108.2-9       - Infrastructure
10.132.108.10-99     - Windows VMs with static IPs (90 IPs)
10.132.108.100-199   - Linux VMs with static IPs (100 IPs)
10.132.108.200-249   - Infrastructure/Special VMs (50 IPs)
10.132.108.250-254   - Reserved
```

### Implementation

Create single static-IP NAD for utility network:

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: vm-static-ip
  namespace: windows-non-prod
  annotations:
    description: "Static IP network for all VMs - utility subnet"
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "name": "vm-static-ip",
      "type": "bridge",
      "bridge": "br-utility",
      "vlan": 102,
      "preserveDefaultVlan": false,
      "macspoofchk": false,
      "ipam": {}
    }
```

### VM Example

```yaml
networks:
  - name: default
    pod: {}
  - name: static-ip
    multus:
      networkName: vm-static-ip
```

**Inside VM:**
- Windows: IP 10.132.108.10, Mask 255.255.252.0, GW 10.132.108.1
- Linux: IP 10.132.108.100, Mask /22, GW 10.132.108.1

### Advantages
✅ Centralized static IP management  
✅ Clear separation: dynamic (linux/windows), static (utility)  
✅ Simpler NAD management  
✅ All static IPs in one subnet  

### Disadvantages
⚠️ Changes purpose of utility subnet  
⚠️ Less IP capacity (1024 IPs total for all static)  
⚠️ May conflict with existing utility network usage  

---

## Option 3: Modify Existing NADs to Support Static (NOT RECOMMENDED)

### Approach
Remove whereabouts IPAM from existing NADs, making all IPs static.

### Issues
❌ Breaks existing dynamic VMs  
❌ Disrupts MTV migrations  
❌ Would require reconfiguring all VMs  
❌ High risk, high effort  

**NOT RECOMMENDED**

---

## Option 4: Hybrid - Separate Bridge for Static IPs

### Approach
Create entirely new bridge interfaces (br-windows-static, etc.) on same VLANs.

### Implementation

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: windows-static-bridge
  namespace: windows-non-prod
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "name": "windows-static-bridge",
      "type": "bridge",
      "bridge": "br-windows-static",    # Different bridge name
      "vlan": 101,
      "ipam": {}
    }
```

### Advantages
✅ Complete isolation from dynamic network  
✅ No risk of conflicts  

### Disadvantages
⚠️ Additional bridges to manage  
⚠️ More complex  
⚠️ Same VLAN, different bridge (potential confusion)  

---

## Recommended Solution: Option 1 (Reserved Static Ranges)

### Summary

**Create 3 new static-IP NADs:**
- `windows-non-prod-static` - IPs 10.132.104.200-249
- `linux-non-prod-static` - IPs 10.132.100.200-249
- `utility-static` - IPs 10.132.108.200-249

**Benefits:**
✅ **S2S VPN Routable** - All IPs already configured in VPN  
✅ **RDP from Company** - Direct access to 10.132.104.x  
✅ **DNS Ready** - Assign specific IPs for DNS entries  
✅ **50 IPs per subnet** - Plenty for static needs  
✅ **No Disruption** - Existing dynamic VMs unaffected  
✅ **Simple Management** - Clear separation of dynamic/static  

### IP Assignment Strategy

**Windows VMs (RDP Priority):**
```
10.132.104.200 - myapp01.company.com (App Server 1)
10.132.104.201 - myapp02.company.com (App Server 2)
10.132.104.202 - sqlserver01.company.com (Database)
10.132.104.203 - webserver01.company.com (Web Server)
... etc
```

**Linux VMs:**
```
10.132.100.200 - lnxapp01.company.com (Linux App 1)
10.132.100.201 - lnxweb01.company.com (Linux Web)
... etc
```

**Utility VMs:**
```
10.132.108.200 - monitoring01.company.com
10.132.108.201 - jumphost01.company.com
... etc
```

### DNS Configuration

In your DNS server (company network):

```
; A Records
myapp01.company.com.        IN  A   10.132.104.200
myapp02.company.com.        IN  A   10.132.104.201
sqlserver01.company.com.    IN  A   10.132.104.202

; PTR Records (Reverse DNS)
200.104.132.10.in-addr.arpa. IN PTR myapp01.company.com.
201.104.132.10.in-addr.arpa. IN PTR myapp02.company.com.
```

### RDP Access from Company Network

**From company workstation:**
```powershell
# RDP to specific server
mstsc /v:10.132.104.200

# Or use DNS name
mstsc /v:myapp01.company.com
```

Traffic flows: `Company Network → S2S VPN → 10.132.104.200 (VM)`

---

## Implementation Plan

### Phase 1: Create Static-IP NADs

1. Create manifest files
2. Apply to cluster
3. Verify NADs created

### Phase 2: Update Whereabouts Ranges (Optional but Recommended)

1. Update existing NADs to end at .199 (exclude .200-249)
2. Apply updates
3. Test existing VMs still work

### Phase 3: Deploy Test VM with Static IP

1. Create test Windows VM with static-IP interface
2. Configure IP 10.132.104.200 inside VM
3. Test connectivity from company network
4. Test RDP access

### Phase 4: Roll Out to Production VMs

1. Identify VMs needing static IPs
2. Assign IPs from pool (.200-249)
3. Update DNS records
4. Migrate VMs to use static-IP NADs

---

## Next Steps

**Choose your approach:**
1. ✅ **Option 1 (Recommended):** Create static-IP NADs with reserved ranges
2. ⚠️ **Option 2:** Use utility subnet exclusively for static IPs
3. ❌ **Option 3:** Not recommended (breaks existing)
4. ⚠️ **Option 4:** Separate bridges (more complex)

**Once chosen, I can:**
1. Generate the complete YAML manifests
2. Create deployment scripts
3. Provide step-by-step instructions
4. Create IP tracking spreadsheet template

---

## Files to Create

1. **static-ip-nads.yaml** - NAD definitions
2. **vm-static-ip-example.yaml** - Example VM manifest
3. **STATIC-IP-ALLOCATION.md** - IP tracking document
4. **CONFIGURE-STATIC-IP-GUIDE.md** - Setup instructions for VMs
5. **DNS-RECORDS-TEMPLATE.md** - DNS configuration examples

Would you like me to proceed with Option 1 (recommended) and create all the necessary files?
