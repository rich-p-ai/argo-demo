# Site-to-Site VPN Settings Map

**Purpose**: Map all site-to-site VPN settings for **ipsec-vpn** (Libreswan VM) and **StrongSwan** (container) to a single reference.

---

## 1. Overview: Two Implementations

| Aspect | **ipsec-vpn VM** (Libreswan) | **StrongSwan container** |
|--------|------------------------------|---------------------------|
| **Namespace** | `windows-non-prod` | `site-to-site-vpn` |
| **Type** | KubeVirt VirtualMachine | Deployment (1 pod) |
| **IPSec stack** | Libreswan 4.15 | strongSwan (EPEL on UBI9) |
| **Config file** | `/etc/ipsec.conf` (on VM) | StrongSwan `ipsec.conf` from ConfigMap |
| **Certs** | NSS DB: `sql:/var/lib/ipsec/nss` | PEM files: `client-cert.pem`, `client-key.pem`, `ca-chain.pem` |
| **Role** | CUDN gateway (10.227.128.0/21) + tunnel termination | Pod-network VPN (hostNetwork); optional route to CUDN |
| **Deployed by** | Applied separately (e.g. `oc apply -f ipsec-vpn-vm.yaml`) | `oc apply -k components/site-to-site-vpn/` (in kustomization) |

---

## 2. AWS Side (Common)

| Setting | Value |
|---------|--------|
| **VPN Connection ID** | `vpn-059ee0661e851adf4` |
| **Customer Gateway** | `cgw-0f82cc789449111b7` |
| **Tunnel 1 (AWS endpoint)** | `3.232.27.186` |
| **Tunnel 2 (AWS endpoint)** | `98.94.136.2` |
| **Auth** | Certificate-based (ACM PCA) |
| **Certificate used** | Endpoint-1 for Tunnel 2; Endpoint-0 for Tunnel 1 (CN: `vpn-059ee0661e851adf4.endpoint-0` / `.endpoint-1`) |

**AWS tunnel options (current vs required for Libreswan)**  
- AWS was configured with **MODP1024** (DH Group 2).  
- Libreswan 4.15 does **not** support MODP1024; needs **MODP1536** (DH Group 5) or higher.  
- Use `scripts/update-aws-vpn-dh-groups.sh` or AWS CLI `modify-vpn-tunnel-options` to set Phase1/Phase2 DH groups to 5,14 (and optionally 15,16).

---

## 3. ipsec-vpn VM (Libreswan) – Settings Map

**Location**: VM `ipsec-vpn` in `windows-non-prod`.  
**Defined in**: `Cluster-Config/components/site-to-site-vpn/ipsec-vpn-vm.yaml` (cloud-init) and **runtime** config documented in `IPSEC-CONFIGURATION-STATUS.md`.

### 3.1 Network (on VM)

| Interface | Role | IP/Net | Notes |
|-----------|------|--------|--------|
| **eth0** | Pod network (VPN egress) | DHCP / default route | `left=%defaultroute` uses this for IKE/ESP to AWS |
| **eth1** | CUDN gateway | **10.227.128.1/21** (or 10.227.128.255 if reset) | Gateway for Windows VMs on CUDN |

- **Left subnet (advertised to AWS)**: `10.227.128.0/21`  
- **Right subnet (on-prem)** in config: `10.63.0.0/16` (additional subnets can be added to `rightsubnet`/`rightsubnets`).

### 3.2 Libreswan `/etc/ipsec.conf` (runtime – from IPSEC-CONFIGURATION-STATUS.md)

```conf
config setup
    logfile=/var/log/pluto.log
    plutodebug=all
    uniqueids=no
    ikev1-policy=accept

conn %default
    ikev2=no
    ike=aes128-sha1-modp1536
    phase2alg=aes128-sha1-modp1536
    ikelifetime=28800s
    salifetime=3600s
    dpdaction=restart
    dpddelay=10
    dpdtimeout=30
    keyingtries=%forever
    rekey=yes
    reauth=no
    authby=rsasig
    leftcert=vpn-059ee0661e851adf4.endpoint-1
    left=%defaultroute
    leftsubnet=10.227.128.0/21
    rightsubnet=10.63.0.0/16
    auto=add
    type=tunnel

conn aws-vpn-tunnel1
    also=%default
    right=3.232.27.186
    rightid="C=US, ST=WA, L=Seattle, O=Amazon.com, OU=AWS, CN=vpn-059ee0661e851adf4.endpoint-0"
    leftid=%fromcert

conn aws-vpn-tunnel2
    also=%default
    right=98.94.136.2
    rightid="C=US, ST=WA, L=Seattle, O=Amazon.com, OU=AWS, CN=vpn-059ee0661e851adf4.endpoint-1"
    leftid=%fromcert
```

