# ROSA HCP Cluster Build Guide

**Document Version:** 1.0  
**Last Updated:** January 2026  
**Author:** Platform Engineering Team

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Architecture](#architecture)
4. [Configuration Reference](#configuration-reference)
5. [Step-by-Step Build Process](#step-by-step-build-process)
6. [Post-Installation Steps](#post-installation-steps)
7. [Cluster Management](#cluster-management)
8. [Troubleshooting](#troubleshooting)

---

## Overview

This guide documents how we build and manage ROSA HCP (Red Hat OpenShift Service on AWS - Hosted Control Plane) clusters using standardized scripts and configuration files.

### What is ROSA HCP?

ROSA HCP is a managed OpenShift service where:
- **Control plane** is fully managed by Red Hat/AWS (no control plane nodes to manage)
- **Worker nodes** run in your AWS account
- **Faster provisioning** (~15 minutes vs 40+ for Classic ROSA)
- **Lower cost** - no control plane infrastructure costs

### Repository Structure

```
rosa-clusters/
├── configs/                    # Cluster configuration files
│   ├── miaocplab.env          # Lab/test cluster (minimal)
│   ├── nonprod.env            # Non-production cluster
│   ├── vpcs/                  # VPC configurations
│   │   ├── README.md          # VPC documentation
│   │   └── nonprod-vpc.env    # VPC subnet reference
│   └── _templates/            # Size templates for new clusters
│       ├── xsmall.env         # 2 workers, single AZ
│       ├── small.env          # 3 workers, multi-AZ
│       ├── medium.env         # 6 workers, multi-AZ
│       └── large.env          # 9 workers, multi-AZ
├── scripts/                   # Automation scripts
│   ├── setup-prereqs.sh       # One-time account setup
│   ├── create-cluster.sh      # Create a cluster
│   ├── create-vpc.sh          # Create ROSA-compatible VPC
│   ├── delete-cluster.sh      # Delete a cluster
│   ├── scale-cluster.sh       # Scale worker nodes
│   ├── get-credentials.sh     # Get login credentials
│   └── list-clusters.sh       # List all clusters
└── docs/                      # Documentation
    └── ROSA-HCP-Cluster-Build-Guide.md
```

### Credentials Setup

Create a `.env` file in the repository root (not committed to git):

```bash
cp .env.example .env
# Edit .env with your ROSA token and AWS credentials
```

---

## Prerequisites

### Required Tools

| Tool | Purpose | Installation |
|------|---------|--------------|
| **ROSA CLI** | Manage ROSA clusters | [Download](https://console.redhat.com/openshift/downloads) |
| **AWS CLI** | AWS authentication | [Install Guide](https://aws.amazon.com/cli/) |
| **oc CLI** | OpenShift operations | [Download](https://console.redhat.com/openshift/downloads) |
| **jq** | JSON parsing (used by scripts) | `brew install jq` or `yum install jq` |

### Required Accounts & Permissions

1. **Red Hat Account** with ROSA entitlement
   - Get your offline token from: https://console.redhat.com/openshift/token

2. **AWS Account** with permissions for:
   - IAM role creation
   - VPC/networking
   - EC2 instances
   - EBS volumes

### Verify Installation

```bash
# Check ROSA CLI
rosa version

# Check AWS CLI
aws --version

# Check oc CLI
oc version --client
```

---

## Architecture

### Cluster Sizing Options

| Size | Workers | Instance Type | vCPU/Node | RAM/Node | AZs | Est. Cost/Month |
|------|---------|---------------|-----------|----------|-----|-----------------|
| **xsmall** | 2 | m5.xlarge | 4 | 16 GB | 1 | ~$433 |
| **small** | 3 | m5.xlarge | 4 | 16 GB | 3 | ~$650 |
| **medium** | 6 | m5.2xlarge | 8 | 32 GB | 3 | ~$1,800 |
| **large** | 9 | m5.4xlarge | 16 | 64 GB | 3 | ~$4,500 |

### nonprod Cluster Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        AWS Region: us-east-1                     │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │    AZ-1a    │  │    AZ-1b    │  │    AZ-1c    │              │
│  │             │  │             │  │             │              │
│  │  ┌───────┐  │  │  ┌───────┐  │  │  ┌───────┐  │              │
│  │  │Worker │  │  │  │Worker │  │  │  │Worker │  │              │
│  │  │m5.xl  │  │  │  │m5.xl  │  │  │  │m5.xl  │  │              │
│  │  └───────┘  │  │  └───────┘  │  │  └───────┘  │              │
│  │             │  │             │  │             │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
│                                                                  │
│  Control Plane: Managed by Red Hat (not in your account)        │
└─────────────────────────────────────────────────────────────────┘
```

---

## Configuration Reference

### Configuration File Location

All cluster configurations are stored as `.env` files in:
```
rosa-clusters/configs/<cluster-name>.env
```

### Complete Variable Reference

Edit the configuration file at `configs/nonprod.env`:

#### Cluster Identification

| Variable | Description | Example | Where to Edit |
|----------|-------------|---------|---------------|
| `CLUSTER_NAME` | Unique cluster name (2-15 chars, lowercase) | `"nonprod"` | Line 9 |
| `ENVIRONMENT` | Environment label for tagging | `"nonprod"` | Line 10 |

#### AWS Configuration

| Variable | Description | Example | Where to Edit |
|----------|-------------|---------|---------------|
| `AWS_REGION` | AWS region for deployment | `"us-east-1"` | Line 13 |

**Available Regions:** us-east-1, us-east-2, us-west-2, eu-west-1, eu-central-1, ap-southeast-1, ap-northeast-1

#### Cluster Sizing

| Variable | Description | Example | Where to Edit |
|----------|-------------|---------|---------------|
| `REPLICAS` | Number of worker nodes | `3` | Line 16 |
| `INSTANCE_TYPE` | EC2 instance type | `"m5.xlarge"` | Line 17 |
| `MULTI_AZ` | Deploy across multiple AZs | `"true"` | Line 18 |

**Recommended Instance Types:**
- `m5.xlarge` - 4 vCPU, 16GB (minimum recommended)
- `m5.2xlarge` - 8 vCPU, 32GB (standard production)
- `m5.4xlarge` - 16 vCPU, 64GB (large workloads)
- `m6i.xlarge` - 4 vCPU, 16GB (newer generation)

#### Autoscaling

| Variable | Description | Example | Where to Edit |
|----------|-------------|---------|---------------|
| `ENABLE_AUTOSCALING` | Enable cluster autoscaler | `"true"` | Line 21 |
| `MIN_REPLICAS` | Minimum worker count | `3` | Line 22 |
| `MAX_REPLICAS` | Maximum worker count | `6` | Line 23 |

#### Networking

| Variable | Description | Example | Where to Edit |
|----------|-------------|---------|---------------|
| `SUBNET_IDS` | Existing subnet IDs (optional) | `"subnet-xxx,subnet-yyy"` | Line 27 |
| `MACHINE_CIDR` | VPC CIDR block | `"10.0.0.0/16"` | Line 28 |
| `SERVICE_CIDR` | Kubernetes service CIDR | `"172.30.0.0/16"` | Line 29 |
| `POD_CIDR` | Pod network CIDR | `"10.128.0.0/14"` | Line 30 |
| `HOST_PREFIX` | Pod CIDR allocation per node | `23` | Line 31 |

> **Note:** Leave `SUBNET_IDS` empty to let ROSA create a new VPC automatically.

#### Access Control

| Variable | Description | Example | Where to Edit |
|----------|-------------|---------|---------------|
| `PRIVATE_CLUSTER` | Restrict API to private network | `"false"` | Line 34 |

#### Version Control

| Variable | Description | Example | Where to Edit |
|----------|-------------|---------|---------------|
| `OPENSHIFT_VERSION` | Specific OCP version (optional) | `"4.14.10"` | Line 37 |

> **Note:** Leave empty to use the latest stable version.

#### Tagging

| Variable | Description | Example | Where to Edit |
|----------|-------------|---------|---------------|
| `TAGS` | AWS resource tags (comma-separated) | `"environment=nonprod,owner=team"` | Line 40 |

#### Advanced Settings

| Variable | Description | Example | Where to Edit |
|----------|-------------|---------|---------------|
| `ACCOUNT_ROLE_PREFIX` | IAM role prefix | `"ManagedOpenShift"` | Line 45 |
| `FIPS` | Enable FIPS mode | `"false"` | Line 46 |
| `DISABLE_WORKLOAD_MONITORING` | Disable user workload monitoring | `"false"` | Line 47 |

---

## Step-by-Step Build Process

### Step 1: Clone the Repository

```bash
git clone <repository-url>
cd argo-demo/rosa-clusters
```

### Step 2: Login to ROSA

```bash
# Get your token from: https://console.redhat.com/openshift/token
rosa login --token=<your-offline-access-token>

# Verify login
rosa whoami
```

**Expected Output:**
```
AWS ARN:                      arn:aws:iam::123456789012:user/your-user
AWS Account ID:               123456789012
AWS Default Region:           us-east-1
OCM API:                      https://api.openshift.com
OCM Account Email:            your-email@example.com
OCM Account ID:               1234567890abcdef
OCM Account Name:             Your Name
OCM Account Username:         your_username
OCM Organization External ID: 12345678
OCM Organization ID:          abcdefgh12345678
OCM Organization Name:        Your Organization
```

### Step 3: One-Time Account Setup

> **Note:** This only needs to be run ONCE per AWS account.

```bash
./scripts/setup-prereqs.sh
```

This script will:
1. ✓ Verify ROSA and AWS credentials
2. ✓ Check AWS service quotas
3. ✓ Verify IAM permissions
4. ✓ Create account-wide IAM roles
5. ✓ Create OIDC configuration
6. ✓ Create operator roles

**Duration:** ~5 minutes

### Step 4: Create VPC (if needed)

ROSA HCP clusters require a VPC with public and private subnets. You can either:
- **Option A:** Use an existing VPC (update `SUBNET_IDS` in your config)
- **Option B:** Create a new VPC with our script

```bash
# Create a new ROSA-compatible VPC
rosa create network rosa-quickstart-default-vpc \
  --param Region=us-east-1 \
  --param Name=nonprod-vpc \
  --param AvailabilityZoneCount=3 \
  --param VpcCidr=10.0.0.0/16 \
  --mode auto \
  --yes

# Get subnet IDs after creation
aws ec2 describe-subnets --region us-east-1 \
  --filters "Name=tag:Name,Values=nonprod-vpc*" \
  --query 'Subnets[*].[SubnetId,Tags[?Key==`Name`].Value|[0]]' \
  --output table
```

Then update your cluster config with the subnet IDs (both public and private).

### Step 5: Review/Edit Configuration

```bash
# View the nonprod configuration
cat configs/nonprod.env

# Edit if needed - update SUBNET_IDS with VPC subnets
vim configs/nonprod.env
```

### Step 6: Create the Cluster

```bash
./scripts/create-cluster.sh nonprod
```

**Expected Output:**
```
Loading configuration from: configs/nonprod.env

Validating prerequisites...
  ✓ ROSA login verified
  ✓ AWS Account: 1813........
  ✓ Cluster name available
  ✓ OIDC Config ID: 2o01.........68

============================================
  Creating ROSA HCP Cluster: nonprod
============================================

Configuration:
  Region:        us-east-1
  Workers:       3 x m5.xlarge
  Multi-AZ:      true
  Autoscaling:   true
    Min/Max:     3/6
  Private:       false

Executing ROSA command...
```

### Step 7: Monitor Installation

```bash
# Watch installation logs (recommended)
rosa logs install -c nonprod --watch

# Or check status periodically
rosa describe cluster -c nonprod
```

**Cluster States:**
| State | Description |
|-------|-------------|
| `pending` | Cluster creation initiated |
| `validating` | Validating configuration |
| `installing` | Infrastructure being provisioned |
| `ready` | Cluster is operational |
| `error` | Installation failed |

**Duration:** ~15-20 minutes

### Step 8: Get Cluster Credentials

```bash
./scripts/get-credentials.sh nonprod
```

**Output:**
```
============================================
  Cluster: nonprod
============================================

State:       ready
API URL:     https://api.nonprod.abc123.p1.openshiftapps.com:6443
Console URL: https://console-openshift-console.apps.nonprod.abc123.p1.openshiftapps.com

Creating admin user...
Admin username: cluster-admin
Admin password: XXXXX-XXXXX-XXXXX-XXXXX
```

### Step 9: Login to the Cluster

```bash
# CLI Login
oc login https://api.nonprod.y8d3.p3.openshiftapps.com:443 \
  -u cluster-admin \
  -p <password-from-step-8>

# Verify
oc get nodes
oc get clusterversion
```

**Or access the Web Console:**
Open the Console URL in your browser and login with the admin credentials.

---

## Post-Installation Steps

### 1. Verify Cluster Health

```bash
# Check nodes
oc get nodes

# Check cluster operators
oc get clusteroperators

# Check cluster version
oc get clusterversion
```

### 2. Configure Identity Provider (Recommended)

The cluster-admin user is temporary. Configure a proper identity provider:

```bash
# Example: Configure LDAP, OIDC, or GitHub authentication
# See: https://docs.openshift.com/rosa/authentication/understanding-identity-provider.html
```

### 3. Register with GitOps (ArgoCD)

Add the cluster to your ArgoCD hub for day-two configuration management:

```bash
# Add cluster to ArgoCD
argocd cluster add <context-name>

# Or create cluster secret manually
```

---

## Cluster Management

### List All Clusters

```bash
./scripts/list-clusters.sh
```

### Scale Workers

```bash
# Scale to 5 workers
./scripts/scale-cluster.sh nonprod 5

# Or use ROSA directly
rosa edit machinepool default -c nonprod --replicas=5
```

### Delete Cluster

```bash
# With confirmation prompt
./scripts/delete-cluster.sh nonprod

# Without confirmation (use with caution)
./scripts/delete-cluster.sh nonprod --yes
```

### Upgrade Cluster

```bash
# List available upgrades
rosa list upgrades -c nonprod

# Upgrade to specific version
rosa upgrade cluster -c nonprod --version 4.14.12 --yes
```

---

## Troubleshooting

### Common Issues

#### Issue: "OIDC configuration not found"

```bash
# Solution: Run prerequisites setup
./scripts/setup-prereqs.sh
```

#### Issue: "Insufficient quota"

```bash
# Check quotas
rosa verify quota

# Request increase via AWS console for:
# - EC2 instances
# - EBS volumes
# - VPCs
# - Elastic IPs
```

#### Issue: Cluster stuck in "installing"

```bash
# Check installation logs
rosa logs install -c nonprod --watch

# Check for errors
rosa describe cluster -c nonprod
```

#### Issue: "Permission denied" running scripts

```bash
# Make scripts executable
chmod +x scripts/*.sh
```

### Useful Debug Commands

```bash
# Detailed cluster info
rosa describe cluster -c nonprod -o json

# List machine pools
rosa list machinepools -c nonprod

# Check OIDC configs
rosa list oidc-config

# Check account roles
rosa list account-roles
```

### Support Contacts

- **ROSA Support:** https://access.redhat.com/support
- **AWS Support:** Via AWS Console
- **Internal Team:** platform-engineering@company.com

---

## Appendix: nonprod Configuration File

**File:** `configs/nonprod.env`

```bash
#------------------------------------------------------------------------------
# ROSA HCP Cluster Configuration: nonprod
# Purpose: Non-Production environment cluster
#------------------------------------------------------------------------------

# Cluster identification
CLUSTER_NAME="nonprod"                    # <-- Edit: Unique cluster name
ENVIRONMENT="nonprod"                     # <-- Edit: Environment label

# AWS Configuration
AWS_REGION="us-east-1"                    # <-- Edit: Target AWS region

# Cluster sizing
REPLICAS=3                                # <-- Edit: Number of workers
INSTANCE_TYPE="m5.xlarge"                 # <-- Edit: Worker instance type
MULTI_AZ="true"                           # <-- Edit: Multi-AZ deployment

# Autoscaling
ENABLE_AUTOSCALING="true"                 # <-- Edit: Enable/disable
MIN_REPLICAS=3                            # <-- Edit: Minimum workers
MAX_REPLICAS=6                            # <-- Edit: Maximum workers

# Networking
# SUBNET_IDS=""                           # <-- Edit: Existing subnets (optional)
MACHINE_CIDR="10.0.0.0/16"               # <-- Edit: VPC CIDR
SERVICE_CIDR="172.30.0.0/16"             # Usually don't change
POD_CIDR="10.128.0.0/14"                 # Usually don't change
HOST_PREFIX=23                            # Usually don't change

# Access
PRIVATE_CLUSTER="false"                   # <-- Edit: true for private API

# Version
# OPENSHIFT_VERSION=""                    # <-- Edit: Specific version (optional)

# Tags
TAGS="environment=nonprod,cost-center=platform-engineering,owner=platform-team"

# Advanced (usually don't change)
ACCOUNT_ROLE_PREFIX="ManagedOpenShift"
FIPS="false"
DISABLE_WORKLOAD_MONITORING="false"
```

---

**Document End**
