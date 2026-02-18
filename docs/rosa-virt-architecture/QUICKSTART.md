# Quick Start Guide

Get up and running with ROSA and VM migration in minutes!

## Step 1: Install All Tools

Open PowerShell (non-elevated) and run:

```powershell
.\install-tools.ps1
```

This will install:
- OpenShift CLI (oc)
- ROSA CLI
- AWS CLI
- kubectl
- GitHub CLI (gh)
- GitLab CLI (glab)
- VMware govc CLI
- virtctl (OpenShift Virtualization)
- jq, yq, Helm

**Note**: Restart PowerShell after installation to refresh PATH.

## Step 2: Verify Installation

```powershell
.\scripts\utilities\verify-setup.ps1
```

This will check all tools and show what still needs to be configured.

## Step 3: Configure Credentials

### AWS Configuration
```powershell
aws configure
# Enter your AWS Access Key ID, Secret Access Key, region, and output format
```

### ROSA Login
```powershell
rosa login
# This will open a browser for Red Hat SSO authentication
```

### GitHub Authentication
```powershell
gh auth login
# Follow the prompts to authenticate
```

### GitLab Authentication
```powershell
glab auth login
# Follow the prompts to authenticate
```

## Step 4: Create ROSA Cluster

```powershell
.\scripts\rosa\create-cluster.ps1 -Name "my-rosa-cluster" -Region "us-east-1"
```

Wait for cluster creation (30-40 minutes), then get admin credentials:

```powershell
rosa create admin --cluster my-rosa-cluster
```

Login to cluster:

```powershell
oc login https://api.my-rosa-cluster.us-east-1.aws.rosa.openshift.com:6443 --username kubeadmin --password <password>
```

## Step 5: Install OpenShift Virtualization

```powershell
.\scripts\operators\install-cnv.ps1 -Wait
```

This will install the CNV operator and HyperConverged resource. Wait for all pods to be running:

```powershell
oc get pods -n openshift-cnv
```

## Step 6: Setup GitHub to GitLab Workflow

### Clone a Repository from GitHub

```powershell
.\scripts\utilities\clone-from-github.ps1 `
  -GitHubRepo "owner/repo-name" `
  -GitLabRepo "gitlab-user/repo-name"
```

This will:
1. Clone the repository from GitHub
2. Set up GitHub as 'source' remote
3. Set up GitLab as 'origin' remote

### Workflow

```powershell
cd source-repos/repo-name

# Pull latest from GitHub
git pull source main

# Push to GitLab
git push origin main
```

## Step 7: Migrate Your First VM

### Configure vCenter Access

```powershell
$env:GOVC_URL = "https://vcenter.example.com/sdk"
$env:GOVC_USERNAME = "administrator@vsphere.local"
$env:GOVC_PASSWORD = "your-password"
$env:GOVC_INSECURE = "true"
```

### Test vCenter Connection

```powershell
govc about
```

### Migrate VM

```powershell
.\scripts\migration\migrate-vm.ps1 `
  -VmName "my-vm" `
  -VcServer "vcenter.example.com" `
  -TargetNamespace "vm-migration"
```

### Monitor Migration

```powershell
# Watch import progress
oc get vmimport -n vm-migration -w

# Once complete, start VM
virtctl start my-vm -n vm-migration

# Connect to console
virtctl console my-vm -n vm-migration
```

## Common Commands

### ROSA Cluster Management

```powershell
# List clusters
rosa list clusters

# Describe cluster
rosa describe cluster --cluster my-rosa-cluster

# Scale cluster
rosa scale cluster --cluster my-rosa-cluster --compute-nodes 6
```

### OpenShift Virtualization

```powershell
# List VMs
oc get vm -A

# List VMIs (running VMs)
oc get vmi -A

# Start VM
virtctl start <vm-name> -n <namespace>

# Stop VM
virtctl stop <vm-name> -n <namespace>

# Connect to console
virtctl console <vm-name> -n <namespace>
```

### VMware vCenter

```powershell
# List VMs
govc ls /datacenter/vm

# Get VM info
govc vm.info /datacenter/vm/VM-Name

# Power on VM
govc vm.power -on /datacenter/vm/VM-Name

# Power off VM
govc vm.power -off /datacenter/vm/VM-Name
```

## Troubleshooting

### Tools Not Found

If tools are not found after installation:

```powershell
# Refresh PATH
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

### Cluster Connection Issues

```powershell
# Verify cluster is ready
rosa describe cluster --cluster my-rosa-cluster

# Recreate admin user
rosa create admin --cluster my-rosa-cluster

# Login again
oc login <cluster-url> --username kubeadmin --password <password>
```

## Next Steps

1. **Review Documentation**:
   - [SETUP.md](SETUP.md) - Complete setup guide
   - [docs/ROSA-CLUSTER-GUIDE.md](docs/ROSA-CLUSTER-GUIDE.md) - ROSA cluster management
   - [docs/VM-MIGRATION-GUIDE.md](docs/VM-MIGRATION-GUIDE.md) - VM migration guide

2. **Set Up GitLab CI/CD**:
   - Review `.gitlab-ci.yml`
   - Configure GitLab CI/CD variables
   - Set up pipelines

3. **Plan Your Migrations**:
   - Inventory VMs to migrate
   - Plan migration order
   - Schedule maintenance windows

4. **Configure Monitoring**:
   - Set up cluster monitoring
   - Configure alerts
   - Set up logging

## Getting Help

- Check the troubleshooting sections in the documentation
- Review OpenShift and ROSA documentation
- Check GitLab CI/CD logs for pipeline issues
- Review VM import events: `oc get events -n <namespace>`

## Project Structure

```
.
├── config/              # Configuration files
│   ├── clusters/        # ROSA cluster configs
│   ├── operators/      # Operator manifests
│   └── vm-migrations/  # VM import configs
├── scripts/            # Automation scripts
│   ├── rosa/          # ROSA management
│   ├── migration/     # VM migration
│   └── utilities/     # Helper scripts
├── docs/              # Documentation
└── source-repos/      # Cloned GitHub repos
```

Happy migrating! 🚀
