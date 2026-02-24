# Attach Site-to-Site VPN to OVN Layer 2 Network - Complete Solution

## Overview

**Goal**: Make VPN pod act as gateway for windows-non-prod CUDN (10.227.128.0/21) by attaching it directly to the OVN Layer 2 overlay network.

**Architecture**:
```
On-Premise Networks ↔ AWS VPN ↔ strongSwan Pod (with 2 interfaces) ↔ Windows VMs
                                    ├─ eth0: Pod network (VPN)
                                    └─ net1: 10.227.128.1 (CUDN gateway)
```

**Benefits**:
- ✅ No separate gateway VM needed
- ✅ VPN pod is the gateway (10.227.128.1)
- ✅ Direct routing between VPN and Windows VMs
- ✅ Simpler architecture
- ✅ Lower resource usage

---

## Implementation Steps

### Step 1: Add site-to-site-vpn Namespace to CUDN

Update the windows-non-prod CUDN to include the site-to-site-vpn namespace:

```yaml
---
# Updated ClusterUserDefinedNetwork for Windows VMs
apiVersion: k8s.ovn.org/v1
kind: ClusterUserDefinedNetwork
metadata:
  name: windows-non-prod
  annotations:
    description: "Secondary network for Windows VMs - 10.227.128.0/21"
    network.openshift.io/purpose: "vm-migration-windows"
spec:
  namespaceSelector:
    matchExpressions:
      - key: kubernetes.io/metadata.name
        operator: In
        values:
          - windows-non-prod
          - openshift-mtv
          - vm-migrations
          - vpn-infra
          - site-to-site-vpn  # ← ADD THIS
  network:
    topology: Layer2
    layer2:
      role: Secondary
      subnets:
        - "10.227.128.0/21"
      ipamLifecycle: Persistent
      mtu: 1500
```

### Step 2: Update VPN Deployment with Multus Annotation

Modify the VPN deployment to:
1. Remove `hostNetwork: true` (incompatible with Multus)
2. Add Multus network annotation for windows-non-prod
3. Add init container to configure routing

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: site-to-site-vpn
  namespace: site-to-site-vpn
  labels:
    app: site-to-site-vpn
    app.kubernetes.io/name: site-to-site-vpn
    app.kubernetes.io/component: vpn-client
  annotations:
    description: "Site-to-Site VPN with CUDN gateway attachment"
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: site-to-site-vpn
  template:
    metadata:
      labels:
        app: site-to-site-vpn
        app.kubernetes.io/name: site-to-site-vpn
        app.kubernetes.io/component: vpn-client
      annotations:
        k8s.v1.cni.cncf.io/networks: |
          [
            {
              "name": "windows-non-prod",
              "namespace": "site-to-site-vpn",
              "ips": ["10.227.128.1/21"]
            }
          ]
    spec:
      serviceAccountName: site-to-site-vpn
      # REMOVED: hostNetwork: true
      # hostNetwork is incompatible with Multus secondary networks
      dnsPolicy: ClusterFirst
      nodeSelector:
        node-role.kubernetes.io/worker: ""
      tolerations:
        - key: "node.kubernetes.io/unschedulable"
          operator: "Exists"
          effect: "NoSchedule"
      initContainers:
        # Configure routing for CUDN gateway
        - name: setup-routing
          image: registry.access.redhat.com/ubi9/ubi:latest
          command:
            - /bin/bash
            - -c
            - |
              #!/bin/bash
              set -e
              echo "Configuring VPN gateway routing for CUDN..."
              
              # Enable IP forwarding
              sysctl -w net.ipv4.ip_forward=1
              sysctl -w net.ipv4.conf.all.rp_filter=0
              sysctl -w net.ipv4.conf.default.rp_filter=0
              
              # Wait for interfaces to be ready
              sleep 5
              
              # Configure static IP on net1 (CUDN interface)
              # The Multus annotation requests 10.227.128.1, but we verify/set it
              ip addr show net1 || echo "net1 interface not ready yet"
              
              # Add NAT rules for CUDN traffic
              iptables -t nat -A POSTROUTING -s 10.227.128.0/21 ! -d 10.227.128.0/21 -j MASQUERADE
              
              # Allow forwarding between CUDN and pod network
              iptables -A FORWARD -i net1 -o eth0 -j ACCEPT
              iptables -A FORWARD -i eth0 -o net1 -m state --state RELATED,ESTABLISHED -j ACCEPT
              iptables -A FORWARD -i net1 -o net1 -j ACCEPT
              
              echo "✓ Routing configured"
              ip addr show
              ip route show
          securityContext:
            privileged: true
            capabilities:
              add:
                - NET_ADMIN
                - SYS_ADMIN
      containers:
        - name: strongswan
          image: registry.access.redhat.com/ubi9/ubi:latest
          command: ["/bin/bash", "/etc/ipsec-config/start-vpn.sh"]
          securityContext:
            privileged: true
            capabilities:
              add:
                - NET_ADMIN
                - SYS_ADMIN
                - NET_RAW
          resources:
            requests:
              cpu: 200m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 1Gi
          volumeMounts:
            - name: ipsec-config
              mountPath: /etc/ipsec-config
              readOnly: true
            - name: vpn-certs
              mountPath: /etc/vpn-certs
              readOnly: true
            - name: run
              mountPath: /run
            - name: var-run
              mountPath: /var/run
          livenessProbe:
            exec:
              command:
                - /bin/sh
                - -c
                - "ps aux | grep -q '[c]haron' && ip addr show net1"
            initialDelaySeconds: 180
            periodSeconds: 60
            failureThreshold: 5
          readinessProbe:
            exec:
              command:
                - /bin/sh
                - -c
                - "ps aux | grep -q '[c]haron' && ip addr show net1"
            initialDelaySeconds: 120
            periodSeconds: 30
      volumes:
        - name: ipsec-config
          configMap:
            name: ipsec-config
            defaultMode: 0755
        - name: vpn-certs
          secret:
            secretName: vpn-certificates
            defaultMode: 0600
        - name: run
          emptyDir: {}
        - name: var-run
          emptyDir: {}