### 3.3 Libreswan settings summary (ipsec-vpn)

| Setting | Value |
|---------|--------|
| **IKE version** | IKEv1 only (`ikev2=no`, `ikev1-policy=accept`) |
| **Phase 1 (IKE)** | AES128, SHA1, MODP1536 (DH 5), 28800s |
| **Phase 2 (ESP)** | AES128-SHA1_96, MODP1536, 3600s |
| **Auth** | `authby=rsasig`, cert in NSS |
| **Left cert (NSS nickname)** | `vpn-059ee0661e851adf4.endpoint-1` |
| **Left ID** | From cert (`leftid=%fromcert`) |
| **DPD** | restart, 10s delay, 30s timeout |
| **NSS DB** | `sql:/var/lib/ipsec/nss` (certutil -L / -K) |

### 3.4 Where ipsec-vpn config is defined

- **Cloud-init (initial VM)**  
  - `ipsec-vpn-vm.yaml`: `userdata` → `write_files` → `/etc/NetworkManager/system-connections/eth1.nmconnection` (10.227.128.1/21), `/etc/ipsec.d/aws-vpn.conf` (placeholder, MODP1024; **overwritten** by actual `/etc/ipsec.conf` on VM).  
- **Runtime (actual)**  
  - `/etc/ipsec.conf` on the VM (as in IPSEC-CONFIGURATION-STATUS.md); maintained manually or by fix scripts.  
- **Helper scripts (host)**  
  - `configure-gateway.sh` – eth1 static IP and iptables.  
  - `fix-ipsec-config.sh` – **StrongSwan-style** config (charondebug, etc.); **not** used for Libreswan VM; do not apply as-is to ipsec-vpn.

---

## 4. StrongSwan Container – Settings Map

**Location**: Deployment `site-to-site-vpn` in `site-to-site-vpn`.  
**Defined in**:  
- `Cluster-Config/components/site-to-site-vpn/configmap.yaml` (`ipsec-config`)  
- `Cluster-Config/components/site-to-site-vpn/deployment.yaml`

### 4.1 ConfigMap `ipsec-config` (StrongSwan ipsec.conf)

- **strongSwan-specific**: `charondebug="ike 2, knl 2, cfg 2, net 2, esp 2, dmn 2, mgr 2"`, `keyexchange=ikev1`, `leftcert=client-cert.pem`, `leftsourceip=...`, `mark=100/200`, `reqid=1/2`.
- **Left**: `left=%defaultroute`, `leftsubnet=0.0.0.0/0` (routes to VPN from pod/node).
- **Right subnets**: `10.63.0.0/16,10.68.0.0/16,10.99.0.0/16,10.110.0.0/16,10.140.0.0/16,10.141.0.0/16,10.158.0.0/16,10.227.112.0/20`.
- **Tunnels**:  
  - Tunnel 1: `right=3.232.27.186`, `rightid="CN=vpn-059ee0661e851adf4.endpoint-0"`, `leftid="vpn-059ee0661e851adf4.endpoint-0"`, `leftsourceip=169.254.43.134`, `mark=100`, `reqid=1`.  
  - Tunnel 2: `right=98.94.136.2`, `rightid="CN=vpn-059ee0661e851adf4.endpoint-1"`, `leftid="vpn-059ee0661e851adf4.endpoint-0"`, `leftsourceip=169.254.118.14`, `mark=200`, `reqid=2`.
- **Algorithms**: `ike=aes128-sha1-modp1024!`, `esp=aes128-sha1-modp1024!` (MODP1024; compatible with AWS DH Group 2).
- **Secrets**: `ipsec.secrets` → `: RSA client-key.pem`.

