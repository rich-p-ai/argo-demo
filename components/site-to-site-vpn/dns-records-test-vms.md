# DNS Records for Test VMs

## Forward Zone Records (Add to corp.cusa.canon.com zone)

```
; Test VMs with Reserved Static IPs
nymsdv297.corp.cusa.canon.com.   IN  A    10.132.104.10
nymsdv301.corp.cusa.canon.com.   IN  A    10.132.104.11
nymsdv312.corp.cusa.canon.com.   IN  A    10.132.104.19
```

## Reverse Zone Records (Add to 10.132.104.0/22 reverse zone)

### Subnet: 104.132.10.in-addr.arpa

```
; Test VMs
10.104.132.10.in-addr.arpa.  IN  PTR  nymsdv297.corp.cusa.canon.com.
11.104.132.10.in-addr.arpa.  IN  PTR  nymsdv301.corp.cusa.canon.com.
19.104.132.10.in-addr.arpa.  IN  PTR  nymsdv312.corp.cusa.canon.com.
```

## CNAME Records (Optional - for easy access)

If you want short names:

```
; Short names
nymsdv297    IN  CNAME  nymsdv297.corp.cusa.canon.com.
nymsdv301    IN  CNAME  nymsdv301.corp.cusa.canon.com.
nymsdv312    IN  CNAME  nymsdv312.corp.cusa.canon.com.
```

## Windows DNS Server Configuration

### Using DNS Manager GUI:

1. Open **DNS Manager** on your DNS server
2. Navigate to **Forward Lookup Zones** → **corp.cusa.canon.com**
3. Right-click → **New Host (A or AAAA)**
4. Add each record:
   - Name: `nymsdv297`
   - IP: `10.132.104.10`
   - ✓ Create associated PTR record
   - Click **Add Host**
5. Repeat for nymsdv301 (.11) and nymsdv312 (.19)

### Using PowerShell:

```powershell
# Add Forward (A) Records
Add-DnsServerResourceRecordA -Name "nymsdv297" -ZoneName "corp.cusa.canon.com" -IPv4Address "10.132.104.10" -CreatePtr
Add-DnsServerResourceRecordA -Name "nymsdv301" -ZoneName "corp.cusa.canon.com" -IPv4Address "10.132.104.11" -CreatePtr
Add-DnsServerResourceRecordA -Name "nymsdv312" -ZoneName "corp.cusa.canon.com" -IPv4Address "10.132.104.19" -CreatePtr

# Verify Records
Get-DnsServerResourceRecord -ZoneName "corp.cusa.canon.com" -Name "nymsdv297"
Get-DnsServerResourceRecord -ZoneName "corp.cusa.canon.com" -Name "nymsdv301"
Get-DnsServerResourceRecord -ZoneName "corp.cusa.canon.com" -Name "nymsdv312"

# Test Resolution
Resolve-DnsName nymsdv297.corp.cusa.canon.com
Resolve-DnsName nymsdv301.corp.cusa.canon.com
Resolve-DnsName nymsdv312.corp.cusa.canon.com
```

## Linux BIND DNS Configuration

If using BIND DNS server:

### Forward Zone File (/var/named/corp.cusa.canon.com.zone)

```bind
; Add to zone file
nymsdv297    IN  A    10.132.104.10
nymsdv301    IN  A    10.132.104.11
nymsdv312    IN  A    10.132.104.19
```

### Reverse Zone File (/var/named/104.132.10.in-addr.arpa.zone)

```bind
; Add to reverse zone file
10    IN  PTR  nymsdv297.corp.cusa.canon.com.
11    IN  PTR  nymsdv301.corp.cusa.canon.com.
19    IN  PTR  nymsdv312.corp.cusa.canon.com.
```

### Reload BIND

```bash
# Check zone files
named-checkzone corp.cusa.canon.com /var/named/corp.cusa.canon.com.zone
named-checkzone 104.132.10.in-addr.arpa /var/named/104.132.10.in-addr.arpa.zone

# Reload zones
rndc reload corp.cusa.canon.com
rndc reload 104.132.10.in-addr.arpa

# Or restart BIND
systemctl restart named
```

## Verification Commands

### From Company Network Workstation:

```powershell
# Test forward lookup
nslookup nymsdv297.corp.cusa.canon.com
nslookup nymsdv301.corp.cusa.canon.com
nslookup nymsdv312.corp.cusa.canon.com

# Test reverse lookup
nslookup 10.132.104.10
nslookup 10.132.104.11
nslookup 10.132.104.19

# Ping by hostname
ping nymsdv297.corp.cusa.canon.com
ping nymsdv301.corp.cusa.canon.com
ping nymsdv312.corp.cusa.canon.com
```

### From Linux:

```bash
# Forward lookup
dig nymsdv297.corp.cusa.canon.com
dig nymsdv301.corp.cusa.canon.com
dig nymsdv312.corp.cusa.canon.com

# Reverse lookup
dig -x 10.132.104.10
dig -x 10.132.104.11
dig -x 10.132.104.19

# Short test
host nymsdv297.corp.cusa.canon.com
host 10.132.104.10
```

## Expected Results

### Forward Lookup:
```
Server:  dns.corp.cusa.canon.com
Address:  10.222.155.x

Name:    nymsdv297.corp.cusa.canon.com
Address:  10.132.104.10
```

### Reverse Lookup:
```
Server:  dns.corp.cusa.canon.com
Address:  10.222.155.x

10.104.132.10.in-addr.arpa    name = nymsdv297.corp.cusa.canon.com
```

## Troubleshooting

### Issue: DNS not resolving

**Check:**
1. DNS server has records: `Get-DnsServerResourceRecord`
2. DNS zone transferred to secondaries: `Get-DnsServerZoneTransfer`
3. Firewall allows DNS (UDP/TCP 53)
4. Client using correct DNS server: `ipconfig /all`

**Fix:**
```powershell
# Clear DNS cache on client
ipconfig /flushdns

# Clear DNS cache on server
Clear-DnsServerCache

# Force zone reload
rndc reload
```

### Issue: Reverse DNS not working

**Check:**
1. Reverse zone exists
2. PTR records created
3. In-addr.arpa zone configured

### Issue: Can ping IP but not hostname

**Problem:** DNS not configured properly

**Solution:**
- Add DNS server to VM network config
- Check DNS suffix search list

## DNS Server IP

**Your DNS Server:** (Update with actual IP)
```
Primary DNS:   10.222.155.x  (or actual company DNS server)
Secondary DNS: 10.222.155.y
```

## Integration with RDP

Once DNS is configured, users can RDP using hostnames:

```
mstsc /v:nymsdv297.corp.cusa.canon.com
mstsc /v:nymsdv301.corp.cusa.canon.com
mstsc /v:nymsdv312.corp.cusa.canon.com
```

Much easier than remembering IP addresses!
