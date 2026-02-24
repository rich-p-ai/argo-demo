# Site-to-Site VPN Component

AWS Site-to-Site VPN connection for ROSA Non-Prod cluster using strongSwan IPSec in a containerized deployment.

## Overview

This component provides secure site-to-site VPN connectivity between on-premise networks and the ROSA Non-Prod OpenShift cluster, enabling:
- Access to OpenShift pods and VMs from on-premise
- Secure IPSec tunnels with certificate-based authentication
- High availability with dual AWS VPN tunnels
- Pod network routing (10.132.0.0/14) to on-premise (10.227.112.0/20)

## Architecture

```
On-Premise Network (10.227.112.0/20)
    ↕ IPSec VPN (Certificate-based)
AWS VPN Connection (vpn-059ee0661e851adf4)
    ├─ Tunnel 1: 3.232.27.186 (requires endpoint-0 cert)
    └─ Tunnel 2: 98.94.136.2 ✅ ACTIVE (endpoint-1 cert)
    ↕
Transit Gateway (tgw-00279fe0ab1ac255c)
    ├─ Route: 10.132.0.0/14 → VPN
    └─ Route: 10.227.112.0/20 → VPN
    ↕
ROSA Non-Prod VPC (vpc-0e9f579449a68a005)
    ├─ VPC CIDR: 10.227.96.0/20
    ├─ Pod Network: 10.132.0.0/14
    └─ strongSwan VPN Pod (hostNetwork)
```

## Components

### Required Files (Deployed)
- **`namespace.yaml`** - Creates `site-to-site-vpn` namespace
- **`rbac.yaml`** - ServiceAccount with necessary permissions
- **`configmap.yaml`** - strongSwan IPSec configuration (ipsec.conf, ipsec.secrets, startup script)
- **`deployment.yaml`** - VPN pod deployment with hostNetwork and privileged security context
- **`kustomization.yaml`** - Kustomize configuration for all resources

### Template Files (Manual Setup)
- **`secret-template.yaml`** - Template for VPN certificates (NOT auto-deployed for security)

## Prerequisites

### 1. VPN Certificates
Obtain the following from AWS VPN connection configuration:
- **Client Certificate** (`client-cert.pem`)
- **Client Private Key** (`client-key.pem`) - decrypted, no passphrase
- **CA Certificate Chain** (`ca-chain.pem`)

### 2. AWS VPN Connection Details
- **VPN Connection ID**: `vpn-059ee0661e851adf4`
- **Customer Gateway**: `cgw-0f82cc789449111b7`
- **Tunnel 1 Endpoint**: `3.232.27.186`
- **Tunnel 2 Endpoint**: `98.94.136.2`

### 3. Network Configuration
- **Remote Network CIDR**: `10.227.112.0/20` (on-premise)
- **Pod Network CIDR**: `10.132.0.0/14` (ROSA Non-Prod pods)
- **VPC CIDR**: `10.227.96.0/20` (worker nodes)

## Installation

### Step 1: Create VPN Certificates Secret

```bash
# Create secret with your VPN certificates
oc create secret generic vpn-certificates \
  -n site-to-site-vpn \
  --from-file=client-cert.pem=/path/to/certificate.txt \
  --from-file=client-key.pem=/path/to/private_key.txt \
  --from-file=ca-chain.pem=/path/to/certificate_chain.txt
```

**IMPORTANT**: 
- Private key must be **decrypted** (no passphrase)
- Certificate files must be in PEM format
- Use the **endpoint-1** certificate for Tunnel 2 (currently active)

### Step 2: Deploy VPN Component

```bash
# From Cluster-Config repository root
oc apply -k components/site-to-site-vpn/
```

**OR** via ArgoCD:
```bash
# ArgoCD will automatically sync from git
# Ensure vpn-certificates secret exists first
```

### Step 3: Verify Deployment

