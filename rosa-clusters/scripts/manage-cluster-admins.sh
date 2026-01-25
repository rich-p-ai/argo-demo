#!/bin/bash
#------------------------------------------------------------------------------
# Script: manage-cluster-admins.sh
# Purpose: Manage cluster administrator access for ROSA clusters
#
# Usage:
#   ./manage-cluster-admins.sh <cluster-name> [action] [username]
#
# Actions:
#   list      - List current cluster admins (default)
#   add       - Add a user as cluster-admin
#   remove    - Remove a user from cluster-admin
#   sync      - Sync admins from configs/admins/cluster-admins.env
#   apply     - Apply ClusterRoleBindings via oc (requires oc login)
#
# Examples:
#   ./manage-cluster-admins.sh test-non-prod list
#   ./manage-cluster-admins.sh test-non-prod add Q12345
#   ./manage-cluster-admins.sh test-non-prod sync
#   ./manage-cluster-admins.sh test-non-prod apply
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
ADMINS_CONFIG="${ROOT_DIR}/configs/admins/cluster-admins.env"

#------------------------------------------------------------------------------
# Functions
#------------------------------------------------------------------------------
print_usage() {
    echo "Usage: $0 <cluster-name> [action] [username]"
    echo ""
    echo "Actions:"
    echo "  list      - List current cluster admins (default)"
    echo "  add       - Add a user as cluster-admin"
    echo "  remove    - Remove a user from cluster-admin"
    echo "  sync      - Sync admins from configs/admins/cluster-admins.env"
    echo "  apply     - Apply ClusterRoleBindings via oc (requires oc login)"
    echo ""
    echo "Examples:"
    echo "  $0 test-non-prod list"
    echo "  $0 test-non-prod add Q12345"
    echo "  $0 test-non-prod remove Q12345"
    echo "  $0 test-non-prod sync"
    echo "  $0 test-non-prod apply"
}

list_admins() {
    local cluster="$1"
    
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}  Cluster Admins: ${cluster}${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""
    
    echo -e "${YELLOW}Users with cluster-admin access (via ROSA):${NC}"
    rosa list users -c "$cluster" 2>/dev/null || echo "  (none or error retrieving)"
    
    echo ""
    echo -e "${YELLOW}Configured admins in cluster-admins.env:${NC}"
    if [ -f "$ADMINS_CONFIG" ]; then
        source "$ADMINS_CONFIG"
        for user in "${CLUSTER_ADMINS[@]}"; do
            echo "  - $user"
        done
    else
        echo "  (config file not found)"
    fi
}

add_admin() {
    local cluster="$1"
    local username="$2"
    
    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: $0 $cluster add <username>"
        exit 1
    fi
    
    echo -e "${YELLOW}Adding ${username} as cluster-admin on ${cluster}...${NC}"
    
    rosa grant user cluster-admin \
        --user="$username" \
        --cluster="$cluster"
    
    echo -e "${GREEN}✓ User ${username} granted cluster-admin access${NC}"
}

remove_admin() {
    local cluster="$1"
    local username="$2"
    
    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: $0 $cluster remove <username>"
        exit 1
    fi
    
    echo -e "${YELLOW}Removing ${username} from cluster-admin on ${cluster}...${NC}"
    
    rosa revoke user cluster-admin \
        --user="$username" \
        --cluster="$cluster"
    
    echo -e "${GREEN}✓ User ${username} removed from cluster-admin${NC}"
}

