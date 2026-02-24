# Static IP Implementation Plan - Test VMs

## Test VMs

| VM Name | Current IP | Current Network | Status | Target IP |
|---------|------------|-----------------|--------|-----------|
| NYMSDV297 | 10.132.104.10 | windows-non-prod (dynamic) | Running | Option 1: Keep 10.132.104.10<br>Option 2: Move to 10.132.104.200 |
| NYMSDV301 | 10.132.104.11 | windows-non-prod (dynamic) | Running | Option 1: Keep 10.132.104.11<br>Option 2: Move to 10.132.104.201 |
| NYMSDV312 | None (pod network only) | pod | Stopped | Assign 10.132.104.19 or 10.132.104.202 |

---

## Option 1: Reserve Current Dynamic IPs (RECOMMENDED FOR TESTING)

### Approach
Keep VMs on current IPs, but reserve them in whereabouts to prevent conflicts.

### Implementation

#### Step 1: Add IPs to Whereabouts Exclusion List

Update the windows-non-prod NAD to exclude these specific IPs:

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: windows-non-prod
  namespace: openshift-mtv
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "name": "windows-non-prod",
      "type": "bridge",
      "bridge": "br-windows",
      "vlan": 101,
      "preserveDefaultVlan": false,
      "macspoofchk": true,
      "ipam": {
        "type": "whereabouts",
        "range": "10.132.104.0/22",
        "range_start": "10.132.104.10",
        "range_end": "10.132.107.250",
        "gateway": "10.132.104.1",
        "routes": [
          {
            "dst": "10.132.0.0/14",
            "gw": "10.132.104.1"
          },
          {
            "dst": "10.227.96.0/20",
            "gw": "10.132.104.1"
          }
        ],
        "exclude": [
          "10.132.104.1/32",
          "10.132.104.2/32",
          "10.132.104.3/32",
          "10.132.104.10/32",
          "10.132.104.11/32",
          "10.132.104.19/32"
        ]
      }
    }
```

#### Step 2: Create DNS Entries

```dns
; Forward zones
nymsdv297.corp.cusa.canon.com.  IN  A   10.132.104.10
nymsdv301.corp.cusa.canon.com.  IN  A   10.132.104.11
nymsdv312.corp.cusa.canon.com.  IN  A   10.132.104.19

; Reverse zones
10.104.132.10.in-addr.arpa.  IN  PTR  nymsdv297.corp.cusa.canon.com.
11.104.132.10.in-addr.arpa.  IN  PTR  nymsdv301.corp.cusa.canon.com.
19.104.132.10.in-addr.arpa.  IN  PTR  nymsdv312.corp.cusa.canon.com.
```

#### Step 3: Test RDP Access

From company network:

```powershell
# Test connectivity
ping 10.132.104.10
ping 10.132.104.11
ping 10.132.104.19

# RDP to VMs
mstsc /v:10.132.104.10    # NYMSDV297
mstsc /v:10.132.104.11    # NYMSDV301
mstsc /v:10.132.104.19    # NYMSDV312

# Or use DNS names
mstsc /v:nymsdv297.corp.cusa.canon.com
```

### Advantages
✅ No changes to VMs  
✅ IPs already assigned and working  
✅ Minimal disruption  
✅ Quick to implement  

### Disadvantages
⚠️ IPs still in "dynamic" range  
⚠️ Not using reserved static pool (.200-.249)  
⚠️ Future VMs might conflict if whereabouts breaks  

---

## Option 2: Migrate to Static IP Range (PRODUCTION APPROACH)

### Approach
Move VMs to dedicated static IP range (10.132.104.200-249).

### New IP Assignments

| VM | Old IP | New IP | Hostname |
|----|--------|--------|----------|
| NYMSDV297 | 10.132.104.10 | 10.132.104.200 | nymsdv297.corp.cusa.canon.com |
| NYMSDV301 | 10.132.104.11 | 10.132.104.201 | nymsdv301.corp.cusa.canon.com |
| NYMSDV312 | (none) | 10.132.104.202 | nymsdv312.corp.cusa.canon.com |

### Implementation

#### Step 1: Create Static-IP NAD

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: windows-non-prod-static
  namespace: windows-non-prod
  annotations:
    description: "Static IP network for Windows VMs requiring fixed IPs for DNS/RDP"
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
```

#### Step 2: Update VM Specs

**For NYMSDV297 and NYMSDV301 (already have network):**

