# ROSA & OpenShift Virtualization Migration Setup Guide

This guide provides comprehensive instructions for setting up your environment to work with Red Hat OpenShift Service on AWS (ROSA) and migrate VMs from VMware vCenter to OpenShift Virtualization.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Tool Installation](#tool-installation)
3. [AWS Configuration](#aws-configuration)
4. [ROSA Setup](#rosa-setup)
5. [GitHub Configuration](#github-configuration)
6. [GitLab Configuration](#gitlab-configuration)
7. [OpenShift Virtualization Setup](#openshift-virtualization-setup)
8. [VMware vCenter Access](#vmware-vcenter-access)
9. [Project Structure](#project-structure)
10. [Quick Start](#quick-start)

## Prerequisites

### Required Accounts
- **Red Hat Account**: With ROSA access and OpenShift subscription
- **AWS Account**: With appropriate IAM permissions for ROSA
- **GitHub Account**: For source code repositories
- **GitLab Account**: For storing migration code and configurations
- **VMware vCenter Access**: Credentials and network access to source vCenter

### System Requirements
- Windows 10/11 or Windows Server 2019+
- PowerShell 5.1 or later
- Minimum 8GB RAM
- Internet connectivity
- Administrator access (for initial installation)

## Tool Installation

### Automated Installation

Run the installation script in a **non-elevated** PowerShell session:

```powershell
.\install-tools.ps1
```

**Important**: Do not run PowerShell as Administrator. The script will handle tool installation and PATH configuration.

### Manual Installation

If automated installation fails, install tools manually:

#### 1. Git
```powershell
# Using winget
winget install Git.Git

# Or download from: https://git-scm.com/download/win
```

#### 2. GitHub CLI
```powershell
winget install GitHub.cli
# Or: https://cli.github.com/
```

#### 3. AWS CLI
```powershell
# Download and install from:
# https://awscli.amazonaws.com/AWSCLIV2.msi
```

#### 4. OpenShift CLI (oc)
```powershell
# Download from Red Hat:
# https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/
# Extract oc.exe to a directory in your PATH
```

#### 5. ROSA CLI
```powershell
# Download from:
# https://github.com/openshift/rosa/releases/latest/download/rosa-windows.zip
# Extract rosa.exe to a directory in your PATH
```

#### 6. GitLab CLI
```powershell
# Download from:
# https://gitlab.com/gitlab-org/cli/-/releases
```

#### 7. Additional Tools
- **kubectl**: https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/
- **virtctl**: Will be available after OpenShift Virtualization is installed
- **govc**: https://github.com/vmware/govmomi/releases
- **jq**: `winget install stedolan.jq`
- **yq**: https://github.com/mikefarah/yq/releases
- **Helm**: `winget install Helm.Helm`

## AWS Configuration

### 1. Configure AWS Credentials

```powershell
aws configure
```

Enter:
- **AWS Access Key ID**: Your IAM user access key
- **AWS Secret Access Key**: Your IAM user secret key
- **Default region**: e.g., `us-east-1`, `us-west-2`
- **Default output format**: `json`

### 2. Verify AWS Access

```powershell
aws sts get-caller-identity
```

### 3. Set Up AWS Profiles (Optional)

For multiple AWS accounts:

```powershell
aws configure --profile rosa-prod
aws configure --profile rosa-dev
```

Use profiles:
```powershell
$env:AWS_PROFILE = "rosa-prod"
aws sts get-caller-identity
```

### 4. Required AWS IAM Permissions

Your AWS user/role needs permissions for:
- ROSA cluster creation and management
- EC2, VPC, IAM operations
- Route53 (if using custom domains)
- S3 (for cluster logs and backups)

## ROSA Setup

### 1. Login to ROSA

```powershell
rosa login
```

This will open a browser for Red Hat SSO authentication.

### 2. Verify ROSA Access

```powershell
rosa whoami
```

### 3. List Available Regions

```powershell
rosa list regions
```

### 4. Verify AWS Account Linking

```powershell
rosa verify quota
```

### 5. Create ROSA Cluster (Example)

```powershell
# Set variables
$CLUSTER_NAME = "my-rosa-cluster"
$REGION = "us-east-1"
$VERSION = "4.15"

# Create cluster
rosa create cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --version $VERSION \
  --compute-machine-type m5.xlarge \
  --compute-nodes 3 \
  --multi-az \
  --machine-cidr 10.0.0.0/16 \
  --service-cidr 172.30.0.0/16 \
  --pod-cidr 10.128.0.0/14 \
  --host-prefix 23
```

### 6. Get Cluster Credentials

```powershell
rosa create admin --cluster $CLUSTER_NAME
```

Or login via console:
```powershell
rosa describe cluster --cluster $CLUSTER_NAME
# Use the console URL and admin credentials
```

### 7. Configure oc CLI

```powershell
# Get kubeconfig
oc login https://api.$CLUSTER_NAME.$REGION.aws.rosa.openshift.com:6443 \
  --username kubeadmin \
  --password <admin-password>
```

## GitHub Configuration

### 1. Authenticate with GitHub

```powershell
gh auth login
```

Choose:
- **GitHub.com**
- **HTTPS** (recommended)
- **Login with a web browser**

### 2. Verify GitHub Access

```powershell
gh auth status
gh repo list
```

### 3. Clone Source Repositories

```powershell
# Example: Clone a repository
gh repo clone owner/repo-name ./source-repos/repo-name
```

### 4. Configure Git for Dual Remotes

```powershell
# Navigate to cloned repo
cd ./source-repos/repo-name

# Add GitLab as upstream remote
git remote add gitlab https://gitlab.com/your-username/repo-name.git

# Verify remotes
git remote -v
```

## GitLab Configuration

### 1. Authenticate with GitLab

```powershell
glab auth login
```

Choose:
- **GitLab.com** or your GitLab instance URL
- **HTTPS** (recommended)
- **Login with a web browser**

### 2. Verify GitLab Access

```powershell
glab auth status
glab repo list
```

### 3. Create GitLab Project

```powershell
# Create a new project
glab repo create rosa-vm-migration --public

# Or use existing project
glab repo clone your-username/rosa-vm-migration
```

### 4. Set Up GitLab CI/CD

See `gitlab-ci.yml` in the project root for CI/CD pipeline configuration.

## OpenShift Virtualization Setup

### 1. Install OpenShift Virtualization Operator

```powershell
# Create namespace
oc create namespace openshift-cnv

# Create OperatorGroup
oc apply -f config/operators/operatorgroup-cnv.yaml

# Create Subscription
oc apply -f config/operators/subscription-cnv.yaml

# Wait for operator installation
oc wait --for=condition=Installed \
  --timeout=10m \
  csv -n openshift-cnv -l operators.coreos.com/kubevirt-hyperconverged.openshift-cnv
```

### 2. Create HyperConverged Resource

```powershell
oc apply -f config/operators/hyperconverged.yaml
```

### 3. Verify Installation

```powershell
# Check operator status
oc get csv -n openshift-cnv

# Check HyperConverged status
oc get hco -n openshift-cnv

# Check pods
oc get pods -n openshift-cnv
```

### 4. Install virtctl CLI

```powershell
# Download virtctl
$virtctlUrl = (oc get -n openshift-cnv deployment/virt-operator -o jsonpath='{.spec.template.spec.containers[0].image}').Replace('virt-operator', 'virtctl')
# Or use pre-installed version from tools directory
```

## VMware vCenter Access

### 1. Configure govc Environment

```powershell
# Set vCenter connection details
$env:GOVC_URL = "https://vcenter.example.com/sdk"
$env:GOVC_USERNAME = "administrator@vsphere.local"
$env:GOVC_PASSWORD = "your-password"
$env:GOVC_INSECURE = "true"  # If using self-signed certificates
```

### 2. Test vCenter Connection

```powershell
govc about
```

### 3. List VMs

```powershell
govc ls /datacenter/vm
```

### 4. Export VM Configuration

```powershell
# Export VM details
govc vm.info -json /datacenter/vm/VM-Name | ConvertFrom-Json
```

## Project Structure

```
.
├── config/
│   ├── clusters/           # ROSA cluster configurations
│   ├── operators/          # Operator manifests
│   ├── vm-migrations/      # VM migration configurations
│   └── networking/         # Network policies, routes
├── scripts/
│   ├── rosa/               # ROSA cluster management scripts
│   ├── migration/          # VM migration scripts
│   └── utilities/          # Helper scripts
├── source-repos/           # Cloned GitHub repositories
├── manifests/              # Kubernetes/OpenShift manifests
├── docs/                   # Documentation
├── .gitlab-ci.yml          # GitLab CI/CD pipeline
├── install-tools.ps1       # Tool installation script
└── SETUP.md               # This file
```

## Quick Start

### 1. Install All Tools

```powershell
.\install-tools.ps1
```

### 2. Configure Credentials

```powershell
# AWS
aws configure

# ROSA
rosa login

# GitHub
gh auth login

# GitLab
glab auth login
```

### 3. Create ROSA Cluster

```powershell
.\scripts\rosa\create-cluster.ps1 -Name "my-cluster" -Region "us-east-1"
```

### 4. Install OpenShift Virtualization

```powershell
.\scripts\operators\install-cnv.ps1
```

### 5. Start VM Migration

```powershell
.\scripts\migration\migrate-vm.ps1 -VmName "my-vm" -VcServer "vcenter.example.com"
```

## Troubleshooting

### PATH Issues

If tools are not found after installation:

```powershell
# Refresh PATH in current session
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# Or restart PowerShell
```

### ROSA Login Issues

```powershell
# Clear ROSA cache
Remove-Item -Recurse -Force $env:USERPROFILE\.config\rosa

# Re-login
rosa login
```

### AWS Credential Issues

```powershell
# Verify credentials
aws sts get-caller-identity

# Check credentials file
cat $env:USERPROFILE\.aws\credentials
```

### OpenShift Connection Issues

```powershell
# Verify cluster access
oc cluster-info

# Check authentication
oc whoami

# Get cluster status
oc get nodes
```

## Next Steps

1. Review the project structure and customize configurations
2. Set up GitLab CI/CD pipelines
3. Create VM migration playbooks
4. Configure monitoring and logging
5. Set up backup and disaster recovery procedures

## Additional Resources

- [ROSA Documentation](https://docs.openshift.com/rosa/)
- [OpenShift Virtualization Documentation](https://docs.openshift.com/container-platform/latest/virt/)
- [VMware Migration Guide](https://docs.openshift.com/container-platform/latest/virt/vmware-vm-import.html)
- [GitLab CI/CD Documentation](https://docs.gitlab.com/ee/ci/)
