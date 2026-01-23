#!/bin/bash
#------------------------------------------------------------------------------
# Script: list-clusters.sh
# Purpose: List all ROSA clusters and their status
#------------------------------------------------------------------------------

set -e

# Colors
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  ROSA Clusters${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

rosa list clusters

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  OIDC Configurations${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

rosa list oidc-config

echo ""
echo "For detailed cluster info:"
echo "  rosa describe cluster -c <cluster-name>"