These VMs currently use the dynamic NAD. We need to edit them to use the static NAD:

```bash
# Edit VM to change network
oc edit vm nymsdv297 -n windows-non-prod

# Change from:
#   networks:
#     - name: net-0
#       multus:
#         networkName: windows-non-prod

# To:
#   networks:
#     - name: net-0
#       multus:
#         networkName: windows-non-prod-static
```

**For NYMSDV312 (currently pod network):**

```bash
# Edit VM to add secondary network
oc edit vm nymsdv312 -n windows-non-prod

# Add networks section:
spec:
  template:
    spec:
      domain:
        devices:
          interfaces:
            - name: default
              masquerade: {}
            - name: net-0
              bridge: {}
      networks:
        - name: default
          pod: {}
        - name: net-0
          multus:
            networkName: windows-non-prod-static
```

#### Step 3: Configure Static IPs Inside VMs

After restarting VMs, login to each and configure the new IP:

**NYMSDV297:**
1. Login via console or RDP (will use old IP initially)
2. Open Network Connections (ncpa.cpl)
3. Find "Ethernet" or "Ethernet 2"
4. Properties → TCP/IPv4 → Properties
5. Configure:
   - IP: `10.132.104.200`
   - Subnet: `255.255.252.0`
   - Gateway: `10.132.104.1`
   - DNS: `10.132.104.53` (or your DNS)
6. Apply and close
7. Test: `ping 10.132.104.1`

**NYMSDV301:**
- Same steps, use IP: `10.132.104.201`

**NYMSDV312:**
- Same steps, use IP: `10.132.104.202`

#### Step 4: Update DNS Records

```dns
; Forward zones - UPDATE to new IPs
nymsdv297.corp.cusa.canon.com.  IN  A   10.132.104.200
nymsdv301.corp.cusa.canon.com.  IN  A   10.132.104.201
nymsdv312.corp.cusa.canon.com.  IN  A   10.132.104.202

; Reverse zones
200.104.132.10.in-addr.arpa.  IN  PTR  nymsdv297.corp.cusa.canon.com.
201.104.132.10.in-addr.arpa.  IN  PTR  nymsdv301.corp.cusa.canon.com.
202.104.132.10.in-addr.arpa.  IN  PTR  nymsdv312.corp.cusa.canon.com.
```

#### Step 5: Test RDP Access

```powershell
# Test new IPs
ping 10.132.104.200
ping 10.132.104.201
ping 10.132.104.202

# RDP to new IPs
mstsc /v:10.132.104.200    # NYMSDV297
mstsc /v:10.132.104.201    # NYMSDV301
mstsc /v:10.132.104.202    # NYMSDV312
```

### Advantages
✅ Uses dedicated static IP range  
✅ Clear separation from dynamic pool  
✅ Proper architecture for production  
✅ No conflicts with whereabouts  
✅ Scalable for more VMs  

### Disadvantages
⚠️ Requires VM restarts  
⚠️ IP addresses change (update DNS)  
⚠️ Manual IP configuration inside VMs  
⚠️ More steps  

---

## Comparison

| Aspect | Option 1: Reserve Current | Option 2: Static Range |
|--------|---------------------------|------------------------|
| **Effort** | Low | Medium |
| **VM Downtime** | None | Restart required |
| **IP Change** | No | Yes (.10/.11/.19 → .200/.201/.202) |
| **DNS Update** | No | Yes |
| **Architecture** | Quick fix | Proper solution |
| **Scalability** | Limited | Good |
| **Risk** | Low | Low-Medium |
| **Recommended For** | Testing/POC | Production |

---

## Recommended Approach: Hybrid

### Phase 1: Test with Option 1 (Reserve Current IPs)
1. Add .10, .11, .19 to whereabouts exclusion list
2. Create DNS entries for current IPs
3. Test RDP access from company network
4. Validate S2S VPN routing works
5. Test connectivity and performance

**Timeline:** 30 minutes

### Phase 2: Migrate to Option 2 (If Phase 1 successful)
1. Create static-IP NAD
2. Schedule maintenance window
3. Migrate VMs to new IPs (.200-.201-.202)
4. Update DNS records
5. Validate RDP access on new IPs

**Timeline:** 2 hours (including testing)

---

## Implementation Commands

### For Option 1 (Quick Test):

