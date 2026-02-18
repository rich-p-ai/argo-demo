# VM Migration Runbook

**Document Version**: 1.0  
**Last Updated**: February 17, 2026  
**Target Platform**: Red Hat OpenShift on AWS (ROSA)  
**Migration Tool**: Migration Toolkit for Virtualization (MTV)

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Pre-Migration Phase](#pre-migration-phase)
4. [Migration Execution](#migration-execution)
5. [Post-Migration Validation](#post-migration-validation)
6. [Rollback Procedures](#rollback-procedures)
7. [Troubleshooting](#troubleshooting)
8. [Appendix](#appendix)

---

## Overview

### Purpose
This runbook provides standardized procedures for migrating virtual machines from on-premises VMware vCenter to Red Hat OpenShift Service on AWS (ROSA) using the Migration Toolkit for Virtualization (MTV).

### Scope
- **Source Environment**: VMware vCenter/ESXi
- **Target Environment**: ROSA Clusters (POC, Non-Prod, QA)
- **VM Types**: Windows and Linux virtual machines
- **Network**: Site-to-Site VPN/IPsec connectivity required

### Key Components
- **MTV Operator**: Handles migration orchestration
- **Storage**: FSx for NetApp ONTAP with Trident CSI
- **Networking**: AWS VPC with VPN connectivity to on-premises
- **VirtIO Drivers**: Required for Windows VM optimal performance

---

## Prerequisites

### Infrastructure Requirements

#### Network Connectivity
- [ ] Site-to-Site VPN established between on-premises and AWS VPC
- [ ] IPsec tunnels verified (Libreswan/StrongSwan)
- [ ] Source and destination networks routable
- [ ] DNS resolution configured for both environments
- [ ] Firewall rules permit:
  - vCenter API access (443/tcp)
  - ESXi access (443/tcp, 902/tcp)
  - NFS/iSCSI storage protocols

#### OpenShift Cluster
```bash
# Verify cluster health
oc get nodes
oc get co  # All cluster operators should be Available=True

# Verify MTV operator installation
oc get csv -n openshift-mtv
oc get pods -n openshift-mtv
```

#### Storage Backend
```bash
# Verify Trident/ODF storage classes
oc get sc
oc get tridentbackend -n trident

# Expected storage classes:
# - trident-csi (for Linux VMs)
# - trident-csi-rwx (for Windows VMs with VirtIO ISO)
```

#### Provider Connectivity
```bash
# Verify vCenter provider connection
oc get provider -n openshift-mtv
oc describe provider <provider-name> -n openshift-mtv

# Status should show "Ready" with no errors
```

### VM Requirements

#### Windows VMs
- [ ] VirtIO drivers injected into source VM disk (if not using post-migration injection)
- [ ] VM powered off before migration (recommended for data consistency)
- [ ] Adequate disk space for migration (1.5x VM disk size)
- [ ] Administrator credentials available for post-migration configuration

#### Linux VMs
- [ ] VM inventory documented (CPU, RAM, disk, network)
- [ ] Cloud-init or similar automation configured (optional)
- [ ] Static IP or DHCP configuration planned
- [ ] Root/sudo credentials available

---

## Pre-Migration Phase

### 1. VM Assessment and Planning

#### Inventory Collection
```bash
# Export VM list from current environment
# Create Wave0-VM-IP-List.csv or similar inventory

# Required fields:
# - VM Name
# - OS Type/Version
# - CPU Count
# - Memory (GB)
# - Disk Size (GB)
# - IP Address (current)
# - Target IP Address
# - Migration Wave/Priority
```

#### Network Planning
```bash
# Document current network configuration
VM_NAME="nymsdv297"  # Example
CURRENT_IP="10.x.x.x"
TARGET_CIDR="10.1.128.0/24"  # AWS VPC subnet
TARGET_IP="10.1.128.x"

# Create network mapping ConfigMap
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: vm-network-mappings
  namespace: openshift-mtv
data:
  ${VM_NAME}: |
    ipAddress: ${TARGET_IP}
    subnetMask: 255.255.255.0
    gateway: 10.1.128.1
    dns1: 10.1.128.2
EOF
```

### 2. VirtIO Driver Preparation (Windows Only)

#### Option A: Pre-Migration Injection
```bash
# Upload VirtIO ISO to PVC
./inject-virtio-drivers.sh <vm-name>

# Verify ISO upload
oc get pvc | grep virtio
```

#### Option B: Post-Migration Installation
- Keep VirtIO ISO available on shared storage (RWX PVC)
- Plan for manual driver installation after first boot

### 3. Create Migration Plan

```yaml
# migration-plan-template.yaml
apiVersion: forklift.konveyor.io/v1beta1
kind: Plan
metadata:
  name: <migration-plan-name>
  namespace: openshift-mtv
spec:
  provider:
    source:
      name: <vcenter-provider-name>
      namespace: openshift-mtv
    destination:
      name: host
      namespace: openshift-mtv
  targetNamespace: <target-namespace>
  warm: false  # Set to true for warm migration (minimal downtime)
  vms:
    - name: <vm-name-in-vcenter>
      hooks: []  # Add pre/post hooks if needed
  map:
    network:
      - source:
          name: <source-network-name>
        destination:
          name: <target-network-attachment-definition>
          type: multus
    storage:
      - source:
          name: <source-datastore-name>
        destination:
          storageClass: trident-csi
          accessMode: ReadWriteOnce
```

#### Apply Migration Plan
```bash
# Create namespace if needed
oc create namespace vm-migrations

# Apply the migration plan
oc apply -f migration-plan-<vm-name>.yaml

# Verify plan is ready
oc get plan -n openshift-mtv
oc describe plan <migration-plan-name> -n openshift-mtv
```

---

## Migration Execution

### Phase 1: Pre-Flight Checks

```bash
# 1. Verify VPN connectivity
ping <on-prem-vcenter-ip>
ping <on-prem-esxi-host-ip>

# 2. Check storage capacity
oc get pv
oc describe sc trident-csi

# 3. Verify provider status
oc get provider -n openshift-mtv -o yaml

# 4. Review migration plan validation
oc get plan <plan-name> -n openshift-mtv -o jsonpath='{.status.conditions}'
```

### Phase 2: Initiate Migration

```bash
# Start migration by creating/updating plan
oc patch plan <plan-name> -n openshift-mtv \
  --type merge \
  -p '{"spec":{"archived":false}}'

# Alternative: Via OpenShift Console
# Navigate to: Migration > Plans for virtualization > Select plan > Start
```

### Phase 3: Monitor Migration Progress

```bash
# Watch migration status
watch oc get plan <plan-name> -n openshift-mtv

# Detailed progress
oc describe plan <plan-name> -n openshift-mtv

# Check migration pod logs
oc get pods -n openshift-mtv | grep migration
oc logs -f <migration-pod-name> -n openshift-mtv

# Monitor VM creation
watch oc get vm -n <target-namespace>
watch oc get vmi -n <target-namespace>
```

### Migration Stages
1. **Validation** (1-2 min): Plan validation and pre-checks
2. **Disk Transfer** (varies): Disk data copied from source to destination
   - Cold migration: VM must be powered off
   - Warm migration: Initial sync while VM running, final sync after shutdown
3. **Import** (5-10 min): VM definition created in OpenShift Virtualization
4. **Conversion** (5-10 min): VM configuration converted to KubeVirt format
5. **Complete**: VM ready to power on

### Phase 4: Expected Timeline

| VM Size | Network Speed | Estimated Duration |
|---------|---------------|-------------------|
| < 50 GB | 1 Gbps | 15-30 minutes |
| 50-100 GB | 1 Gbps | 30-60 minutes |
| 100-200 GB | 1 Gbps | 1-2 hours |
| > 200 GB | 1 Gbps | 2+ hours |

*Note: Add 10-15 minutes for conversion and import phases*

---

## Post-Migration Validation

### 1. VM Power-On

```bash
# Check VM status
oc get vm <vm-name> -n <namespace>

# Start the VM
virtctl start <vm-name> -n <namespace>

# Monitor startup
watch oc get vmi <vm-name> -n <namespace>

# Check VM events
oc describe vmi <vm-name> -n <namespace>
```

### 2. Console Access

```bash
# Access VM console
virtctl console <vm-name> -n <namespace>

# For graphical console (requires VNC viewer)
virtctl vnc <vm-name> -n <namespace>
```

### 3. Network Validation

#### Linux VMs
```bash
# Via console or virtctl
virtctl ssh <vm-name> -n <namespace>

# Check IP configuration
ip addr show
ip route show
cat /etc/resolv.conf

# Test connectivity
ping 8.8.8.8
ping <gateway-ip>
curl -I https://www.google.com
```

#### Windows VMs
```powershell
# Via RDP after network configured or through console

# Check network adapters
Get-NetAdapter
Get-NetIPAddress
Get-NetIPConfiguration

# VirtIO driver status
Get-PnpDevice | Where-Object {$_.FriendlyName -like "*VirtIO*"}

# Test connectivity
Test-NetConnection -ComputerName 8.8.8.8
Test-NetConnection -ComputerName <domain-controller>
```

### 4. Application Validation

#### Standard Checks
- [ ] Services started automatically
- [ ] Application logs show no errors
- [ ] Database connectivity verified
- [ ] Web applications accessible
- [ ] Scheduled tasks/cron jobs operational
- [ ] Monitoring agents reporting

#### Windows-Specific
```powershell
# Check services
Get-Service | Where-Object {$_.StartType -eq "Automatic" -and $_.Status -ne "Running"}

# Event logs
Get-EventLog -LogName Application -Newest 50 -EntryType Error
Get-EventLog -LogName System -Newest 50 -EntryType Error
```

#### Linux-Specific
```bash
# Check services
systemctl --failed
systemctl list-units --type=service --state=running

# Check logs
journalctl -xe -n 100
tail -100 /var/log/messages
```

### 5. Performance Validation

```bash
# Resource usage from OpenShift
oc adm top pod -n <namespace>

# Within VM - Linux
top
free -h
df -h
iostat -x 1 5

# Within VM - Windows
Get-Counter '\Processor(_Total)\% Processor Time'
Get-Counter '\Memory\Available MBytes'
```

### 6. Update DNS/Load Balancers

```bash
# Update DNS records to point to new IP
# Update load balancer pools
# Update monitoring/backup configurations

# Verify DNS propagation
nslookup <vm-hostname>
dig <vm-hostname>
```

---

## Rollback Procedures

### Scenario 1: Migration Fails During Transfer

```bash
# Check migration status
oc get plan <plan-name> -n openshift-mtv -o yaml

# Cancel migration
oc delete plan <plan-name> -n openshift-mtv

# Clean up any created resources
oc delete vm <vm-name> -n <namespace> --force --grace-period=0
oc delete pvc <vm-name>-disk-* -n <namespace>

# Source VM remains unchanged - power it back on if needed
```

### Scenario 2: VM Boots But Has Issues

```bash
# Stop the problematic VM
virtctl stop <vm-name> -n <namespace>

# Option A: Troubleshoot and fix (preferred)
# - Check logs: oc logs virt-launcher-<vm-name>-xxx
# - Fix network configuration via console
# - Install/update drivers

# Option B: Delete and re-migrate
oc delete vm <vm-name> -n <namespace>
# Recreate migration plan with fixes
# Re-run migration
```

### Scenario 3: Application Not Working

1. **Keep VM Running**: Troubleshoot application issues
2. **Revert DNS**: Point services back to source VM temporarily
3. **Fix Issues**: Install missing dependencies, fix configurations
4. **Test**: Validate application before switching back

### Critical Rollback Decision Points

| Time Since Migration | Rollback Complexity | Recommendation |
|---------------------|---------------------|----------------|
| < 1 hour | Simple | Can safely rollback, source unchanged |
| 1-4 hours | Moderate | Assess issue severity before rollback |
| > 4 hours | Complex | Fix forward unless critical issue |
| Production changes made to target | High | Cannot easily rollback |

---

## Troubleshooting

### Common Issues

#### Issue: Migration Plan Validation Fails

**Symptoms:**
```bash
oc get plan <plan-name> -n openshift-mtv
# Status: Not Ready / Validation Failed
```

**Resolution:**
```bash
# Check validation errors
oc describe plan <plan-name> -n openshift-mtv | grep -A 20 "Conditions:"

# Common causes:
# 1. Provider not connected
oc get provider -n openshift-mtv
oc describe provider <provider-name> -n openshift-mtv

# 2. Network mapping incorrect
oc get network-map -n openshift-mtv
oc get network-attachment-definition -A

# 3. Storage class not found
oc get sc

# 4. Source VM not found or powered on
# Verify VM name matches exactly in vCenter
```

#### Issue: Migration Stuck at "Disk Transfer"

**Symptoms:**
- Migration shows progress but very slow
- No errors but transfer takes excessive time

**Resolution:**
```bash
# 1. Check network connectivity
oc exec -it <migration-pod> -n openshift-mtv -- ping <esxi-host>

# 2. Check VPN/IPsec tunnel status
./diagnose-ipsec-vm.sh

# 3. Monitor bandwidth
oc logs -f <migration-pod> -n openshift-mtv | grep -i "transfer\|progress\|rate"

# 4. Check storage I/O
oc get pvc -n <namespace>
oc describe pvc <vm-disk-pvc> -n <namespace>

# 5. If truly stuck (no progress for 30+ min), consider canceling and restarting
```

#### Issue: VM Won't Boot After Migration

**Symptoms:**
```bash
oc get vmi <vm-name> -n <namespace>
# Status: Scheduling / CrashLoopBackOff
```

**Resolution:**
```bash
# 1. Check VM events
oc describe vmi <vm-name> -n <namespace>

# 2. Check virt-launcher logs
POD=$(oc get pod -n <namespace> -l vm.kubevirt.io/name=<vm-name> -o name)
oc logs -f $POD -n <namespace>

# 3. Common issues:
# - Insufficient resources
oc describe node <node-name>

# - Storage not bound
oc get pvc -n <namespace>

# - Network configuration
oc get network-attachment-definition -n <namespace>

# 4. Try starting with console access
virtctl start <vm-name> -n <namespace>
virtctl console <vm-name> -n <namespace>
```

#### Issue: Windows VM Network Not Working

**Symptoms:**
- VM boots but no network connectivity
- Network adapter showing as "Unknown Device"

**Resolution:**
```bash
# 1. VirtIO drivers not installed/recognized
# Access console: virtctl vnc <vm-name> -n <namespace>

# 2. Mount VirtIO ISO
oc patch vm <vm-name> -n <namespace> --type merge -p '
spec:
  template:
    spec:
      volumes:
      - name: virtio-drivers
        persistentVolumeClaim:
          claimName: virtio-drivers-iso-rwx
      domain:
        devices:
          disks:
          - name: virtio-drivers
            cdrom:
              bus: sata'

# 3. Restart VM and install drivers manually
virtctl restart <vm-name> -n <namespace>

# 4. Follow WINDOWS-VIRTIO-DRIVER-INSTALL.md guide
```

#### Issue: Linux VM Network Configuration Wrong

**Symptoms:**
- VM boots but has wrong IP or no network

**Resolution:**
```bash
# Access VM console
virtctl console <vm-name> -n <namespace>

# Check network configuration
ip addr show
cat /etc/sysconfig/network-scripts/ifcfg-eth0  # RHEL/CentOS
cat /etc/netplan/*.yaml  # Ubuntu

# Update configuration (RHEL example)
cat <<EOF | sudo tee /etc/sysconfig/network-scripts/ifcfg-eth0
TYPE=Ethernet
BOOTPROTO=static
NAME=eth0
DEVICE=eth0
ONBOOT=yes
IPADDR=10.1.128.x
NETMASK=255.255.255.0
GATEWAY=10.1.128.1
DNS1=10.1.128.2
EOF

# Restart networking
sudo nmcli connection reload
sudo nmcli connection up eth0
# Or: sudo systemctl restart NetworkManager

# Verify
ping 8.8.8.8
```

#### Issue: Storage Performance Issues

**Symptoms:**
- VM running but very slow disk I/O
- Applications timing out

**Resolution:**
```bash
# 1. Check Trident backend health
oc get tridentbackend -n trident
oc describe tridentbackend <backend-name> -n trident

# 2. Check PVC status
oc get pvc -n <namespace>
oc describe pvc <vm-disk-pvc> -n <namespace>

# 3. Check FSx ONTAP status (AWS Console or CLI)
aws fsx describe-file-systems --file-system-ids <fsxn-id>

# 4. Within VM, check for I/O errors
# Linux: dmesg | grep -i error
# Windows: Event Viewer > System logs

# 5. Consider storage class change for better performance
# Edit VM spec to use different storage class if available
```

---

## Appendix

### A. Required Tools and CLIs

```bash
# OpenShift CLI
oc version

# KubeVirt virtctl
virtctl version

# AWS CLI (for FSx management)
aws --version

# jq (for JSON processing)
jq --version
```

### B. Important Namespaces

| Namespace | Purpose |
|-----------|---------|
| `openshift-mtv` | MTV operator and migration plans |
| `openshift-cnv` | OpenShift Virtualization operator |
| `trident` | Trident CSI driver for storage |
| `vm-migrations` | Target namespace for migrated VMs |

### C. Key Configuration Files

```bash
# Current workspace files
ls -l *.md | grep -i migration
ls -l *.yaml | grep -i vm
ls -l *.sh | grep -i migration

# Important scripts:
# - inject-virtio-drivers.sh
# - update-vm-ips-automated.sh
# - validate-windows-test-vm.sh
# - diagnose-ipsec-vm.sh
```

### D. Reference Documentation

- [Red Hat MTV Documentation](https://access.redhat.com/documentation/en-us/migration_toolkit_for_virtualization/)
- [OpenShift Virtualization](https://docs.openshift.com/container-platform/latest/virt/about-virt.html)
- [Trident Documentation](https://docs.netapp.com/us-en/trident/)
- Workspace Quick References:
  - `CROSS-CLUSTER-MIGRATION-QUICKSTART.md`
  - `LINUX-NON-PROD-QUICKSTART.md`
  - `WINDOWS-TEST-VM-QUICKREF.md`

### E. Support Contacts and Escalation

```yaml
# Update with your team's contact information
L1_Support:
  - Team: Platform Engineering
  - Contact: platformeng@example.com
  - Hours: 24x7

L2_Support:
  - Team: OpenShift Architects
  - Contact: ocp-architects@example.com
  - Hours: Business hours

Vendor_Support:
  - Red Hat Support: https://access.redhat.com/support
  - AWS Support: Your TAM or support case
  - NetApp Support: For FSx ONTAP issues
```

### F. Migration Checklist Template

```markdown
## Migration Checklist: <VM-NAME>

### Pre-Migration
- [ ] VM inventory documented
- [ ] Network configuration planned (IP, DNS, GW)
- [ ] Storage requirements verified
- [ ] VirtIO drivers prepared (Windows)
- [ ] Migration plan created and validated
- [ ] Backup verified
- [ ] Change ticket approved
- [ ] Stakeholders notified

### Migration
- [ ] VPN connectivity confirmed
- [ ] Source VM powered off (cold migration)
- [ ] Migration initiated
- [ ] Disk transfer monitored
- [ ] Import completed successfully
- [ ] VM created in OpenShift

### Post-Migration
- [ ] VM powered on successfully
- [ ] Console access verified
- [ ] Network connectivity tested
- [ ] Drivers installed/verified (Windows)
- [ ] Services started
- [ ] Application validation passed
- [ ] Performance acceptable
- [ ] DNS/LB updated
- [ ] Monitoring configured
- [ ] Documentation updated
- [ ] Stakeholders notified

### Sign-off
- Migration Completed By: _______________
- Date/Time: _______________
- Validated By: _______________
- Issues/Notes: _______________
```

---

## Document Control

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-17 | Platform Team | Initial version |

**Review Schedule**: Quarterly or after major infrastructure changes

**Distribution**: Platform Engineering, Operations, Application Teams

---

*For questions or updates to this runbook, contact the OpenShift Platform Team.*
