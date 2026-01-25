#!/bin/bash
#------------------------------------------------------------------------------
# Quick Bootstrap Script for test-non-prod Cluster
# 
# This is a convenience wrapper around bootstrap-gitops.sh specifically
# configured for the test-non-prod cluster.
#
# Usage:
#   ./bootstrap-test-non-prod.sh [--push] [--dry-run]
#
# Options:
#   --push      Commit and push any pending changes to git before bootstrap
#   --dry-run   Show what would be applied without making changes
#
# Prerequisites:
#   1. AWS CLI configured with appropriate credentials
#   2. ROSA CLI installed and authenticated
#   3. Logged into the test-non-prod cluster:
#      - Run: ./configure-cluster-access.sh test-non-prod
#      - Or: oc login <api-server> --username=<user>
#------------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration for test-non-prod cluster
CLUSTER_NAME="test-non-prod"
GITOPS_REPO="https://github.com/rich-p-ai/argo-demo.git"
GIT_BRANCH="main"

# Default flags
PUSH_FLAG=""
DRY_RUN_FLAG=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --push|-p)
            PUSH_FLAG="--push"
            shift
            ;;
        --dry-run|-d)
            DRY_RUN_FLAG="--dry-run"
            shift
            ;;
        --help|-h)
            head -25 "$0" | grep "^#" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}Bootstrap GitOps for test-non-prod Cluster${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo "Cluster:    ${CLUSTER_NAME}"
echo "Repository: ${GITOPS_REPO}"
echo "Branch:     ${GIT_BRANCH}"
echo ""

# Check if logged into the correct cluster
if ! oc whoami &> /dev/null; then
    print_error "Not logged into any OpenShift cluster!"
    echo ""
    echo "Please login to the test-non-prod cluster first:"
    echo "  Option 1: ${SCRIPT_DIR}/configure-cluster-access.sh test-non-prod"
    echo "  Option 2: oc login <api-server> --username=<user>"
    exit 1
fi

CURRENT_SERVER=$(oc whoami --show-server)
print_info "Current API Server: ${CURRENT_SERVER}"

# Confirm before proceeding
echo ""
read -p "Proceed with GitOps bootstrap on test-non-prod? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Bootstrap cancelled."
    exit 0
fi

# Execute the bootstrap
exec "${SCRIPT_DIR}/bootstrap-gitops.sh" \
    --cluster "${CLUSTER_NAME}" \
    --repo "${GITOPS_REPO}" \
    --branch "${GIT_BRANCH}" \
    ${PUSH_FLAG} \
    ${DRY_RUN_FLAG}
