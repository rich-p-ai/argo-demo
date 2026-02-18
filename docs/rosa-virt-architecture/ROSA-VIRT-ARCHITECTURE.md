# ROSA OpenShift Virtualization Architecture — vCenter-to-ROSA Migration with Site-to-Site VPN

**Document Version**: 2.0  
**Date**: February 17, 2026  
**Classification**: Internal — Architecture Design Document  
**Author**: OpenShift Platform Architecture Team  
**Status**: Approved for Implementation

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Goals and Assumptions](#2-architecture-goals-and-assumptions)
3. [Logical and Physical Architecture](#3-logical-and-physical-architecture)
4. [Network and Security Design](#4-network-and-security-design)
5. [Storage Design](#5-storage-design)
6. [Platform Services and Operators](#6-platform-services-and-operators)
7. [Migration Architecture — vCenter to ROSA Virt via MTV](#7-migration-architecture--vcenter-to-rosa-virt-via-mtv)
8. [Day-2 Operations](#8-day-2-operations)
9. [Risks, Constraints, and Mitigations](#9-risks-constraints-and-mitigations)
10. [Implementation Phases](#10-implementation-phases)
11. [Appendices](#11-appendices)

---

## 1. Executive Summary

This document defines the production-grade architecture for running virtual machine workloads on **Red Hat OpenShift Service on AWS (ROSA)** using **OpenShift Virtualization (KubeVirt)**. It covers end-to-end design from network connectivity (site-to-site IPsec VPN) through storage (FSx for NetApp ONTAP with Trident CSI), migration tooling (Migration Toolkit for Virtualization — MTV), and Day-2 operational patterns.

### Business Context

The organisation is migrating VM workloads from on-premises VMware vCenter/vSphere to ROSA-hosted OpenShift Virtualization. The migration reduces dependency on VMware licensing, consolidates infrastructure into a managed Kubernetes platform, and positions the organisation for future containerisation of legacy applications.

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Managed platform | ROSA (HCP or Classic, v4.18+) | AWS-managed control plane; reduced operational overhead |
| VM runtime | OpenShift Virtualization (KubeVirt) | Red Hat-supported, integrated with OCP lifecycle |
| Migration tool | MTV (Forklift) | Native vCenter-to-KubeVirt migration; Red Hat supported |
| VPN connectivity | Certificate-based S2S IPsec (Libreswan in-cluster VMs + AWS TGW) | NAT-friendly, no static EIP required, HA failover in ~5 s |
| VM overlay network | ClusterUserDefinedNetwork (CUDN) with IPAM disabled | Direct routable access to VMs from VPC without per-VM LBs |
| Storage | FSx for NetApp ONTAP (SAN + NAS) via Trident CSI | iSCSI block for VM disks, NFS for shared/RWX; snapshots, clones, expansion |
| Secrets management | External Secrets Operator → AWS Secrets Manager | Automated credential lifecycle; no manual secret rotation |
| GitOps | OpenShift GitOps (Argo CD) | Declarative cluster configuration; drift detection |

### Scope

- **In scope**: Non-prod and production ROSA clusters, Windows and Linux VM migration, S2S VPN, ONTAP SAN/NAS storage, monitoring, backup, DR patterns.
- **Out of scope**: Application-level refactoring to containers, multi-region DR (addressed as future-state guidance), custom hardware appliances.

---

## 2. Architecture Goals and Assumptions

### Goals

| ID | Goal | Measure of Success |
|----|------|--------------------|
| G1 | Migrate vCenter VMs to ROSA Virt with < 30 min downtime per VM (cold) | MTV plan completes; VM boots and passes validation checklist |
| G2 | Provide direct, routable network access to VMs from corporate networks | Bidirectional ping/TCP between on-prem hosts and CUDN VMs |
| G3 | Deliver enterprise storage with snapshot, clone, and expansion | Trident backends Bound; PVC operations < 15 s |
| G4 | Maintain HA for VPN gateway (< 10 s failover) | Keepalived failover test passes |
| G5 | Implement Day-2 automation (GitOps, monitoring, backup) | Argo CD apps healthy; alerts firing; OADP backups completing |

### Assumptions

| ID | Assumption | Impact if Invalid |
|----|------------|-------------------|
| A1 | ROSA cluster runs v4.18+ with bare-metal instance machine pool (`m5.metal` or `m5zn.metal`) | OpenShift Virtualization requires bare-metal workers for nested virt / KVM |
| A2 | AWS Transit Gateway (TGW) is available in the target region (us-east-1) | VPN termination requires TGW or VGW; architecture changes if unavailable |
| A3 | On-prem vCenter is reachable over VPN on ports 443 and 902 | MTV cannot pull disk images without vCenter/ESXi connectivity |
| A4 | FSx for NetApp ONTAP is provisioned in the ROSA VPC with iSCSI and NFS LIFs | Trident backends require network-reachable ONTAP endpoints |
| A5 | Non-overlapping CIDRs between VPC, CUDN, and on-prem networks | Routing breaks on overlap; CUDN CIDR must be unique |
| A6 | ACM Private CA is available for certificate-based VPN authentication | Cert-based auth eliminates PSK and static-IP dependencies |

### Constraints

| ID | Constraint |
|----|------------|
| C1 | ROSA does not expose underlying host networking (no Bridge/SR-IOV); CUDN + S2S VPN is the supported path for direct VM reachability |
| C2 | IPAM must be disabled on the CUDN to allow gateway VMs to forward traffic for other IPs; manual IP assignment required on every VM |
| C3 | ROSA STS mode requires IAM roles with scoped permissions; no long-lived access keys |
| C4 | `oc adm` operations are limited on ROSA; cluster-admin is via `rosa grant user` |

---

## 3. Logical and Physical Architecture

### 3.1 High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                               ON-PREMISES DATA CENTER                                   │
│                                                                                         │
│  ┌──────────────┐   ┌──────────────┐   ┌────────────────────────────────────┐           │
│  │   vCenter     │   │  ESXi Hosts  │   │  Corporate Network                │           │
│  │  (Source VMs) │   │  (VMDK disks)│   │  10.63.0.0/16, 10.68.0.0/16, ... │           │
│  └──────┬───────┘   └──────┬───────┘   └────────────────┬───────────────────┘           │
│         │ 443/tcp          │ 443,902/tcp                 │                               │
│         └──────────────────┴─────────────────────────────┘                               │
│                                        │                                                 │
│                              Corporate WAN / Router                                      │
│                                        │                                                 │
└────────────────────────────────────────┼─────────────────────────────────────────────────┘
                                         │ Internet / DX
                                         ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                              AWS REGION (us-east-1)                                    │
│                                                                                        │
│  ┌───────────────────────────────────────────────────────────────────────────────────┐  │
│  │                    TRANSIT GATEWAY  (tgw-041316428b4c331d0)                       │  │
│  │   ┌─────────────┐   ┌──────────────┐   ┌─────────────────────────────────┐       │  │
│  │   │ VPN Attach   │   │ VPC Attach   │   │ VPC Attach (Non-Prod)           │       │  │
│  │   │ (S2S IPsec)  │   │ (POC)        │   │ vpc-0e9f579449a68a005           │       │  │
│  │   └──────┬───────┘   └──────────────┘   └───────────────┬─────────────────┘       │  │
│  └──────────┼───────────────────────────────────────────────┼────────────────────────┘  │
│             │ IKE/ESP (UDP 500/4500)                        │                          │
│             ▼                                               ▼                          │
│  ┌────────────────────────────────────────────────────────────────────────────────┐    │
│  │                     ROSA VPC  (10.227.96.0/20)                                │    │
│  │                                                                                │    │
│  │  ┌─────────────────┐  ┌──────────────────┐  ┌──────────────────────────────┐  │    │
│  │  │ Private Subnet   │  │ Private Subnet    │  │ Private Subnet              │  │    │
│  │  │ AZ-a             │  │ AZ-b              │  │ AZ-c                        │  │    │
│  │  │ 10.227.97.0/24   │  │ 10.227.98.0/24   │  │ 10.227.99.0/24             │  │    │
│  │  │                  │  │                   │  │                             │  │    │
│  │  │  ┌────────────┐ │  │  ┌─────────────┐  │  │  ┌────────────────────┐    │  │    │
│  │  │  │ m5.metal   │ │  │  │ m5.metal    │  │  │  │ m5.metal           │    │  │    │
│  │  │  │ Worker     │ │  │  │ Worker      │  │  │  │ Worker             │    │  │    │
│  │  │  │ Node       │ │  │  │ Node        │  │  │  │ Node               │    │  │    │
│  │  │  └────────────┘ │  │  └─────────────┘  │  │  └────────────────────┘    │  │    │
│  │  └─────────────────┘  └──────────────────┘  └──────────────────────────────┘  │    │
│  │                                                                                │    │
│  │  ┌─────────────────────────────────────────────────────────────────────────┐   │    │
│  │  │            ROSA OCP Cluster (non-prod.5wp0.p3.openshiftapps.com)       │   │    │
│  │  │                                                                         │   │    │
│  │  │   ┌─────────────────────────────────────────────────────────────────┐   │   │    │
│  │  │   │  CUDN Overlay (vm-network)  — 10.227.128.0/21  (IPAM off)     │   │   │    │
│  │  │   │                                                                 │   │   │    │
│  │  │   │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────┐  │   │   │    │
│  │  │   │  │ ipsec-a  │ │ ipsec-b  │ │ nymsdv297│ │  nymsdv301 ...   │  │   │   │    │
│  │  │   │  │ Libreswan│ │ Libreswan│ │ Win VM   │ │  Win/Linux VMs   │  │   │   │    │
│  │  │   │  │.128.10   │ │.128.11   │ │.128.20   │ │  .128.21+        │  │   │   │    │
│  │  │   │  │ VIP: .1  │ │ standby  │ │          │ │                  │  │   │   │    │
│  │  │   │  └──────────┘ └──────────┘ └──────────┘ └──────────────────┘  │   │   │    │
│  │  │   └─────────────────────────────────────────────────────────────────┘   │   │    │
│  │  │                                                                         │   │    │
│  │  │   Operators: CNV │ MTV │ Trident │ GitOps │ ESO │ Monitoring            │   │    │
│  │  └─────────────────────────────────────────────────────────────────────────┘   │    │
│  │                                                                                │    │
│  │  ┌──────────────────────────────────────────────────────────────────────┐      │    │
│  │  │  FSx for NetApp ONTAP  (fs-0ed7b12fbd51c89ae)                      │      │    │
│  │  │  SVM: svm-nonprod │ iSCSI LIFs: 10.227.97.67, 10.227.102.138      │      │    │
│  │  │  Mgmt LIF: 198.19.180.139 │ NFS LIF: 198.19.180.139               │      │    │
│  │  └──────────────────────────────────────────────────────────────────────┘      │    │
│  └────────────────────────────────────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Logical Architecture Layers

| Layer | Components |
|-------|------------|
| **Connectivity** | AWS TGW, S2S VPN (cert-based CGW), NAT Gateway, Internet Gateway |
| **Cluster Platform** | ROSA managed control plane, bare-metal worker machine pool, OVN-Kubernetes SDN |
| **VM Overlay** | ClusterUserDefinedNetwork (CUDN) — `vm-network`, IPAM disabled, Libreswan IPsec gateway VMs, Keepalived HA |
| **Compute** | KubeVirt VirtualMachine / VirtualMachineInstance resources on bare-metal workers |
| **Storage** | FSx ONTAP → Trident CSI (ontap-san-economy for block, trident-csi for NFS) |
| **Migration** | MTV operator, vCenter Provider, StorageMap, NetworkMap, Plan, Migration CRDs |
| **Operations** | OpenShift GitOps (Argo CD), cluster monitoring (Prometheus/Alertmanager), logging (Loki/CLO), OADP backup, cert-manager, ESO |
| **Security** | IAM STS roles, SGs, NACLs, OCP RBAC, NetworkPolicies, SCCs, ACM PCA certs |

### 3.3 Physical Topology

| Resource | Specification |
|----------|--------------|
| **ROSA Cluster** | v4.18+, STS mode, multi-AZ (3 AZs), PrivateLink or public API |
| **Control Plane** | AWS-managed (ROSA); 3 masters across AZs (transparent) |
| **Worker Machine Pool** | `m5.metal` (96 vCPU, 384 GiB RAM) or `m5zn.metal`; minimum 3 nodes across AZs; autoscaling 3–6 |
| **Infra Machine Pool** | `m5.xlarge` (4 vCPU, 16 GiB); 3 nodes for monitoring, logging, ingress; optional |
| **FSx ONTAP** | Multi-AZ deployment, 2+ TiB SSD tier, auto-tiering to capacity pool; single SVM |
| **VPN** | AWS S2S VPN → TGW; 2 tunnels; Libreswan VMs inside cluster as CGW peer |

---

## 4. Network and Security Design

### 4.1 AWS VPC Layout

```
VPC: 10.227.96.0/20  (vpc-0e9f579449a68a005, "ROSA-Non-Prod")
│
├── Private Subnets (worker nodes, FSx endpoints)
│   ├── 10.227.97.0/24   — AZ us-east-1a
│   ├── 10.227.98.0/24   — AZ us-east-1b
│   └── 10.227.99.0/24   — AZ us-east-1c
│
├── Public Subnets (NAT GW, optional ALB)
│   ├── 10.227.100.0/24  — AZ us-east-1a
│   ├── 10.227.101.0/24  — AZ us-east-1b
│   └── 10.227.102.0/24  — AZ us-east-1c
│
└── Firewall / TGW Subnets (if using AWS Network Firewall)
    └── 10.227.103.0/28  — per AZ (optional)
```

**Routing summary**:

| Route Table | Destination | Target | Purpose |
|-------------|-------------|--------|---------|
| Private RT (per AZ) | 0.0.0.0/0 | NAT Gateway | Internet egress |
| Private RT (per AZ) | 10.227.128.0/21 (CUDN) | TGW | Traffic to VM overlay via VPN |
| Private RT (per AZ) | 10.63.0.0/16 (on-prem) | TGW | Traffic to corporate via VPN |
| Public RT | 0.0.0.0/0 | IGW | Inbound from internet |
| TGW RT | 10.227.128.0/21 | VPN attachment | CUDN reachable via IPsec |
| TGW RT | 10.227.96.0/20 | VPC attachment | VPC reachable from VPN |

### 4.2 ROSA Cluster Network CIDRs

| Network | CIDR | Description |
|---------|------|-------------|
| Machine Network | 10.227.96.0/20 | VPC CIDR; worker node primary IPs |
| Cluster Network (Pod) | 10.128.0.0/14 (default) | OVN-Kubernetes pod overlay; /23 per node |
| Service Network | 172.30.0.0/16 (default) | ClusterIP services |
| CUDN (VM Network) | 10.227.128.0/21 | User-defined overlay for VM workloads; IPAM disabled |

> **Critical**: The CUDN CIDR must not overlap with the VPC CIDR, on-prem CIDRs, or the cluster/service networks.

### 4.3 VPN Topology and Traffic Flows

```
   On-Premises                           AWS
┌──────────────┐                  ┌──────────────────────────────────────────┐
│  Corporate   │   Internet /    │            Transit Gateway                │
│  Router      │──── DX ────────▶│  ┌─────────┐        ┌─────────┐         │
│  (CGW peer)  │                 │  │ Tunnel 1 │        │ Tunnel 2 │         │
│              │                 │  │ 3.232.   │        │ 98.94.   │         │
│              │                 │  │ 27.186   │        │ 136.2    │         │
└──────────────┘                 │  └────┬─────┘        └────┬─────┘         │
                                 │       │     VPN Attach     │              │
                                 │       └────────┬───────────┘              │
                                 │                │                          │
                                 │         ┌──────▼──────┐                   │
                                 │         │  TGW Route   │                  │
                                 │         │  Table       │                  │
                                 │         └──────┬───────┘                  │
                                 │                │                          │
                                 │       ┌────────▼─────────────┐            │
                                 │       │    VPC Attach         │           │
                                 │       │    (Non-Prod VPC)     │           │
                                 │       └────────┬──────────────┘           │
                                 └────────────────┼──────────────────────────┘
                                                  │
                                                  ▼
                                 ┌───────────────────────────────┐
                                 │   ROSA VPC Private Subnets    │
                                 │   (Worker Nodes)              │
                                 │                               │
                                 │   Worker → NAT GW → Internet  │
                                 │   │                           │
                                 │   ▼                           │
                                 │   ┌─────────────────────┐    │
                                 │   │  ipsec-a VM          │    │
                                 │   │  eth0: pod network   │    │
                                 │   │  eth1: CUDN          │    │
                                 │   │  10.227.128.10       │    │
                                 │   │  VIP: 10.227.128.1   │    │
                                 │   │                      │    │
                                 │   │  IKE/ESP → NAT GW    │    │
                                 │   │  → AWS Tunnel EIPs    │    │
                                 │   └─────────────────────┘    │
                                 │            ↕ CUDN overlay     │
                                 │   ┌─────────────────────┐    │
                                 │   │  Workload VMs        │    │
                                 │   │  10.227.128.20+      │    │
                                 │   │  next-hop: .128.1    │    │
                                 │   └─────────────────────┘    │
                                 └───────────────────────────────┘
```

**Traffic flow: On-prem host → VM in ROSA**

1. On-prem host sends packet to `10.227.128.20` (CUDN VM IP).
2. Corporate router routes `10.227.128.0/21` via VPN tunnel to AWS TGW.
3. TGW routes `10.227.128.0/21` → VPN attachment → IPsec tunnel → Libreswan VM.
4. Libreswan VM decapsulates ESP, forwards on CUDN interface (eth1) to `10.227.128.20`.

**Traffic flow: VM in ROSA → On-prem host**

1. VM sends packet to `10.63.x.x`; static route points next-hop to VIP `10.227.128.1`.
2. Active ipsec VM (holding VIP via Keepalived) receives packet on eth1.
3. Libreswan matches policy, encapsulates in ESP, sends via eth0 → NAT GW → AWS tunnel EIP → TGW → on-prem.

### 4.4 VPN Design Details

| Parameter | Value |
|-----------|-------|
| **VPN Connection** | `vpn-059ee0661e851adf4` |
| **Customer Gateway** | `cgw-0f82cc789449111b7` (cert-based, no static IP) |
| **Transit Gateway** | `tgw-041316428b4c331d0` |
| **Authentication** | Certificate (ACM PCA — root CA + subordinate CA) |
| **IKE Version** | IKEv2 recommended (IKEv1 supported for backward compat) |
| **Phase 1** | AES-128, SHA-1, MODP1536 (DH Group 5) minimum |
| **Phase 2 (ESP)** | AES-128-SHA1, MODP1536, 3600 s SA lifetime |
| **Tunnel count** | 2 (one per AWS endpoint); ECMP optional with VTI |
| **DPD** | 10 s delay, 30 s timeout, restart action |
| **In-cluster peer** | Libreswan 4.15 on CentOS Stream 10 VM (`ipsec-a`, `ipsec-b`) |
| **HA** | Keepalived VRRP; VIP `10.227.128.1` floats between ipsec-a and ipsec-b |
| **Failover time** | ~5 seconds |
| **Left subnet** | `10.227.128.0/21` (CUDN) |
| **Right subnets** | `10.63.0.0/16`, `10.68.0.0/16`, `10.99.0.0/16`, `10.110.0.0/16`, `10.140.0.0/16`, `10.141.0.0/16`, `10.158.0.0/16` |

**AWS DH Group caveat**: AWS defaults to MODP1024 (DH Group 2). Libreswan 4.15+ rejects MODP1024. Use `modify-vpn-tunnel-options` to set DH groups 5, 14 (and optionally 15, 16).

### 4.5 DNS Strategy

| Zone | Service | Resolution Path |
|------|---------|-----------------|
| `corp.cusa.canon.com` (on-prem) | On-prem AD DNS | ROSA → conditional forwarder via CoreDNS Corefile customisation → on-prem DNS over VPN |
| `*.openshiftapps.com` (ROSA API/apps) | Route 53 public hosted zone (ROSA-managed) | External clients resolve via public DNS |
| `svc.cluster.local` | CoreDNS (in-cluster) | Pod/Service discovery, internal only |
| `*.fsx.us-east-1.amazonaws.com` (FSx) | Route 53 Resolver inbound endpoint or VPC DNS | Worker nodes resolve via VPC DHCP options |
| VM hostname resolution | Option A: Register VMs in on-prem DNS via VPN; Option B: Route 53 private hosted zone | Depends on whether VMs keep corporate FQDNs post-migration |

**CoreDNS forward plugin** (for on-prem domain resolution):

```yaml
apiVersion: operator.openshift.io/v1
kind: DNS
metadata:
  name: default
spec:
  servers:
    - name: corp-forward
      zones:
        - corp.cusa.canon.com
      forwardPlugin:
        upstreams:
          - 10.63.x.x    # On-prem DNS server (reachable over VPN)
          - 10.63.x.y
        policy: Random
        transportConfig:
          transport: Cleartext
```

### 4.6 Ingress Strategy

| Traffic Type | Mechanism | Notes |
|-------------|-----------|-------|
| OCP API (cluster admin) | ROSA-managed NLB or PrivateLink | Private API endpoint recommended for production |
| OCP Routes (*.apps) | ROSA default Ingress Controller (NLB) | Public or private based on cluster config |
| Direct VM access (SSH/RDP/app ports) | S2S VPN → CUDN (routable) | No LB needed per VM; corporate tools work unmodified |
| VM HTTP services | OCP Route or Service (NodePort/LoadBalancer) | Optional; depends on whether app needs external exposure |
| `virtctl ssh/vnc/console` | Kubernetes API (RBAC-gated) | For admin access; no VPN dependency |

### 4.7 Security Controls

#### 4.7.1 IAM (AWS)

| Role | Purpose |
|------|---------|
| ROSA Installer role | Cluster provisioning and lifecycle |
| ROSA Control Plane role | Managed control plane operations |
| ROSA Worker role (instance profile) | EC2, EBS, ECR access for workers |
| Trident IAM role | FSx ONTAP API calls (if IRSA used) |
| ESO IAM role (IRSA) | Read from AWS Secrets Manager |

All roles use STS (short-lived tokens). No long-lived AWS credentials stored on-cluster.

#### 4.7.2 Security Groups

| SG | Inbound Rules |
|----|---------------|
| Worker SG | CUDN CIDR (`10.227.128.0/21`) → ICMP, TCP 22, TCP 80, TCP 443 |
| Worker SG | On-prem CIDRs → TCP 443, TCP 6443 (if cross-cluster MTV) |
| FSx SG | VPC CIDR → TCP 443 (mgmt), TCP 3260 (iSCSI), TCP 2049 (NFS), TCP 111 (portmapper) |
| TGW / VPN | Managed by AWS; no explicit SG (tunnels terminate at TGW) |

#### 4.7.3 NACLs

Allow ICMP and required TCP/UDP between CUDN CIDR (`10.227.128.0/21`) and VPC subnets bidirectionally. Default NACLs allow all; tighten per security policy.

#### 4.7.4 OCP Security

| Control | Implementation |
|---------|----------------|
| RBAC | Namespace-scoped roles; `cluster-admin` via `rosa grant`; MTV service account with vCenter credentials |
| NetworkPolicy | Default deny in VM namespaces; allow MTV controller traffic, monitoring scrape, DNS |
| SecurityContextConstraints | `privileged` SCC for Trident node pods and ipsec VMs (requires `net.ipv4.ip_forward`, raw sockets) |
| Pod Security Admission | `restricted` baseline; exemptions for `trident`, `openshift-cnv`, `openshift-mtv` namespaces |
| Egress controls | EgressNetworkPolicy or NetworkPolicy egress rules to restrict VM outbound to approved CIDRs |

#### 4.7.5 Certificate Management

| Certificate | Managed By | Rotation |
|-------------|-----------|----------|
| VPN device cert | ACM PCA (subordinate CA) | Auto-renew via ACM; re-export PKCS#12 to VMs |
| ROSA API / Ingress TLS | ROSA-managed (Let's Encrypt or custom) | Automatic |
| Internal cluster CA | OCP service-ca-operator | Automatic (13-month rotation) |
| Custom app certs | cert-manager + Let's Encrypt or internal CA | CertificateRequest CRDs |

---

## 5. Storage Design

### 5.1 Storage Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                       FSx for NetApp ONTAP                          │
│               fs-0ed7b12fbd51c89ae  (Multi-AZ)                      │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  SVM: svm-nonprod  (svm-06457f84b785fb321)                   │  │
│  │                                                               │  │
│  │  Management LIF ─── 198.19.180.139  (TCP 443)                │  │
│  │  NFS Data LIF ───── 198.19.180.139  (TCP 2049)               │  │
│  │  iSCSI LIFs:                                                  │  │
│  │    AZ-a: 10.227.97.67   (TCP 3260)                           │  │
│  │    AZ-b: 10.227.102.138 (TCP 3260)                           │  │
│  │                                                               │  │
│  │  Aggregates:  SSD (primary)  →  Capacity Pool (auto-tier)    │  │
│  └───────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────┬──────────────────────────────────┘
                                   │
                    iSCSI (block) / NFS (file)
                                   │
┌──────────────────────────────────▼──────────────────────────────────┐
│                    Trident CSI Driver (v24.10+)                      │
│                    Namespace: trident                                │
│                                                                     │
│  ┌──────────────────────┐   ┌───────────────────────────────┐      │
│  │ Backend: NAS          │   │ Backend: SAN Economy           │      │
│  │ fsx-ontap-nas-nonprod │   │ fsx-san-nonprod                │      │
│  │ Driver: ontap-nas     │   │ Driver: ontap-san-economy      │      │
│  │ Protocol: NFS         │   │ Protocol: iSCSI                │      │
│  │ Use: RWX shares,      │   │ Use: VM boot/data disks,       │      │
│  │      shared config    │   │      block PVCs                 │      │
│  └──────────────────────┘   └───────────────────────────────┘      │
└──────────────────────────────────┬──────────────────────────────────┘
                                   │
                    PersistentVolume (CSI)
                                   │
┌──────────────────────────────────▼──────────────────────────────────┐
│                    Storage Classes                                   │
│                                                                     │
│  ┌───────────────────────────┐  ┌────────────────────────────────┐ │
│  │ ontap-san-economy         │  │ trident-csi                    │ │
│  │ (DEFAULT)                 │  │                                │ │
│  │ volumeMode: Block         │  │ volumeMode: Filesystem         │ │
│  │ accessModes: RWO          │  │ accessModes: RWO, RWX          │ │
│  │ fstype: ext4              │  │ fstype: nfs                    │ │
│  │ reclaimPolicy: Delete     │  │ reclaimPolicy: Delete          │ │
│  │ allowVolumeExpansion: true│  │ allowVolumeExpansion: true     │ │
│  └───────────────────────────┘  └────────────────────────────────┘ │
└──────────────────────────────────┬──────────────────────────────────┘
                                   │
                    PVC binding
                                   │
┌──────────────────────────────────▼──────────────────────────────────┐
│            OpenShift Virtualization VM Disks                         │
│                                                                     │
│  VirtualMachine:                                                    │
│    spec.dataVolumeTemplates:                                        │
│      - name: rootdisk                                               │
│        spec:                                                        │
│          storage:                                                    │
│            storageClassName: ontap-san-economy                       │
│            accessModes: [ReadWriteOnce]                              │
│            volumeMode: Block                                         │
│            resources:                                                │
│              requests:                                               │
│                storage: 60Gi                                         │
│          source:                                                     │
│            pvc:   # or http/registry for base images                 │
│              name: imported-disk-from-mtv                            │
│              namespace: vm-migrations                                │
│                                                                     │
│  VirtIO Drivers ISO:                                                │
│    PVC: virtio-drivers-iso-rwx                                      │
│    StorageClass: trident-csi (NFS, RWX)                             │
│    Mounted as CDROM to Windows VMs                                  │
└─────────────────────────────────────────────────────────────────────┘
```

### 5.2 CSI Driver: Trident

**Choice rationale**: NetApp Trident is the only CSI driver certified for FSx for NetApp ONTAP. It supports both `ontap-nas` (NFS) and `ontap-san` / `ontap-san-economy` (iSCSI) backends from a single operator.

**Installation**: Trident Operator via Helm or OperatorHub. Deployed in namespace `trident`.

### 5.3 Storage Classes

| Storage Class | Driver | Protocol | Access Modes | Volume Mode | Use Case |
|--------------|--------|----------|--------------|-------------|----------|
| `ontap-san-economy` (default) | ontap-san-economy | iSCSI | RWO | Block | VM boot disks, data disks, database volumes |
| `trident-csi` | ontap-nas | NFS | RWO, RWX | Filesystem | Shared config, VirtIO ISO, log aggregation, RWX needs |
| `gp3-csi` (AWS default) | ebs.csi.aws.com | EBS | RWO | Filesystem | Non-VM workloads (monitoring PVs, etcd if exposed) |

### 5.4 Backend Configurations

**SAN Economy Backend** (`backend-fsx-san-nonprod`):

```yaml
apiVersion: trident.netapp.io/v1
kind: TridentBackendConfig
metadata:
  name: backend-fsx-san-nonprod
  namespace: trident
spec:
  version: 1
  backendName: fsx-san-nonprod
  storageDriverName: ontap-san-economy
  managementLIF: svm-06457f84b785fb321.fs-0ed7b12fbd51c89ae.fsx.us-east-1.amazonaws.com
  dataLIF: iscsi.svm-06457f84b785fb321.fs-0ed7b12fbd51c89ae.fsx.us-east-1.amazonaws.com
  svm: svm-nonprod
  credentials:
    name: backend-fsx-ontap-secret
  igroupName: trident
  defaults:
    spaceReserve: none
    encryption: "false"
    snapshotPolicy: default
    snapshotReserve: "5"
```

**NAS Backend** (`backend-fsx-ontap-nas`):

```yaml
apiVersion: trident.netapp.io/v1
kind: TridentBackendConfig
metadata:
  name: backend-fsx-ontap-nas
  namespace: trident
spec:
  version: 1
  backendName: fsx-ontap-nas-nonprod
  storageDriverName: ontap-nas
  managementLIF: svm-06457f84b785fb321.fs-0ed7b12fbd51c89ae.fsx.us-east-1.amazonaws.com
  dataLIF: svm-06457f84b785fb321.fs-0ed7b12fbd51c89ae.fsx.us-east-1.amazonaws.com
  svm: svm-nonprod
  credentials:
    name: backend-fsx-ontap-secret
  defaults:
    spaceReserve: none
    encryption: "false"
    snapshotPolicy: default
    snapshotReserve: "5"
    exportPolicy: default
```

### 5.5 VM Disk Access Modes and Volume Modes

| Scenario | Access Mode | Volume Mode | Storage Class | Notes |
|----------|-------------|-------------|---------------|-------|
| VM boot disk (no live migration) | RWO | Block | ontap-san-economy | Standard for single-node scheduling |
| VM boot disk (live migration) | **RWX** | **Block** | Requires ontap-san (not economy) or NFS | Economy driver uses LUN-in-FlexVol sharing; RWX block requires `ontap-san` driver or NFS with block emulation |
| VM data disk (database) | RWO | Block | ontap-san-economy | Dedicated LUN per PVC |
| Shared ISO / config | RWX | Filesystem | trident-csi (NFS) | VirtIO ISO, cloud-init NoCloud |

### 5.6 Live Migration Storage Impact

OpenShift Virtualization live migration requires the VM disk PVC to be accessible from both source and destination nodes simultaneously. This means:

- **RWX Block** is required for VM disks during live migration.
- `ontap-san-economy` (LUN-sharing in a FlexVol) does **not** support RWX block.
- **Options for live migration**:
  1. Use `ontap-san` driver (dedicated FlexVol per LUN) with multi-attach — requires ONTAP 9.12+ and Trident 23.07+ with `sanType: iscsi` and `lunsPerFlexvol: 1`.
  2. Use `ontap-nas` with `volumeMode: Block` (NFS-backed block device) — simplest path for RWX block on ONTAP.
  3. Accept that VMs on `ontap-san-economy` cannot live migrate (cold migration / restart only).

**Recommendation**: Use `ontap-san-economy` for non-prod (no live migration requirement); create an additional `ontap-san` backend with RWX support for production VMs that require live migration.

### 5.7 Snapshot, Clone, and Expansion

| Feature | SAN Economy | NAS | Notes |
|---------|-------------|-----|-------|
| Volume Expansion | Yes | Yes | `allowVolumeExpansion: true` on StorageClass |
| VolumeSnapshot | Yes (Trident VolumeSnapshotClass) | Yes | ONTAP snapshot; near-instant, space-efficient |
| Clone (from PVC) | Yes | Yes | ONTAP FlexClone; used by MTV for disk import |
| Clone (from Snapshot) | Yes | Yes | Restore point-in-time |

**VolumeSnapshotClass**:

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: trident-snapshotclass
driver: csi.trident.netapp.io
deletionPolicy: Delete
```

### 5.8 Topology and Failure Domains

FSx for NetApp ONTAP in multi-AZ mode provides automatic failover between AZs. iSCSI LIFs are distributed across AZs:

| AZ | iSCSI LIF |
|----|-----------|
| us-east-1a | 10.227.97.67 |
| us-east-1b | 10.227.102.138 |

Trident automatically handles multipath I/O. Worker nodes in each AZ connect to the nearest iSCSI LIF. On FSx failover (standby → active), iSCSI sessions reconnect transparently.

**Topology labels** are not strictly required for FSx ONTAP (it handles HA internally) but can be set on StorageClass for workload-aware scheduling:

```yaml
allowedTopologies:
  - matchLabelExpressions:
      - key: topology.kubernetes.io/zone
        values:
          - us-east-1a
          - us-east-1b
```

---

## 6. Platform Services and Operators

### 6.1 Operator Matrix

| Operator / Component | Namespace | Why Needed | Key Config | ROSA Caveats | Dependencies |
|----------------------|-----------|------------|------------|--------------|--------------|
| **OpenShift Virtualization** | `openshift-cnv` | Run VMs (KubeVirt) on OCP | HyperConverged CR; `m5.metal` workers; enable live migration, UEFI boot | Bare-metal instance pool required; no nested virt on non-metal | None (core) |
| **Migration Toolkit for Virtualization (MTV)** | `openshift-mtv` | Migrate VMs from vCenter to KubeVirt | ForkliftController CR; Provider (vCenter + host); NetworkMap; StorageMap | Requires vCenter reachable from cluster (over VPN) | OpenShift Virtualization, Trident |
| **Trident CSI (NetApp)** | `trident` | Provision PVCs on FSx ONTAP (iSCSI + NFS) | TridentOrchestrator CR; TridentBackendConfig (SAN + NAS); credentials Secret | Worker SG must allow iSCSI (3260) and NFS (2049) to FSx | FSx ONTAP provisioned; credentials secret |
| **OpenShift GitOps (Argo CD)** | `openshift-gitops` | Declarative cluster config, operator deployment, drift detection | ArgoCD CR; ApplicationSets for cluster-config repo | ROSA-managed operators may conflict; use `ignoreDifferences` for managed resources | Git repo (GitLab/GitHub) |
| **External Secrets Operator (ESO)** | `external-secrets` | Sync secrets from AWS Secrets Manager → OCP Secrets | ClusterSecretStore (AWS SM); ExternalSecret per secret | IAM role via IRSA/STS for SM access | AWS Secrets Manager; IAM role |
| **Cluster Logging (Loki + CLO)** | `openshift-logging` | Aggregate VM, pod, and audit logs | ClusterLogForwarder → Loki (or Splunk/ELK); LokiStack for in-cluster | ROSA ships with CloudWatch integration; CLO optional overlay | S3 bucket (for Loki storage) |
| **Cluster Monitoring** | `openshift-monitoring` (built-in) | Prometheus, Alertmanager, Grafana dashboards for VMs and cluster | UserWorkloadMonitoring enabled; custom PrometheusRules for VM alerts | ROSA manages core monitoring; user-workload monitoring is opt-in | None (built-in) |
| **OADP (OpenShift API for Data Protection)** | `openshift-adp` | Backup/restore VMs, namespaces, PVCs | DataProtectionApplication CR; Velero + Restic; S3 target; VolumeSnapshotLocation for Trident | OADP v1.4+; CSI snapshots via Trident VolumeSnapshotClass | S3 bucket; Trident VolumeSnapshotClass |
| **cert-manager** | `cert-manager` | Automate TLS certificate lifecycle for apps, ingress | ClusterIssuer (Let's Encrypt / internal CA); Certificate CRDs | Not bundled with ROSA; install via OLM or Helm | Issuer (ACME / CA) |
| **NMState Operator** | `openshift-nmstate` | Declarative node network config (if needed for secondary NICs) | NodeNetworkConfigurationPolicy CRDs | Limited on ROSA (managed nodes); primarily useful for advanced bonding | None |
| **Kubernetes NMState** | (via CNV) | Node network state reporting | Auto-deployed with CNV | Read-only on ROSA unless advanced config needed | OpenShift Virtualization |
| **Multus CNI** | `openshift-multus` (built-in) | Attach VMs to multiple networks (CUDN) | NetworkAttachmentDefinition (auto-created by CUDN) | Built into OCP; CUDN leverages Multus for secondary NIC | OVN-Kubernetes |
| **External DNS** (optional) | `external-dns` | Auto-register VM/Service DNS records in Route 53 | ExternalDNS CR targeting Route 53 hosted zone | Requires IAM role for Route 53 access | Route 53 hosted zone; IAM role |
| **AWS Secrets Manager CSI** (alternative to ESO) | `kube-system` | Mount SM secrets as volumes | SecretProviderClass CRDs | Alternative to ESO; less flexible for K8s Secret sync | AWS SM; IAM role |
| **Kyverno / OPA Gatekeeper** | `kyverno` or `gatekeeper-system` | Policy enforcement (require labels, restrict SCC, enforce resource limits) | ClusterPolicy CRDs (Kyverno) or ConstraintTemplate (Gatekeeper) | Kyverno preferred for simplicity; Gatekeeper for OPA-based orgs | None |
| **Compliance Operator** | `openshift-compliance` | CIS / NIST scan profiles; remediation | ScanSetting + ScanSettingBinding; ComplianceScan CRDs | ROSA-specific profile available | None |

### 6.2 Operator Installation Order

1. **OpenShift Virtualization** — prerequisite for VMs
2. **Trident CSI** — prerequisite for storage
3. **OpenShift GitOps** — manages remaining operators declaratively
4. **ESO** — provides secrets for Trident, MTV, etc.
5. **MTV** — requires CNV + storage + secrets
6. **OADP** — requires storage (S3 + CSI snapshots)
7. **Logging, Monitoring enhancements, cert-manager, policy** — Day-2

---

## 7. Migration Architecture — vCenter to ROSA Virt via MTV

### 7.1 Migration Flow Diagram

```
┌──────────────────────────────────────────────────────────────────────────┐
│                        MIGRATION WORKFLOW                                │
│                                                                          │
│  ┌──────────┐    ┌───────────┐    ┌──────────┐    ┌─────────────────┐  │
│  │ 1. PREP  │───▶│ 2. PLAN   │───▶│ 3. EXEC  │───▶│ 4. VALIDATE    │  │
│  │          │    │           │    │          │    │                 │  │
│  │ Provider │    │ NetworkMap│    │ Disk     │    │ Boot VM         │  │
│  │ Creds    │    │ StorageMap│    │ Transfer │    │ Network test    │  │
│  │ NS/RBAC  │    │ Plan CR   │    │ Import   │    │ App validation  │  │
│  │ VirtIO   │    │ Validate  │    │ Convert  │    │ DNS cutover     │  │
│  └──────────┘    └───────────┘    └──────────┘    └─────────────────┘  │
│       │                │                │                  │             │
│       ▼                ▼                ▼                  ▼             │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                    ROLLBACK PATH                                 │   │
│  │  Cancel plan → Delete VM/PVCs → Power on source VM → Revert DNS │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────┘

Data flow during disk transfer:

  vCenter (443) ──── VMware VDDK ────▶ MTV Controller Pod
       │                                     │
  ESXi (443,902) ── NBDSSL ──────────▶ Disk Transfer Pod
       │                                     │
       │              (over VPN)              ▼
       │                              PVC (Trident CSI)
       │                              ontap-san-economy
       │                                     │
       └─────────── Network Path ────────────┘
            On-prem ↔ VPN ↔ TGW ↔ VPC ↔ ROSA Pod Network
```

### 7.2 Prerequisites

| Prerequisite | Detail |
|-------------|--------|
| **VPN connectivity** | Bidirectional: ROSA pods must reach vCenter (443/tcp) and ESXi hosts (443, 902/tcp) over VPN |
| **vCenter credentials** | Service account with read-only access to inventory + VM disks; stored as OCP Secret |
| **vCenter CA cert** | If vCenter uses self-signed cert, import CA into MTV provider config |
| **RBAC** | MTV operator service account needs cluster-admin or scoped roles; migration user needs edit on target namespace |
| **Target namespace** | Pre-created with ResourceQuota, LimitRange, NetworkPolicy |
| **Storage classes** | `ontap-san-economy` (default) and `trident-csi` available and backends Bound |
| **CUDN** | `vm-network` ClusterUserDefinedNetwork deployed with IPAM disabled |
| **VirtIO drivers** | For Windows VMs: `virtio-drivers-iso-rwx` PVC (RWX NFS) pre-populated |

### 7.3 Provider Setup

**vCenter Provider** (source):

```yaml
apiVersion: forklift.konveyor.io/v1beta1
kind: Provider
metadata:
  name: vcenter-source
  namespace: openshift-mtv
spec:
  type: vsphere
  url: https://vcenter.corp.cusa.canon.com/sdk
  secret:
    name: vcenter-credentials
    namespace: openshift-mtv
```

**Host Provider** (destination — built-in):

```yaml
apiVersion: forklift.konveyor.io/v1beta1
kind: Provider
metadata:
  name: host
  namespace: openshift-mtv
spec:
  type: openshift
  url: https://api.non-prod.5wp0.p3.openshiftapps.com:6443
  # 'host' provider auto-detects local cluster
```

### 7.4 Network Mapping

```yaml
apiVersion: forklift.konveyor.io/v1beta1
kind: NetworkMap
metadata:
  name: vmware-to-rosa-netmap
  namespace: openshift-mtv
spec:
  provider:
    source:
      name: vcenter-source
      namespace: openshift-mtv
    destination:
      name: host
      namespace: openshift-mtv
  map:
    - source:
        name: VM Network        # VMware port group name
        type: network
      destination:
        name: vm-network         # CUDN NAD name
        namespace: vpn-infra     # or target namespace
        type: multus
```

### 7.5 Storage Mapping

```yaml
apiVersion: forklift.konveyor.io/v1beta1
kind: StorageMap
metadata:
  name: vmware-to-ontap-stormap
  namespace: openshift-mtv
spec:
  provider:
    source:
      name: vcenter-source
      namespace: openshift-mtv
    destination:
      name: host
      namespace: openshift-mtv
  map:
    - source:
        name: datastore1          # VMware datastore name
      destination:
        storageClass: ontap-san-economy
        accessMode: ReadWriteOnce
        volumeMode: Block
```

### 7.6 Migration Plan

```yaml
apiVersion: forklift.konveyor.io/v1beta1
kind: Plan
metadata:
  name: wave0-dev-vms
  namespace: openshift-mtv
spec:
  provider:
    source:
      name: vcenter-source
      namespace: openshift-mtv
    destination:
      name: host
      namespace: openshift-mtv
  targetNamespace: windows-non-prod
  warm: false
  map:
    network:
      name: vmware-to-rosa-netmap
      namespace: openshift-mtv
    storage:
      name: vmware-to-ontap-stormap
      namespace: openshift-mtv
  vms:
    - id: vm-1234          # vCenter MoRef ID for nymsdv297
      name: nymsdv297
    - id: vm-1235
      name: nymsdv301
    - id: vm-1236
      name: nymsdv351
```

### 7.7 Migration Execution Stages

| Stage | Duration (typical) | What Happens |
|-------|-------------------|--------------|
| **Validation** | 1–2 min | Plan CRD validated; provider connectivity checked; mappings verified |
| **DiskTransfer** | 15 min – 2+ hrs | VDDK/NBDSSL streams VMDK data over VPN to importer pod; writes to PVC via Trident |
| **Import** | 5–10 min | VM definition (CPU, memory, NICs, disks) converted to KubeVirt VirtualMachine CR |
| **VirtIOConversion** | 2–5 min (Linux) | virt-v2v converts disk images (drivers, boot loader) for KVM compatibility |
| **Complete** | — | VM ready to start; Plan status = `Succeeded` |

### 7.8 Cutover Patterns

| Pattern | Downtime | When to Use |
|---------|----------|-------------|
| **Cold migration** | Full (disk transfer + conversion) | Non-prod, batch migrations, VMs that can tolerate hours of downtime |
| **Warm migration** | Minimal (final incremental sync + conversion) | Production VMs requiring < 30 min downtime |
| **Staged migration** | Planned window | Pre-copy disk days ahead; final cutover in maintenance window |

### 7.9 Rollback

1. **During transfer**: Delete the Plan CR. PVCs and partial VMs are garbage-collected. Source VM untouched.
2. **After conversion**: Delete the VirtualMachine CR and associated PVCs. Power on source VM. Revert DNS.
3. **After validation**: If the migrated VM is functional but has issues, keep it stopped while troubleshooting. Source VM remains available as fallback.

**Rollback decision matrix**:

| Time Since Cutover | Complexity | Action |
|--------------------|-----------|--------|
| < 1 hour | Low | Revert DNS, power on source |
| 1–4 hours | Medium | Assess severity; prefer fix-forward |
| > 4 hours / data written to target | High | Fix-forward unless critical |

### 7.10 Common Failure Modes

| Failure | Symptom | Resolution |
|---------|---------|------------|
| VPN down during transfer | Migration stalls at DiskTransfer | Check `ipsec status` on gateway VMs; verify Keepalived VIP; check AWS tunnel status |
| vCenter auth failure | Provider status `NotReady` | Verify credentials Secret; test `curl -k https://vcenter/sdk` from a pod |
| Storage backend offline | PVC stuck in `Pending` | Check `oc get tridentbackendconfig -n trident -o wide`; verify FSx credentials |
| Disk too large for economy LUN pool | PVC provision fails | Check FlexVol capacity; expand FlexVol or use dedicated `ontap-san` backend |
| Windows VM no network | VM boots, NIC shows "Unknown" | VirtIO drivers not present; mount `virtio-drivers-iso-rwx` as CDROM; install drivers |
| ESXi 902/tcp blocked | NBDSSL transfer fails | Verify VPN routes include ESXi host subnet; check SG/NACL for 902/tcp |

---

## 8. Day-2 Operations

### 8.1 Monitoring

| What | Tool | Config |
|------|------|--------|
| Cluster health | Built-in Prometheus + Alertmanager | `openshift-monitoring`; enable UserWorkloadMonitoring |
| VM metrics | KubeVirt metrics exporter (bundled with CNV) | CPU, memory, disk I/O, network per VMI |
| Trident storage | Trident Prometheus metrics (`/metrics` endpoint) | Backend status, provisioning latency, IOPS |
| VPN health | Custom PrometheusRule + blackbox-exporter | Probe VPN tunnel endpoints; alert on down > 60 s |
| FSx ONTAP | CloudWatch (AWS-side) | Throughput, IOPS, latency; alarm on > 80% capacity |

**Example alert — VPN tunnel down**:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: vpn-tunnel-alerts
  namespace: openshift-monitoring
spec:
  groups:
    - name: vpn.rules
      rules:
        - alert: VPNTunnelDown
          expr: probe_success{job="vpn-tunnel-probe"} == 0
          for: 2m
          labels:
            severity: critical
          annotations:
            summary: "S2S VPN tunnel is down"
            description: "IPsec tunnel has been unreachable for > 2 minutes. Check ipsec-a/b VMs and AWS VPN console."
```

### 8.2 Logging

| Log Source | Collector | Destination |
|-----------|-----------|-------------|
| Container / pod logs | CLO (Vector / Fluentd) | Loki (in-cluster) or Splunk (external) |
| VM serial console | `virtctl console` / virt-launcher logs | Captured in pod logs → CLO pipeline |
| VM syslog (inside guest) | rsyslog inside VM → TCP forwarder | Loki or Splunk via ClusterLogForwarder |
| Audit logs | OCP audit → CLO | S3 or Splunk for compliance retention |

### 8.3 Backup and Restore

| Component | Tool | Strategy |
|-----------|------|----------|
| VM disks | OADP + Trident CSI snapshots | Schedule: daily for non-prod, every 4 hours for prod; retain 7 days |
| VM definitions | OADP (Velero) namespace backup | Captures VM CRs, Secrets, ConfigMaps |
| Cluster config | GitOps (Argo CD) | Entire cluster state in Git; re-apply to rebuild |
| FSx ONTAP | FSx automatic backups | Daily; retain 30 days; cross-region copy for DR |
| Secrets | AWS Secrets Manager | Versioned; ESO syncs to cluster |

**OADP Schedule example**:

```yaml
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: vm-namespace-daily
  namespace: openshift-adp
spec:
  schedule: "0 2 * * *"
  template:
    includedNamespaces:
      - windows-non-prod
    snapshotVolumes: true
    storageLocation: default
    volumeSnapshotLocations:
      - trident-vsl
    ttl: 168h0m0s
```

### 8.4 Upgrades

| Component | Upgrade Path | Cadence |
|-----------|-------------|---------|
| ROSA cluster | `rosa upgrade cluster` (managed) | Quarterly (z-stream monthly) |
| OpenShift Virtualization | OLM auto-update (approval: Manual recommended for prod) | Follows OCP release cycle |
| MTV | OLM channel update | As needed |
| Trident | Helm upgrade or operator update | Align with ONTAP and OCP versions |
| FSx ONTAP | AWS-managed; maintenance windows | Automatic; confirm ONTAP version compatibility |

**Upgrade order**: ROSA platform → CNV → Trident → MTV → Day-2 operators.

### 8.5 Disaster Recovery

| Scenario | RTO Target | RPO Target | Recovery Method |
|----------|-----------|-----------|-----------------|
| Single VM failure | < 5 min | 0 (running state) | OCP auto-restarts VMI on healthy node |
| Worker node failure | < 10 min | 0 | VMI rescheduled to another node (requires RWX storage for live state) |
| AZ failure | < 15 min | < 4 hrs | VMs restart on nodes in surviving AZs; VPN failover via Keepalived |
| VPN failure | ~5 s (Keepalived) | 0 | Secondary ipsec VM takes over; tunnels re-establish |
| Full cluster loss | < 4 hrs | < 24 hrs | Rebuild cluster from GitOps; restore VMs from OADP + FSx snapshots |
| Region failure | TBD (future) | < 24 hrs | FSx cross-region backup; standby ROSA cluster in DR region |

---

## 9. Risks, Constraints, and Mitigations

| ID | Risk / Constraint | Likelihood | Impact | Mitigation |
|----|-------------------|-----------|--------|------------|
| R1 | VPN throughput bottleneck during bulk migration | High | Medium | Schedule migrations off-peak; use warm migration for large disks; consider AWS Direct Connect for sustained bandwidth |
| R2 | CUDN IPAM disabled requires manual IP assignment on every VM | Certain | Medium | Automate IP assignment via cloud-init userdata or post-migration script; maintain IP allocation spreadsheet/IPAM tool |
| R3 | Libreswan DH group mismatch with AWS defaults | High | High | Pre-configure AWS VPN tunnel options to DH Group 5/14 before deploying Libreswan; validate with `ipsec status` |
| R4 | FSx ONTAP credentials not managed (manual secret) | Medium | High | Deploy ESO with AWS Secrets Manager; automate rotation; alert on ExternalSecret sync failures |
| R5 | Windows VMs require VirtIO drivers post-migration | Certain | Medium | Pre-inject drivers into VMDK before migration; maintain `virtio-drivers-iso-rwx` PVC; document manual install |
| R6 | `ontap-san-economy` does not support RWX block (no live migration) | Certain | Medium | Acceptable for non-prod; add `ontap-san` backend for prod VMs requiring live migration |
| R7 | ROSA managed nodes limit NMState / advanced networking config | Medium | Low | Use CUDN + VPN pattern (supported); avoid node-level network changes |
| R8 | Port security disabled on CUDN (any VM can spoof IP) | Certain | Medium | Enforce network segmentation via namespace isolation; apply OCP NetworkPolicies; document accepted risk |
| R9 | MTV migration speed limited by VPN bandwidth | High | Medium | Pre-copy large disks during off-hours; use warm migration; validate bandwidth with `iperf3` before cutover |
| R10 | Single FSx ONTAP SVM for all workloads | Low | Medium | Monitor IOPS/throughput; provision additional SVMs or file systems if contention observed |

---

## 10. Implementation Phases

### Phase 0 — Foundation (Weeks 1–2)

| Task | Owner | Deliverable |
|------|-------|------------|
| Provision ROSA cluster (multi-AZ, STS, `m5.metal` pool) | Platform Team | Running cluster, `oc` access |
| Provision FSx for NetApp ONTAP (multi-AZ) | Cloud Team | FSx file system + SVM |
| Create ACM PCA (root + subordinate CA) | Security Team | CA active, device cert exported |
| Create TGW, CGW, S2S VPN | Network Team | VPN connection created, tunnels configured |
| Configure VPC route tables and SGs | Network Team | Routes + SGs for CUDN and on-prem CIDRs |

### Phase 1 — MVP Platform (Weeks 3–4)

| Task | Owner | Deliverable |
|------|-------|------------|
| Install OpenShift Virtualization operator | Platform Team | HyperConverged CR healthy |
| Install Trident CSI; configure backends and storage classes | Platform Team | Backends Bound; test PVC provisions |
| Deploy CUDN (`vm-network`, IPAM disabled) | Platform Team | CUDN object created |
| Deploy ipsec-a + ipsec-b gateway VMs with Libreswan + Keepalived | Platform Team | VPN tunnel UP; bidirectional ping validated |
| Install MTV operator; configure vCenter provider | Platform Team | Provider `Ready`; VM inventory visible |
| Install ESO; sync Trident + vCenter credentials | Platform Team | ExternalSecrets syncing |

### Phase 2 — Wave 0 Migration (Weeks 5–6)

| Task | Owner | Deliverable |
|------|-------|------------|
| Migrate 2–3 non-critical dev VMs (e.g., nymsdv297, nymsdv301) | Migration Team | VMs running on ROSA; network validated |
| Configure secondary NIC (CUDN) on migrated VMs | Migration Team | VMs reachable from on-prem via VPN |
| Validate application functionality | App Owners | Sign-off per VM |
| Document lessons learned; refine runbook | Platform Team | Updated VMMigrationRunbook.md |

### Phase 3 — Non-Prod Waves (Weeks 7–12)

| Task | Owner | Deliverable |
|------|-------|------------|
| Migrate remaining dev VMs (Wave 0 complete list) | Migration Team | All Wave 0 VMs on ROSA |
| Migrate QA VMs (Wave 1) | Migration Team | QA environment on ROSA |
| Deploy monitoring + alerting (custom PrometheusRules) | Platform Team | Alerts firing for VPN, storage, VM health |
| Deploy OADP; configure backup schedules | Platform Team | Daily backups completing |
| Deploy logging (CLO → Loki or Splunk) | Platform Team | VM logs aggregated |
| Deploy policy engine (Kyverno) | Platform Team | Policies enforcing labels, resource limits |

### Phase 4 — Production Hardening (Weeks 13–16)

| Task | Owner | Deliverable |
|------|-------|------------|
| Provision production ROSA cluster | Platform Team | Prod cluster with same architecture |
| Add `ontap-san` backend for RWX block (live migration) | Platform Team | Live migration tested |
| Deploy VTI-based IPsec (ECMP, dual tunnel) | Platform Team | Higher VPN availability |
| Run Compliance Operator scans; remediate findings | Security Team | Clean CIS scan |
| DR drill: simulate AZ failure, VPN failover, VM recovery | Platform Team | DR runbook validated |
| Migrate production VMs (warm migration, maintenance window) | Migration Team | Prod VMs on ROSA |

### Phase 5 — Steady State (Ongoing)

| Activity | Cadence |
|----------|---------|
| ROSA cluster upgrades | Quarterly (z-stream monthly) |
| Operator updates | Monthly review; apply after testing in non-prod |
| Backup validation (restore test) | Monthly |
| DR drill | Quarterly |
| Capacity review (FSx, compute) | Monthly |
| Security scan (Compliance Operator) | Weekly |
| Certificate rotation review | Quarterly (ACM PCA auto-renews) |

---

## 11. Appendices

### Appendix A — Key CRDs Reference

| CRD | API Group | Purpose |
|-----|-----------|---------|
| `VirtualMachine` | `kubevirt.io/v1` | Defines a VM (CPU, memory, disks, NICs, cloud-init) |
| `VirtualMachineInstance` | `kubevirt.io/v1` | Running instance of a VM |
| `DataVolume` | `cdi.kubevirt.io/v1beta1` | Orchestrates disk import/clone into PVC |
| `HyperConverged` | `hco.kubevirt.io/v1beta1` | Top-level CNV operator config |
| `ClusterUserDefinedNetwork` | `k8s.ovn.org/v1` | Defines secondary overlay network (CUDN) |
| `Provider` | `forklift.konveyor.io/v1beta1` | MTV source/destination provider |
| `NetworkMap` | `forklift.konveyor.io/v1beta1` | Maps VMware networks to OCP networks |
| `StorageMap` | `forklift.konveyor.io/v1beta1` | Maps VMware datastores to OCP storage classes |
| `Plan` | `forklift.konveyor.io/v1beta1` | Migration plan (VMs to migrate + mappings) |
| `Migration` | `forklift.konveyor.io/v1beta1` | Execution record of a Plan |
| `TridentBackendConfig` | `trident.netapp.io/v1` | Defines ONTAP backend for Trident |
| `TridentOrchestrator` | `trident.netapp.io/v1` | Top-level Trident operator config |
| `VolumeSnapshot` | `snapshot.storage.k8s.io/v1` | Point-in-time PVC snapshot |
| `VolumeSnapshotClass` | `snapshot.storage.k8s.io/v1` | Defines snapshot driver and policy |
| `ExternalSecret` | `external-secrets.io/v1beta1` | Syncs external secret store → K8s Secret |
| `ClusterSecretStore` | `external-secrets.io/v1beta1` | Cluster-wide secret store connection |
| `Application` | `argoproj.io/v1alpha1` | Argo CD application definition |
| `DataProtectionApplication` | `oadp.openshift.io/v1alpha1` | OADP operator config |
| `Schedule` | `velero.io/v1` | Velero backup schedule |
| `ClusterPolicy` | `kyverno.io/v1` | Kyverno policy definition |
| `PrometheusRule` | `monitoring.coreos.com/v1` | Custom alerting rules |
| `ClusterLogForwarder` | `observability.openshift.io/v1` | Log forwarding pipeline config |

### Appendix B — Example CUDN Definition

```yaml
apiVersion: k8s.ovn.org/v1
kind: ClusterUserDefinedNetwork
metadata:
  name: vm-network
spec:
  namespaceSelector:
    matchExpressions:
      - key: kubernetes.io/metadata.name
        operator: In
        values:
          - vpn-infra
          - windows-non-prod
          - linux-non-prod
  network:
    topology: Layer2
    layer2:
      role: Secondary
      subnets:
        - cidr: 10.227.128.0/21
      ipam:
        mode: Disabled
```

### Appendix C — IPsec Gateway VM Definition (Simplified)

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: ipsec-a
  namespace: vpn-infra
spec:
  running: true
  template:
    metadata:
      labels:
        app: ipsec-gateway
        role: primary
    spec:
      nodeSelector:
        topology.kubernetes.io/zone: us-east-1a
      domain:
        cpu:
          cores: 2
        memory:
          guest: 4Gi
        devices:
          interfaces:
            - name: default
              masquerade: {}
            - name: cudn
              bridge: {}
          disks:
            - name: rootdisk
              disk:
                bus: virtio
            - name: cloudinit
              disk:
                bus: virtio
      networks:
        - name: default
          pod: {}
        - name: cudn
          multus:
            networkName: vm-network
      volumes:
        - name: rootdisk
          dataVolume:
            name: ipsec-a-rootdisk
        - name: cloudinit
          cloudInitNoCloud:
            userData: |
              #cloud-config
              packages:
                - libreswan
                - keepalived
              runcmd:
                - nmcli con add type ethernet ifname eth1 con-name cudn ip4 10.227.128.10/21
                - nmcli con up cudn
                - sysctl -w net.ipv4.ip_forward=1
                - sysctl -w net.ipv4.conf.all.rp_filter=0
  dataVolumeTemplates:
    - metadata:
        name: ipsec-a-rootdisk
      spec:
        storage:
          storageClassName: ontap-san-economy
          accessModes: [ReadWriteOnce]
          resources:
            requests:
              storage: 20Gi
        sourceRef:
          kind: DataSource
          name: centos-stream10
          namespace: openshift-virtualization-os-images
```

### Appendix D — Keepalived Configuration

**ipsec-a** (`/etc/keepalived/keepalived.conf`):

```
vrrp_script chk_ipsec {
    script "/usr/sbin/ipsec status > /dev/null 2>&1"
    interval 2
    weight 2
}

vrrp_instance VPN_GW {
    state MASTER
    interface eth1
    virtual_router_id 51
    priority 101
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass s3cur3vpn
    }
    virtual_ipaddress {
        10.227.128.1/21
    }
    track_script {
        chk_ipsec
    }
    notify_master "/usr/sbin/ipsec start"
    notify_backup "/usr/sbin/ipsec stop"
    notify_fault  "/usr/sbin/ipsec stop"
}
```

**ipsec-b**: Same config with `state BACKUP`, `priority 100`.

### Appendix E — Libreswan Configuration

```
config setup
    logfile=/var/log/pluto.log
    plutodebug=control
    uniqueids=no

conn %default
    ikev2=insist
    ike=aes128-sha256-modp2048,aes128-sha1-modp1536
    esp=aes128-sha256-modp2048,aes128-sha1-modp1536
    ikelifetime=28800s
    salifetime=3600s
    dpdaction=restart
    dpddelay=10
    dpdtimeout=30
    keyingtries=%forever
    rekey=yes
    authby=rsasig
    leftcert=<acm-cert-nickname>
    left=%defaultroute
    leftsubnet=10.227.128.0/21
    auto=start
    type=tunnel

conn aws-vpn-tunnel1
    also=%default
    right=3.232.27.186
    rightsubnet=10.63.0.0/16,10.68.0.0/16,10.99.0.0/16,10.110.0.0/16,10.140.0.0/16,10.141.0.0/16,10.158.0.0/16
    rightid="C=US, ST=WA, L=Seattle, O=Amazon.com, OU=AWS, CN=vpn-059ee0661e851adf4.endpoint-0"
    leftid=%fromcert

conn aws-vpn-tunnel2
    also=%default
    right=98.94.136.2
    rightsubnet=10.63.0.0/16,10.68.0.0/16,10.99.0.0/16,10.110.0.0/16,10.140.0.0/16,10.141.0.0/16,10.158.0.0/16
    rightid="C=US, ST=WA, L=Seattle, O=Amazon.com, OU=AWS, CN=vpn-059ee0661e851adf4.endpoint-1"
    leftid=%fromcert
```

### Appendix F — Port and Protocol Reference

| Source | Destination | Port/Protocol | Purpose |
|--------|-------------|---------------|---------|
| ipsec VM (eth0) | AWS Tunnel EIPs | UDP 500, UDP 4500 | IKE + NAT-T encapsulated ESP |
| MTV controller pod | vCenter | TCP 443 | VMware SDK API |
| MTV importer pod | ESXi hosts | TCP 443, TCP 902 | VDDK / NBDSSL disk transfer |
| Worker nodes | FSx Mgmt LIF | TCP 443 | ONTAP API (Trident management) |
| Worker nodes | FSx iSCSI LIFs | TCP 3260 | iSCSI data path |
| Worker nodes | FSx NFS LIF | TCP 2049, TCP 111 | NFS data path |
| On-prem hosts | CUDN VMs | Any (routed via VPN) | Application traffic |
| CUDN VMs | On-prem hosts | Any (routed via VPN, next-hop VIP) | Application traffic, DNS, AD auth |
| Pods | CoreDNS | TCP/UDP 53 | DNS resolution |
| ESO controller | AWS Secrets Manager | TCP 443 (HTTPS) | Secret sync |
| OADP / Velero | S3 | TCP 443 (HTTPS) | Backup storage |

### Appendix G — Verification Commands

```bash
# --- Cluster Health ---
oc get nodes -o wide
oc get co                                    # All operators Available=True
oc get mcp                                   # MachineConfigPools updated

# --- OpenShift Virtualization ---
oc get csv -n openshift-cnv                  # CNV operator version
oc get hyperconverged -n openshift-cnv       # HCO status
oc get vm -A                                 # All VMs
oc get vmi -A                                # Running VM instances

# --- VPN ---
virtctl console ipsec-a -n vpn-infra         # Then: sudo ipsec status
oc get vm -n vpn-infra                       # Gateway VMs running
# From ipsec VM: ping <on-prem-host-ip>
# From on-prem: ping 10.227.128.20 (CUDN VM)

# --- Storage ---
oc get tridentbackendconfig -n trident -o wide   # Backends Bound
oc get sc                                         # Storage classes
oc get pvc -A | grep -E 'ontap|trident'           # ONTAP-backed PVCs

# --- MTV ---
oc get csv -n openshift-mtv                       # MTV operator version
oc get provider -n openshift-mtv                  # Providers Ready
oc get plan -n openshift-mtv                      # Migration plans
oc get migration -n openshift-mtv                 # Active migrations

# --- GitOps ---
oc get application -n openshift-gitops            # Argo CD apps Synced/Healthy

# --- Backup ---
oc get schedule -n openshift-adp                  # Backup schedules
oc get backup -n openshift-adp                    # Recent backups

# --- Secrets ---
oc get externalsecret -A                          # ESO sync status
```

---

## Document Control

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-04 | Platform Architecture | Initial draft |
| 2.0 | 2026-02-17 | Platform Architecture | Full architecture doc with S2S VPN, MTV, ONTAP, Day-2 operations |

**Review Schedule**: Quarterly or after major infrastructure changes  
**Distribution**: Platform Engineering, Network Engineering, Security, Application Teams, Management

---

*End of document.*
