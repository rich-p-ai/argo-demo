#!/bin/bash
#------------------------------------------------------------------------------
# Script: get-credentials.sh
# Purpose: Get login credentials for a ROSA cluster
#
# Usage: ./get-credentials.sh <cluster-name>
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
    echo "Usage: $0 <cluster-name>"
    exit 1
fi

CLUSTER_NAME="$1"

#------------------------------------------------------------------------------
# Check Cluster
#------------------------------------------------------------------------------
echo -e "${YELLOW}Getting cluster info...${NC}"
if ! rosa describe cluster -c "$CLUSTER_NAME" &> /dev/null; then
    echo -e "${RED}Error: Cluster '${CLUSTER_NAME}' not found${NC}"
    exit 1
fi

# Get cluster details
CLUSTER_INFO=$(rosa describe cluster -c "$CLUSTER_NAME" -o json)
API_URL=$(echo "$CLUSTER_INFO" | jq -r '.api.url')
CONSOLE_URL=$(echo "$CLUSTER_INFO" | jq -r '.console.url')
STATE=$(echo "$CLUSTER_INFO" | jq -r '.state')

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Cluster: ${CLUSTER_NAME}${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""
echo "State:       ${STATE}"
echo "API URL:     ${API_URL}"
echo "Console URL: ${CONSOLE_URL}"
echo ""

if [ "$STATE" != "ready" ]; then
    echo -e "${YELLOW}Warning: Cluster is not ready yet (state: ${STATE})${NC}"
    echo "Wait for cluster to be ready before getting credentials."
    exit 1
fi

#------------------------------------------------------------------------------
# Check for Existing Admin
#------------------------------------------------------------------------------
echo -e "${YELLOW}Checking for admin user...${NC}"
ADMIN_EXISTS=$(rosa list users -c "$CLUSTER_NAME" 2>/dev/null | grep -c "cluster-admin" || true)

if [ "$ADMIN_EXISTS" -eq 0 ]; then
    echo "No admin user found. Creating one..."
    echo ""
    rosa create admin -c "$CLUSTER_NAME"
else
    echo "Admin user already exists."
    echo ""
    echo "To reset admin password:"
    echo "  rosa delete admin -c ${CLUSTER_NAME} --yes"
    echo "  rosa create admin -c ${CLUSTER_NAME}"
fi

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Login Commands${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "# Login with oc CLI:"
echo "oc login ${API_URL} -u cluster-admin -p <password-from-above>"
echo ""
echo "# Or open web console:"
echo "${CONSOLE_URL}"
