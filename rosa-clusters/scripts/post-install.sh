#!/bin/bash
#------------------------------------------------------------------------------
# Script: post-install.sh
# Purpose: Run all post-installation tasks for a ROSA HCP cluster
#
# Tasks:
#   1. Wait for cluster to be ready
#   2. Configure VPC endpoint security groups for corporate access
#   3. Create cluster admin user
#   4. Configure LDAP identity provider (optional)
#
# Usage: ./post-install.sh <cluster-name> [--skip-ldap]
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

#------------------------------------------------------------------------------
# Parse Arguments
#------------------------------------------------------------------------------
if [ $# -lt 1 ]; then
    echo "Usage: $0 <cluster-name> [--skip-ldap]"
    echo ""
    echo "Runs all post-installation tasks for a ROSA HCP cluster."
    echo ""
    echo "Options:"
    echo "  --skip-ldap    Skip LDAP identity provider configuration"
    echo ""
    echo "Example:"
    echo "  $0 rosa-test"
    echo "  $0 rosa-test --skip-ldap"
    exit 1
fi

CLUSTER_NAME="$1"
SKIP_LDAP="false"

if [ "$2" == "--skip-ldap" ]; then
    SKIP_LDAP="true"
fi

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  ROSA HCP Post-Install: ${CLUSTER_NAME}${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

#------------------------------------------------------------------------------
# Step 1: Wait for Cluster to be Ready
#------------------------------------------------------------------------------
echo -e "${YELLOW}Step 1: Checking cluster status...${NC}"

CLUSTER_STATE=$(rosa describe cluster -c "$CLUSTER_NAME" -o json 2>/dev/null | jq -r '.state' || echo "not_found")

if [ "$CLUSTER_STATE" == "not_found" ]; then
    echo -e "${RED}Error: Cluster '${CLUSTER_NAME}' not found${NC}"
    exit 1
fi

if [ "$CLUSTER_STATE" == "ready" ]; then
    echo "  ✓ Cluster is ready"
else
    echo "  Cluster state: ${CLUSTER_STATE}"
    echo ""
    echo -e "${YELLOW}Waiting for cluster to be ready...${NC}"
    echo "  (This may take 15-20 minutes for a new cluster)"
    echo ""
    
    while [ "$CLUSTER_STATE" != "ready" ]; do
        sleep 30
        CLUSTER_STATE=$(rosa describe cluster -c "$CLUSTER_NAME" -o json 2>/dev/null | jq -r '.state')
        echo "  Current state: ${CLUSTER_STATE}"
        
        if [ "$CLUSTER_STATE" == "error" ]; then
            echo -e "${RED}Error: Cluster entered error state${NC}"
            echo "Check logs: rosa logs install -c ${CLUSTER_NAME}"
            exit 1
        fi
    done
    echo ""
    echo "  ✓ Cluster is now ready"
fi

#------------------------------------------------------------------------------
# Step 2: Configure Corporate Network Access
#------------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}Step 2: Configuring corporate network access...${NC}"

if [ -f "${SCRIPT_DIR}/configure-cluster-access.sh" ]; then
    bash "${SCRIPT_DIR}/configure-cluster-access.sh" "$CLUSTER_NAME"
else
    echo -e "${RED}Warning: configure-cluster-access.sh not found${NC}"
    echo "  Skipping security group configuration"
fi

#------------------------------------------------------------------------------
# Step 3: Create Admin User
#------------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}Step 3: Creating cluster admin user...${NC}"

# Check if admin already exists
EXISTING_ADMIN=$(rosa list users -c "$CLUSTER_NAME" 2>/dev/null | grep "cluster-admin" || true)

if [ -n "$EXISTING_ADMIN" ]; then
    echo "  ✓ Admin user already exists"
    echo ""
    echo "  To reset password: rosa delete admin -c ${CLUSTER_NAME} && rosa create admin -c ${CLUSTER_NAME}"
else
    rosa create admin -c "$CLUSTER_NAME"
    echo ""
    echo "  ✓ Admin user created"
    echo -e "  ${YELLOW}IMPORTANT: Save the password shown above!${NC}"
fi

#------------------------------------------------------------------------------
# Step 4: Configure LDAP (Optional)
#------------------------------------------------------------------------------
echo ""
if [ "$SKIP_LDAP" == "true" ]; then
    echo -e "${YELLOW}Step 4: LDAP configuration skipped (--skip-ldap)${NC}"
else
    echo -e "${YELLOW}Step 4: Configuring LDAP identity provider...${NC}"
    
    # Check if LDAP config exists
    LDAP_CONFIG="${ROOT_DIR}/configs/idp/ldap-canon.env"
    
    if [ ! -f "$LDAP_CONFIG" ]; then
        echo "  LDAP configuration not found: ${LDAP_CONFIG}"
        echo "  Skipping LDAP setup"
    else
        # Check if LDAP IDP already exists
        EXISTING_LDAP=$(rosa list idps -c "$CLUSTER_NAME" 2>/dev/null | grep "LDAP" || true)
        
        if [ -n "$EXISTING_LDAP" ]; then
            echo "  ✓ LDAP identity provider already configured"
        else
            # Source LDAP config
            source "$LDAP_CONFIG"
            
            echo "  Creating LDAP identity provider..."
            rosa create idp \
                --cluster="$CLUSTER_NAME" \
                --type=ldap \
                --name=LDAP \
                --url="$LDAP_URL" \
                --bind-dn="$LDAP_BIND_DN" \
                --bind-password="$LDAP_BIND_PASSWORD" \
                --id-attributes="$LDAP_ID_ATTRIBUTE" \
                --email-attributes="$LDAP_EMAIL_ATTRIBUTE" \
                --name-attributes="$LDAP_NAME_ATTRIBUTE" \
                --username-attributes="$LDAP_USERNAME_ATTRIBUTE" \
                --insecure \
                --mapping-method="$LDAP_MAPPING_METHOD"
            
            echo ""
            echo "  ✓ LDAP identity provider created"
        fi
    fi
fi

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Post-Install Complete: ${CLUSTER_NAME}${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""

# Get cluster URLs
CLUSTER_INFO=$(rosa describe cluster -c "$CLUSTER_NAME" -o json)
API_URL=$(echo "$CLUSTER_INFO" | jq -r '.api.url')
CONSOLE_URL=$(echo "$CLUSTER_INFO" | jq -r '.console.url')

echo "Cluster Access:"
echo "  API URL:     ${API_URL}"
echo "  Console URL: ${CONSOLE_URL}"
echo ""
echo "Login Methods:"
echo "  - cluster-admin (HTPasswd)"

if [ "$SKIP_LDAP" != "true" ]; then
    LDAP_IDP=$(rosa list idps -c "$CLUSTER_NAME" 2>/dev/null | grep "LDAP" || true)
    if [ -n "$LDAP_IDP" ]; then
        echo "  - LDAP (Canon AD)"
    fi
fi

echo ""
echo "CLI Login:"
echo "  oc login ${API_URL} --username cluster-admin --password <password>"
echo ""
echo -e "${GREEN}Done!${NC}"
