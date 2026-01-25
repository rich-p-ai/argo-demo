# ROSA Cluster Components Reference

**Cluster Name:** rosa  
**Cluster ID:** 2j8f2n27o4uou1912nm630a54rrjsn98  
**External ID:** 7522f05d-dfb6-4e66-96a2-3e59d9b84d0f  
**Inspected:** 2026-01-23

---

## 1. Cluster Configuration

| Component | Value |
|-----------|-------|
| **Type** | ROSA HCP (Hosted Control Plane) |
| **OpenShift Version** | 4.20.8 |
| **Channel Group** | stable |
| **Region** | us-east-1 |
| **Control Plane Availability** | MultiAZ |
| **Data Plane Availability** | MultiAZ |
| **Private Cluster** | Yes (PrivateLink) |
| **State** | ready |

### Cluster URLs

| Endpoint | URL |
|----------|-----|
| **API URL** | https://api.rosa.m34m.p3.openshiftapps.com:443 |
| **Console URL** | https://console-openshift-console.apps.rosa.rosa.m34m.p3.openshiftapps.com |
| **DNS** | rosa.m34m.p3.openshiftapps.com |
| **Details Page** | https://console.redhat.com/openshift/details/s/2y9Crmt3ZXStB96twzQMHOwVsm2 |

---

## 2. AWS Account Configuration

| Setting | Value |
|---------|-------|
| **AWS Account** | 656113190503 |
| **AWS Billing Account** | 207621282346 |

---

## 3. Network Configuration

| Setting | Value |
|---------|-------|
| **Network Type** | OVNKubernetes |
| **Machine CIDR** | 10.222.152.0/22 |
| **Service CIDR** | 10.222.159.0/24 |
| **Pod CIDR** | 10.222.160.0/20 |
| **Host Prefix** | /25 |

### Subnets (3 AZs - Private)

| Subnet ID | Availability Zone |
|-----------|-------------------|
| subnet-0609b813c0c9ea063 | us-east-1a |
| subnet-0e452618acb9f2150 | us-east-1c |
| subnet-0f8a8c62041bd1c24 | us-east-1d |

---

## 4. Compute Configuration (Machine Pools)

| Pool ID | Replicas | Instance Type | AZ | Subnet | Disk Size | Version | Autorepair |
|---------|----------|---------------|-----|--------|-----------|---------|------------|
| workers-0 | 2 | r6i.metal | us-east-1a | subnet-0609b813c0c9ea063 | 300 GiB | 4.19.16 | Yes |
| workers-1 | 1 | r6i.metal | us-east-1c | subnet-0e452618acb9f2150 | 300 GiB | 4.19.16 | Yes |
| workers-2 | 1 | r6i.metal | us-east-1d | subnet-0f8a8c62041bd1c24 | 300 GiB | 4.19.16 | Yes |

**Total Workers:** 4 nodes (desired: 3, current: 4)

### Instance Details (r6i.metal)

| Specification | Value |
|---------------|-------|
| vCPUs | 128 |
| Memory | 1024 GiB |
| Storage | EBS-only |
| Network | 50 Gbps |

---

## 5. IAM Components

### 5.1 Account Roles (HCP)

These roles are shared across all ROSA HCP clusters in the account.

| Role Name | Role Type | ARN | AWS Managed |
|-----------|-----------|-----|-------------|
| ManagedOpenShift-HCP-ROSA-Installer-Role | Installer | arn:aws:iam::656113190503:role/ManagedOpenShift-HCP-ROSA-Installer-Role | Yes |
| ManagedOpenShift-HCP-ROSA-Support-Role | Support | arn:aws:iam::656113190503:role/ManagedOpenShift-HCP-ROSA-Support-Role | Yes |
| ManagedOpenShift-HCP-ROSA-Worker-Role | Worker | arn:aws:iam::656113190503:role/ManagedOpenShift-HCP-ROSA-Worker-Role | Yes |

