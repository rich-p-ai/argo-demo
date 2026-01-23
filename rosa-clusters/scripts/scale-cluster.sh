#!/bin/bash
#------------------------------------------------------------------------------
# Script: scale-cluster.sh
# Purpose: Scale a ROSA HCP cluster's worker nodes
#
# Usage: ./scale-cluster.sh <cluster-name> <replicas>
#        ./scale-cluster.sh miaocplab 4
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
if [ $# -lt 2 ]; then
    echo "Usage: $0 <cluster-name> <replicas>"
    echo ""
    echo "Examples:"
    echo "  $0 miaocplab 4     # Scale to 4 workers"
    echo "  $0 miaocplab 2     # Scale down to 2 workers"
    exit 1
fi

CLUSTER_NAME="$1"
REPLICAS="$2"

#------------------------------------------------------------------------------
# Validate
#------------------------------------------------------------------------------
if ! [[ "$REPLICAS" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Error: Replicas must be a number${NC}"
    exit 1
fi

if [ "$REPLICAS" -lt 2 ]; then
    echo -e "${RED}Error: Minimum 2 replicas required for ROSA HCP${NC}"
    exit 1
fi

#------------------------------------------------------------------------------
# Check Cluster
#------------------------------------------------------------------------------
echo -e "${YELLOW}Checking cluster...${NC}"
if ! rosa describe cluster -c "$CLUSTER_NAME" &> /dev/null; then
    echo -e "${RED}Error: Cluster '${CLUSTER_NAME}' not found${NC}"
    exit 1
fi

#------------------------------------------------------------------------------
# Get Current Machine Pool
#------------------------------------------------------------------------------
echo ""
echo -e "${CYAN}Current machine pools:${NC}"
rosa list machinepools -c "$CLUSTER_NAME"

echo ""

#------------------------------------------------------------------------------
# Scale
#------------------------------------------------------------------------------
echo -e "${YELLOW}Scaling default machine pool to ${REPLICAS} replicas...${NC}"
rosa edit machinepool default -c "$CLUSTER_NAME" --replicas="$REPLICAS"

echo ""
echo -e "${GREEN}✓ Scale operation initiated${NC}"
echo ""
echo "Check status:"
echo "  rosa list machinepools -c ${CLUSTER_NAME}"
echo "  oc get nodes"
