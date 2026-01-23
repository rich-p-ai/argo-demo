#!/bin/bash
#------------------------------------------------------------------------------
# Script: setup-prereqs.sh
# Purpose: Set up ROSA HCP prerequisites (account roles and OIDC config)
#
# Run this ONCE per AWS account before creating any clusters.
#------------------------------------------------------------------------------

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  ROSA HCP Prerequisites Setup${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

#------------------------------------------------------------------------------
# Check Required Tools
#------------------------------------------------------------------------------
echo -e "${YELLOW}Checking required tools...${NC}"

if ! command -v rosa &> /dev/null; then
    echo -e "${RED}Error: ROSA CLI not found${NC}"
    echo "Install from: https://console.redhat.com/openshift/downloads"
    exit 1
fi
echo "  ✓ rosa CLI: $(rosa version 2>/dev/null | head -1)"

if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI not found${NC}"
    echo "Install from: https://aws.amazon.com/cli/"
    exit 1
fi
echo "  ✓ aws CLI: $(aws --version 2>/dev/null | awk '{print $1}')"

echo ""

#------------------------------------------------------------------------------
# Verify ROSA Login
#------------------------------------------------------------------------------
echo -e "${YELLOW}Verifying ROSA login...${NC}"
if ! rosa whoami &> /dev/null; then
    echo -e "${RED}Error: Not logged in to ROSA${NC}"
    echo "Run: rosa login --token=<your-token>"
    echo "Get token from: https://console.redhat.com/openshift/token"
    exit 1
fi
rosa whoami
echo ""

#------------------------------------------------------------------------------
# Verify AWS Credentials
#------------------------------------------------------------------------------
echo -e "${YELLOW}Verifying AWS credentials...${NC}"
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured${NC}"
    echo "Configure with: aws configure"
    exit 1
fi
aws sts get-caller-identity
echo ""

#------------------------------------------------------------------------------
# Verify Quota
#------------------------------------------------------------------------------
echo -e "${YELLOW}Verifying AWS service quotas...${NC}"
rosa verify quota || {
    echo -e "${YELLOW}Warning: Some quotas may need to be increased${NC}"
}
echo ""

#------------------------------------------------------------------------------
# Verify Permissions
#------------------------------------------------------------------------------
echo -e "${YELLOW}Verifying AWS permissions...${NC}"
rosa verify permissions || {
    echo -e "${YELLOW}Warning: Some permissions may be missing${NC}"
}
echo ""

#------------------------------------------------------------------------------
# Create Account Roles
#------------------------------------------------------------------------------
echo -e "${YELLOW}Creating/verifying account-wide IAM roles...${NC}"
echo "This creates roles with prefix 'ManagedOpenShift'"
echo ""

rosa create account-roles --hosted-cp --mode auto --yes

echo ""

#------------------------------------------------------------------------------
# Create OIDC Configuration
#------------------------------------------------------------------------------
echo -e "${YELLOW}Creating OIDC configuration...${NC}"

# Check for existing OIDC configs
EXISTING_OIDC=$(rosa list oidc-config -o json 2>/dev/null | jq -r '.[0].id // empty')

if [ -n "$EXISTING_OIDC" ]; then
    echo "Found existing OIDC configuration: ${EXISTING_OIDC}"
    OIDC_CONFIG_ID="$EXISTING_OIDC"
    echo "Using existing OIDC config: ${OIDC_CONFIG_ID}"
else
    echo "Creating new OIDC configuration..."
    rosa create oidc-config --mode auto --yes
    # Get the newly created OIDC config ID
    OIDC_CONFIG_ID=$(rosa list oidc-config -o json 2>/dev/null | jq -r '.[-1].id // empty')
fi

if [ -z "$OIDC_CONFIG_ID" ]; then
    echo -e "${RED}Error: Could not determine OIDC config ID${NC}"
    exit 1
fi

echo ""
echo "OIDC Config ID: ${OIDC_CONFIG_ID}"
echo ""

#------------------------------------------------------------------------------
# Create Operator Roles
#------------------------------------------------------------------------------
echo -e "${YELLOW}Creating operator roles for OIDC config...${NC}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
rosa create operator-roles --hosted-cp \
    --oidc-config-id "$OIDC_CONFIG_ID" \
    --installer-role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/ManagedOpenShift-HCP-ROSA-Installer-Role" \
    --prefix "ManagedOpenShift" \
    --mode auto --yes 2>/dev/null || echo "Operator roles may already exist"

echo ""

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "OIDC Configuration ID: ${CYAN}${OIDC_CONFIG_ID}${NC}"
echo ""
echo "This OIDC config ID will be used automatically by the create-cluster.sh script."
echo ""
echo "To list all OIDC configs:"
echo "  rosa list oidc-config"
echo ""
echo "To list account roles:"
echo "  rosa list account-roles"
echo ""
echo -e "${GREEN}You can now create clusters using:${NC}"
echo "  ./scripts/create-cluster.sh miaocplab"