```bash
# Check pod status
oc get pods -n site-to-site-vpn

# Check logs for tunnel establishment
POD=$(oc get pods -n site-to-site-vpn -l app=site-to-site-vpn -o jsonpath='{.items[0].metadata.name}')
oc logs -n site-to-site-vpn $POD | grep -E "ESTABLISHED|IKE_SA"

# Expected output:
# IKE_SA aws-vpn-tunnel2[2] established between 10.227.96.122[CN=vpn-059ee0661e851adf4.endpoint-1]...98.94.136.2[CN=vpn-059ee0661e851adf4.endpoint-1]
```

### Step 4: Verify VPN Connectivity

```bash
# From on-premise workstation (after completing AWS/Palo Alto routing)
ping 10.130.2.23  # Example pod IP
ssh cloud-user@10.130.2.23  # Example VM access
```

## Configuration Details

### strongSwan IPSec Configuration

**Key Parameters**:
- **IKE Version**: IKEv1
- **Encryption**: AES-128-CBC
- **Authentication**: RSA signature (certificate-based)
- **Hash**: SHA1
- **DH Group**: modp1024 (group2)
- **IKE Lifetime**: 28800s (8 hours)
- **IPSec Lifetime**: 3600s (1 hour)
- **DPD**: Enabled (10s delay, 30s timeout)

**Traffic Selector**:
- **Local**: `0.0.0.0/0` (all cluster traffic)
- **Remote**: `10.227.112.0/20` (on-premise network)

### Deployment Configuration

**Pod Specifications**:
- **Networking**: `hostNetwork: true` (direct host access)
- **Security**: Privileged container with `NET_ADMIN`, `SYS_ADMIN`, `NET_RAW` capabilities
- **Resources**:
  - Requests: 200m CPU, 512Mi memory
  - Limits: 1000m CPU, 1Gi memory
- **Probes**:
  - Liveness: Checks for charon process and VTI interface (180s initial delay)
  - Readiness: Checks for charon process (120s initial delay)

## Troubleshooting

### Pod Failing to Start

**Check certificates**:
```bash
oc get secret vpn-certificates -n site-to-site-vpn -o yaml
```

**Check pod logs**:
```bash
oc logs -n site-to-site-vpn <pod-name> --tail=100
```

**Common Issues**:
- Private key has passphrase (must be decrypted)
- Certificate format incorrect (must be PEM)
- Wrong certificate (using endpoint-0 cert for Tunnel 2)

### VPN Tunnel Not Establishing

**Check strongSwan logs**:
```bash
POD=$(oc get pods -n site-to-site-vpn -l app=site-to-site-vpn -o jsonpath='{.items[0].metadata.name}')
oc logs -n site-to-site-vpn $POD | grep -E "IKE|error|failed"
```

**Common Issues**:
- Certificate mismatch (leftid/rightid)
- AWS VPN configuration mismatch
- Firewall blocking UDP 500/4500

### Connectivity Issues

**Check routing**:
```bash
# On VPN pod
oc exec -n site-to-site-vpn <pod-name> -- ip route

# Verify kernel parameters
oc exec -n site-to-site-vpn <pod-name> -- sysctl net.ipv4.ip_forward
```

**Verify AWS routing**:
```bash
# Check TGW route table
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id tgw-rtb-0ff564f70c91bf1d5 \
  --filters "Name=route-search.exact-match,Values=10.132.0.0/14" \
  --region us-east-1

# Check VPC route table
aws ec2 describe-route-tables \
  --route-table-ids rtb-0467d201a9cbdb89c \
  --region us-east-1 \
  --query 'RouteTables[0].Routes[?DestinationCidrBlock==`10.132.0.0/14`]'
```

**Check Palo Alto firewall**:
```
show vpn ipsec-sa
show address POD-CIDR-NONPROD
show rulebase pbf rules pbf-vpn-vpn-059ee0661e851adf4-0
```

## Maintenance

### Update VPN Configuration

1. Edit `configmap.yaml` with new settings
2. Commit and push to git
3. Delete configmap and pod to force recreation:
   ```bash
   oc delete configmap ipsec-config -n site-to-site-vpn
   oc delete pod -n site-to-site-vpn -l app=site-to-site-vpn
   ```
