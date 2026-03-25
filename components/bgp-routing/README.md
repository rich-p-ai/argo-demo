# BGP Routing Component

**Cluster**: non-prod (`api.non-prod.tamn.p3.openshiftapps.com`)  
**Region**: us-east-1 · **VPC**: `vpc-0e9f579449a68a005`  
**OCP**: 4.20+ · **Feature**: FRR-K8s + OVN-Kubernetes RouteAdvertisements

---

## Overview

This component enables **L3 direct routing** — migrated VMs receive a `10.100.x.x` Pod IP that is natively reachable from anywhere within the AWS VPC without NAT or IPSec tunnels.

It uses the **AWS VPC Route Server** to dynamically program VPC subnet route tables via BGP. Three dedicated worker nodes (one per AZ) run FRR and peer with Route Server endpoints. When a VM starts in `linux-non-prod` or `windows-non-prod`, the Route Server immediately programs a host route pointing to the BGP router node that owns that Pod — traffic flows directly to the VM.

```
AWS VPC
  Any host / EC2 / service
       │
       │  10.100.0.0/16 → bgp-router-N ENI
       │  (Route Server programs VPC subnet route tables via BGP)
       ▼
  BGP Router Worker (bgp_router=true)
   ├── bgp-router-1  us-east-1a  (FRR ASN 65001)
   ├── bgp-router-2  us-east-1c  (FRR ASN 65001)
   └── bgp-router-3  us-east-1d  (FRR ASN 65001)
       │  FRR-K8s peers with 6 Route Server endpoints (2 per AZ, ASN 65000)
       ▼
  Migrated VM  10.100.x.x  (Primary CUDN — default route)
  Namespace: linux-non-prod / windows-non-prod
```

---

## Prerequisites

### AWS Prerequisites (provisioned by the AWS team)

The following AWS resources must exist in `vpc-0e9f579449a68a005` before the OCP scripts run.  
These are not scripted here — they are provisioned by the AWS/infrastructure team.

| Resource | Detail | AWS CLI to verify |
|---|---|---|
| VPC Route Server | ASN `65000`, propagation enabled on VPC route tables | `aws ec2 describe-route-servers` |
| Route Server Endpoints | 6 total — 2 per worker subnet (us-east-1a/c/d) | `aws ec2 describe-route-server-endpoints` |
| Route Server Peers | 6 total — 2 per BGP router node | `aws ec2 describe-route-server-peers` |
| BGP Router MachinePools | 3× `m5.xlarge`, one per AZ, labeled `bgp_router=true` | `rosa list machinepools -c non-prod` |
| Src/Dst Check disabled | On primary ENI of all 3 router EC2 instances | `aws ec2 describe-instances --filters Name=tag:bgp_router,Values=true` |

Once the AWS team confirms these are in place, **collect the 6 Route Server Endpoint IPs** and fill them into the state file:

```bash
# Get endpoint IPs from AWS
aws ec2 describe-route-server-endpoints \
  --region us-east-1 \
  --query 'RouteServerEndpoints[*].{SubnetId:SubnetId,IP:EniAddress,State:State}' \
  --output table

# Copy template and fill in the IPs
cp scripts/bgp/bgp-state.env.template scripts/bgp/bgp-state.env
# edit scripts/bgp/bgp-state.env — replace all CHANGE_ME values
```

### OCP Scripts (run by the OpenShift team)

| Step | Script | What it does | Time |
|---|---|---|---|
| 1 | `scripts/bgp/01-patch-network-operator.sh` | Patches Network operator to enable FRR + RouteAdvertisements | 10–15 min |
| 2 | `scripts/bgp/02-apply-frr-config.sh` | Populates RS endpoint IPs → applies FRRConfiguration, CUDN, RouteAdvertisements | 5 min |

```bash
cd ~/work
# Fill in bgp-state.env first (see above), then:
bash scripts/bgp/01-patch-network-operator.sh   # prompts for confirmation
bash scripts/bgp/02-apply-frr-config.sh
```

`scripts/bgp/bgp-state.env` is gitignored. The template `bgp-state.env.template` is tracked in git and shows exactly which values are needed.

---

## Resources in this Component