### 4.2 StrongSwan settings summary

| Setting | Value |
|---------|--------|
| **IKE** | IKEv1, AES128, SHA1, MODP1024, 28800s |
| **ESP** | AES128-SHA1, MODP1024, 3600s |
| **Auth** | RSA sig, PEM certs |
| **Cert/key** | `client-cert.pem`, `client-key.pem` (from secret `vpn-certificates`) |
| **CA** | `ca-chain.pem` (in secret) → strongSwan ipsec.d/cacerts |
| **Left subnet** | 0.0.0.0/0 |
| **Right subnets** | 10.63, 10.68, 10.99, 10.110, 10.140, 10.141, 10.158, 10.227.112.0/20 |

### 4.3 Certificates (StrongSwan)

- **Kubernetes secret**: `vpn-certificates` in `site-to-site-vpn`.  
- **Source**: ExternalSecret → AWS Secrets Manager key `ROSA-NONPROD-VPN-Tunnel2-Certificates`.  
- **Files**: `client-cert.pem`, `client-key.pem`, `ca-chain.pem` (see `externalsecret-vpn-certs.yaml`).

### 4.4 Startup (container)

- **Script**: ConfigMap `start-vpn.sh` → installs strongSwan from EPEL, copies config/certs to `/etc/strongswan/`, runs `starter --nofork` (charon).
- **Probes**: Liveness/readiness check for process `charon`.

---

## 5. Side-by-Side: Key Differences

| Setting | ipsec-vpn (Libreswan) | StrongSwan container |
|---------|------------------------|----------------------|
| **leftsubnet** | 10.227.128.0/21 | 0.0.0.0/0 |
| **rightsubnet** | 10.63.0.0/16 (expandable) | 10.63, 10.68, 10.99, 10.110, 10.140, 10.141, 10.158, 10.227.112.0/20 |
| **DH group** | MODP1536 (required by Libreswan 4.15) | MODP1024 (AWS DH 2) |
| **Config syntax** | Libreswan (plutodebug, ikev1-policy, leftcert=NSS name) | StrongSwan (charondebug, leftcert=filename, leftsourceip, mark, reqid) |
| **Certs** | NSS DB (certutil) | PEM files |
| **Gateway for CUDN** | Yes – eth1 10.227.128.1/21 | No – optional route to CUDN via gateway VM |

---

## 6. File Reference

| What | File path |
|------|-----------|
| ipsec-vpn VM definition + cloud-init | `Cluster-Config/components/site-to-site-vpn/ipsec-vpn-vm.yaml` |
| Libreswan runtime config (documented) | `IPSEC-CONFIGURATION-STATUS.md` |
| StrongSwan config (ConfigMap) | `Cluster-Config/components/site-to-site-vpn/configmap.yaml` |
| StrongSwan deployment | `Cluster-Config/components/site-to-site-vpn/deployment.yaml` |
| VPN certs (ExternalSecret) | `Cluster-Config/components/site-to-site-vpn/externalsecret-vpn-certs.yaml` |
| Gateway script (eth1 + iptables) | `Cluster-Config/components/site-to-site-vpn/configure-gateway.sh` |
| AWS DH group update script | `scripts/update-aws-vpn-dh-groups.sh` |
| Legacy fix script (StrongSwan-style; do not use on Libreswan VM) | `fix-ipsec-config.sh` |

---

## 7. Quick verification commands

**ipsec-vpn VM (Libreswan)**  
```bash
virtctl console ipsec-vpn -n windows-non-prod
# then on VM:
ip addr show eth1
ipsec status
certutil -L -d sql:/var/lib/ipsec/nss
tail -20 /var/log/pluto.log
```

**StrongSwan pod**  
```bash
oc get pods -n site-to-site-vpn -l app=site-to-site-vpn
oc rsh -n site-to-site-vpn deployment/site-to-site-vpn -- ps aux | grep charon
oc logs -n site-to-site-vpn deployment/site-to-site-vpn
```

**AWS VPN**  
```bash
aws ec2 describe-vpn-connections --vpn-connection-ids vpn-059ee0661e851adf4
```
