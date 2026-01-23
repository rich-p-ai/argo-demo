#!/bin/bash
#------------------------------------------------------------------------------
# Script: create-vpc.sh
# Purpose: Create a VPC for ROSA HCP clusters
#
# Usage: ./create-vpc.sh <vpc-name> <region> [availability-zones] [cidr]
#
# Examples:
#   ./create-vpc.sh nonprod-vpc us-east-2
#   ./create-vpc.sh prod-vpc us-west-2 3 10.1.0.0/16
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
    echo "Usage: $0 <vpc-name> <region> [availability-zones] [cidr]"
    echo ""
    echo "Arguments:"
    echo "  vpc-name            Name for the VPC (e.g., nonprod-vpc)"
    echo "  region              AWS region (e.g., us-east-2)"
    echo "  availability-zones  Number of AZs: 1, 2, or 3 (default: 3)"
    echo "  cidr                VPC CIDR block (default: 10.0.0.0/16)"
    echo ""
    echo "Examples:"
    echo "  $0 nonprod-vpc us-east-2"
    echo "  $0 prod-vpc us-west-2 3 10.1.0.0/16"
    echo "  $0 dev-vpc us-east-1 1 10.2.0.0/16"
    exit 1
fi

VPC_NAME="$1"
REGION="$2"
AZ_COUNT="${3:-3}"
VPC_CIDR="${4:-10.0.0.0/16}"

#------------------------------------------------------------------------------
# Validate
#------------------------------------------------------------------------------
if [[ ! "$AZ_COUNT" =~ ^[1-3]$ ]]; then
    echo -e "${RED}Error: Availability zones must be 1, 2, or 3${NC}"
    exit 1
fi

#------------------------------------------------------------------------------
# Check for existing VPC
#------------------------------------------------------------------------------
echo -e "${YELLOW}Checking for existing VPC named '${VPC_NAME}'...${NC}"
EXISTING=$(aws ec2 describe-vpcs --region "$REGION" \
    --filters "Name=tag:Name,Values=${VPC_NAME}*" \
    --query 'Vpcs[0].VpcId' --output text 2>/dev/null)

if [ "$EXISTING" != "None" ] && [ -n "$EXISTING" ]; then
    echo -e "${RED}Error: VPC with name '${VPC_NAME}' already exists: ${EXISTING}${NC}"
    echo ""
    echo "To use existing VPC, get subnet IDs with:"
    echo "  aws ec2 describe-subnets --region ${REGION} --filters \"Name=vpc-id,Values=${EXISTING}\" --output table"
    exit 1
fi

#------------------------------------------------------------------------------
# Create VPC
#------------------------------------------------------------------------------
echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Creating VPC: ${VPC_NAME}${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""
echo "Configuration:"
echo "  Name:       ${VPC_NAME}"
echo "  Region:     ${REGION}"
echo "  CIDR:       ${VPC_CIDR}"
echo "  AZs:        ${AZ_COUNT}"
echo ""

echo -e "${YELLOW}Creating VPC using ROSA network template...${NC}"
echo "(This will take 2-3 minutes)"
echo ""

rosa create network rosa-quickstart-default-vpc \
    --param Region="${REGION}" \
    --param Name="${VPC_NAME}" \
    --param AvailabilityZoneCount="${AZ_COUNT}" \
    --param VpcCidr="${VPC_CIDR}" \
    --mode auto \
    --yes

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  VPC Created Successfully!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""

#------------------------------------------------------------------------------
# Get Subnet IDs
#------------------------------------------------------------------------------
echo -e "${YELLOW}Retrieving subnet information...${NC}"
echo ""

# Get VPC ID
VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" \
    --filters "Name=tag:Name,Values=${VPC_NAME}" \
    --query 'Vpcs[0].VpcId' --output text)

echo "VPC ID: ${VPC_ID}"
echo ""

# Get Public Subnets
echo "Public Subnets:"
PUBLIC_SUBNETS=$(aws ec2 describe-subnets --region "$REGION" \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=*Public*" \
    --query 'Subnets[*].[SubnetId,AvailabilityZone]' --output text)
echo "$PUBLIC_SUBNETS" | while read subnet az; do
    echo "  - $subnet ($az)"
done

# Get Private Subnets
echo ""
echo "Private Subnets:"
PRIVATE_SUBNETS=$(aws ec2 describe-subnets --region "$REGION" \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=*Private*" \
    --query 'Subnets[*].[SubnetId,AvailabilityZone]' --output text)
echo "$PRIVATE_SUBNETS" | while read subnet az; do
    echo "  - $subnet ($az)"
done

# Build subnet ID strings
PUBLIC_IDS=$(aws ec2 describe-subnets --region "$REGION" \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=*Public*" \
    --query 'Subnets[*].SubnetId' --output text | tr '\t' ',')

PRIVATE_IDS=$(aws ec2 describe-subnets --region "$REGION" \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=*Private*" \
    --query 'Subnets[*].SubnetId' --output text | tr '\t' ',')

ALL_IDS="${PUBLIC_IDS},${PRIVATE_IDS}"

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Configuration for cluster .env file${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""
echo "Add these to your cluster config file:"
echo ""
echo "# VPC: ${VPC_NAME} (${VPC_ID})"
echo "AWS_REGION=\"${REGION}\""
echo "SUBNET_IDS=\"${ALL_IDS}\""
echo "MACHINE_CIDR=\"${VPC_CIDR}\""
echo ""
echo -e "${GREEN}VPC is ready for ROSA HCP cluster deployment!${NC}"