| File | Kind | Purpose |
|---|---|---|
| `namespace.yaml` | `Namespace` ×2 | Patches `linux-non-prod` + `windows-non-prod` — adds Primary CUDN opt-in labels |
| `cudn-bgp-prod.yaml` | `ClusterUserDefinedNetwork` | Primary Layer2 network `10.100.0.0/16` — covers both namespaces |
| `route-advertisements.yaml` | `RouteAdvertisements` | Wires the CUDN to FRR-K8s for BGP advertisement |
| `kustomization.yaml` | `Kustomization` | Kustomize entry with `ServerSideApply=true, SkipDryRunOnMissingResource=true` |

The cluster-specific **`FRRConfiguration`** (BGP peer IPs) lives in the cluster overlay:
`clusters/non-prod/overlays/bgp-routing/frr-configuration.yaml`  
It is populated automatically by `scripts/bgp/05-apply-frr-config.sh`.

---

## BGP Parameters

| Parameter | Value |
|---|---|
| Pod network CIDR advertised | `10.100.0.0/16` |
| ROSA cluster ASN (FRR) | `65001` |
| AWS Route Server ASN | `65000` |
| BGP keepalive (liveness) | `bgp-keepalive` |
| FRR multi-protocol BGP | Disabled (`disableMP: true`) |
| Route convergence on failure | ~30 s (BGP keepalive timeout) |
| Worker node instance type | `m5.xlarge` (1 per AZ) |
| Src/Dst check on router ENI | Disabled (required) |

---

## Network Design

### CIDR Summary

| Network | CIDR | Note |
|---|---|---|
| VPC / Machine CIDR | `10.227.96.0/20` | Worker nodes, existing infrastructure |
| BGP Primary CUDN | `10.100.0.0/16` | Advertised — VM default interface |

### VM Interface Layout

Every VM migrated into `linux-non-prod` or `windows-non-prod` receives:

```
eth0   10.100.x.x   Primary CUDN cluster-udn-bgp-prod   ← default route
```

IP assignment is **Persistent** — the VM keeps the same `10.100.x.x` address across restarts.

### Namespace Labels Required

Both target namespaces must carry these labels (applied by `namespace.yaml`):

```yaml
k8s.ovn.org/primary-user-defined-network: ""   # opts namespace into Primary CUDN
cluster-udn: bgp-prod                           # CUDN selector
```

> These labels must be present **before** any VMs are created in the namespace.  
> Since `namespace.yaml` uses `ServerSideApply=true`, ArgoCD merges them without
> disturbing other namespace metadata.

---

## Activation (ArgoCD)

Once both OCP scripts complete successfully and script 02 validates BGP sessions, enable the ArgoCD application by uncommenting the `bgp-routing` block in `clusters/non-prod/values.yaml`:

```yaml
bgp-routing:
  annotations:
    argocd.argoproj.io/compare-options: IgnoreExtraneous
    argocd.argoproj.io/sync-wave: "10"
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true,ServerSideApply=true
  destination:
    namespace: openshift-frr-k8s
  source:
    path: clusters/non-prod/overlays/bgp-routing
    targetRevision: main
```

ArgoCD will then own the lifecycle of the CUDN, RouteAdvertisements, and FRRConfiguration going forward.

---

## Validation

```bash
# 1. Confirm namespace labels
oc get namespace linux-non-prod -o jsonpath='{.metadata.labels}' | grep primary-user-defined-network
oc get namespace windows-non-prod -o jsonpath='{.metadata.labels}' | grep primary-user-defined-network

# 2. CUDN active and covering both namespaces
oc get clusteruserdefinednetwork cluster-udn-bgp-prod

# 3. RouteAdvertisements in place
oc get routeadvertisements

# 4. FRR pods running on bgp_router nodes
oc get pods -n openshift-frr-k8s -o wide

# 5. BGP sessions Established (run on each router node)
for NODE in $(oc get nodes -l bgp_router=true -o jsonpath='{.items[*].metadata.name}'); do
  POD=$(oc get pods -n openshift-frr-k8s --field-selector="spec.nodeName=${NODE}" \
    -o jsonpath='{.items[0].metadata.name}')
  echo "=== ${NODE} ==="
  oc exec -n openshift-frr-k8s "${POD}" -c frr -- vtysh -c "show bgp summary"
done

# 6. AWS VPC route tables show 10.100.0.0/16
aws ec2 describe-route-tables \
  --region us-east-1 \
  --filters "Name=vpc-id,Values=vpc-0e9f579449a68a005" \
  --query 'RouteTables[*].Routes[?DestinationCidrBlock==`10.100.0.0/16`]' \
  --output table

# 7. Test VM gets a 10.100.x.x IP
oc get vmi -n linux-non-prod -o wide
```