sync_admins() {
    local cluster="$1"
    
    if [ ! -f "$ADMINS_CONFIG" ]; then
        echo -e "${RED}Error: Config file not found: ${ADMINS_CONFIG}${NC}"
        exit 1
    fi
    
    source "$ADMINS_CONFIG"
    
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}  Syncing Cluster Admins: ${cluster}${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""
    
    # Get current admins
    echo -e "${YELLOW}Current cluster admins:${NC}"
    rosa list users -c "$cluster" 2>/dev/null || true
    echo ""
    
    # Add configured admins
    echo -e "${YELLOW}Adding configured cluster admins...${NC}"
    for user in "${CLUSTER_ADMINS[@]}"; do
        echo -n "  Adding $user... "
        if rosa grant user cluster-admin --user="$user" --cluster="$cluster" 2>/dev/null; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${YELLOW}(already exists or error)${NC}"
        fi
    done
    
    # Add dedicated admins if any
    if [ ${#DEDICATED_ADMINS[@]} -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}Adding configured dedicated admins...${NC}"
        for user in "${DEDICATED_ADMINS[@]}"; do
            echo -n "  Adding $user... "
            if rosa grant user dedicated-admin --user="$user" --cluster="$cluster" 2>/dev/null; then
                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${YELLOW}(already exists or error)${NC}"
            fi
        done
    fi
    
    echo ""
    echo -e "${GREEN}Sync complete!${NC}"
    echo ""
    
    # Show final state
    echo -e "${YELLOW}Final cluster admins:${NC}"
    rosa list users -c "$cluster" 2>/dev/null || true
}

apply_rolebindings() {
    local cluster="$1"
    
    # Check if logged in to cluster
    if ! oc whoami &>/dev/null; then
        echo -e "${RED}Error: Not logged in to OpenShift cluster${NC}"
        echo "Please login first: oc login <cluster-api-url>"
        exit 1
    fi
    
    CURRENT_CLUSTER=$(oc whoami --show-server 2>/dev/null)
    echo -e "${YELLOW}Applying ClusterRoleBindings to: ${CURRENT_CLUSTER}${NC}"
    echo ""
    
    if [ ! -f "$ADMINS_CONFIG" ]; then
        echo -e "${RED}Error: Config file not found: ${ADMINS_CONFIG}${NC}"
        exit 1
    fi
    
    source "$ADMINS_CONFIG"
    
    # Create ClusterRoleBinding for each admin
    for user in "${CLUSTER_ADMINS[@]}"; do
        echo -n "  Creating ClusterRoleBinding for $user... "
        
        cat <<EOF | oc apply -f - 2>/dev/null
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-admin-${user,,}
  labels:
    managed-by: rosa-cluster-scripts
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: ${user}
EOF
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗${NC}"
        fi
    done
    
    # Create ClusterRoleBinding for admin groups
    for group in "${CLUSTER_ADMIN_GROUPS[@]}"; do
        echo -n "  Creating ClusterRoleBinding for group $group... "
        
        cat <<EOF | oc apply -f - 2>/dev/null
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-admin-group-${group,,}
  labels:
    managed-by: rosa-cluster-scripts
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: ${group}
EOF
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗${NC}"
        fi
    done
    
    echo ""
    echo -e "${GREEN}ClusterRoleBindings applied!${NC}"
    echo ""
    echo "Verify with:"
    echo "  oc get clusterrolebindings -l managed-by=rosa-cluster-scripts"
}

#------------------------------------------------------------------------------
# Parse Arguments
#------------------------------------------------------------------------------
if [ $# -lt 1 ]; then
    print_usage
    exit 1
fi

CLUSTER_NAME="$1"
ACTION="${2:-list}"
USERNAME="$3"

# Verify cluster exists
if ! rosa describe cluster -c "$CLUSTER_NAME" &>/dev/null; then
    echo -e "${RED}Error: Cluster '${CLUSTER_NAME}' not found${NC}"
    exit 1
fi

#------------------------------------------------------------------------------
# Execute Action
#------------------------------------------------------------------------------
case "$ACTION" in
    list)
        list_admins "$CLUSTER_NAME"
        ;;
    add)
        add_admin "$CLUSTER_NAME" "$USERNAME"
        ;;
    remove)
        remove_admin "$CLUSTER_NAME" "$USERNAME"
        ;;
    sync)
        sync_admins "$CLUSTER_NAME"
        ;;
    apply)
        apply_rolebindings "$CLUSTER_NAME"
        ;;
    *)
        echo -e "${RED}Error: Unknown action '${ACTION}'${NC}"
        print_usage
        exit 1
        ;;
esac