```

### Step 3: Update strongSwan Configuration

No changes needed to ipsec.conf - `leftsubnet=0.0.0.0/0` will advertise all traffic including the CUDN.

---

## Alternative: Use Static IP Annotation

If the Multus `ips` annotation doesn't work, we can configure the IP in the init container:

```yaml
annotations:
  k8s.v1.cni.cncf.io/networks: windows-non-prod

initContainers:
  - name: setup-routing
    command:
      - /bin/bash
      - -c
      - |
        # Remove any auto-assigned IP
        ip addr flush dev net1
        
        # Add our desired gateway IP
        ip addr add 10.227.128.1/21 dev net1
        ip link set net1 up
        
        # Continue with forwarding setup...
```

---

## Deployment Procedure

### 1. Update CUDN to include site-to-site-vpn namespace

```bash
oc patch clusteruserdefinednetwork windows-non-prod --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/namespaceSelector/matchExpressions/0/values/-",
    "value": "site-to-site-vpn"
  }
]'

# Verify NAD created
oc get network-attachment-definitions -n site-to-site-vpn | grep windows-non-prod
```

### 2. Backup current VPN deployment

```bash
oc get deployment site-to-site-vpn -n site-to-site-vpn -o yaml > vpn-deployment-backup.yaml
```

### 3. Apply updated deployment

```bash
oc apply -f vpn-deployment-with-cudn.yaml
```

### 4. Monitor VPN pod restart

```bash
# Watch pod restart
oc get pods -n site-to-site-vpn -w

# Check new pod has 2 interfaces
POD=$(oc get pods -n site-to-site-vpn -l app=site-to-site-vpn -o jsonpath='{.items[0].metadata.name}')
oc exec -n site-to-site-vpn $POD -- ip addr show
```

### 5. Verify VPN connectivity

```bash
# Check VPN tunnel is up
oc logs -n site-to-site-vpn $POD | grep -E "ESTABLISHED|IKE_SA"

# Check CUDN interface
oc exec -n site-to-site-vpn $POD -- ip addr show net1
# Should show: 10.227.128.1/21

