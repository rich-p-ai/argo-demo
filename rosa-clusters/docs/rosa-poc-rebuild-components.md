# ROSA POC Cluster - Component Rebuild List

**Source Cluster:** rosa (7522f05d-dfb6-4e66-96a2-3e59d9b84d0f)  
**Inspected:** 2026-01-23  
**Purpose:** Document all components needed to rebuild this cluster via GitOps

---

## Executive Summary

The ROSA POC cluster has **10 operator subscriptions** and multiple configurations that need to be captured in the argo-demo repository. Currently, the repo has **partial coverage** - several operators and configurations are missing.

| Category | Deployed | In Repo | Gap |
|----------|----------|---------|-----|
| Operators | 10 | 4 | 6 missing |
| Storage Backends | 3 | 0 | 3 missing |
| Configurations | 5+ | 2 | 3+ missing |

---

## 1. Operators - Currently Deployed

### 1.1 Operators ALREADY in argo-demo repo

| Operator | Namespace | Channel | Status |
|----------|-----------|---------|--------|
| MTV (Forklift) | openshift-mtv | release-v2.10 | ✅ In repo |
| External Secrets Operator | external-secrets-operator | alpha | ✅ In repo |
| NetApp Trident | openshift-operators | stable | ✅ In repo |
| Node Health Check | (not deployed) | - | ✅ In repo (not used on this cluster) |

### 1.2 Operators MISSING from argo-demo repo (NEED TO ADD)

| Operator | Namespace | Channel | Priority |
|----------|-----------|---------|----------|
| **OpenShift Virtualization** | openshift-cnv | stable | **HIGH** |
| **Ansible Automation Platform** | aap | stable-2.6 | **HIGH** |
| **OADP (Velero)** | openshift-migration | stable | **HIGH** |
| **MTC (Migration Toolkit)** | openshift-migration | release-v1.8 | MEDIUM |
| **Web Terminal** | openshift-operators | fast | LOW |
| **DevWorkspace Operator** | openshift-operators | fast | LOW |
| **Deployment Validation Operator** | openshift-deployment-validation-operator | alpha | LOW |

---

## 2. Storage Configuration

### 2.1 Storage Classes Deployed

| Name | Provisioner | Default | Status |
|------|-------------|---------|--------|
| ontap-san-economy | csi.trident.netapp.io | **Yes** | ❌ Not in repo |
| trident-csi | csi.trident.netapp.io | No | ❌ Not in repo |
| gp3-csi | ebs.csi.aws.com | No | Built-in |
| gp2-csi | ebs.csi.aws.com | No | Built-in |

### 2.2 Trident Backend Configs (NEED TO ADD)

| Backend Name | Driver | Namespace |
|--------------|--------|-----------|
| fsx-ontap | ontap-nas | trident |
| fsx-ontap-linux | ontap-nas | trident |
| fsx-ontap-san-econ | ontap-san-economy | trident |

**Required Components:**
- `TridentBackendConfig` CRs for each backend
- `StorageClass` definitions
- Default storage class annotation

---

## 3. Virtualization Configuration

### 3.1 OpenShift Virtualization (NEED TO ADD)

**Operator Subscription:**
```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: kubevirt-hyperconverged
  namespace: openshift-cnv
spec:
  channel: stable
  name: kubevirt-hyperconverged
  source: redhat-operators
  sourceNamespace: openshift-marketplace
```

**HyperConverged CR Configuration:**
- Live migration enabled (evictionStrategy: LiveMigrate)
- Common boot images enabled
- Multi-arch boot image import disabled
- Infrastructure highly available: true

**Console Plugins Enabled:**
- kubevirt-plugin
- forklift-console-plugin

### 3.2 Virtual Machines

- **127 VMs** deployed across namespaces:
  - linux-dev-vms
  - linux-nonprd-vms
  - windows-demo-vms
  - windows-nonprd-vms

---

## 4. Backup & Migration Configuration

### 4.1 OADP / Velero (NEED TO ADD)

**Operator Subscription:**
```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: redhat-oadp-operator
  namespace: openshift-migration
spec:
  channel: stable
  name: redhat-oadp-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
```

**DataProtectionApplication CR:**
- Name: velero
- Namespace: openshift-migration
- (Backup storage location config needed)

### 4.2 MTC - Migration Toolkit for Containers (NEED TO ADD)

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: mtc-operator
  namespace: openshift-migration
spec:
  channel: release-v1.8
  name: mtc-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
```

---

## 5. Automation Configuration

### 5.1 Ansible Automation Platform (NEED TO ADD)

**Operator Subscription:**
```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ansible-automation-platform-operator
  namespace: aap
spec:
  channel: stable-2.6
  name: ansible-automation-platform-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
```

**AutomationController CR:**
- Name: rosa-ansible-controller
- Namespace: aap
- (Full configuration needed)

---

## 6. Secrets Management

### 6.1 External Secrets Configuration (NEED TO ADD)

**SecretStore:**
- Name: secretstore-beyondtrust
- Namespace: external-secrets-operator
- Provider: BeyondTrust (configuration needed)

**ExternalSecrets:**
- 1 ExternalSecret configured
- (May need to document the secret mappings)

---

## 7. Developer Tools (Optional)

### 7.1 Web Terminal (NEED TO ADD - Low Priority)

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: web-terminal
  namespace: openshift-operators
spec:
  channel: fast
  name: web-terminal
  source: redhat-operators
  sourceNamespace: openshift-marketplace
```

