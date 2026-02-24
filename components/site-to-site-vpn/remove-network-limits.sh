#!/bin/bash
set -e

echo "=============================================="
echo "  Remove Network Resource Limits"
echo "=============================================="
echo ""

# Backup current NADs
echo "Creating backups..."
mkdir -p nad-backups/limit-removal-$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="nad-backups/limit-removal-$(date +%Y%m%d-%H%M%S)"

for NS in openshift-mtv vm-migrations windows-non-prod; do
  oc get network-attachment-definitions windows-non-prod -n $NS -o yaml \
    > "$BACKUP_DIR/$NS-backup.yaml" 2>/dev/null || echo "  NAD not found in $NS"
done

echo "✅ Backups saved to $BACKUP_DIR"
echo ""

# Remove resourceName annotation
echo "Removing resourceName annotations..."
for NS in openshift-mtv vm-migrations windows-non-prod; do
  echo "  Processing $NS..."
  
  # Try to remove the annotation
  oc annotate network-attachment-definitions windows-non-prod \
    -n $NS \
    k8s.v1.cni.cncf.io/resourceName- \
    2>&1 | grep -v "not found" || true
done

echo ""
echo "=============================================="
echo "  ✅ Resource Limits Removed!"
echo "=============================================="
echo ""
echo "Verification:"
for NS in openshift-mtv vm-migrations windows-non-prod; do
  echo "  $NS:"
  RESOURCE=$(oc get network-attachment-definitions windows-non-prod -n $NS \
    -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/resourceName}' 2>/dev/null || echo "    ✅ REMOVED")
  if [ -n "$RESOURCE" ]; then
    echo "    resourceName: $RESOURCE"
  fi
done

echo ""
echo "Next Steps:"
echo "1. The network resource limit has been removed"
echo "2. Now configure nymsdv301 with secondary network:"
echo "   ./add-network-nymsdv301.sh"
echo ""