### 5.2 Operator Roles (Cluster-Specific)

These roles are specific to this cluster (prefix: `rosa-zvtx`).

| Role Name | Purpose |
|-----------|---------|
| rosa-zvtx-kube-system-kms-provider | KMS encryption provider |
| rosa-zvtx-openshift-image-registry-installer-cloud-credentials | Image registry S3 access |
| rosa-zvtx-openshift-ingress-operator-cloud-credentials | Ingress/Route53 management |
| rosa-zvtx-openshift-cluster-csi-drivers-ebs-cloud-credentials | EBS CSI driver |
| rosa-zvtx-openshift-cloud-network-config-controller-cloud-creden | Cloud network configuration |
| rosa-zvtx-kube-system-kube-controller-manager | Kube controller manager |
| rosa-zvtx-kube-system-capa-controller-manager | Cluster API AWS provider |
| rosa-zvtx-kube-system-control-plane-operator | Control plane operator |

### 5.3 OIDC Provider

| Component | Value |
|-----------|-------|
| **OIDC Endpoint URL** | https://oidc.op1.openshiftapps.com/2j8efj68qregg90ldmjcj7nbv0p9t3pf |
| **OIDC Provider ARN** | arn:aws:iam::656113190503:oidc-provider/oidc.op1.openshiftapps.com/2j8efj68qregg90ldmjcj7nbv0p9t3pf |
| **Type** | Managed |

---

## 6. Security Configuration

| Setting | Value |
|---------|-------|
| **EC2 Metadata Http Tokens** | required (IMDSv2) |
| **FIPS Mode** | Disabled |
| **Etcd Encryption** | Disabled |
| **Delete Protection** | Disabled |
| **External Authentication** | Disabled |

---

## 7. Monitoring & Logging

| Setting | Value |
|---------|-------|
| **User Workload Monitoring** | Enabled |
| **Audit Log Forwarding** | Disabled |

---

## 8. Component Summary for New Cluster

To create a similar cluster, you need the following components:

### Pre-requisites (One-time per Account)

1. **Account Roles** - Already exist in account 656113190503
   - ManagedOpenShift-HCP-ROSA-Installer-Role
   - ManagedOpenShift-HCP-ROSA-Support-Role
   - ManagedOpenShift-HCP-ROSA-Worker-Role

### Per-Cluster Components (Created During Cluster Build)

1. **OIDC Provider** - Auto-created by ROSA (managed)
2. **Operator Roles** - Auto-created with cluster-specific prefix
3. **Machine Pools** - Configured during/after cluster creation

### Required AWS Resources

1. **VPC** with:
   - Private subnets (1 per AZ for PrivateLink cluster)
   - Route tables configured for Transit Gateway or NAT
   - VPC endpoints (optional, for improved security)

2. **IAM Permissions** for:
   - ROSA service to create/manage resources
   - Operator roles to access AWS services (S3, EBS, Route53, etc.)

### Cluster Build Command Example

```bash
rosa create cluster \
  --cluster-name=<name> \
  --sts \
  --hosted-cp \
  --region=us-east-1 \
  --subnet-ids=<subnet-ids> \
  --machine-cidr=<cidr> \
  --service-cidr=<cidr> \
  --pod-cidr=<cidr> \
  --host-prefix=<prefix> \
  --replicas=<count> \
  --compute-machine-type=<instance-type> \
  --private
```

---

## 9. Cost Considerations

| Component | Estimated Monthly Cost |
|-----------|------------------------|
| ROSA HCP Management Fee | ~$123/month |
| 4x r6i.metal instances | ~$19,200/month (on-demand) |
| EBS Storage (300 GiB x 4) | ~$120/month |
| Data Transfer | Variable |

**Note:** r6i.metal instances are bare-metal instances typically used for specialized workloads requiring dedicated hardware (e.g., ODF storage nodes, high-performance computing).

---

*Generated: 2026-01-23*