# Check routing
oc exec -n site-to-site-vpn $POD -- ip route show
```

### 6. Configure Windows VMs

```powershell
# From each Windows VM console
$adapter = (Get-NetAdapter | Where-Object { $_.Status -eq 'Up' })[1]

Remove-NetIPAddress -InterfaceAlias $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
Remove-NetRoute -InterfaceAlias $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue

# Use VPN pod as gateway
New-NetIPAddress -InterfaceAlias $adapter.Name `
                 -IPAddress "10.227.128.11" `
                 -PrefixLength 21 `
                 -DefaultGateway "10.227.128.1"

# Test
ping 10.227.128.1  # VPN pod
ping 8.8.8.8       # Internet via VPN
```

---

## Important Considerations

### 1. hostNetwork Incompatibility

**Problem**: `hostNetwork: true` and Multus secondary networks are mutually exclusive.

**Solution**: Remove `hostNetwork: true` and rely on pod network for VPN connectivity.

**Impact**:
- ✅ VPN can still reach AWS VPN endpoints (3.232.27.186, 98.94.136.2)
- ✅ VPN can still route pod network traffic (10.132.0.0/14)
- ✅ VPN now also has direct CUDN connectivity (10.227.128.0/21)

### 2. Source IP for VPN Tunnel

Without `hostNetwork: true`, the VPN tunnel will use the pod's IP as source. This should work fine, but verify with:

```bash
# Check VPN tunnel source IP
oc exec -n site-to-site-vpn $POD -- ip route get 3.232.27.186
```

If there are issues, we can configure SNAT on worker nodes.

### 3. Delete Gateway VM

Once VPN pod is working with CUDN, delete the separate gateway VM:

```bash
oc delete vm vpn-gateway -n windows-non-prod
```

---

## Troubleshooting

### Issue: NAD not created in site-to-site-vpn namespace

**Check**:
```bash
oc get clusteruserdefinednetwork windows-non-prod -o yaml | grep -A 10 namespaceSelector
```

**Fix**:
```bash
oc edit clusteruserdefinednetwork windows-non-prod
# Add site-to-site-vpn to values list
```

### Issue: VPN pod has no net1 interface

**Check**:
```bash
oc get pod $POD -n site-to-site-vpn -o yaml | grep -A 5 k8s.v1.cni.cncf.io/networks
```

**Fix**:
Ensure Multus annotation is correct in deployment spec.

### Issue: VPN tunnel doesn't establish

**Check logs**:
```bash
oc logs -n site-to-site-vpn $POD | grep -i error
```

**Common causes**:
- Certificate issues (same as before)
- Routing issues (check `ip route`)
- Firewall blocking UDP 500/4500

### Issue: Windows VMs can't reach VPN pod (10.227.128.1)

**Check**:
```bash
# From VPN pod
oc exec -n site-to-site-vpn $POD -- ip addr show net1
oc exec -n site-to-site-vpn $POD -- ping 10.227.128.11  # Windows VM

# From Windows VM
ping 10.227.128.1
arp -a | findstr 10.227.128.1
```

**Fix**:
Verify both are on same CUDN (windows-non-prod).

---

## Summary

**This approach:**
- ✅ Eliminates need for gateway VM
- ✅ VPN pod becomes the gateway (10.227.128.1)
- ✅ Direct routing between VPN and CUDN
- ✅ Simpler architecture
- ✅ Uses standard OVN Layer 2 features

**Trade-offs:**
- ⚠️ Cannot use `hostNetwork: true` (incompatible with Multus)
- ⚠️ VPN pod uses pod IP as source (not worker node IP)
- ⚠️ Requires CUDN update to include site-to-site-vpn namespace

**Next Steps:**
1. Update CUDN namespace selector
2. Update VPN deployment with Multus annotation
3. Restart VPN pod
4. Configure Windows VMs to use 10.227.128.1 as gateway
5. Test end-to-end connectivity

---

**Document Created**: 2026-02-12  
**Approach**: Attach VPN directly to OVN Layer 2  
**Status**: Ready for implementation
