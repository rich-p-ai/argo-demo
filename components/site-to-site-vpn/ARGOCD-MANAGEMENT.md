# Site-to-Site VPN - ArgoCD Management Guide

## Overview

The site-to-site VPN solution consists of multiple components managed differently:

### Components

| Component | Namespace | Managed By | Source File |
|-----------|-----------|------------|-------------|
| VPN Pod (strongSwan) | site-to-site-vpn | ✅ ArgoCD | kustomization.yaml |
| Gateway VM | windows-non-prod | ⚠️ Manual | kustomization-gateway-vm.yaml |
| CUDN (windows-non-prod) | cluster-wide | ⚠️ Manual | cudn-windows-non-prod.yaml |
| NetworkAttachmentDefinition | site-to-site-vpn | ⚠️ Manual | nad-site-to-site-vpn.yaml |

---

## Current ArgoCD Configuration

### ✅ Managed by ArgoCD

The VPN pod deployment is currently managed by ArgoCD:
- **Application**: site-to-site-vpn
- **Source**: Cluster-Config/components/site-to-site-vpn
- **Kustomization**: kustomization.yaml
- **Tracking ID**: `site-to-site-vpn:apps/Deployment:site-to-site-vpn/site-to-site-vpn`

**Resources Managed**:
- Namespace (site-to-site-vpn)
- ServiceAccount and RBAC
- ConfigMap (ipsec-config) ← **UPDATED with gateway route**
- Deployment (site-to-site-vpn)
- ExternalSecret (VPN certificates)

### ⚠️ NOT Managed by ArgoCD (Manual)

The following resources are deployed manually:
- Gateway VM (vpn-gateway)
- CUDN updates
- NetworkAttachmentDefinitions

---

## Updated Configuration

### ConfigMap Changes (Managed by ArgoCD)

**File**: `Cluster-Config/components/site-to-site-vpn/configmap.yaml`

**Changes Made**:
```bash
# Added route to windows-non-prod CUDN via gateway VM
ip route add 10.227.128.0/21 via 10.135.0.23 dev eth0
```

**ArgoCD Sync**: ArgoCD will automatically detect and apply this change.

### Gateway VM (NOT Managed by ArgoCD)

**File**: `Cluster-Config/components/site-to-site-vpn/vpn-gateway-vm.yaml`

**Deployment**:
```bash
# Option 1: Deploy via kustomize
oc apply -k Cluster-Config/components/site-to-site-vpn/kustomization-gateway-vm.yaml

# Option 2: Deploy directly
oc apply -f Cluster-Config/components/site-to-site-vpn/vpn-gateway-vm.yaml
```

**Status**: ✅ Already deployed manually (VM running)

---

## Making Gateway VM Managed by ArgoCD (Optional)

If you want ArgoCD to manage the Gateway VM:

### Option A: Create Separate ArgoCD Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vpn-gateway-vm
  namespace: argocd
spec:
  project: default
  source:
    repoURL: <your-git-repo>
    targetRevision: main
    path: Cluster-Config/components/site-to-site-vpn
    kustomize:
      namePrefix: ""
      commonLabels: {}
      kustomization: kustomization-gateway-vm.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: windows-non-prod
  syncPolicy:
    automated:
      prune: false  # Don't auto-prune VMs
      selfHeal: true
    syncOptions:
      - CreateNamespace=false
```

### Option B: Include in Existing Application

Add to existing site-to-site-vpn ArgoCD application:
```yaml
# Update kustomization.yaml
resources:
  - namespace.yaml
  - rbac.yaml
  - configmap.yaml
  - deployment.yaml
  - externalsecret-vpn-certs.yaml
  - vpn-gateway-vm.yaml  # Add this
```

**⚠️ Warning**: Managing VMs with ArgoCD requires careful consideration:
- VM state (running/stopped) management
- DataVolume lifecycle
- Backup/restore procedures

---

## Deployment Workflow

### For VPN Pod Changes (ConfigMap, Deployment)

1. **Update source files** in `Cluster-Config/components/site-to-site-vpn/`
2. **Commit and push** to Git
3. **ArgoCD auto-syncs** (or manual sync)
4. **VPN pod restarts** with new configuration

### For Gateway VM

1. **Update** `vpn-gateway-vm.yaml`
2. **Manual apply**:
   ```bash
   oc apply -f Cluster-Config/components/site-to-site-vpn/vpn-gateway-vm.yaml
   ```
3. **Restart VM** if needed:
   ```bash
   virtctl restart vpn-gateway -n windows-non-prod
   ```

### For CUDN Changes

1. **Update** `cudn-windows-non-prod.yaml`
2. **Manual apply**:
   ```bash
   oc apply -f Cluster-Config/components/site-to-site-vpn/cudn-windows-non-prod.yaml
   ```
3. **Verify NADs** created in all namespaces

---

## Sync Status Check

### Check if Resources are Managed by ArgoCD

```bash
# Check VPN deployment
oc get deployment site-to-site-vpn -n site-to-site-vpn -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/tracking-id}'

