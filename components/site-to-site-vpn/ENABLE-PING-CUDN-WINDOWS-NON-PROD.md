# Enable Ping (ICMP) for CUDN Windows-Non-Prod

**Purpose:** Allow ping (ICMP Echo Request/Reply) to and from Windows VMs attached to the CUDN `windows-non-prod` network (10.227.128.0/21).

---

## Summary

- **Inbound ping to Windows VMs:** Windows Firewall blocks inbound ICMP by default. Enable the ICMPv4-In rule on each VM (or via GPO).
- **Outbound ping from Windows VMs:** Usually allowed by default; if blocked, check network/firewall path (e.g. corporate firewall or VPN path).
- **Between VMs on CUDN:** Each VM that should *respond* to ping needs the inbound rule; no OpenShift/OVN change needed for L2 CUDN.

---

## 1. Enable Inbound Ping on Each Windows VM (Required)

So that other hosts (corporate workstations, other VMs) can ping the Windows VM.

### Option A: PowerShell (one-time, per VM)

Run **as Administrator** on the Windows VM:

```powershell
# Enable the built-in rule "File and Printer Sharing (Echo Request - ICMPv4-In)"
Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing"

# Or enable only ICMPv4 Echo Request (minimal change)
New-NetFirewallRule -DisplayName "Allow ICMPv4 Echo Request" `
  -Protocol ICMPv4 `
  -IcmpType 8 `
  -Enabled True `
  -Direction Inbound `
  -Action Allow
```

To restrict to the CUDN subnet only (optional, more secure):

```powershell
New-NetFirewallRule -DisplayName "Allow ICMPv4 Echo Request (CUDN)" `
  -Protocol ICMPv4 `
  -IcmpType 8 `
  -Enabled True `
  -Direction Inbound `
  -Action Allow `
  -RemoteAddress 10.227.128.0/21
```

### Option B: GUI (one-time, per VM)

1. Open **Windows Defender Firewall with Advanced Security**.
2. **Inbound Rules** → find **File and Printer Sharing (Echo Request - ICMPv4-In)**.
3. Right-click → **Enable Rule**.

### Option C: Group Policy (many VMs, same domain)

1. Create or edit a GPO that applies to the Windows VMs (or their OU).
2. **Computer Configuration** → **Policies** → **Windows Settings** → **Security Settings** → **Windows Defender Firewall with Advanced Security** → **Inbound Rules**.
3. New Rule → **Custom** → Protocol: **ICMPv4** → ICMP settings: **Echo Request** → Allow → Apply to the relevant profile (Domain/Private/Public).
4. Link the GPO to the OU containing the CUDN windows-non-prod VMs.

---

## 2. Verify

**From a corporate workstation or another host on the same network:**

```powershell
ping <windows-vm-corporate-ip>
```

**From inside the Windows VM (outbound ping):**

```powershell
ping 10.227.128.1
ping <another-host-on-cudn>
```

---

## 3. Network Path (If Ping Still Fails)

- **VPN path:** Ensure the IPSec VPN from the cluster (e.g. ipsec-vpn VM at 10.227.128.1) to the corporate side is up so traffic can reach 10.227.128.0/21. See `IPSEC-CONFIGURATION-STATUS.md` if tunnels are not establishing.
- **Corporate firewall/ACL:** If there is a firewall between the CUDN segment and the rest of the corporate network, ensure **ICMP** (or at least Echo Request/Reply) is allowed for 10.227.128.0/21. No change is required in the OpenShift CUDN definition; it is L2 and does not filter ICMP.

---

## Reference

- CUDN definition: `Cluster-Config/components/site-to-site-vpn/cudn-windows-non-prod.yaml` (10.227.128.0/21).
- Gateway for Windows VMs on CUDN: `10.227.128.1` (ipsec-vpn VM eth1).