---

## Rollback

AWS resources are never deleted. Only OCP objects are removed:

```bash
# Remove OCP BGP objects
oc delete routeadvertisements bgp-prod-advertisements
oc delete clusteruserdefinednetwork cluster-udn-bgp-prod
oc delete frrconfigurations bgp-router-nodes -n openshift-frr-k8s

# Remove Primary CUDN labels from namespaces
oc label namespace linux-non-prod  k8s.ovn.org/primary-user-defined-network- cluster-udn-
oc label namespace windows-non-prod k8s.ovn.org/primary-user-defined-network- cluster-udn-

# Disable FRR on Network operator (triggers OVN rolling restart)
oc patch network.operator.openshift.io cluster --type=merge -p='{
  "spec": {
    "additionalRoutingCapabilities": null,
    "defaultNetwork": {"ovnKubernetesConfig": {"routeAdvertisements": "Disabled"}}
  }
}'

# Remove BGP router MachinePools (AWS Route Server infrastructure stays)
rosa delete machinepool --cluster=non-prod --machinepool=bgp-router-1 -y
rosa delete machinepool --cluster=non-prod --machinepool=bgp-router-2 -y
rosa delete machinepool --cluster=non-prod --machinepool=bgp-router-3 -y
```

---

## AWS Resources Created by the Scripts

| Resource | Count | Purpose |
|---|---|---|
| VPC Route Server | 1 | BGP control plane, ASN 65000 |
| Route Server Endpoints | 6 | 2 per AZ — BGP peering termination |
| Route Server Peers | 6 | 2 per router node — BGP sessions |
| Security Group | 1 | RFC1918 ingress on router nodes |
| MachinePools | 3 | 1× `m5.xlarge` per AZ, `bgp_router=true` |

All AWS resources are **additive only** — no existing VPC or cluster resources are modified.

---

## File Inventory

```
components/bgp-routing/
├── README.md                        ← This file
├── kustomization.yaml               ← ServerSideApply + SkipDryRunOnMissingResource
├── namespace.yaml                   ← Patches linux-non-prod + windows-non-prod
├── cudn-bgp-prod.yaml               ← Primary CUDN 10.100.0.0/16
└── route-advertisements.yaml        ← BGP route advertisement config

clusters/non-prod/overlays/bgp-routing/
├── kustomization.yaml               ← Includes component + frr-configuration
└── frr-configuration.yaml           ← FRR BGP peers (populated by script 02)

scripts/bgp/
├── bgp-state.env.template           ← Fill in RS endpoint IPs from AWS team
├── bgp-state.env                    ← Filled-in state (gitignored, copy from template)
├── 01-patch-network-operator.sh     ← OCP: enable FRR + RouteAdvertisements
└── 02-apply-frr-config.sh           ← OCP: apply all BGP Kubernetes objects
```

---

## References

- [AWS VPC Route Server](https://docs.aws.amazon.com/vpc/latest/userguide/dynamic-routing-route-server.html)
- [OVN-Kubernetes FRR-K8s](https://docs.openshift.com/container-platform/4.20/networking/ovn_kubernetes_network_provider/about-ovn-kubernetes.html)
- [OpenShift RouteAdvertisements](https://docs.openshift.com/container-platform/4.20/networking/ovn_kubernetes_network_provider/configuring-egress-ips-ovn.html)
- [ROSA HCP MachinePools](https://docs.openshift.com/rosa/rosa_cluster_admin/rosa_nodes/rosa-managing-worker-nodes.html)
- [rosa-bgp reference implementation](https://github.com/msemanrh/rosa-bgp)

---

**Last Updated**: 2026-03-24  
**OCP Version**: 4.20.12  
**Maintained by**: OpenShift Platform Team
