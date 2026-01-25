# ROSA HCP Cluster Specification - Canon USA

**Document Version:** 1.0  
**Generated:** January 23, 2026  
**Purpose:** Document existing ROSA cluster configuration for nonprod cluster recreation

---

## Executive Summary

This document captures the complete configuration of the existing Canon USA ROSA HCP (Hosted Control Plane) cluster running in AWS Account `656113190503`. Use this specification as a reference when building the new nonprod cluster.

---

## Table of Contents

1. [Existing Cluster Overview](#existing-cluster-overview)
2. [AWS Account & Region Configuration](#aws-account--region-configuration)
3. [Network Architecture](#network-architecture)
4. [Compute Configuration](#compute-configuration)
5. [IAM Roles & OIDC](#iam-roles--oidc)
6. [OpenShift Configuration](#openshift-configuration)
7. [Nonprod Cluster Recommendations](#nonprod-cluster-recommendations)
8. [Nonprod Configuration File](#nonprod-configuration-file)

---

## Existing Cluster Overview

| Attribute | Value |
|-----------|-------|
| **Cluster Name** | `rosa` |
| **Cluster ID** | `2j8f2n27o4uou1912nm630a54rrjsn98` |
| **Topology** | Hosted Control Plane (HCP) |
| **State** | `ready` |
| **Created** | 2025-06-06 |
| **OpenShift Version** | 4.20.8 |
| **Available Upgrade** | 4.20.10 |
| **Console URL** | https://console-openshift-console.apps.rosa.rosa.m34m.p3.openshiftapps.com |
| **API URL** | https://api.rosa.m34m.p3.openshiftapps.com:443 |
| **API Access** | Internal (PrivateLink) |

---

## AWS Account & Region Configuration

### Account Details

| Attribute | Value |
|-----------|-------|
| **AWS Account ID** | `656113190503` |
| **Billing Account ID** | `207621282346` |
| **AWS Region** | `us-east-1` (N. Virginia) |
| **OCM Organization** | Cannon USA |
| **OCM Organization ID** | `1LEVPA7eus3PjfHr4wdF1VAOE9w` |

### AWS Tags Applied

| Tag Key | Tag Value |
|---------|-----------|
| `project` | `rosa` |
| `red-hat-clustertype` | `rosa` |
| `red-hat-managed` | `true` |

---

## Network Architecture

### VPC Configuration

| Attribute | Value |
|-----------|-------|
| **VPC ID** | `vpc-0a70417afafb28e82` |
| **VPC Name** | `ROSA-DEV` |
| **Environment Tag** | `RedhatAWS` |
| **PrivateLink** | **Enabled** |
| **Public Access** | **Disabled** (API is internal only) |
| **Internet Gateway** | None |
| **NAT Gateway** | None |
| **Connectivity** | **Site-to-Site VPN via Transit Gateway** |

### VPN / Transit Gateway Architecture

| Component | ID | Details |
|-----------|-----|---------|
| **Transit Gateway** | `tgw-07baf7176234416a5` | Central routing hub |
| **VPN Connection** | `vpn-0e42dd982c6950074` | IPsec.1, State: available |
| **Customer Gateway** | `cgw-0f82cc789449111b7` | Certificate-based auth, BGP ASN: 65000 |
| **VPC Attachment** | `tgw-attach-010ef75bc73010944` | ROSA-DEV VPC attached |
| **VPN Attachment** | `tgw-attach-036098f03467de517` | VPN attached to TGW |

**Architecture Diagram:**
```
                              ┌─────────────────────────────────────┐
                              │     Aviatrix Transit Gateway        │
                              │     tgw-041316428b4c331d0           │
                              └─────────────────────────────────────┘
                                       │              │
                    ┌──────────────────┘              └──────────────────┐
                    ▼                                                     ▼
┌─────────────────────────────┐                       ┌─────────────────────────────┐
│      ROSA-DEV VPC           │                       │    ROSA-Non-Prod VPC        │
│   vpc-0a70417afafb28e82     │                       │   vpc-0e9f579449a68a005     │
│   10.222.152.0/22           │                       │   10.227.96.0/20            │
│   (Prod Cluster)            │                       │   (Nonprod Cluster)         │
└─────────────────────────────┘                       └─────────────────────────────┘
                                       │
                              ┌────────┴────────┐
                              │  On-Premises    │
                              │  (Site-to-Site  │
                              │      VPN)       │
                              └─────────────────┘
```

**Nonprod VPC (ROSA-Non-Prod):** Already exists and is attached to Aviatrix Transit Gateway with full routing configured.

### VPC CIDR Blocks (Multiple)

The VPC uses multiple CIDR associations:

| CIDR Block | Association ID | Purpose |
|------------|----------------|---------|
| `10.222.152.0/24` | `vpc-cidr-assoc-0d0507be3bf59f41c` | Primary CIDR |
| `10.222.153.0/24` | `vpc-cidr-assoc-02f431bd90c76312d` | Secondary CIDR |
| `10.222.154.0/24` | `vpc-cidr-assoc-081043ba898e64af3` | Tertiary CIDR |

**Effective Machine CIDR (per cluster config):** `10.222.152.0/22`

### Subnets

All subnets are **private** (no public IP assignment):

| Subnet ID | Name | AZ | CIDR Block | Purpose |
|-----------|------|-----|------------|---------|
| `subnet-0609b813c0c9ea063` | Redhat-devsubnet1-10.222.152.0/24 | us-east-1a | 10.222.152.0/24 | Worker nodes |
| `subnet-0e452618acb9f2150` | 10.222.153.0/24 | us-east-1c | 10.222.153.0/24 | Worker nodes |
| `subnet-0f8a8c62041bd1c24` | 10.222.154.0/24 | us-east-1d | 10.222.154.0/24 | Worker nodes |

### Network CIDRs

| Network | CIDR | Purpose |
|---------|------|---------|
| **Machine CIDR** | `10.222.152.0/22` | VPC/Node network |
| **Pod CIDR** | `10.222.160.0/20` | Pod network |
| **Service CIDR** | `10.222.159.0/24` | Kubernetes services |
| **Host Prefix** | `/25` | Per-node pod CIDR allocation |

### VPC Endpoints

| Endpoint ID | Service | Type | State |
|-------------|---------|------|-------|
| `vpce-01472ebacc5674b33` | Private Router (PrivateLink) | Interface | available |
| `vpce-0c087f73253b2a7f2` | S3 | Gateway | available |
| `vpce-0310b48ad9f17e733` | S3 | Gateway | available |

### Security Groups

| Group ID | Group Name | Description |
|----------|------------|-------------|
| `sg-0246ff792a26eaa29` | `2j8f2n27o4uou1912nm630a54rrjsn98-default-sg` | Default worker security group |
| `sg-0ccdbda6f007e6e98` | `2j8f2n27o4uou1912nm630a54rrjsn98-vpce-private-router` | VPC endpoint security group |
| `sg-051bec750b59fcaa3` | `rosa-api-sg` | API access from outside VPC |
| `sg-0be7ea0cb6e0918cd` | `Rosa_devsg` | Custom dev security group |
| `sg-0b80e36f3141e2058` | `ROSA-FSXONTAP-FSxONTAPSecurityGroup-*` | FSx for ONTAP access |

---

## Compute Configuration

### Worker Node Configuration

| Attribute | Value |
|-----------|-------|
| **Total Workers** | 4 (current) |
| **Instance Type** | `r6i.metal` |
| **Root Volume Size** | 300 GiB |
| **Multi-AZ** | Yes (3 AZs) |
| **Autoscaling** | Cluster-level enabled |
| **Auto-repair** | Yes |

### Machine Pools

| Pool ID | Instance Type | Replicas | AZ | Subnet | Disk | Version |
|---------|---------------|----------|-----|--------|------|---------|
| `workers-0` | r6i.metal | 2/1 | us-east-1a | subnet-0609b813c0c9ea063 | 300 GiB | 4.19.16 |
| `workers-1` | r6i.metal | 1/1 | us-east-1c | subnet-0e452618acb9f2150 | 300 GiB | 4.19.16 |
| `workers-2` | r6i.metal | 1/1 | us-east-1d | subnet-0f8a8c62041bd1c24 | 300 GiB | 4.19.16 |

**Note:** The existing cluster uses `r6i.metal` instances (128 vCPU, 1024 GB RAM) which are **very large and expensive**. For nonprod, consider using smaller instances.

### Instance Type Recommendations for Nonprod

| Size | Instance Type | vCPU | RAM | Monthly Est. |
|------|---------------|------|-----|--------------|
| **Lab/Dev** | m5.xlarge | 4 | 16 GB | ~$140/node |
| **Nonprod** | m5.2xlarge | 8 | 32 GB | ~$280/node |
| **Staging** | m5.4xlarge | 16 | 64 GB | ~$560/node |
| **Current (r6i.metal)** | r6i.metal | 128 | 1024 GB | ~$3,000/node |

---

## IAM Roles & OIDC

### OIDC Configuration

| Attribute | Value |
|-----------|-------|
| **OIDC Config ID** | `2j8efj68qregg90ldmjcj7nbv0p9t3pf` |
| **Issuer URL** | https://oidc.op1.openshiftapps.com/2j8efj68qregg90ldmjcj7nbv0p9t3pf |
| **Managed** | Yes |
| **Reusable** | Yes |
| **Created** | 2025-06-06T18:39:08Z |

### Account Roles (HCP)

| Role Name | Type | ARN | AWS Managed |
|-----------|------|-----|-------------|
| `ManagedOpenShift-HCP-ROSA-Installer-Role` | Installer | `arn:aws:iam::656113190503:role/ManagedOpenShift-HCP-ROSA-Installer-Role` | Yes |
| `ManagedOpenShift-HCP-ROSA-Worker-Role` | Worker | `arn:aws:iam::656113190503:role/ManagedOpenShift-HCP-ROSA-Worker-Role` | Yes |
| `ManagedOpenShift-HCP-ROSA-Support-Role` | Support | `arn:aws:iam::656113190503:role/ManagedOpenShift-HCP-ROSA-Support-Role` | Yes |

### Operator Roles

The cluster uses operator role prefix: `rosa-zvtx`

| Namespace | Operator | Role ARN |
|-----------|----------|----------|
| `kube-system` | kms-provider | `arn:aws:iam::656113190503:role/rosa-zvtx-kube-system-kms-provider` |
| `openshift-image-registry` | installer-cloud-credentials | `arn:aws:iam::656113190503:role/rosa-zvtx-openshift-image-registry-installer-cloud-credentials` |
| `openshift-ingress-operator` | cloud-credentials | `arn:aws:iam::656113190503:role/rosa-zvtx-openshift-ingress-operator-cloud-credentials` |
| `openshift-cluster-csi-drivers` | ebs-cloud-credentials | `arn:aws:iam::656113190503:role/rosa-zvtx-openshift-cluster-csi-drivers-ebs-cloud-credentials` |
| `openshift-cloud-network-config-controller` | cloud-credentials | `arn:aws:iam::656113190503:role/rosa-zvtx-openshift-cloud-network-config-controller-cloud-creden` |
| `kube-system` | kube-controller-manager | `arn:aws:iam::656113190503:role/rosa-zvtx-kube-system-kube-controller-manager` |
| `kube-system` | capa-controller-manager | `arn:aws:iam::656113190503:role/rosa-zvtx-kube-system-capa-controller-manager` |
| `kube-system` | control-plane-operator | `arn:aws:iam::656113190503:role/rosa-zvtx-kube-system-control-plane-operator` |

---

## OpenShift Configuration

### Cluster Features

| Feature | Status |
|---------|--------|
| **STS Mode** | Enabled |
| **Managed Policies** | Yes |
| **FIPS Mode** | Disabled |
| **etcd Encryption** | Disabled |
| **User Workload Monitoring** | Enabled |
| **Delete Protection** | Disabled |
| **Multi-Architecture** | Enabled |
| **Network Type** | OVNKubernetes |
| **EC2 Metadata (IMDSv2)** | Required |
| **Billing Model** | marketplace-aws |

### Identity Providers

Currently no external identity providers configured. Uses `cluster-admin` user.

---

## Nonprod Cluster Recommendations

Based on the existing cluster configuration, here are recommendations for the nonprod cluster:

### Cost-Optimized Configuration

| Setting | Current (rosa) | Recommended (nonprod) | Rationale |
|---------|----------------|----------------------|-----------|
| **Instance Type** | r6i.metal | m5.2xlarge | Reduce cost from ~$12k/mo to ~$800/mo |
| **Workers** | 4 | 3 | Minimum for multi-AZ HA |
| **Autoscaling** | Yes | Yes (3-6) | Scale as needed |
| **Multi-AZ** | Yes | Yes | Maintain HA |
| **Private Cluster** | Yes (PrivateLink) | Yes (PrivateLink) | Maintain security, use Site-to-Site VPN |
| **Root Volume** | 300 GiB | 100 GiB | Sufficient for nonprod |

### Estimated Monthly Costs

| Configuration | Workers | Instance | Est. Monthly |
|---------------|---------|----------|--------------|
| **Current cluster** | 4 × r6i.metal | 128 vCPU/1TB RAM | ~$12,000+ |
| **Nonprod (recommended)** | 3 × m5.2xlarge | 8 vCPU/32GB RAM | ~$1,800 |
| **Nonprod (minimal)** | 3 × m5.xlarge | 4 vCPU/16GB RAM | ~$650 |

### Key Differences for Nonprod

1. **Network Access**: Both clusters use PrivateLink (API internal only) with access via existing **Site-to-Site VPN** connection.

2. **Instance Type**: The current `r6i.metal` instances are massive bare-metal servers. Use `m5.xlarge` or `m5.2xlarge` for nonprod.

3. **VPC Options**:
   - **Option A**: Create new VPC with VPN connectivity (recommended for isolation)
   - **Option B**: Use existing VPC with new subnets (if VPN routing allows)
   - **Option C**: Use different CIDR ranges to avoid conflicts with prod

4. **OpenShift Version**: Use 4.20.x (latest stable) or match prod for compatibility testing.

5. **VPN Connectivity**: Ensure the nonprod VPC CIDR ranges are added to the Site-to-Site VPN routing configuration.

---

## Nonprod Configuration File

Create this file at `configs/canon-nonprod.env`:

```bash
#------------------------------------------------------------------------------
# ROSA HCP Cluster Configuration: canon-nonprod
# Purpose: Canon USA Non-Production environment cluster
# Based on: Existing "rosa" cluster specification
#------------------------------------------------------------------------------
# Estimated Monthly Cost: ~$1,800/month (recommended) or ~$650 (minimal)
#   - ROSA HCP fee: ~$123/month
#   - 3x m5.2xlarge: ~$840/month
#   - NAT Gateways: ~$100/month
#   - Data transfer/storage: ~$50/month
#------------------------------------------------------------------------------

# Cluster identification
CLUSTER_NAME="canon-nonprod"
ENVIRONMENT="nonprod"

# AWS Configuration
AWS_REGION="us-east-1"
AWS_BILLING_ACCOUNT="207621282346"

#------------------------------------------------------------------------------
# Cluster Sizing - Choose ONE option
#------------------------------------------------------------------------------

# OPTION 1: Cost-Optimized (Similar capability, ~$650/month)
# REPLICAS=3
# INSTANCE_TYPE="m5.xlarge"        # 4 vCPU, 16GB RAM

# OPTION 2: Standard Nonprod (Recommended, ~$1,800/month)
REPLICAS=3
INSTANCE_TYPE="m5.2xlarge"         # 8 vCPU, 32GB RAM

# Multi-AZ for high availability
MULTI_AZ="true"

#------------------------------------------------------------------------------
# Autoscaling
#------------------------------------------------------------------------------
ENABLE_AUTOSCALING="true"
MIN_REPLICAS=3
MAX_REPLICAS=6

#------------------------------------------------------------------------------
# Networking - CHOOSE ONE OPTION
#------------------------------------------------------------------------------

# OPTION A: Public Cluster (Recommended for nonprod - easier access)
# Create VPC first: rosa create network rosa-quickstart-default-vpc \
#   --param Region=us-east-1 --param Name=canon-nonprod-vpc \
#   --param AvailabilityZoneCount=3 --param VpcCidr=10.1.0.0/16 --mode auto --yes
#
# Then add subnet IDs here:
# SUBNET_IDS="<public-subnet-1>,<public-subnet-2>,<public-subnet-3>,<private-subnet-1>,<private-subnet-2>,<private-subnet-3>"
MACHINE_CIDR="10.1.0.0/16"
SERVICE_CIDR="172.30.0.0/16"
POD_CIDR="10.128.0.0/14"
HOST_PREFIX=23

# OPTION B: Private Cluster with PrivateLink (Match prod)
# Requires existing private VPC with connectivity (DirectConnect/VPN)
# PRIVATE_CLUSTER="true"
# Use same network settings as prod cluster:
# MACHINE_CIDR="10.222.152.0/22"
# SERVICE_CIDR="10.222.159.0/24"
# POD_CIDR="10.222.160.0/20"
# HOST_PREFIX=25

# Access - Set to "true" for private PrivateLink cluster like prod
PRIVATE_CLUSTER="false"

#------------------------------------------------------------------------------
# OpenShift Version
#------------------------------------------------------------------------------
# Match prod version for compatibility testing, or use latest stable
OPENSHIFT_VERSION="4.20.8"

# Available versions (as of 2026-01-23):
# 4.20.10, 4.20.8, 4.20.6, 4.20.4, 4.20.3, 4.20.2, 4.20.1, 4.20.0
# 4.19.x, 4.18.31 (default), 4.17.x, 4.16.x

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------
TAGS="environment=nonprod,project=rosa,cost-center=platform-engineering,owner=platform-team"

#------------------------------------------------------------------------------
# Advanced Settings
#------------------------------------------------------------------------------
ACCOUNT_ROLE_PREFIX="ManagedOpenShift"
FIPS="false"
DISABLE_WORKLOAD_MONITORING="false"

# Use existing OIDC config (shared with prod)
# OIDC_CONFIG_ID="2j8efj68qregg90ldmjcj7nbv0p9t3pf"
```

---

## Quick Start: Build Nonprod Cluster

### Prerequisites Checklist

- [ ] ROSA CLI installed and logged in
- [ ] AWS CLI configured with correct account credentials
- [ ] IAM roles already exist (from prod setup)
- [ ] OIDC configuration exists (can reuse prod)

### Build Steps

The ROSA-Non-Prod VPC already exists with Transit Gateway connectivity configured. No VPC creation needed.

```bash
# 1. Login to ROSA (if not already)
rosa login --token=<your-token>

# 2. Verify account roles exist
rosa list account-roles

# 3. Verify OIDC config exists
rosa list oidc-config

# 4. Verify VPC and subnets (already configured in canon-nonprod.env)
aws ec2 describe-subnets --region us-east-1 \
  --filters "Name=vpc-id,Values=vpc-0e9f579449a68a005" \
  --query 'Subnets[*].[SubnetId,Tags[?Key==`Name`].Value|[0],CidrBlock,AvailabilityZone]' \
  --output table

# 5. Create the cluster
./scripts/create-cluster.sh canon-nonprod

# 6. Monitor installation (~15-20 min)
rosa logs install -c canon-nonprod --watch

# 7. Get credentials when ready (access via VPN)
./scripts/get-credentials.sh canon-nonprod
```

**Important:** Since this is a PrivateLink cluster, you must be connected to the Site-to-Site VPN to access the cluster API and console.

### Nonprod VPC Details (ROSA-Non-Prod)

| Attribute | Value |
|-----------|-------|
| **VPC ID** | `vpc-0e9f579449a68a005` |
| **VPC Name** | `ROSA-Non-Prod` |
| **CIDR** | `10.227.96.0/20` |
| **Transit Gateway** | `tgw-041316428b4c331d0` (Aviatrix) |
| **TGW Attachment** | `tgw-attach-0d436f1bee7eb5bd3` |

| Subnet ID | AZ | CIDR | Available IPs |
|-----------|-----|------|---------------|
| `subnet-008068c7368e05ff9` | us-east-1a | 10.227.96.0/22 | 1018 |
| `subnet-013a30e0e93221460` | us-east-1c | 10.227.100.0/22 | 1019 |
| `subnet-052579b87e36014dc` | us-east-1d | 10.227.104.0/22 | 1019 |

---

## Appendix: ROSA CLI Command Reference

### Cluster Management

```bash
# List clusters
rosa list clusters

# Describe cluster (human readable)
rosa describe cluster -c <cluster-name>

# Describe cluster (JSON for scripting)
rosa describe cluster -c <cluster-name> -o json

# List machine pools
rosa list machinepools -c <cluster-name>

# Scale machine pool
rosa edit machinepool -c <cluster-name> --replicas=<count> <pool-name>

# List available upgrades
rosa list upgrades -c <cluster-name>

# Upgrade cluster
rosa upgrade cluster -c <cluster-name> --version <version> --yes
```

### IAM & OIDC

```bash
# List account roles
rosa list account-roles

# List OIDC configs
rosa list oidc-config

# List operator roles
rosa list operator-roles
```

---

**Document End**
