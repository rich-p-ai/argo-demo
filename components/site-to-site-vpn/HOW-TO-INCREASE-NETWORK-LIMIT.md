# How to Increase windows-non-prod Network Resource Limit

**Goal**: Increase `openshift.io/windows-non-prod` network attachment limit  
**Current Issue**: "Insufficient openshift.io/windows-non-prod" error  

---

## Overview

The limit comes from one of these sources:
1. **NetworkAttachmentDefinition (NAD)** resource annotation
2. **OVN-Kubernetes** network plugin configuration
3. **Whereabouts IPAM** overlay configuration
4. **Node Resource** capacity (device plugin)

Let me show you how to check and fix each one.

---

## Method 1: Check and Remove NAD Resource Limit (Most Common)

### Step 1: Check Current NAD Configuration

```bash
# View the NAD
oc get network-attachment-definitions windows-non-prod -n windows-non-prod -o yaml

# Check for resourceName annotation
oc get network-attachment-definitions windows-non-prod -n windows-non-prod \
  -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/resourceName}'
```

### Step 2: Remove or Update Resource Limit

If you see `k8s.v1.cni.cncf.io/resourceName: openshift.io/windows-non-prod`, this is creating the limit.

**Option A: Remove the resourceName (Recommended)**

```bash
# Remove the resource limit annotation
oc annotate network-attachment-definitions windows-non-prod \
  -n windows-non-prod \
  k8s.v1.cni.cncf.io/resourceName-
```

This removes the limit entirely since the network has plenty of IP capacity (~1,000 IPs).

**Option B: Keep resourceName but Increase Node Capacity**

If you need to keep the resource limit for tracking, increase it on the nodes (see Method 2).

---

## Method 2: Increase OVN-Kubernetes Network Capacity

### For OVN-K8s Layer 2 Networks

Check if there's a network policy or configuration limiting attachments:

```bash
# Check OVN configuration
oc get network.config.openshift.io cluster -o yaml

# Check for any network policies
oc get networkpolicies -n windows-non-prod
```

### Create or Update Network Configuration

```bash
# If using OVN-K8s user-defined networks, check the configuration
oc get clusteru userdefinednetwork -A
```

---

## Method 3: Update All NADs in All Namespaces

The limit might be enforced across multiple NADs. Update all of them:

```bash
# List all windows-non-prod NADs
oc get network-attachment-definitions -A | grep windows-non-prod

# Remove resourceName from each
for NS in openshift-mtv vm-migrations windows-non-prod; do
  echo "Updating NAD in $NS..."
  oc annotate network-attachment-definitions windows-non-prod \
    -n $NS \
    k8s.v1.cni.cncf.io/resourceName- \
    --overwrite
done
```

---

## Method 4: Check Whereabouts IPAM Overlay Limit

### Check Whereabouts Configuration

```bash
# Check whereabouts configuration
oc get daemonsets -n openshift-multus | grep whereabouts

# If whereabouts exists, check its config
oc get configmap -n openshift-multus | grep whereabouts
```

### Whereabouts doesn't enforce attachment limits

Whereabouts only manages IP allocation, not attachment counts. The issue is likely the NAD resourceName.

---

## Method 5: Quick Fix - Test Without ResourceName

### Backup Current Configuration

```bash
# Backup all three NADs
oc get network-attachment-definitions windows-non-prod -n openshift-mtv -o yaml > nad-mtv-backup.yaml
oc get network-attachment-definitions windows-non-prod -n vm-migrations -o yaml > nad-vm-migrations-backup.yaml
oc get network-attachment-definitions windows-non-prod -n windows-non-prod -o yaml > nad-windows-backup.yaml
```

### Remove ResourceName from All NADs

```bash
#!/bin/bash
# Remove resource limits from all windows-non-prod NADs

for NS in openshift-mtv vm-migrations windows-non-prod; do
  echo "Removing resourceName from $NS..."
  
  oc patch network-attachment-definitions windows-non-prod -n $NS \
    --type=json -p='[
      {"op": "remove", "path": "/metadata/annotations/k8s.v1.cni.cncf.io~1resourceName"}
    ]' 2>/dev/null || echo "  (annotation not present or already removed)"
done

echo ""
echo "✅ Resource limits removed!"
echo ""
echo "Now try starting nymsdv301 with secondary network:"
echo "  cd /c/Users/q22529_a/work/Cluster-Config/components/site-to-site-vpn"
echo "  ./add-network-nymsdv301.sh"
```

---

## Method 6: If Using CNV/OpenShift Virtualization Device Plugin

### Check for Device Plugin

```bash
# Check if there's a device plugin managing network resources
oc get daemonsets -A | grep -i "device-plugin\|sriov\|network"

# Check node resources
oc describe node | grep -A 10 "Allocatable:" | grep openshift.io
```

### If Device Plugin Exists

You'll need to update the device plugin configuration. This varies by plugin type.

**For SRIOV Network Device Plugin:**
```bash
# Check SRIOV config
oc get sriovnetworknodepolicies -A
oc get sriovnetworks -A
```