# Check ConfigMap
oc get configmap ipsec-config -n site-to-site-vpn -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/tracking-id}'

# Check Gateway VM
oc get vm vpn-gateway -n windows-non-prod -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/tracking-id}'

# Check CUDN
oc get clusteruserdefinednetwork windows-non-prod -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/tracking-id}'
```

### Force ArgoCD Sync

```bash
# If ArgoCD is slow to detect changes
argocd app sync site-to-site-vpn

# Or via UI
# ArgoCD UI → Applications → site-to-site-vpn → SYNC
```

---

## Configuration Drift Prevention

### ArgoCD Behavior

- **Auto-sync enabled**: ArgoCD will revert manual changes
- **Self-heal enabled**: ArgoCD continuously reconciles to Git state
- **Prune enabled**: ArgoCD will delete resources not in Git

### Making Manual Changes Permanent

If you make manual changes (e.g., `oc patch`, `oc edit`):

1. **Capture the change**:
   ```bash
   oc get <resource> -o yaml > updated-resource.yaml
   ```

2. **Update Git repo**:
   ```bash
   cp updated-resource.yaml Cluster-Config/components/site-to-site-vpn/
   git add .
   git commit -m "Update VPN configuration"
   git push
   ```

3. **Wait for ArgoCD sync** or force sync

---

## Testing After Changes

### After VPN ConfigMap Update

```bash
# Wait for ArgoCD sync
argocd app wait site-to-site-vpn --sync

# Check VPN pod restarted
oc get pods -n site-to-site-vpn -w

# Verify route added
POD=$(oc get pods -n site-to-site-vpn -l app=site-to-site-vpn -o jsonpath='{.items[0].metadata.name}')
oc exec -n site-to-site-vpn $POD -- ip route show | grep 10.227.128

# Check VPN tunnel
oc logs -n site-to-site-vpn $POD | grep ESTABLISHED
```

### After Gateway VM Changes

```bash
# Check VM status
oc get vm,vmi -n windows-non-prod | grep vpn-gateway

# Verify network interfaces
oc get vmi vpn-gateway -n windows-non-prod -o jsonpath='{.status.interfaces}'

# Test connectivity
virtctl console vpn-gateway -n windows-non-prod
# Inside VM:
ip addr show
ping 8.8.8.8
```

---

## Rollback Procedure

### Rollback VPN Configuration (ArgoCD Managed)

```bash
# Option 1: Rollback via Git
git revert <commit-hash>
git push
# ArgoCD will auto-sync to previous state

# Option 2: Rollback via ArgoCD
argocd app rollback site-to-site-vpn <revision-number>

# Option 3: Manual rollback
oc apply -f Cluster-Config/components/site-to-site-vpn/deployment-backup-*.yaml
```

### Rollback Gateway VM

```bash
# Delete current VM
oc delete vm vpn-gateway -n windows-non-prod

# Redeploy from backup or previous version
oc apply -f <backup-file>.yaml
```

---

## Summary

### Current State

✅ **VPN ConfigMap Updated** - Added static route to gateway VM  
✅ **Changes in Git** - Source files updated in Cluster-Config  
✅ **Gateway VM Deployed** - Running but not ArgoCD-managed  
⏳ **ArgoCD Sync Pending** - Will auto-sync ConfigMap changes  

### Next Steps

1. **Monitor ArgoCD sync** of VPN configmap
2. **Verify VPN pod restart** and route addition
3. **Complete gateway VM configuration** (NAT/routing)
4. **Test end-to-end connectivity**

### Files Updated

- `Cluster-Config/components/site-to-site-vpn/configmap.yaml` ✅
- `Cluster-Config/components/site-to-site-vpn/kustomization-gateway-vm.yaml` ✅ (new)
- `Cluster-Config/components/site-to-site-vpn/ARGOCD-MANAGEMENT.md` ✅ (this file)

---

**Document Created**: 2026-02-12  
**ArgoCD Status**: ConfigMap changes will auto-sync  
**Manual Resources**: Gateway VM, CUDN (not ArgoCD managed)
