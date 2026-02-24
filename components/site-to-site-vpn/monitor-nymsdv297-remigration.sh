#!/bin/bash
# Monitor NYMSDV297 re-migration progress

MIGRATION_NAME="nymsdv297-remigration-c6n4d"
PLAN_NAME="nymsdv297-remigration"
NAMESPACE="openshift-mtv"

echo "=============================================="
echo "NYMSDV297 Re-Migration Monitor"
echo "=============================================="
echo ""
echo "Migration: $MIGRATION_NAME"
echo "Plan: $PLAN_NAME"
echo "Started: $(date)"
echo ""

# Function to get VM status
get_vm_status() {
    oc get migration $MIGRATION_NAME -n $NAMESPACE -o jsonpath='{.status.vms[0]}' 2>/dev/null | jq -r '
        "Phase: \(.phase // "N/A")",
        "Current Pipeline: \(.pipeline[] | select(.phase == "Running") | .name // "N/A")",
        ""
    '
}

# Function to get disk transfer progress
get_disk_progress() {
    oc get migration $MIGRATION_NAME -n $NAMESPACE -o jsonpath='{.status.vms[0].pipeline[]}' 2>/dev/null | jq -r '
        select(.name == "DiskTransfer") |
        "Disk Transfer Progress: \(.progress.completed // 0) / \(.progress.total // 0) MB",
        "Status: \(.phase // "Pending")",
        "",
        "Individual Disks:",
        (.tasks[]? | "  - \(.name): \(.progress.completed // 0) / \(.progress.total // 0) MB (\(.phase // "Pending"))")
    '
}

# Function to get warm migration stats
get_warm_stats() {
    oc get migration $MIGRATION_NAME -n $NAMESPACE -o jsonpath='{.status.vms[0].warm}' 2>/dev/null | jq -r '
        "Warm Migration Stats:",
        "  Precopies: \(.precopies | length)",
        "  Successes: \(.successes // 0)",
        "  Failures: \(.failures // 0)",
        "  Next Precopy: \(.nextPrecopyAt // "N/A")",
        ""
    '
}

# Main monitoring loop
while true; do
    clear
    echo "=============================================="
    echo "NYMSDV297 Re-Migration Monitor"
    echo "=============================================="
    echo ""
    echo "Last Update: $(date)"
    echo ""
    
    # Get overall migration status
    echo "=== Migration Status ==="
    oc get migration $MIGRATION_NAME -n $NAMESPACE 2>/dev/null
    echo ""
    
    # Get VM status
    echo "=== VM Migration Details ==="
    get_vm_status
    echo ""
    
    # Get disk progress
    echo "=== Disk Transfer ==="
    get_disk_progress
    echo ""
    
    # Get warm migration stats
    echo "=== Warm Migration ==="
    get_warm_stats
    echo ""
    
    # Check if completed
    COMPLETED=$(oc get migration $MIGRATION_NAME -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' 2>/dev/null)
    FAILED=$(oc get migration $MIGRATION_NAME -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null)
    
    if [ "$COMPLETED" == "True" ]; then
        echo "✅ MIGRATION COMPLETED SUCCESSFULLY!"
        break
    elif [ "$FAILED" == "True" ]; then
        echo "❌ MIGRATION FAILED!"
        echo ""
        echo "Error Details:"
        oc get migration $MIGRATION_NAME -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Failed")].message}' 2>/dev/null
        break
    fi
    
    echo "Refreshing in 30 seconds... (Ctrl+C to exit)"
    sleep 30
done

echo ""
echo "=============================================="
echo "Final Migration State"
echo "=============================================="
oc get migration $MIGRATION_NAME -n $NAMESPACE -o yaml
