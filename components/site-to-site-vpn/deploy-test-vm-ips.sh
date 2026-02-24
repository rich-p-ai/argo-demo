#!/bin/bash
# Deploy Static IP Reservation for Test VMs
# This script reserves IPs .10, .11, and .19 from whereabouts dynamic allocation

set -e

echo "=================================================="
echo "  Reserve Static IPs for Test VMs"
echo "=================================================="
echo ""
echo "Test VMs:"
echo "  - NYMSDV297: 10.132.104.10"
echo "  - NYMSDV301: 10.132.104.11"
echo "  - NYMSDV312: 10.132.104.19"
echo ""
echo "This will update the windows-non-prod NAD to exclude"
echo "these IPs from whereabouts dynamic allocation."
echo ""

# Check if logged in
if ! oc whoami &>/dev/null; then
    echo "❌ ERROR: Not logged into OpenShift cluster"
    echo "Please login first:"
    echo "  oc login https://api.non-prod.5wp0.p3.openshiftapps.com:443"
    exit 1
fi

CLUSTER=$(oc whoami --show-server)
USER=$(oc whoami)
echo "✅ Logged in as: $USER"
echo "✅ Cluster: $CLUSTER"
echo ""

# Verify VMs exist
echo "Checking if test VMs exist..."
for VM in nymsdv297 nymsdv301 nymsdv312; do
    if oc get vm $VM -n windows-non-prod &>/dev/null; then
        echo "  ✅ VM $VM found"
    else
        echo "  ⚠️  VM $VM not found"
    fi
done
echo ""

# Backup current NADs
echo "Backing up current NADs..."
mkdir -p backups
oc get nad windows-non-prod -n openshift-mtv -o yaml > backups/windows-non-prod-openshift-mtv-backup.yaml 2>/dev/null || echo "  ⚠️  NAD not found in openshift-mtv"
oc get nad windows-non-prod -n vm-migrations -o yaml > backups/windows-non-prod-vm-migrations-backup.yaml 2>/dev/null || echo "  ⚠️  NAD not found in vm-migrations"
oc get nad windows-non-prod -n windows-non-prod -o yaml > backups/windows-non-prod-windows-non-prod-backup.yaml 2>/dev/null || echo "  ⚠️  NAD not found in windows-non-prod"
echo "✅ Backups saved to backups/ directory"
echo ""

# Confirm before proceeding
read -p "Apply IP reservations? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

# Apply the updated NADs
echo ""
echo "Applying updated NADs with IP exclusions..."
oc apply -f reserve-test-vm-ips.yaml

echo ""
echo "✅ NADs updated successfully!"
echo ""

# Verify exclusions
echo "Verifying IP exclusions..."
echo ""
echo "=== openshift-mtv namespace ==="
oc get nad windows-non-prod -n openshift-mtv -o jsonpath='{.spec.config}' | jq -r 'fromjson | .ipam.exclude'

echo ""
echo "=== vm-migrations namespace ==="
oc get nad windows-non-prod -n vm-migrations -o jsonpath='{.spec.config}' | jq -r 'fromjson | .ipam.exclude'

echo ""
echo "=== windows-non-prod namespace ==="
oc get nad windows-non-prod -n windows-non-prod -o jsonpath='{.spec.config}' | jq -r 'fromjson | .ipam.exclude'

echo ""
echo "=================================================="
echo "  ✅ Deployment Complete!"
echo "=================================================="
echo ""
echo "Current VM IP addresses:"
oc get vmi nymsdv297 nymsdv301 -n windows-non-prod -o custom-columns=NAME:.metadata.name,IP:.status.interfaces[0].ipAddress --no-headers 2>/dev/null || echo "  No running VMIs found"

echo ""
echo "Next Steps:"
echo "  1. Add DNS records (see dns-records-test-vms.md)"
echo "  2. Test RDP connectivity from company network"
echo "  3. Verify VMs are accessible at their IPs"
echo ""
echo "Rollback (if needed):"
echo "  oc apply -f backups/windows-non-prod-openshift-mtv-backup.yaml"
echo "  oc apply -f backups/windows-non-prod-vm-migrations-backup.yaml"
echo "  oc apply -f backups/windows-non-prod-windows-non-prod-backup.yaml"
echo ""
