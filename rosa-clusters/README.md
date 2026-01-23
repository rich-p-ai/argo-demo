# ROSA HCP Cluster Management

This directory contains scripts and configurations for managing ROSA HCP (Hosted Control Plane) clusters using the ROSA CLI.

**For detailed team documentation, see: [docs/ROSA-HCP-Cluster-Build-Guide.md](docs/ROSA-HCP-Cluster-Build-Guide.md)**

## Directory Structure

```
rosa-clusters/
├── configs/                    # Cluster configuration files
│   ├── miaocplab.env          # Lab/test cluster (minimal cost)
│   ├── nonprod.env            # Non-production cluster
│   ├── _templates/            # Size templates
│   └── vpcs/                  # VPC configurations
│       ├── README.md          # VPC documentation
│       └── nonprod-vpc.env    # nonprod VPC config
├── scripts/                   # Management scripts
│   ├── setup-prereqs.sh       # One-time account setup
│   ├── create-vpc.sh          # Create VPC for cluster
│   ├── create-cluster.sh      # Create a new cluster
│   ├── delete-cluster.sh      # Delete a cluster
│   ├── scale-cluster.sh       # Scale worker nodes
│   ├── get-credentials.sh     # Get login credentials
│   └── list-clusters.sh       # List all clusters
├── docs/                      # Documentation
│   └── ROSA-HCP-Cluster-Build-Guide.md
└── README.md
```

## Prerequisites

1. **ROSA CLI** - Install from [Red Hat Console](https://console.redhat.com/openshift/downloads)
2. **AWS CLI** - Configured with appropriate credentials
3. **Red Hat Account** - With ROSA entitlement

## Quick Start

### 1. Initial Setup (One-time per AWS account)

```bash
# Login to ROSA
rosa login --token=<your-token>

# Run prerequisites setup
./scripts/setup-prereqs.sh
```

### 2. Create VPC (Required for ROSA HCP)

```bash
# Create a VPC in your target region
./scripts/create-vpc.sh <vpc-name> <region> [az-count] [cidr]

# Example: Create VPC in Ohio with 3 AZs
./scripts/create-vpc.sh nonprod-vpc us-east-2 3 10.0.0.0/16

# The script outputs subnet IDs to add to your cluster config
```

### 3. Create Cluster

```bash
# Edit config with VPC subnet IDs from step 2
vim configs/nonprod.env

# Create the cluster
./scripts/create-cluster.sh nonprod

# Monitor progress (~15-20 min)
rosa logs install -c nonprod --watch

# Get credentials when ready
./scripts/get-credentials.sh nonprod
```

### 4. Create a New Cluster from Template

```bash
# Copy a template
cp configs/_templates/xsmall.env configs/my-new-cluster.env

# Edit the configuration (add VPC subnet IDs)
vim configs/my-new-cluster.env

# Create the cluster
./scripts/create-cluster.sh my-new-cluster
```

## Cluster Sizes

| Size   | Workers | Instance Type | AZs | Est. Monthly Cost |
|--------|---------|---------------|-----|-------------------|
| xsmall | 2       | m5.xlarge     | 1   | ~$433             |
| small  | 3       | m5.xlarge     | 3   | ~$650             |
| medium | 6       | m5.2xlarge    | 3   | ~$1,800           |
| large  | 9       | m5.4xlarge    | 3   | ~$4,500           |

## Useful ROSA Commands

```bash
# List clusters
rosa list clusters

# Describe a cluster
rosa describe cluster -c <cluster-name>

# Get cluster credentials
rosa create admin -c <cluster-name>

# Watch cluster installation progress
rosa logs install -c <cluster-name> --watch

# List machine pools
rosa list machinepools -c <cluster-name>

# Scale workers
rosa edit machinepool -c <cluster-name> --replicas=4 default

# Delete cluster
rosa delete cluster -c <cluster-name>
```

## Cost Optimization Tips

1. **Single AZ** - Use single availability zone for dev/test
2. **Autoscaling** - Enable to scale down during idle
3. **Smaller instances** - m5.xlarge is the minimum recommended
4. **Delete when not in use** - HCP clusters can be recreated quickly (~15 min)
