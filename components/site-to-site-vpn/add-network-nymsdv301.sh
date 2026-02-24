#!/bin/bash
# Apply Secondary Network to NYMSDV301 After Limit Increase
# Run this script AFTER cluster admin increases network resource limit

set -e

VM_NAME="nymsdv301"
NAMESPACE="windows-non-prod"
STATIC_IP="10.132.104.11"

echo "=============================================="
echo "  Add Secondary Network to NYMSDV301"
echo "=============================================="
echo ""
echo "VM: $VM_NAME"
echo "Namespace: $NAMESPACE"
echo "Static IP: $STATIC_IP"
echo ""

# Check if VM exists
echo "Checking VM status..."
if ! oc get vm $VM_NAME -n $NAMESPACE &>/dev/null; then
    echo "❌ Error: VM $VM_NAME not found in namespace $NAMESPACE"
    exit 1
fi

VM_STATUS=$(oc get vm $VM_NAME -n $NAMESPACE -o jsonpath='{.status.printableStatus}')
echo "✅ VM found (Status: $VM_STATUS)"
echo ""

# Stop VM
echo "Stopping VM..."
oc patch vm $VM_NAME -n $NAMESPACE --type merge -p '{"spec":{"runStrategy":"Halted"}}'

echo "Waiting for VM to stop..."
sleep 15

# Verify VMI is gone
while oc get vmi $VM_NAME -n $NAMESPACE &>/dev/null; do
    echo "  Waiting for VMI to terminate..."
    sleep 5
done
echo "✅ VM stopped"
echo ""

# Add secondary network annotation
echo "Adding secondary network configuration..."
oc patch vm $VM_NAME -n $NAMESPACE --type=json -p='[
  {
    "op": "add",
    "path": "/spec/template/metadata/annotations",
    "value": {
      "k8s.v1.cni.cncf.io/networks": "[{\"name\":\"windows-non-prod\",\"namespace\":\"windows-non-prod\",\"ips\":[\"'$STATIC_IP'\"]}]"
    }
  }
]'

echo "✅ Network annotation added"
echo ""

# Add secondary network interface
echo "Adding network interface to VM spec..."
oc patch vm $VM_NAME -n $NAMESPACE --type=json -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/domain/devices/interfaces/-",
    "value": {
      "name": "net-1",
      "bridge": {},
      "model": "virtio"
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/networks/-",
    "value": {
      "name": "net-1",
      "multus": {
        "networkName": "windows-non-prod"
      }
    }
  }
]'

echo "✅ Network interface added"
echo ""

# Start VM
echo "Starting VM with secondary network..."
oc patch vm $VM_NAME -n $NAMESPACE --type merge -p '{"spec":{"runStrategy":"Always"}}'

echo "Waiting for VM to start..."
sleep 30

# Monitor VM startup
echo ""
echo "VM Status:"
oc get vmi $VM_NAME -n $NAMESPACE -o wide 2>&1 || echo "VMI not yet created..."

# Wait for Running phase
echo ""
echo "Waiting for VM to reach Running phase..."
for i in {1..12}; do
    PHASE=$(oc get vmi $VM_NAME -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
    echo "  Attempt $i/12: Phase = $PHASE"
    
    if [ "$PHASE" == "Running" ]; then
        echo "✅ VM is Running!"
        break
    elif [ "$PHASE" == "Scheduling" ] || [ "$PHASE" == "Pending" ]; then
        sleep 10
    elif [ "$PHASE" == "Failed" ]; then
        echo "❌ VM failed to start!"
        echo ""
        echo "Checking for errors..."
        oc describe vmi $VM_NAME -n $NAMESPACE | tail -30
        exit 1
    else
        sleep 10
    fi
done

echo ""
echo "=============================================="
echo "  Verification"
echo "=============================================="
echo ""

# Get VM details
echo "VM Status:"
oc get vmi $VM_NAME -n $NAMESPACE -o wide

echo ""
echo "Network Interfaces:"
oc get vmi $VM_NAME -n $NAMESPACE -o jsonpath='{.status.interfaces}' | jq .

echo ""
echo "Expected IP on secondary interface: $STATIC_IP"
ACTUAL_IP=$(oc get vmi $VM_NAME -n $NAMESPACE -o jsonpath='{.status.interfaces[?(@.name=="net-1")].ipAddress}' 2>/dev/null || echo "Not yet assigned")
echo "Actual IP: $ACTUAL_IP"

if [ "$ACTUAL_IP" == "$STATIC_IP" ]; then
    echo "✅ Static IP correctly assigned!"
else
    echo "⚠️  IP not yet assigned or incorrect. Cloud-init may still be configuring..."
    echo "   Wait 2-3 minutes for Windows to boot and cloud-init to run"
fi

echo ""
echo "=============================================="
echo "  Next Steps"
echo "=============================================="
echo ""
echo "1. Wait for Windows to fully boot (2-3 minutes)"
echo ""
echo "2. Verify IP from OpenShift:"
echo "   oc get vmi $VM_NAME -n $NAMESPACE -o jsonpath='{.status.interfaces}' | jq ."
echo ""
echo "3. Test connectivity from company network:"
echo "   ping $STATIC_IP"
echo "   mstsc /v:$STATIC_IP"
echo ""
echo "4. If RDP fails, check Windows Firewall via console:"
echo "   virtctl console $VM_NAME -n $NAMESPACE"
echo ""
echo "5. Inside Windows, verify network configuration:"
echo "   ipconfig /all"
echo "   # Should show $STATIC_IP on one of the adapters"
echo ""

echo "=============================================="
echo "  ✅ Configuration Complete!"
echo "=============================================="
