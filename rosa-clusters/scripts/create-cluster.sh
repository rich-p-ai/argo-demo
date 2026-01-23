#!/bin/bash
#------------------------------------------------------------------------------
# Script: create-cluster.sh
# Purpose: Create a ROSA HCP cluster from configuration file
#
# Usage: ./create-cluster.sh <cluster-name>
#        ./create-cluster.sh miaocplab
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
CONFIGS_DIR="${ROOT_DIR}/configs"

#------------------------------------------------------------------------------
# Functions
#------------------------------------------------------------------------------
print_usage() {
    echo "Usage: $0 <cluster-name>"
    echo ""
    echo "Creates a ROSA HCP cluster using configuration from configs/<cluster-name>.env"
    echo ""
    echo "Available configurations:"
    for config in "${CONFIGS_DIR}"/*.env; do
        if [ -f "$config" ]; then
            name=$(basename "$config" .env)
            echo "  - $name"
        fi
    done
    echo ""
    echo "Example:"
    echo "  $0 miaocplab"
}

#------------------------------------------------------------------------------
# Parse Arguments
#------------------------------------------------------------------------------
if [ $# -lt 1 ]; then
    print_usage
    exit 1
fi

CLUSTER_NAME="$1"
CONFIG_FILE="${CONFIGS_DIR}/${CLUSTER_NAME}.env"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: Configuration file not found: ${CONFIG_FILE}${NC}"
    echo ""
    echo "Create one from a template:"
    echo "  cp configs/_templates/xsmall.env configs/${CLUSTER_NAME}.env"
    exit 1
fi

#------------------------------------------------------------------------------
# Load Configuration
#------------------------------------------------------------------------------
echo -e "${CYAN}Loading configuration from: ${CONFIG_FILE}${NC}"
source "$CONFIG_FILE"

#------------------------------------------------------------------------------
# Validate Prerequisites
#------------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}Validating prerequisites...${NC}"

# Check ROSA login
if ! rosa whoami &> /dev/null; then
    echo -e "${RED}Error: Not logged in to ROSA. Run: rosa login${NC}"
    exit 1
fi
echo "  ✓ ROSA login verified"

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured${NC}"
    exit 1
fi
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "  ✓ AWS Account: ${AWS_ACCOUNT_ID}"

# Check if cluster already exists
if rosa describe cluster -c "$CLUSTER_NAME" &> /dev/null; then
    echo -e "${RED}Error: Cluster '${CLUSTER_NAME}' already exists${NC}"
    echo "To delete it: rosa delete cluster -c ${CLUSTER_NAME}"
    exit 1
fi
echo "  ✓ Cluster name available"

#------------------------------------------------------------------------------
# Get OIDC Config
#------------------------------------------------------------------------------
if [ -z "$OIDC_CONFIG_ID" ]; then
    echo ""
    echo -e "${YELLOW}Looking up OIDC configuration...${NC}"
    OIDC_CONFIG_ID=$(rosa list oidc-config -o json 2>/dev/null | jq -r '.[0].id // empty')
    
    if [ -z "$OIDC_CONFIG_ID" ]; then
        echo -e "${RED}Error: No OIDC configuration found${NC}"
        echo "Run: ./scripts/setup-prereqs.sh"
        exit 1
    fi
fi
echo "  ✓ OIDC Config ID: ${OIDC_CONFIG_ID}"

#------------------------------------------------------------------------------
# Build ROSA Command
#------------------------------------------------------------------------------
echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Creating ROSA HCP Cluster: ${CLUSTER_NAME}${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""
echo "Configuration:"
echo "  Region:        ${AWS_REGION}"
echo "  Workers:       ${REPLICAS} x ${INSTANCE_TYPE}"
echo "  Multi-AZ:      ${MULTI_AZ}"
echo "  Autoscaling:   ${ENABLE_AUTOSCALING}"
if [ "$ENABLE_AUTOSCALING" == "true" ]; then
echo "    Min/Max:     ${MIN_REPLICAS}/${MAX_REPLICAS}"
fi
echo "  Private:       ${PRIVATE_CLUSTER}"
echo ""

# Build the rosa create cluster command
ROSA_CMD="rosa create cluster"
ROSA_CMD+=" --cluster-name=${CLUSTER_NAME}"
ROSA_CMD+=" --hosted-cp"
ROSA_CMD+=" --sts"
ROSA_CMD+=" --mode=auto"
ROSA_CMD+=" --yes"

# Region
ROSA_CMD+=" --region=${AWS_REGION}"

# Billing account (required for HCP)
# Use AWS_BILLING_ACCOUNT if set, otherwise use current account
BILLING_ACCOUNT="${AWS_BILLING_ACCOUNT:-$AWS_ACCOUNT_ID}"
ROSA_CMD+=" --billing-account=${BILLING_ACCOUNT}"

# OIDC
ROSA_CMD+=" --oidc-config-id=${OIDC_CONFIG_ID}"

# Compute
ROSA_CMD+=" --compute-machine-type=${INSTANCE_TYPE}"

# Autoscaling or fixed replicas (can't use both)
if [ "$ENABLE_AUTOSCALING" == "true" ]; then
    ROSA_CMD+=" --enable-autoscaling"
    ROSA_CMD+=" --min-replicas=${MIN_REPLICAS}"
    ROSA_CMD+=" --max-replicas=${MAX_REPLICAS}"
else
    ROSA_CMD+=" --replicas=${REPLICAS}"
fi

# Multi-AZ (deprecated for HCP but kept for compatibility)
if [ "$MULTI_AZ" == "true" ]; then
    ROSA_CMD+=" --multi-az"
fi

# Networking
if [ -n "$SUBNET_IDS" ]; then
    ROSA_CMD+=" --subnet-ids=${SUBNET_IDS}"
fi
ROSA_CMD+=" --machine-cidr=${MACHINE_CIDR}"
ROSA_CMD+=" --service-cidr=${SERVICE_CIDR}"
ROSA_CMD+=" --pod-cidr=${POD_CIDR}"
ROSA_CMD+=" --host-prefix=${HOST_PREFIX}"

# Private cluster
if [ "$PRIVATE_CLUSTER" == "true" ]; then
    ROSA_CMD+=" --private"
fi

# OpenShift version
if [ -n "$OPENSHIFT_VERSION" ]; then
    ROSA_CMD+=" --version=${OPENSHIFT_VERSION}"
fi

# Tags
if [ -n "$TAGS" ]; then
    ROSA_CMD+=" --tags=${TAGS}"
fi

# FIPS
if [ "$FIPS" == "true" ]; then
    ROSA_CMD+=" --fips"
fi

# Workload monitoring
if [ "$DISABLE_WORKLOAD_MONITORING" == "true" ]; then
    ROSA_CMD+=" --disable-workload-monitoring"
fi

# Account role prefix
if [ -n "$ACCOUNT_ROLE_PREFIX" ] && [ "$ACCOUNT_ROLE_PREFIX" != "ManagedOpenShift" ]; then
    ROSA_CMD+=" --role-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ACCOUNT_ROLE_PREFIX}-HCP-ROSA-Installer-Role"
    ROSA_CMD+=" --support-role-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ACCOUNT_ROLE_PREFIX}-HCP-ROSA-Support-Role"
    ROSA_CMD+=" --worker-iam-role=arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ACCOUNT_ROLE_PREFIX}-HCP-ROSA-Worker-Role"
fi

# Operator role prefix
if [ -n "$OPERATOR_ROLE_PREFIX" ]; then
    ROSA_CMD+=" --operator-roles-prefix=${OPERATOR_ROLE_PREFIX}"
else
    ROSA_CMD+=" --operator-roles-prefix=${CLUSTER_NAME}"
fi

#------------------------------------------------------------------------------
# Execute
#------------------------------------------------------------------------------
echo -e "${YELLOW}Executing ROSA command...${NC}"
echo ""
echo "Command:"
echo "$ROSA_CMD" | tr ' ' '\n' | sed 's/^/  /'
echo ""

# Run the command
eval "$ROSA_CMD"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Cluster creation initiated!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "The cluster will take approximately 15-20 minutes to be ready."
echo ""
echo "Monitor progress:"
echo "  rosa logs install -c ${CLUSTER_NAME} --watch"
echo ""
echo "Check status:"
echo "  rosa describe cluster -c ${CLUSTER_NAME}"
echo ""
echo "After cluster is ready, create admin user:"
echo "  rosa create admin -c ${CLUSTER_NAME}"
echo ""
echo "Or watch until ready and create admin automatically:"
echo "  rosa describe cluster -c ${CLUSTER_NAME} --watch && rosa create admin -c ${CLUSTER_NAME}"
