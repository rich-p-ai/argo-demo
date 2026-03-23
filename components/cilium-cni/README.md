# Cilium CNI Component

**CNI**: Cilium 1.19.x — AWS ENI IPAM Mode + BGP Control Plane  
**Certification**: Isovalent Networking for Kubernetes — Red Hat Certified for OpenShift HCP  
**Clusters**: ROSA HCP non-prod (east / west)

---

## Overview

This component manages Cilium's post-install GitOps configuration:

| Resource | Purpose |
|----------|---------|
| `values-eni.yaml` | Helm values for initial Cilium installation (ENI IPAM, BGP, Hubble) |
| `bgp/cilium-bgp-cluster-config.yaml` | BGP session topology — worker nodes peer to VPC router (ASN 65010 → 64512) |
| `bgp/cilium-bgp-peer-config.yaml` | BGP peer settings — timers, graceful restart, address families |
| `bgp/cilium-bgp-advertisement.yaml` | Advertise Service LoadBalancer IPs to on-premises via Transit Gateway |
| `bgp/cilium-lb-ipam-pool.yaml` | LoadBalancer IP pools: service (10.227.108.0/24), linux-cudn, windows-cudn |

## Deployment Flow

Cilium must be **installed via Helm before ArgoCD syncs this component**.  
The install script lives in `Cluster-Build/rosa-clusters/scripts/install-cilium-cni.sh`.

```
1. Create cluster with --no-cni   (create-cluster.sh, CNI_TYPE=cilium)
2. Install Cilium via Helm        (install-cilium-cni.sh — uses values-eni.yaml)
3. ArgoCD syncs BGP resources     (this component, sync-wave: 20)
```

## Architecture

```
  Worker Nodes (r6i.metal)
       │  BGP ASN 65010
       │  Peers → 10.227.96.1 (VPC Router, ASN 64512)
       ▼
  Transit Gateway → On-Premises (Canon)
```

**ENI mode** — pods receive real VPC IPs, no overlay encapsulation, no VPN gateways.

## IP Pool Summary

| Pool | CIDR | Used For |
|------|------|---------|
| `service-pool` | 10.227.108.0/24 | General LoadBalancer VIPs |
| `linux-cudn-pool` | 10.227.120.0/21 | Linux VM CUDN services |
| `windows-cudn-pool` | 10.227.128.0/21 | Windows VM CUDN services |

Services labeled `bgp-advertise: "true"` receive a VIP from the pool and have
a /32 host route advertised via BGP to the VPC router and on-premises.

## References

- [Cilium ENI IPAM](https://docs.cilium.io/en/stable/network/concepts/ipam/eni/)
- [Cilium BGP Control Plane](https://docs.cilium.io/en/stable/network/bgp-control-plane/)
- [ROSA BYO CNI](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/install_rosa_with_hcp_clusters/rosa-hcp-cluster-no-cni)
- [Isovalent on ROSA HCP](https://isovalent.com/blog/post/red-hat-certifies-isovalent-networking-for-kubernetes-on-openshift-hosted-control-planes/)
