#!/bin/bash
#------------------------------------------------------------------------------
# Script: configure-cluster-access.sh
# Purpose: Configure VPC endpoint security groups for corporate network access
#
# This script adds corporate network CIDRs to the cluster's VPC endpoint
# security group to allow access from Canon corporate networks.
#
# Usage: ./configure-cluster-access.sh <cluster-name>
#
# Run this after cluster creation to enable network access.
#------------------------------------------------------------------------------

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
NETWORK_CONFIG="${ROOT_DIR}/configs/network/corporate-cidrs.env"

#------------------------------------------------------------------------------
# Parse Arguments
#------------------------------------------------------------------------------
if [ $# -lt 1 ]; then
    echo "Usage: $0 <cluster-name>"
    echo ""
    echo "Configures VPC endpoint security groups for corporate network access."
    echo ""
    echo "Example:"
    echo "  $0 rosa-test"
    exit 1
fi

CLUSTER_NAME="$1"

#------------------------------------------------------------------------------
# Load Corporate CIDRs
#------------------------------------------------------------------------------
if [ ! -f "$NETWORK_CONFIG" ]; then
    echo -e "${RED}Error: Corporate CIDRs config not found: ${NETWORK_CONFIG}${NC}"
    exit 1
fi

source "$NETWORK_CONFIG"

#------------------------------------------------------------------------------
# Get Cluster Information
#------------------------------------------------------------------------------
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Configuring Access: ${CLUSTER_NAME}${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

echo -e "${YELLOW}Getting cluster details...${NC}"

# Get cluster info
CLUSTER_INFO=$(rosa describe cluster -c "$CLUSTER_NAME" -o json 2>/dev/null)
if [ -z "$CLUSTER_INFO" ]; then
    echo -e "${RED}Error: Cluster '${CLUSTER_NAME}' not found${NC}"
    exit 1
fi

CLUSTER_ID=$(echo "$CLUSTER_INFO" | jq -r '.id')
CLUSTER_STATE=$(echo "$CLUSTER_INFO" | jq -r '.state')
AWS_REGION=$(echo "$CLUSTER_INFO" | jq -r '.region.id')
VPC_CIDR=$(echo "$CLUSTER_INFO" | jq -r '.network.machine_cidr')

echo "  Cluster ID: ${CLUSTER_ID}"
echo "  State: ${CLUSTER_STATE}"
echo "  Region: ${AWS_REGION}"
echo "  VPC CIDR: ${VPC_CIDR}"

if [ "$CLUSTER_STATE" != "ready" ] && [ "$CLUSTER_STATE" != "installing" ]; then
    echo -e "${RED}Error: Cluster is in '${CLUSTER_STATE}' state. Expected 'ready' or 'installing'.${NC}"
    exit 1
fi

#------------------------------------------------------------------------------
# Find VPC Endpoint Security Group
#------------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}Finding VPC endpoint security group...${NC}"

# Get subnets from cluster to find VPC
SUBNET_ID=$(echo "$CLUSTER_INFO" | jq -r '.network.subnets[0]')

# Get VPC ID from subnet
VPC_ID=$(aws ec2 describe-subnets --subnet-ids "$SUBNET_ID" --region "$AWS_REGION" \
    --query 'Subnets[0].VpcId' --output text)

echo "  VPC ID: ${VPC_ID}"

# Find VPC endpoints for this cluster (by naming pattern)
VPCE_SG=$(aws ec2 describe-vpc-endpoints --region "$AWS_REGION" \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "VpcEndpoints[?contains(Groups[0].GroupName, '${CLUSTER_ID}')].Groups[0].GroupId" \
    --output text | head -1)

if [ -z "$VPCE_SG" ] || [ "$VPCE_SG" == "None" ]; then
    # Try alternate pattern - look for any vpce-private-router security group
    VPCE_SG=$(aws ec2 describe-security-groups --region "$AWS_REGION" \
        --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=*${CLUSTER_ID}*vpce*" \
        --query 'SecurityGroups[0].GroupId' --output text)
fi

if [ -z "$VPCE_SG" ] || [ "$VPCE_SG" == "None" ]; then
    echo -e "${YELLOW}Warning: Could not find VPC endpoint security group automatically.${NC}"
    echo "The cluster may still be creating VPC endpoints."
    echo ""
    echo "You can run this script again once the cluster is ready, or manually find the SG:"
    echo "  aws ec2 describe-security-groups --region ${AWS_REGION} \\"
    echo "    --filters \"Name=vpc-id,Values=${VPC_ID}\" \"Name=group-name,Values=*vpce*\" \\"
    echo "    --query 'SecurityGroups[*].[GroupId,GroupName]' --output table"
    exit 0
fi

echo "  VPC Endpoint Security Group: ${VPCE_SG}"

#------------------------------------------------------------------------------
# Get Current Rules
#------------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}Checking existing security group rules...${NC}"

EXISTING_CIDRS=$(aws ec2 describe-security-groups --group-ids "$VPCE_SG" --region "$AWS_REGION" \
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`443`].IpRanges[*].CidrIp' --output text)

echo "  Existing CIDRs on port 443:"
echo "$EXISTING_CIDRS" | tr '\t' '\n' | sed 's/^/    /'

#------------------------------------------------------------------------------
# Add Corporate CIDRs
#------------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}Adding corporate network CIDRs...${NC}"

ADDED=0
SKIPPED=0

for CIDR in "${CORPORATE_CIDRS[@]}"; do
    # Check if CIDR already exists
    if echo "$EXISTING_CIDRS" | grep -q "$CIDR"; then
        echo "  - ${CIDR} (already exists, skipping)"
        ((SKIPPED++))
    else
        echo "  + ${CIDR} (adding)"
        aws ec2 authorize-security-group-ingress \
            --group-id "$VPCE_SG" \
            --protocol tcp \
            --port 443 \
            --cidr "$CIDR" \
            --region "$AWS_REGION" 2>/dev/null || {
                echo -e "    ${YELLOW}Warning: Could not add ${CIDR} (may already exist)${NC}"
            }
        ((ADDED++))
    fi
done

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Security Group Configuration Complete${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Summary:"
echo "  Security Group: ${VPCE_SG}"
echo "  CIDRs Added: ${ADDED}"
echo "  CIDRs Skipped: ${SKIPPED} (already existed)"
echo ""
echo "Corporate users should now be able to access:"
echo "  - API: https://api.${CLUSTER_NAME}.*"
echo "  - Console: https://console-openshift-console.apps.*"
echo ""
echo -e "${GREEN}Done!${NC}"
