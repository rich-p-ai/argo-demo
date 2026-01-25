# RBAC Manifests for ROSA Clusters

This directory contains Kubernetes RBAC (Role-Based Access Control) manifests for managing cluster access.

## Files

| File | Purpose |
|------|---------|
| `cluster-admins.yaml` | Full cluster-admin access for platform team |
| `dedicated-admins.yaml` | Limited admin access (cannot modify operators) |

## Roles Overview

### cluster-admin
Full administrative access to the cluster. Can:
- Manage all resources in all namespaces
- Modify cluster operators and settings
- Access all system namespaces
- Create/delete namespaces
- Manage RBAC

### dedicated-admin (ROSA-specific)
Limited administrative access. Can:
- Manage projects and namespaces
- View cluster-level resources
- Manage most workloads

Cannot:
- Modify cluster operators
- Access system namespaces (openshift-*, kube-*)
- Modify cluster-wide settings

## Usage

### Manual Application

```bash
# Apply cluster admin RBAC
oc apply -f cluster-admins.yaml

# Apply dedicated admin RBAC
oc apply -f dedicated-admins.yaml

# Verify
oc get clusterrolebindings -l app.kubernetes.io/component=rbac
```

### Via Script

```bash
# Use the management script
../scripts/manage-cluster-admins.sh <cluster-name> apply
```

### Via ArgoCD/GitOps

Add this directory as an ArgoCD Application:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cluster-rbac
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/argo-demo.git
    targetRevision: HEAD
    path: rosa-clusters/manifests/rbac
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: false
      selfHeal: true
```

## Adding New Admins

### Option 1: ROSA CLI (Recommended for ROSA)

```bash
# Add cluster-admin
rosa grant user cluster-admin --user=USERNAME --cluster=CLUSTER_NAME

# Add dedicated-admin
rosa grant user dedicated-admin --user=USERNAME --cluster=CLUSTER_NAME

# List current admins
rosa list users -c CLUSTER_NAME
```

### Option 2: Edit YAML Manifests

1. Edit `cluster-admins.yaml` or `dedicated-admins.yaml`
2. Add user under `subjects`:
   ```yaml
   - apiGroup: rbac.authorization.k8s.io
     kind: User
     name: NEW_USERNAME
   ```
3. Apply: `oc apply -f cluster-admins.yaml`

### Option 3: Use Management Script

```bash
# Add single user
./scripts/manage-cluster-admins.sh CLUSTER_NAME add USERNAME

# Sync from config file
./scripts/manage-cluster-admins.sh CLUSTER_NAME sync
```

## Configuration File

The script reads from `configs/admins/cluster-admins.env`:

```bash
CLUSTER_ADMINS=(
    "Q22529"    # Richard Sawyers
    "Q11013"    # Service Account
)

DEDICATED_ADMINS=(
    # Limited admin users
)
```

## Verification

```bash
# Check who has cluster-admin
oc get clusterrolebindings -o wide | grep cluster-admin

# Check specific user's roles
oc auth can-i --list --as=USERNAME

# Test as user
oc auth can-i create pods --as=USERNAME -n default
oc auth can-i delete clusteroperators --as=USERNAME
```
