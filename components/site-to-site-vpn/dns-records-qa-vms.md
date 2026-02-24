# DNS Records for QA VMs

## Overview

This document contains DNS record configurations for the QA VMs migrated to OpenShift:
- **NYMSQA428** - 10.132.104.20
- **NYMSQA429** - 10.132.104.21

## Forward DNS (A Records)

Add these records to your company DNS server in the appropriate zone:

```dns
; QA Virtual Machines - OpenShift Non-Prod
NYMSQA428.domain.com.    IN  A  10.132.104.20
NYMSQA429.domain.com.    IN  A  10.132.104.21
```

**Replace `domain.com` with your actual domain name.**

### Windows DNS Server (PowerShell)

```powershell
# Add A records
Add-DnsServerResourceRecordA -Name "NYMSQA428" -ZoneName "domain.com" -IPv4Address "10.132.104.20"
Add-DnsServerResourceRecordA -Name "NYMSQA429" -ZoneName "domain.com" -IPv4Address "10.132.104.21"
```

### BIND DNS Server

```bash
# Edit zone file
vi /var/named/domain.com.zone

# Add records
NYMSQA428    IN  A  10.132.104.20
NYMSQA429    IN  A  10.132.104.21

# Reload zone
rndc reload domain.com
```

## Reverse DNS (PTR Records)

Add these records for reverse DNS lookups:

```dns
; Reverse zone: 104.132.10.in-addr.arpa
20.104.132.10.in-addr.arpa.  IN  PTR  NYMSQA428.domain.com.
21.104.132.10.in-addr.arpa.  IN  PTR  NYMSQA429.domain.com.
```

### Windows DNS Server (PowerShell)

```powershell
# Add PTR records
Add-DnsServerResourceRecordPtr -Name "20" -ZoneName "104.132.10.in-addr.arpa" -PtrDomainName "NYMSQA428.domain.com"
Add-DnsServerResourceRecordPtr -Name "21" -ZoneName "104.132.10.in-addr.arpa" -PtrDomainName "NYMSQA429.domain.com"
```

### BIND DNS Server

```bash
# Edit reverse zone file
vi /var/named/104.132.10.in-addr.arpa.zone

# Add PTR records
20    IN  PTR  NYMSQA428.domain.com.
21    IN  PTR  NYMSQA429.domain.com.

# Reload zone
rndc reload 104.132.10.in-addr.arpa
```

## Verification

### Test Forward DNS Resolution

```bash
# From Windows
nslookup NYMSQA428.domain.com
nslookup NYMSQA429.domain.com

# From Linux
dig NYMSQA428.domain.com
dig NYMSQA429.domain.com

# Expected output:
# Name: NYMSQA428.domain.com
# Address: 10.132.104.20
```

### Test Reverse DNS Resolution

```bash
# From Windows
nslookup 10.132.104.20
nslookup 10.132.104.21

# From Linux
dig -x 10.132.104.20
dig -x 10.132.104.21

# Expected output:
# 20.104.132.10.in-addr.arpa  name = NYMSQA428.domain.com.
```

### Test Connectivity

After DNS records are active (may take up to DNS TTL time):

```bash
# Ping by hostname
ping NYMSQA428
ping NYMSQA429

# RDP by hostname
mstsc /v:NYMSQA428
mstsc /v:NYMSQA429
```

## DNS Propagation

- **Internal DNS**: Changes typically propagate in seconds to minutes
- **DNS Cache**: Users may need to flush DNS cache:
  ```cmd
  ipconfig /flushdns
  ```

## Complete DNS Record Set (All Migrated VMs)

For reference, here are all VM DNS records including previous test VMs:

### Forward DNS (A Records)
```dns
; Test VMs
NYMSDV297.domain.com.    IN  A  10.132.104.10
NYMSDV301.domain.com.    IN  A  10.132.104.11
NYMSDV312.domain.com.    IN  A  10.132.104.19

; QA VMs
NYMSQA428.domain.com.    IN  A  10.132.104.20
NYMSQA429.domain.com.    IN  A  10.132.104.21
```

### Reverse DNS (PTR Records)
```dns
; Test VMs
10.104.132.10.in-addr.arpa.  IN  PTR  NYMSDV297.domain.com.
11.104.132.10.in-addr.arpa.  IN  PTR  NYMSDV301.domain.com.
19.104.132.10.in-addr.arpa.  IN  PTR  NYMSDV312.domain.com.

; QA VMs
20.104.132.10.in-addr.arpa.  IN  PTR  NYMSQA428.domain.com.
21.104.132.10.in-addr.arpa.  IN  PTR  NYMSQA429.domain.com.
```

## Automation Option

### Bulk Add DNS Records (PowerShell)

```powershell
# Define VM records
$vms = @(
    @{Name="NYMSDV297"; IP="10.132.104.10"},
    @{Name="NYMSDV301"; IP="10.132.104.11"},
    @{Name="NYMSDV312"; IP="10.132.104.19"},
    @{Name="NYMSQA428"; IP="10.132.104.20"},
    @{Name="NYMSQA429"; IP="10.132.104.21"}
)

$zone = "domain.com"
$reverseZone = "104.132.10.in-addr.arpa"

# Add A and PTR records
foreach ($vm in $vms) {
    $name = $vm.Name
    $ip = $vm.IP
    $lastOctet = $ip.Split('.')[-1]
    
    # Add A record
    Add-DnsServerResourceRecordA -Name $name -ZoneName $zone -IPv4Address $ip -ErrorAction SilentlyContinue
    Write-Host "Added A record: $name.$zone -> $ip"
    
    # Add PTR record
    Add-DnsServerResourceRecordPtr -Name $lastOctet -ZoneName $reverseZone -PtrDomainName "$name.$zone" -ErrorAction SilentlyContinue
    Write-Host "Added PTR record: $ip -> $name.$zone"
}

Write-Host "`nDNS records added successfully!"
```

### Bulk Add DNS Records (BIND/Linux)

```bash
#!/bin/bash
# add-vm-dns-records.sh

ZONE_FILE="/var/named/domain.com.zone"
REV_ZONE_FILE="/var/named/104.132.10.in-addr.arpa.zone"

# Add A records
cat >> $ZONE_FILE << 'EOF'
; Migrated VMs - OpenShift Non-Prod
NYMSDV297    IN  A  10.132.104.10
NYMSDV301    IN  A  10.132.104.11
NYMSDV312    IN  A  10.132.104.19
NYMSQA428    IN  A  10.132.104.20
NYMSQA429    IN  A  10.132.104.21
EOF

# Add PTR records
cat >> $REV_ZONE_FILE << 'EOF'
; Migrated VMs - OpenShift Non-Prod
10    IN  PTR  NYMSDV297.domain.com.
11    IN  PTR  NYMSDV301.domain.com.
19    IN  PTR  NYMSDV312.domain.com.
20    IN  PTR  NYMSQA428.domain.com.
21    IN  PTR  NYMSQA429.domain.com.
EOF

# Increment serial numbers
# (Manual step - edit zone files to update serial)

# Reload zones
rndc reload domain.com
rndc reload 104.132.10.in-addr.arpa

echo "DNS records added successfully!"
```

## Notes

- Ensure reverse DNS zone `104.132.10.in-addr.arpa` exists on your DNS server
- Update serial numbers in zone files before reloading (BIND)
- DNS changes may require zone transfer to secondary DNS servers
- Test DNS resolution from multiple network locations

---

**Next Step**: After adding DNS records, wait for propagation and test resolution before attempting RDP connections by hostname.
