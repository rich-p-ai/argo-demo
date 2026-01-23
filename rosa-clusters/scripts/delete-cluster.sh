#!/bin/bash
#------------------------------------------------------------------------------
# Script: delete-cluster.sh
# Purpose: Delete a ROSA HCP cluster
#
# Usage: ./delete-cluster.sh <cluster-name> [--yes]
#------------------------------------------------------------------------------

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

#------------------------------------------------------------------------------
# Parse Arguments
#------------------------------------------------------------------------------
if [ $# -lt 1 ]; then
    echo "Usage: $0 <cluster-name> [--yes]"
    echo ""
    echo "Options:"
    echo "  --yes    Skip confirmation prompt"
    exit 1
fi

CLUSTER_NAME="$1"
AUTO_APPROVE="$2"

#------------------------------------------------------------------------------
# Verify Cluster Exists
#------------------------------------------------------------------------------
echo -e "${YELLOW}Checking cluster status...${NC}"
if ! rosa describe cluster -c "$CLUSTER_NAME" &> /dev/null; then
    echo -e "${RED}Error: Cluster '${CLUSTER_NAME}' not found${NC}"
    echo ""
    echo "List available clusters:"
    rosa list clusters
    exit 1
fi

# Show cluster info
rosa describe cluster -c "$CLUSTER_NAME" | head -20

echo ""
echo -e "${RED}============================================${NC}"
echo -e "${RED}  WARNING: This will DELETE the cluster!${NC}"
echo -e "${RED}============================================${NC}"
echo ""
echo "Cluster: ${CLUSTER_NAME}"
echo ""
echo -e "${YELLOW}All workloads and data will be permanently lost!${NC}"
echo ""

#------------------------------------------------------------------------------
# Confirmation
#------------------------------------------------------------------------------
if [ "$AUTO_APPROVE" != "--yes" ]; then
    read -p "Type the cluster name to confirm deletion: " CONFIRM
    if [ "$CONFIRM" != "$CLUSTER_NAME" ]; then
        echo -e "${RED}Confirmation failed. Aborting.${NC}"
        exit 1
    fi
    echo ""
fi

#------------------------------------------------------------------------------
# Delete Cluster
#------------------------------------------------------------------------------
echo -e "${YELLOW}Deleting cluster...${NC}"
rosa delete cluster -c "$CLUSTER_NAME" --yes --watch

echo ""
echo -e "${YELLOW}Cleaning up operator roles...${NC}"
rosa delete operator-roles -c "$CLUSTER_NAME" --mode auto --yes 2>/dev/null || true

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Cluster '${CLUSTER_NAME}' deleted${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Note: OIDC config and account roles are retained for other clusters."
echo ""
echo "To delete OIDC config (if no longer needed):"
echo "  rosa delete oidc-config --oidc-config-id <id> --mode auto --yes"
