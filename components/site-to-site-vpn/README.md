# Site-to-Site VPN Component

AWS Site-to-Site VPN connectivity for the ROSA Non-Prod cluster using StrongSwan IPSec with certificate-based mutual authentication.

## Architecture

Two StrongSwan VPN gateway VMs terminate the IPSec tunnels and act as gateways for their respective CUDN networks. A containerized StrongSwan pod provides an alternative pod-network-level VPN endpoint.

```
Canon Corporate Networks (on-premise)
  10.63.0.0/16, 10.68.0.0/16, 10.99.0.0/16,
  10.110.0.0/16, 10.140.0.0/16, 10.141.0.0/16,
  10.158.0.0/16, 10.227.112.0/20
    ↕
Palo Alto Firewall → AWS Transit Gateway (tgw-00279fe0ab1ac255c)
    ↕ IPSec (IKEv1, certificate-based RSA auth)
AWS VPN Connection: vpn-059ee0661e851adf4
    ├─ Tunnel 1: 3.232.27.186 (inside IP 169.254.43.134)
    └─ Tunnel 2: 98.94.136.2  (inside IP 169.254.118.14)
    ↕
ROSA Non-Prod VPC (vpc-0e9f579449a68a005, CIDR 10.227.96.0/20)
    │
    ├─ ipsec-vpn-windows VM (windows-non-prod)
    │   eth0: pod network   eth1: 10.227.128.1/21 (CUDN gateway)
    │   └─ Windows VMs use 10.227.128.1 as default gateway
    │
    ├─ ipsec-vpn-linux VM (linux-non-prod)
    │   eth0: pod network   eth1: 10.227.120.1/21 (CUDN gateway)
    │   └─ Linux VMs use 10.227.120.1 as default gateway
    │
    └─ site-to-site-vpn Pod (site-to-site-vpn namespace)
        hostNetwork VPN pod for pod-network-level routing
```

## VPN Gateway VMs

| VM | Namespace | CUDN Subnet | Gateway IP | File |
|----|-----------|-------------|------------|------|
| `ipsec-vpn-windows` | `windows-non-prod` | `10.227.128.0/21` | `10.227.128.1` | `ipsec-vpn-windows.yaml` |
| `ipsec-vpn-linux` | `linux-non-prod` | `10.227.120.0/21` | `10.227.120.1` | `ipsec-vpn-linux.yaml` |

Both VMs run CentOS Stream 9 with StrongSwan installed from EPEL. Configuration is embedded via cloud-init and uses legacy `ipsec.conf` (stroke mode) to avoid the swanctl/VICI PSK conflict.

### IPSec Parameters

| Parameter | Value |
|-----------|-------|
| IKE Version | IKEv1 (`keyexchange=ikev1`) |
| Phase 1 (IKE) | AES128-SHA1-MODP1024, lifetime 28800s |
| Phase 2 (ESP) | AES128-SHA1-MODP1024, lifetime 3600s |
| Authentication | RSA signatures (certificate-based) |
| DPD | restart, 10s delay, 30s timeout |
| Certificate CN | `vpn-059ee0661e851adf4.endpoint-1` |

### Deploy a Gateway VM

```bash
# Deploy the windows-non-prod VPN gateway
oc apply -f components/site-to-site-vpn/ipsec-vpn-windows.yaml

# Deploy the linux-non-prod VPN gateway
oc apply -f components/site-to-site-vpn/ipsec-vpn-linux.yaml
```

### Verify Gateway VM

```bash
virtctl ssh root@vmi/ipsec-vpn-windows -n windows-non-prod
/usr/local/bin/vpn-status.sh
```

### Helper Scripts (on each VM)

| Script | Purpose |
|--------|---------|
| `vpn-status.sh` | Full status check: interfaces, routes, tunnels, connectivity |
| `start-vpn.sh` | (Re)start StrongSwan in stroke mode |
| `configure-vpn-gateway.sh` | Full first-boot configuration (runs automatically via cloud-init) |
| `inject-certs.sh` | Copy certs from K8s secret into VM (run from cluster, not VM) |
| `cleanup-swanctl.sh` | Remove conflicting swanctl PSK configs |

## Container VPN Pod

The pod deployment provides VPN at the host-network level, useful for pod-to-on-prem routing without going through the CUDN gateway VMs.

| File | Purpose |
|------|---------|
| `namespace.yaml` | `site-to-site-vpn` namespace |
| `rbac.yaml` | ServiceAccount with privileged SCC |
| `configmap.yaml` | StrongSwan ipsec.conf, ipsec.secrets, startup script |
| `deployment.yaml` | VPN pod (hostNetwork, privileged) |
| `kustomization.yaml` | Kustomize overlay for all pod resources |