```bash
# 1. Backup current NAD
oc get nad windows-non-prod -n openshift-mtv -o yaml > windows-non-prod-backup.yaml

# 2. Update NAD with exclusions
cat <<'EOF' | oc apply -f -
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: windows-non-prod
  namespace: openshift-mtv
  labels:
    app.kubernetes.io/component: mtv-network
    app.kubernetes.io/name: windows-non-prod
    cluster: rosa-non-prod
    environment: non-prod
    network.openshift.io/type: vm-migration
  annotations:
    description: Secondary network for Windows VMs - 10.132.104.0/22
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "name": "windows-non-prod",
      "type": "bridge",
      "bridge": "br-windows",
      "vlan": 101,
      "preserveDefaultVlan": false,
      "macspoofchk": true,
      "ipam": {
        "type": "whereabouts",
        "range": "10.132.104.0/22",
        "range_start": "10.132.104.10",
        "range_end": "10.132.107.250",
        "gateway": "10.132.104.1",
        "routes": [
          {
            "dst": "10.132.0.0/14",
            "gw": "10.132.104.1"
          },
          {
            "dst": "10.227.96.0/20",
            "gw": "10.132.104.1"
          }
        ],
        "exclude": [
          "10.132.104.1/32",
          "10.132.104.2/32",
          "10.132.104.3/32",
          "10.132.104.10/32",
          "10.132.104.11/32",
          "10.132.104.19/32"
        ]
      }
    }
EOF

# 3. Verify update
oc get nad windows-non-prod -n openshift-mtv -o yaml | grep -A 6 exclude

# 4. Test - VMs should keep their IPs
oc get vmi nymsdv297 nymsdv301 -n windows-non-prod -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.interfaces[0].ipAddress}{"\n"}{end}'
```

### For Option 2 (Production Setup):

```bash
# 1. Create static-IP NAD
oc apply -f static-ip-nads.yaml

# 2. Verify NAD created
oc get nad windows-non-prod-static -n windows-non-prod

# 3. Stop VMs
oc patch vm nymsdv297 -n windows-non-prod --type merge -p '{"spec":{"running":false}}'
oc patch vm nymsdv301 -n windows-non-prod --type merge -p '{"spec":{"running":false}}'

# 4. Wait for VMs to stop
oc wait --for=delete vmi/nymsdv297 -n windows-non-prod --timeout=300s
oc wait --for=delete vmi/nymsdv301 -n windows-non-prod --timeout=300s

# 5. Update VM network references (manual edit required)
oc edit vm nymsdv297 -n windows-non-prod
oc edit vm nymsdv301 -n windows-non-prod
oc edit vm nymsdv312 -n windows-non-prod

# 6. Start VMs
oc patch vm nymsdv297 -n windows-non-prod --type merge -p '{"spec":{"running":true}}'
oc patch vm nymsdv301 -n windows-non-prod --type merge -p '{"spec":{"running":true}}'
oc patch vm nymsdv312 -n windows-non-prod --type merge -p '{"spec":{"running":true}}'

# 7. Configure static IPs inside each VM (manual - see steps above)
```

---

## Testing Checklist

### Network Connectivity Tests

From company network workstation:

- [ ] Ping NYMSDV297 IP
- [ ] Ping NYMSDV301 IP
- [ ] Ping NYMSDV312 IP
- [ ] RDP to NYMSDV297
- [ ] RDP to NYMSDV301
- [ ] RDP to NYMSDV312
- [ ] DNS resolution for hostnames
- [ ] Reverse DNS lookup

### From VMs (inside Windows):

- [ ] Ping gateway (10.132.104.1)
- [ ] Ping company DNS server
- [ ] Ping other VMs
- [ ] Access internet (if configured)
- [ ] Access internal company resources

---

## Rollback Plan

### If Option 1 Fails:
```bash
# Restore original NAD
oc apply -f windows-non-prod-backup.yaml
```

### If Option 2 Fails:
```bash
# Revert VMs to dynamic NAD
oc edit vm nymsdv297 -n windows-non-prod
# Change networkName back to: windows-non-prod

# Restart VMs - they'll get dynamic IPs again
```

---

## Files to Create

1. **static-ip-nads.yaml** - NAD definition for static IPs
2. **vm-network-patches.yaml** - Patches to update VM network refs
3. **dns-records.txt** - DNS zone file entries
4. **test-connectivity.ps1** - PowerShell script to test from company network
5. **configure-vm-static-ip.ps1** - Script to run inside Windows VMs

Would you like me to create these files now?