### 7.2 DevWorkspace Operator (NEED TO ADD - Low Priority)

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: devworkspace-operator
  namespace: openshift-operators
spec:
  channel: fast
  name: devworkspace-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
```

---

## 8. Cluster Management

### 8.1 ACM Agent (Managed Cluster)

The cluster is registered as a managed cluster with ACM:
- Agent namespaces: open-cluster-management-agent, open-cluster-management-agent-addon
- This is typically configured from the hub cluster, not the spoke

---

## 9. Components to Add to argo-demo Repository

### HIGH Priority - Core Infrastructure

| Component | Folder Path | Files Needed |
|-----------|-------------|--------------|
| **openshift-virtualization-operator** | `components/openshift-virtualization-operator/` | namespace.yaml, operator-group.yaml, subscription.yaml |
| **openshift-virtualization-configuration** | `components/openshift-virtualization-configuration/` | hyperconverged.yaml |
| **aap-operator** | `components/aap-operator/` | namespace.yaml, operator-group.yaml, subscription.yaml |
| **aap-configuration** | `components/aap-configuration/` | automation-controller.yaml |
| **oadp-operator** | `components/oadp-operator/` | namespace.yaml, operator-group.yaml, subscription.yaml |
| **oadp-configuration** | `components/oadp-configuration/` | data-protection-application.yaml |
| **trident-configuration** | `components/trident-configuration/` | backend-configs.yaml, storage-classes.yaml |

### MEDIUM Priority - Migration & Secrets

| Component | Folder Path | Files Needed |
|-----------|-------------|--------------|
| **mtc-operator** | `components/mtc-operator/` | subscription.yaml |
| **eso-beyondtrust** | `components/eso-beyondtrust/` | secret-store.yaml |

### LOW Priority - Developer Tools

| Component | Folder Path | Files Needed |
|-----------|-------------|--------------|
| **web-terminal-operator** | `components/web-terminal-operator/` | subscription.yaml |
| **devworkspace-operator** | `components/devworkspace-operator/` | subscription.yaml |

---

## 10. Suggested Cluster Configuration (values.yaml)

For a cluster similar to the POC (rosa), create a cluster folder with:

```yaml
# clusters/rosa-poc/values.yaml

applications:

  # OpenShift Virtualization
  openshift-virtualization-operator:
    annotations:
      argocd.argoproj.io/compare-options: IgnoreExtraneous
      argocd.argoproj.io/sync-wave: '5'
    destination:
      namespace: openshift-cnv
    source:
      path: components/openshift-virtualization-operator

  openshift-virtualization-configuration:
    annotations:
      argocd.argoproj.io/compare-options: IgnoreExtraneous
      argocd.argoproj.io/sync-wave: '10'
    destination:
      namespace: openshift-cnv
    source:
      path: clusters/rosa-poc/overlays/openshift-virtualization-configuration

  # Ansible Automation Platform
  aap-operator:
    annotations:
      argocd.argoproj.io/compare-options: IgnoreExtraneous
      argocd.argoproj.io/sync-wave: '5'
    destination:
      namespace: aap
    source:
      path: components/aap-operator

  # OADP / Velero
  oadp-operator:
    annotations:
      argocd.argoproj.io/compare-options: IgnoreExtraneous
      argocd.argoproj.io/sync-wave: '5'
    destination:
      namespace: openshift-migration
    source:
      path: components/oadp-operator

  # Trident Storage Configuration
  trident-configuration:
    annotations:
      argocd.argoproj.io/compare-options: IgnoreExtraneous
      argocd.argoproj.io/sync-wave: '10'
    destination:
      namespace: trident
    source:
      path: clusters/rosa-poc/overlays/trident-configuration

  # MTV Configuration (already in repo)
  mtv-configuration:
    annotations:
      argocd.argoproj.io/compare-options: IgnoreExtraneous
      argocd.argoproj.io/sync-wave: '10'
    destination:
      namespace: openshift-mtv
    source:
      path: clusters/rosa-poc/overlays/mtv-configuration
```

---

## 11. Implementation Checklist

### Phase 1: Core Operators
- [ ] Create `components/openshift-virtualization-operator/`
- [ ] Create `components/openshift-virtualization-configuration/`
- [ ] Create `components/aap-operator/`
- [ ] Create `components/oadp-operator/`

### Phase 2: Storage & Configuration
- [ ] Create `components/trident-configuration/` with backend configs
- [ ] Create storage class definitions
- [ ] Create `components/eso-beyondtrust/` secret store

### Phase 3: Cluster-Specific Overlays
- [ ] Create `clusters/rosa-poc/` folder structure
- [ ] Create cluster-specific overlays for virtualization
- [ ] Create cluster-specific Trident backend configs
- [ ] Create cluster-specific AAP configuration

### Phase 4: Group Configuration
- [ ] Add virtualization to `groups/non-prod/` values
- [ ] Add OADP to appropriate group

---

*Generated: 2026-01-23*
