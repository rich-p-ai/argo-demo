#!/bin/bash
set -e

# Reserve Static IPs for QA VMs: NYMSQA428 (.20) and NYMSQA429 (.21)
# Updates NADs in openshift-mtv, vm-migrations, and windows-non-prod namespaces

echo "================================================"
echo "Reserve IPs for QA VMs (428 & 429)"
echo "================================================"
echo ""
echo "Target IPs:"
echo "  - 10.132.104.20 (NYMSQA428)"
echo "  - 10.132.104.21 (NYMSQA429)"
echo ""

# Backup existing NADs
BACKUP_DIR="nad-backups/qa-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "Backing up existing NADs to $BACKUP_DIR..."
oc get network-attachment-definitions windows-non-prod -n openshift-mtv -o yaml > "$BACKUP_DIR/openshift-mtv.yaml" 2>/dev/null || echo "  - NAD not found in openshift-mtv (will create)"
oc get network-attachment-definitions windows-non-prod -n vm-migrations -o yaml > "$BACKUP_DIR/vm-migrations.yaml" 2>/dev/null || echo "  - NAD not found in vm-migrations (will create)"
oc get network-attachment-definitions windows-non-prod -n windows-non-prod -o yaml > "$BACKUP_DIR/windows-non-prod.yaml" 2>/dev/null || echo "  - NAD not found in windows-non-prod (will create)"
echo ""

# Apply updated NADs
echo "Updating NADs with .20 and .21 exclusions..."

for NS in openshift-mtv vm-migrations windows-non-prod; do
  echo "  - Updating NAD in $NS..."
  oc delete network-attachment-definitions windows-non-prod -n $NS --ignore-not-found=true
done

oc apply -f reserve-qa-vm-ips.yaml

echo ""
echo "✅ IP Reservations Applied Successfully!"
echo ""

# Verify exclusions
echo "Verifying exclusions in each namespace..."
for NS in openshift-mtv vm-migrations windows-non-prod; do
  echo ""
  echo "Namespace: $NS"
  oc get network-attachment-definitions windows-non-prod -n $NS -o jsonpath='{.spec.config}' | jq -r '.ipam.exclude[]' 2>/dev/null || echo "  - Could not parse exclude list"
done

echo ""
echo "================================================"
echo "Deployment Complete!"
echo "================================================"
echo ""
echo "Next Steps:"
echo "1. Migrate NYMSQA428 and NYMSQA429 using MTV"
echo "2. After migration, configure static IPs:"
echo "   ./add-static-ip-to-vm.sh nymsqa428 10.132.104.20"
echo "   ./add-static-ip-to-vm.sh nymsqa429 10.132.104.21"
echo "3. Start VMs - cloud-init will auto-configure"
echo "4. Update DNS records (A and PTR)"
echo "5. Test RDP from company network"
echo ""