4. Verify new pod starts successfully

### Update VPN Certificates

```bash
# Delete existing secret
oc delete secret vpn-certificates -n site-to-site-vpn

# Create new secret with updated certificates
oc create secret generic vpn-certificates \
  -n site-to-site-vpn \
  --from-file=client-cert.pem=/path/to/new/certificate.txt \
  --from-file=client-key.pem=/path/to/new/private_key.txt \
  --from-file=ca-chain.pem=/path/to/new/certificate_chain.txt

# Restart pod
oc delete pod -n site-to-site-vpn -l app=site-to-site-vpn
```

### Monitor VPN Health

```bash
# Check pod status
oc get pods -n site-to-site-vpn -w

# Watch logs for DPD keep-alives
POD=$(oc get pods -n site-to-site-vpn -l app=site-to-site-vpn -o jsonpath='{.items[0].metadata.name}')
oc logs -n site-to-site-vpn $POD -f | grep -E "DPD|ESTABLISHED"

# Check for errors
oc logs -n site-to-site-vpn $POD --tail=100 | grep -i error
```

## Security Considerations

### Pod Security
- **Privileged mode**: Required for IPSec tunnel management
- **hostNetwork**: Required for VPN termination on node
- **Capabilities**: NET_ADMIN, SYS_ADMIN, NET_RAW required for tunnel setup

### Certificate Management
- Certificates stored in Kubernetes Secret (base64 encoded)
- Private key must be protected (never commit to git)
- Rotate certificates before expiration (AWS VPN certs expire after 1 year)

### Network Security
- IPSec provides encryption and authentication
- Certificate-based authentication (no PSK)
- DPD ensures tunnel liveness

## Dual Tunnel Configuration

**Current Status**: Single tunnel active (Tunnel 2)
- **Tunnel 1 (3.232.27.186)**: Requires endpoint-0 certificate (currently unavailable)
- **Tunnel 2 (98.94.136.2)**: Active with endpoint-1 certificate ✅

**For High Availability**: Deploy separate pod for Tunnel 1 with endpoint-0 certificate
- See: `/docs/VPN-DUAL-TUNNEL-SOLUTION.md`

## Additional Resources

### Documentation
- **Full Routing Configuration**: `/docs/VPN-ROUTING-FIX-ACTION-PLAN.md`
- **TGW Investigation**: `/docs/TGW-PEERING-INVESTIGATION.md`
- **Palo Alto Configuration**: `/docs/PALO-ALTO-POD-NETWORK-CONFIG.md`
- **Implementation Summary**: `/docs/VPN-IMPLEMENTATION-SUMMARY.md`

### AWS Resources
- **VPN Connection**: vpn-059ee0661e851adf4
- **Transit Gateway**: tgw-00279fe0ab1ac255c
- **TGW Route Table**: tgw-rtb-0ff564f70c91bf1d5
- **VPC**: vpc-0e9f579449a68a005
- **VPC Route Table**: rtb-0467d201a9cbdb89c

### OpenShift Resources
```bash
# View all VPN resources
oc get all -n site-to-site-vpn

# View VPN configuration
oc get configmap ipsec-config -n site-to-site-vpn -o yaml

# View deployment
oc get deployment site-to-site-vpn -n site-to-site-vpn -o yaml
```

## Support

**Issues**:
- VPN pod crashes: Check certificates and strongSwan logs
- No connectivity: Verify AWS routing and Palo Alto firewall
- Tunnel flapping: Check AWS VPN status and DPD timeouts

**Logs**:
```bash
# Full pod logs
oc logs -n site-to-site-vpn <pod-name>

# Follow logs in real-time
oc logs -n site-to-site-vpn <pod-name> -f

# Previous pod logs (if crashed)
oc logs -n site-to-site-vpn <pod-name> --previous
```

---

**Component Version**: 1.0  
**Last Updated**: 2026-02-02  
**strongSwan Version**: Latest from EPEL 9  
**Maintained by**: OpenShift Team