### Deploy Container VPN

```bash
# Create certificate secret first
oc create secret generic vpn-certificates \
  -n site-to-site-vpn \
  --from-file=client-cert.pem \
  --from-file=client-key.pem \
  --from-file=ca-chain.pem

# Deploy
oc apply -k components/site-to-site-vpn/
```

## CUDN Networks

| File | Network | Subnet | Topology |
|------|---------|--------|----------|
| `cudn-windows-non-prod.yaml` | `windows-non-prod` | `10.227.128.0/21` | Layer2, IPAM disabled |
| `cudn-linux-non-prod.yaml` | `linux-non-prod` | `10.227.120.0/21` | Layer2, IPAM disabled |

## Certificate Management

Certificates are sourced from AWS Secrets Manager via ExternalSecrets:

| File | Namespace | AWS Secret Key |
|------|-----------|----------------|
| `externalsecret-vpn-certs.yaml` | `site-to-site-vpn` | `ROSA-NONPROD-VPN-Tunnel2-Certificates` |
| `externalsecret-vpn-certs-linux.yaml` | `linux-non-prod` | `ROSA-NONPROD-VPN-Tunnel2-Certificates` |

Required certificate files: `client-cert.pem`, `client-key.pem` (decrypted), `ca-chain.pem`.

## AWS Resources

| Resource | ID |
|----------|----|
| VPN Connection | `vpn-059ee0661e851adf4` |
| Customer Gateway | `cgw-0f82cc789449111b7` |
| Transit Gateway | `tgw-00279fe0ab1ac255c` |
| VPC | `vpc-0e9f579449a68a005` |

## File Inventory

```
site-to-site-vpn/
├── README.md                          # This file
├── ipsec-vpn-windows.yaml             # StrongSwan VM for windows-non-prod
├── ipsec-vpn-linux.yaml               # StrongSwan VM for linux-non-prod
├── cudn-windows-non-prod.yaml         # CUDN network (10.227.128.0/21)
├── cudn-linux-non-prod.yaml           # CUDN network (10.227.120.0/21)
├── externalsecret-vpn-certs.yaml      # ExternalSecret (site-to-site-vpn ns)
├── externalsecret-vpn-certs-linux.yaml# ExternalSecret (linux-non-prod ns)
├── deployment.yaml                    # Container VPN pod deployment
├── configmap.yaml                     # StrongSwan config for container VPN
├── kustomization.yaml                 # Kustomize for container VPN
├── namespace.yaml                     # site-to-site-vpn namespace
├── rbac.yaml                          # RBAC / privileged SCC
├── nad-site-to-site-vpn.yaml          # NAD for VPN pod CUDN attachment
└── secret-template.yaml               # Template for manual cert secret
```

## Troubleshooting

### VM Tunnels Not Establishing

```bash
# SSH into the VM
virtctl ssh root@vmi/ipsec-vpn-windows -n windows-non-prod

# Check StrongSwan status
strongswan statusall 2>/dev/null || ipsec statusall

# Check logs
journalctl -u strongswan --since "5 minutes ago"
tail -50 /var/log/charon.log

# Verify certificates
ls -la /etc/strongswan/ipsec.d/{certs,private,cacerts}/
openssl x509 -in /etc/strongswan/ipsec.d/certs/client-cert.pem -noout -subject -dates

# Check for swanctl PSK conflict
ls /etc/strongswan/swanctl/conf.d/
```

### Container VPN Pod Issues

```bash
POD=$(oc get pods -n site-to-site-vpn -l app=site-to-site-vpn -o jsonpath='{.items[0].metadata.name}')
oc logs -n site-to-site-vpn $POD --tail=100
oc exec -n site-to-site-vpn $POD -- ip route
```

### Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `NO_PROPOSAL_CHOSEN` | DH group mismatch | Ensure AWS VPN uses MODP1024 (DH2) or update to MODP1536 |
| PSK auth instead of cert | swanctl configs conflict | Run `cleanup-swanctl.sh`, restart with `start-vpn.sh` |
| `target must contain type and name` | virtctl syntax | Use `vmi/vm-name` format: `virtctl ssh root@vmi/ipsec-vpn-windows` |
| `sudo: command not found` | SSH failed, ran locally | Fix the virtctl command first, then run sudo inside the VM |

---

**Last Updated**: 2026-02-24
**StrongSwan Version**: Latest from EPEL 9
**Maintained by**: OpenShift Team