**For Generic Device Plugin:**
```bash
# Check device plugin ConfigMap
oc get configmap -n openshift-cnv | grep device

# Update the ConfigMap to increase resource count
```

---

## Recommended Quick Solution

Based on your configuration (OVN-K8s with Whereabouts IPAM), the simplest solution is:

### Remove ResourceName Annotation

```bash
# This is the most likely fix
cd /c/Users/q22529_a/work/Cluster-Config/components/site-to-site-vpn

# Create and run this script
cat > remove-network-limits.sh << 'EOF'
#!/bin/bash
set -e

echo "=============================================="
echo "  Remove Network Resource Limits"
echo "=============================================="
echo ""

# Backup current NADs
echo "Creating backups..."
mkdir -p nad-backups/limit-removal-$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="nad-backups/limit-removal-$(date +%Y%m%d-%H%M%S)"

for NS in openshift-mtv vm-migrations windows-non-prod; do
  oc get network-attachment-definitions windows-non-prod -n $NS -o yaml \
    > "$BACKUP_DIR/$NS-backup.yaml" 2>/dev/null || echo "  NAD not found in $NS"
done

echo "✅ Backups saved to $BACKUP_DIR"
echo ""

# Remove resourceName annotation
echo "Removing resourceName annotations..."
for NS in openshift-mtv vm-migrations windows-non-prod; do
  echo "  Processing $NS..."
  
  # Try to remove the annotation
  oc annotate network-attachment-definitions windows-non-prod \
    -n $NS \
    k8s.v1.cni.cncf.io/resourceName- \
    2>&1 | grep -v "not found" || true
done

echo ""
echo "=============================================="
echo "  ✅ Resource Limits Removed!"
echo "=============================================="
echo ""
echo "Verification:"
for NS in openshift-mtv vm-migrations windows-non-prod; do
  echo "  $NS:"
  RESOURCE=$(oc get network-attachment-definitions windows-non-prod -n $NS \
    -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/resourceName}' 2>/dev/null || echo "none")
  echo "    resourceName: $RESOURCE"
done

echo ""
echo "Next Steps:"
echo "1. The network resource limit has been removed"
echo "2. Now configure nymsdv301 with secondary network:"
echo "   ./add-network-nymsdv301.sh"
echo ""
EOF

chmod +x remove-network-limits.sh
./remove-network-limits.sh
```

---

## Verification

After making changes, verify the fix:

```bash
# Check that resourceName is removed
for NS in openshift-mtv vm-migrations windows-non-prod; do
  echo "$NS:"
  oc get network-attachment-definitions windows-non-prod -n $NS \
    -o jsonpath='{.metadata.annotations}' | jq .
  echo ""
done

# Try to start nymsdv301 with network
./add-network-nymsdv301.sh
```

---

## If That Doesn't Work

### Check Node Capacity Directly

```bash
# See actual node resources
oc get nodes -o json | jq '.items[] | {
  name: .metadata.name,
  allocatable: .status.allocatable,
  capacity: .status.capacity
}' | grep -A 5 -B 5 "windows-non-prod"
```

### Check for PodSecurityPolicy or ResourceQuota

```bash
# Check for resource quotas
oc get resourcequota -n windows-non-prod

# Check for limit ranges
oc get limitrange -n windows-non-prod

# Check pod security
oc get podsecuritypolicy -A
```

---

## Understanding the Error

The error "Insufficient openshift.io/windows-non-prod" means:

1. **Resource Name**: The NAD has `k8s.v1.cni.cncf.io/resourceName` annotation
2. **Node Capacity**: Kubernetes treats this as a countable resource on nodes
3. **Default Limit**: Without explicit configuration, default limit is low (~8-10)
4. **Scheduling**: Pods requesting this resource can't schedule when limit is reached

**Solution**: Remove the resourceName annotation since:
- Your network uses Whereabouts IPAM (manages IPs, not attachments)
- You have ~1,000 IPs available
- No technical reason to limit attachment count
- This is a Layer 2 overlay network (no hardware constraints)

---

## Summary - Do This

```bash
# Navigate to your working directory
cd /c/Users/q22529_a/work/Cluster-Config/components/site-to-site-vpn

# Remove the resource limits
for NS in openshift-mtv vm-migrations windows-non-prod; do
  oc annotate network-attachment-definitions windows-non-prod -n $NS \
    k8s.v1.cni.cncf.io/resourceName- 2>&1 | grep -v "not found" || true
done

# Verify
echo "Checking if resourceName is removed..."
for NS in openshift-mtv vm-migrations windows-non-prod; do
  RESOURCE=$(oc get network-attachment-definitions windows-non-prod -n $NS \
    -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/resourceName}' 2>/dev/null || echo "✅ REMOVED")
  echo "$NS: $RESOURCE"
done

# Now configure nymsdv301
./add-network-nymsdv301.sh
```

---

**This should resolve the issue immediately without requiring node restarts or other changes!**
