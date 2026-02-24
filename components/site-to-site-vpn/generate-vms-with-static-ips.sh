#!/bin/bash
# Batch VM Creation with Static IPs
# This script generates VM manifests with static IP configuration

# Input CSV format: hostname,ip,mac_address,memory,cpu,disk_pvc
# Example: nymsdv297,10.132.104.10,00:50:56:bd:4e:b1,8Gi,4,nymsdv297-disk

generate_vm_manifest() {
    local HOSTNAME=$1
    local IP=$2
    local MAC=$3
    local MEMORY=${4:-8Gi}
    local CPU=${5:-4}
    local DISK_PVC=${6:-${HOSTNAME}-disk}
    local DNS_SERVER=${7:-10.132.104.53}
    local DNS_SECONDARY=${8:-8.8.8.8}
    
    cat <<EOF
---
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: ${HOSTNAME}
  namespace: windows-non-prod
  labels:
    app: windows-vm
    static-ip: "true"
    ip: "${IP}"
    hostname: "${HOSTNAME}"
  annotations:
    description: "Windows VM with static IP ${IP}"
spec:
  running: false
  template:
    metadata:
      labels:
        kubevirt.io/vm: ${HOSTNAME}
    spec:
      domain:
        cpu:
          cores: ${CPU}
        devices:
          disks:
            - name: rootdisk
              disk:
                bus: virtio
            - name: cloudinitdisk
              disk:
                bus: sata
          interfaces:
            - name: default
              masquerade: {}
            - name: net-0
              bridge: {}
              macAddress: "${MAC}"
        resources:
          requests:
            memory: ${MEMORY}
      networks:
        - name: default
          pod: {}
        - name: net-0
          multus:
            networkName: windows-non-prod
      volumes:
        - name: rootdisk
          persistentVolumeClaim:
            claimName: ${DISK_PVC}
        - name: cloudinitdisk
          cloudInitNoCloud:
            userData: |
              #cloud-config
              write_files:
                - path: C:\\configure-static-ip.ps1
                  permissions: '0644'
                  content: |
                    # Wait for network to be ready
                    Start-Sleep -Seconds 10
                    
                    # Find interface by MAC address
                    \$InterfaceName = (Get-NetAdapter | Where-Object {\$_.MacAddress -eq "${MAC}"}).Name
                    
                    if (\$InterfaceName) {
                        Write-Host "Configuring interface: \$InterfaceName"
                        
                        # Disable DHCP
                        Set-NetIPInterface -InterfaceAlias \$InterfaceName -Dhcp Disabled -ErrorAction SilentlyContinue
                        
                        # Remove existing IP
                        Remove-NetIPAddress -InterfaceAlias \$InterfaceName -Confirm:\$false -ErrorAction SilentlyContinue
                        
                        # Set Static IP
                        New-NetIPAddress -InterfaceAlias \$InterfaceName \`
                          -IPAddress "${IP}" \`
                          -PrefixLength 22 \`
                          -DefaultGateway "10.132.104.1" \`
                          -ErrorAction SilentlyContinue
                        
                        # Set DNS
                        Set-DnsClientServerAddress -InterfaceAlias \$InterfaceName \`
                          -ServerAddresses ("${DNS_SERVER}","${DNS_SECONDARY}")
                        
                        # Enable RDP
                        Set-ItemProperty -Path 'HKLM:\\System\\CurrentControlSet\\Control\\Terminal Server' \`
                          -name "fDenyTSConnections" -value 0
                        
                        # Configure Firewall for RDP and Ping
                        Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
                        Enable-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)" -ErrorAction SilentlyContinue
                        
                        # Set hostname
                        Rename-Computer -NewName "${HOSTNAME^^}" -Force -ErrorAction SilentlyContinue
                        
                        # Log configuration
                        \$LogContent = @"
Static IP Configuration Completed:
Hostname: ${HOSTNAME}
IP Address: ${IP}
Gateway: 10.132.104.1
DNS: ${DNS_SERVER}, ${DNS_SECONDARY}
Interface: \$InterfaceName
MAC: ${MAC}
Configured: \$(Get-Date)
"@
                        \$LogContent | Out-File C:\\static-ip-config.log
                        
                        Write-Host "Static IP configured successfully"
                    } else {
                        Write-Host "ERROR: Interface with MAC ${MAC} not found"
                        Get-NetAdapter | Out-File C:\\interfaces.log
                    }
              
              runcmd:
                - powershell.exe -ExecutionPolicy Bypass -File C:\\configure-static-ip.ps1
EOF
}

# Main script
if [ -z "$1" ]; then
    echo "Usage: $0 <vm-list.csv> [output-file.yaml]"
    echo ""
    echo "CSV Format: hostname,ip,mac_address,memory,cpu,disk_pvc"
    echo "Example:"
    echo "nymsdv297,10.132.104.10,00:50:56:bd:4e:b1,8Gi,4,nymsdv297-disk"
    echo "nymsdv301,10.132.104.11,00:50:56:8b:5f:43,16Gi,8,nymsdv301-disk"
    exit 1
fi

INPUT_CSV=$1
OUTPUT_FILE=${2:-vms-with-static-ips.yaml}

if [ ! -f "$INPUT_CSV" ]; then
    echo "Error: Input file $INPUT_CSV not found"
    exit 1
fi

echo "Generating VM manifests from $INPUT_CSV..."
echo "Output file: $OUTPUT_FILE"
echo ""

# Clear output file
> "$OUTPUT_FILE"

# Skip header line and process each VM
tail -n +2 "$INPUT_CSV" | while IFS=',' read -r hostname ip mac memory cpu disk_pvc; do
    # Trim whitespace
    hostname=$(echo "$hostname" | xargs)
    ip=$(echo "$ip" | xargs)
    mac=$(echo "$mac" | xargs)
    memory=$(echo "$memory" | xargs)
    cpu=$(echo "$cpu" | xargs)
    disk_pvc=$(echo "$disk_pvc" | xargs)
    
    echo "Generating manifest for $hostname ($ip)..."
    generate_vm_manifest "$hostname" "$ip" "$mac" "$memory" "$cpu" "$disk_pvc" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
done

echo ""
echo "✅ Generated VM manifests in $OUTPUT_FILE"
echo ""
echo "To apply:"
echo "  oc apply -f $OUTPUT_FILE"
echo ""
echo "To start VMs:"
echo "  oc patch vm <vm-name> -n windows-non-prod --type merge -p '{\"spec\":{\"running\":true}}'"
