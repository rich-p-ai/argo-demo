#!/bin/bash
# Update Existing VMs with Cloud-Init for Static IP Configuration
# This patches VMs to add cloud-init disk for static IP configuration

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <vm-name> <static-ip> [mac-address]"
    echo ""
    echo "Example:"
    echo "  $0 nymsdv297 10.132.104.10 00:50:56:bd:4e:b1"
    echo ""
    exit 1
fi

VM_NAME=$1
STATIC_IP=$2
MAC_ADDRESS=${3:-""}
NAMESPACE="windows-non-prod"

echo "=========================================="
echo "  Update VM with Static IP Configuration"
echo "=========================================="
echo ""
echo "VM Name: $VM_NAME"
echo "Static IP: $STATIC_IP"
echo "MAC Address: $MAC_ADDRESS"
echo "Namespace: $NAMESPACE"
echo ""

# Check if VM exists
if ! oc get vm $VM_NAME -n $NAMESPACE &>/dev/null; then
    echo "❌ ERROR: VM $VM_NAME not found in namespace $NAMESPACE"
    exit 1
fi

echo "✅ VM found"
echo ""

# Check if VM is running
VM_RUNNING=$(oc get vm $VM_NAME -n $NAMESPACE -o jsonpath='{.spec.running}')
if [ "$VM_RUNNING" = "true" ]; then
    echo "⚠️  WARNING: VM is currently running"
    echo "VM must be stopped to update cloud-init configuration"
    echo ""
    read -p "Stop VM now? (yes/no): " STOP_VM
    if [ "$STOP_VM" = "yes" ]; then
        echo "Stopping VM..."
        oc patch vm $VM_NAME -n $NAMESPACE --type merge -p '{"spec":{"running":false}}'
        echo "Waiting for VM to stop..."
        oc wait --for=delete vmi/$VM_NAME -n $NAMESPACE --timeout=300s
        echo "✅ VM stopped"
    else
        echo "Aborted. Stop VM manually and run again."
        exit 0
    fi
fi

# Create cloud-init secret
echo ""
echo "Creating cloud-init secret for static IP configuration..."

cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${VM_NAME}-cloudinit
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  userdata: |
    #cloud-config
    write_files:
      - path: C:\\configure-static-ip.ps1
        permissions: '0644'
        content: |
          # Wait for network
          Start-Sleep -Seconds 10
          
          # Configure Static IP
          \$IP = "${STATIC_IP}"
          \$Gateway = "10.132.104.1"
          \$DNS = @("10.132.104.53","8.8.8.8")
          
          # Find interface
          if ("${MAC_ADDRESS}") {
              \$Adapter = Get-NetAdapter | Where-Object {\$_.MacAddress -eq "${MAC_ADDRESS}"}
          } else {
              \$Adapter = Get-NetAdapter | Where-Object {\$_.Status -eq "Up"} | Select-Object -First 1
          }
          
          if (\$Adapter) {
              \$InterfaceName = \$Adapter.Name
              Write-Host "Configuring interface: \$InterfaceName"
              
              # Remove DHCP config
              Set-NetIPInterface -InterfaceAlias \$InterfaceName -Dhcp Disabled -ErrorAction SilentlyContinue
              Remove-NetIPAddress -InterfaceAlias \$InterfaceName -Confirm:\$false -ErrorAction SilentlyContinue
              Remove-NetRoute -InterfaceAlias \$InterfaceName -Confirm:\$false -ErrorAction SilentlyContinue
              
              # Set static IP
              New-NetIPAddress -InterfaceAlias \$InterfaceName \`
                -IPAddress \$IP \`
                -PrefixLength 22 \`
                -DefaultGateway \$Gateway
              
              # Set DNS
              Set-DnsClientServerAddress -InterfaceAlias \$InterfaceName -ServerAddresses \$DNS
              
              # Enable RDP
              Set-ItemProperty -Path 'HKLM:\\System\\CurrentControlSet\\Control\\Terminal Server' \`
                -name "fDenyTSConnections" -value 0
              
              # Configure Firewall
              Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
              Enable-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)" -ErrorAction SilentlyContinue
              
              # Set hostname
              Rename-Computer -NewName "${VM_NAME^^}" -Force -ErrorAction SilentlyContinue
              
              # Log
              "Static IP ${STATIC_IP} configured on \$(Get-Date)" | Out-File C:\\static-ip-config.log
              
              Write-Host "Configuration complete!"
          } else {
              Write-Host "ERROR: Network adapter not found"
              Get-NetAdapter | Out-File C:\\adapters.log
          }
    
    runcmd:
      - powershell.exe -ExecutionPolicy Bypass -File C:\\configure-static-ip.ps1
EOF

echo "✅ Cloud-init secret created"
echo ""

# Patch VM to add cloud-init disk
echo "Patching VM to add cloud-init disk..."

# Get current VM spec
VM_SPEC=$(oc get vm $VM_NAME -n $NAMESPACE -o json)

# Check if cloudinitdisk already exists
HAS_CLOUDINIT=$(echo "$VM_SPEC" | jq '.spec.template.spec.domain.devices.disks[] | select(.name=="cloudinitdisk")' | wc -l)

if [ "$HAS_CLOUDINIT" -gt 0 ]; then
    echo "⚠️  VM already has cloudinitdisk - updating..."
    oc patch vm $VM_NAME -n $NAMESPACE --type=json -p='[
      {"op": "replace", "path": "/spec/template/spec/volumes", "value": [
        '"$(echo "$VM_SPEC" | jq -c '.spec.template.spec.volumes[] | select(.name!="cloudinitdisk")')"',
        {
          "name": "cloudinitdisk",
          "cloudInitNoCloud": {
            "secretRef": {
              "name": "'"${VM_NAME}-cloudinit"'"
            }
          }
        }
      ]}
    ]'
else
    echo "Adding cloudinitdisk to VM..."
    # Add cloud-init disk
    oc patch vm $VM_NAME -n $NAMESPACE --type=json -p='[
      {"op": "add", "path": "/spec/template/spec/domain/devices/disks/-", "value": 
        {"name": "cloudinitdisk", "disk": {"bus": "sata"}}
      },
      {"op": "add", "path": "/spec/template/spec/volumes/-", "value":
        {"name": "cloudinitdisk", "cloudInitNoCloud": {"secretRef": {"name": "'"${VM_NAME}-cloudinit"'"}}}
      }
    ]'
fi

echo "✅ VM patched with cloud-init configuration"
echo ""
echo "=========================================="
echo "  ✅ Configuration Complete!"
echo "=========================================="
echo ""
echo "Next Steps:"
echo "  1. Reserve IP in whereabouts:"
echo "     Add ${STATIC_IP}/32 to windows-non-prod NAD exclusion list"
echo ""
echo "  2. Start the VM:"
echo "     oc patch vm $VM_NAME -n $NAMESPACE --type merge -p '{\"spec\":{\"running\":true}}'"
echo ""
echo "  3. Monitor first boot (cloud-init runs):"
echo "     oc get vmi $VM_NAME -n $NAMESPACE -w"
echo ""
echo "  4. Verify static IP configured:"
echo "     oc get vmi $VM_NAME -n $NAMESPACE -o jsonpath='{.status.interfaces[0].ipAddress}'"
echo ""
echo "  5. Check configuration log (via console):"
echo "     virtctl console $VM_NAME -n $NAMESPACE"
echo "     # Inside Windows: type C:\\static-ip-config.log"
echo ""
echo "  6. Test from company network:"
echo "     ping ${STATIC_IP}"
echo "     mstsc /v:${STATIC_IP}"
echo ""
