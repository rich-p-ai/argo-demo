#!/bin/bash
#------------------------------------------------------------------------------
# Bootstrap Red Hat GitOps (OpenShift GitOps) on a ROSA Cluster
# 
# This script deploys Red Hat GitOps operator, configures ArgoCD, and deploys
# the App of Apps pattern to manage cluster configurations via GitOps.
#
# Prerequisites:
#   - oc CLI installed and logged into the target cluster
#   - envsubst (gettext) installed
#   - Git configured with appropriate credentials
#   - Cluster admin access
#
# Usage:
#   ./bootstrap-gitops.sh [OPTIONS]
#
# Options:
#   -c, --cluster     Cluster name (default: test-non-prod)
#   -r, --repo        GitOps repository URL (required)
#   -b, --branch      Git branch to use (default: main)
#   -p, --push        Commit and push changes to git after bootstrap
#   -d, --dry-run     Show what would be applied without making changes
#   -h, --help        Show this help message
#
# Example:
#   ./bootstrap-gitops.sh -c test-non-prod -r https://github.com/rich-p-ai/argo-demo.git -p
#------------------------------------------------------------------------------

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BOOTSTRAP_DIR="${REPO_ROOT}/.bootstrap"

# Default values
CLUSTER_NAME="test-non-prod"
GIT_BRANCH="main"
GIT_PUSH="false"
DRY_RUN="false"
GITOPS_REPO=""
WAIT_TIMEOUT=300  # 5 minutes

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#------------------------------------------------------------------------------
# Functions
#------------------------------------------------------------------------------

print_header() {
    echo -e "\n${BLUE}============================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================================${NC}\n"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "\n${BLUE}>>> Step $1: $2${NC}"
}

show_help() {
    head -40 "$0" | grep "^#" | sed 's/^# \?//'
    exit 0
}

check_command() {
    local cmd=$1
    if ! command -v "$cmd" &> /dev/null; then
        print_error "$cmd is not installed. Please install it and try again."
        return 1
    fi
    print_info "✓ $cmd is available"
}

wait_for_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    local condition=$4
    local timeout=${5:-$WAIT_TIMEOUT}
    
    print_info "Waiting for $resource_type/$resource_name in $namespace to be $condition (timeout: ${timeout}s)..."
    
    local start_time=$(date +%s)
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $timeout ]; then
            print_error "Timeout waiting for $resource_type/$resource_name"
            return 1
        fi
        
        if oc get "$resource_type" "$resource_name" -n "$namespace" &> /dev/null; then
            local status
            case $condition in
                "ready")
                    if oc wait "$resource_type/$resource_name" -n "$namespace" --for=condition=Ready --timeout=10s &> /dev/null; then
                        print_info "✓ $resource_type/$resource_name is ready"
                        return 0
                    fi
                    ;;
                "available")
                    if oc wait "$resource_type/$resource_name" -n "$namespace" --for=condition=Available --timeout=10s &> /dev/null; then
                        print_info "✓ $resource_type/$resource_name is available"
                        return 0
                    fi
                    ;;
                "exists")
                    print_info "✓ $resource_type/$resource_name exists"
                    return 0
                    ;;
            esac
        fi
        
        echo -n "."
        sleep 5
    done
}

wait_for_csv() {
    local csv_prefix=$1
    local namespace=$2
    local timeout=${3:-$WAIT_TIMEOUT}
    
    print_info "Waiting for ClusterServiceVersion starting with '$csv_prefix' in $namespace..."
    
    local start_time=$(date +%s)
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $timeout ]; then
            print_error "Timeout waiting for CSV"
            return 1
        fi
        
        local csv_name
        csv_name=$(oc get csv -n "$namespace" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep "^${csv_prefix}" | head -1 || true)
        
        if [ -n "$csv_name" ]; then
            local phase
            phase=$(oc get csv "$csv_name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
            if [ "$phase" == "Succeeded" ]; then
                print_info "✓ ClusterServiceVersion $csv_name is Succeeded"
                return 0
            fi
            print_info "CSV $csv_name phase: $phase"
        fi
        
        echo -n "."
        sleep 10
    done
}

verify_cluster_connection() {
    print_step "1" "Verifying cluster connection"
    
    if ! oc whoami &> /dev/null; then
        print_error "Not logged into any OpenShift cluster. Please run 'oc login' first."
        exit 1
    fi
    
    local current_user
    current_user=$(oc whoami)
    local current_context
    current_context=$(oc config current-context 2>/dev/null || echo "unknown")
    local api_server
    api_server=$(oc whoami --show-server)
    
    print_info "Logged in as: $current_user"
    print_info "API Server: $api_server"
    print_info "Context: $current_context"
    
    # Verify cluster-admin access
    if ! oc auth can-i '*' '*' --all-namespaces &> /dev/null; then
        print_error "Current user does not have cluster-admin privileges."
        exit 1
    fi
    print_info "✓ Cluster admin access confirmed"
}

create_gitops_namespace() {
    print_step "2" "Creating OpenShift GitOps namespace"
    
    if [ "$DRY_RUN" == "true" ]; then
        print_info "[DRY-RUN] Would create namespace openshift-gitops-operator"
        return 0
    fi
    
    if ! oc get namespace openshift-gitops-operator &> /dev/null; then
        oc create namespace openshift-gitops-operator
        print_info "✓ Created namespace openshift-gitops-operator"
    else
        print_info "Namespace openshift-gitops-operator already exists"
    fi
}

deploy_gitops_operator() {
    print_step "3" "Deploying Red Hat OpenShift GitOps Operator"
    
    if [ "$DRY_RUN" == "true" ]; then
        print_info "[DRY-RUN] Would apply:"
        print_info "  - ${BOOTSTRAP_DIR}/subscription.yaml"
        print_info "  - ${BOOTSTRAP_DIR}/cluster-rolebinding.yaml"
        return 0
    fi
    
    # Apply the Subscription
    print_info "Applying GitOps operator subscription..."
    oc apply -f "${BOOTSTRAP_DIR}/subscription.yaml"
    
    # Wait for the operator to be installed
    print_info "Waiting for GitOps operator to install..."
    wait_for_csv "openshift-gitops-operator" "openshift-gitops-operator" 300
    
    # Wait for openshift-gitops namespace to be created
    print_info "Waiting for openshift-gitops namespace..."
    local timeout=120
    local start_time=$(date +%s)
    while ! oc get namespace openshift-gitops &> /dev/null; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        if [ $elapsed -ge $timeout ]; then
            print_error "Timeout waiting for openshift-gitops namespace"
            exit 1
        fi
        echo -n "."
        sleep 5
    done
    print_info "✓ Namespace openshift-gitops created"
    
    # Apply ClusterRoleBinding
    print_info "Applying ClusterRoleBinding for GitOps service account..."
    oc apply -f "${BOOTSTRAP_DIR}/cluster-rolebinding.yaml"
    print_info "✓ ClusterRoleBinding applied"
    
    # Wait for default ArgoCD instance to be ready
    print_info "Waiting for default ArgoCD instance to be ready..."
    sleep 30  # Give the operator time to create resources
    wait_for_resource "argocd" "openshift-gitops" "openshift-gitops" "exists" 180
}

configure_argocd() {
    print_step "4" "Configuring ArgoCD instance"
    
    # Set environment variables for substitution
    export cluster_name="${CLUSTER_NAME}"
    export cluster_base_domain
    cluster_base_domain=$(oc get ingress.config.openshift.io cluster --template='{{.spec.domain}}' | sed -e "s/^apps.//")
    export platform_base_domain="${cluster_base_domain#*.}"
    export gitops_repo="${GITOPS_REPO}"
    
    print_info "Environment variables set:"
    print_info "  cluster_name: ${cluster_name}"
    print_info "  cluster_base_domain: ${cluster_base_domain}"
    print_info "  platform_base_domain: ${platform_base_domain}"
    print_info "  gitops_repo: ${gitops_repo}"
    
    if [ "$DRY_RUN" == "true" ]; then
        print_info "[DRY-RUN] Would apply ArgoCD configuration:"
        envsubst < "${BOOTSTRAP_DIR}/argocd.yaml" | head -50
        print_info "... (truncated)"
        return 0
    fi
    
    # Apply ArgoCD configuration with variable substitution
    print_info "Applying ArgoCD configuration..."
    envsubst < "${BOOTSTRAP_DIR}/argocd.yaml" | oc apply -f -
    print_info "✓ ArgoCD configuration applied"
    
    # Wait for ArgoCD components to be ready
    print_info "Waiting for ArgoCD server to be ready..."
    sleep 30
    
    local timeout=300
    local start_time=$(date +%s)
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $timeout ]; then
            print_error "Timeout waiting for ArgoCD components"
            exit 1
        fi
        
        local server_ready
        server_ready=$(oc get deployment openshift-gitops-server -n openshift-gitops -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        local repo_ready
        repo_ready=$(oc get deployment openshift-gitops-repo-server -n openshift-gitops -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        local controller_ready
        controller_ready=$(oc get statefulset openshift-gitops-application-controller -n openshift-gitops -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        
        if [ "${server_ready:-0}" -ge 1 ] && [ "${repo_ready:-0}" -ge 1 ] && [ "${controller_ready:-0}" -ge 1 ]; then
            print_info "✓ ArgoCD components are ready"
            break
        fi
        
        print_info "Waiting for ArgoCD (server: $server_ready, repo: $repo_ready, controller: $controller_ready)..."
        sleep 10
    done
}

deploy_root_application() {
    print_step "5" "Deploying Root Application (App of Apps)"
    
    # Ensure environment variables are set
    export cluster_name="${CLUSTER_NAME}"
    export gitops_repo="${GITOPS_REPO}"
    
    if [ "$DRY_RUN" == "true" ]; then
        print_info "[DRY-RUN] Would apply root application:"
        envsubst < "${BOOTSTRAP_DIR}/root-application.yaml"
        return 0
    fi
    
    # Apply root application with variable substitution
    print_info "Applying root application for cluster: ${cluster_name}..."
    envsubst < "${BOOTSTRAP_DIR}/root-application.yaml" | oc apply -f -
    print_info "✓ Root application deployed"
    
    # Wait for the root application to sync
    print_info "Waiting for root application to sync..."
    sleep 15
    
    local timeout=180
    local start_time=$(date +%s)
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $timeout ]; then
            print_warn "Timeout waiting for root application to sync. This may be normal for the first sync."
            break
        fi
        
        local sync_status
        sync_status=$(oc get application root-applications -n openshift-gitops -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        local health_status
        health_status=$(oc get application root-applications -n openshift-gitops -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
        
        if [ "$sync_status" == "Synced" ]; then
            print_info "✓ Root application synced successfully (health: $health_status)"
            break
        fi
        
        print_info "Root application status: sync=$sync_status, health=$health_status"
        sleep 10
    done
}

git_commit_and_push() {
    print_step "6" "Committing and pushing changes to Git"
    
    if [ "$GIT_PUSH" != "true" ]; then
        print_info "Git push disabled. Skipping..."
        return 0
    fi
    
    cd "$REPO_ROOT"
    
    if [ "$DRY_RUN" == "true" ]; then
        print_info "[DRY-RUN] Would commit and push changes to branch: $GIT_BRANCH"
        return 0
    fi
    
    # Check if there are any changes
    if git diff --quiet && git diff --staged --quiet; then
        print_info "No changes to commit"
        return 0
    fi
    
    # Add all changes
    git add -A
    
    # Commit
    local commit_msg="Bootstrap GitOps for cluster: ${CLUSTER_NAME}"
    git commit -m "$commit_msg" || {
        print_warn "Nothing to commit or commit failed"
        return 0
    }
    
    # Push
    print_info "Pushing changes to origin/${GIT_BRANCH}..."
    git push origin "${GIT_BRANCH}"
    print_info "✓ Changes pushed to Git"
}

print_summary() {
    print_header "Bootstrap Summary"
    
    local argocd_route
    argocd_route=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}' 2>/dev/null || echo "Not available")
    
    echo -e "${GREEN}Bootstrap completed successfully!${NC}"
    echo ""
    echo "Cluster Name:    ${CLUSTER_NAME}"
    echo "GitOps Repo:     ${GITOPS_REPO}"
    echo "ArgoCD URL:      https://${argocd_route}"
    echo ""
    echo "Applications deployed from cluster configuration:"
    echo "  - Path: clusters/${CLUSTER_NAME}/"
    echo "  - Groups: all, non-prod, geo-east"
    echo ""
    echo "To access ArgoCD:"
    echo "  1. Navigate to: https://${argocd_route}"
    echo "  2. Login with your OpenShift credentials"
    echo ""
    echo "To monitor applications:"
    echo "  oc get applications -n openshift-gitops"
    echo ""
    echo "To check application status:"
    echo "  oc get applications -n openshift-gitops -o wide"
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--cluster)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -r|--repo)
            GITOPS_REPO="$2"
            shift 2
            ;;
        -b|--branch)
            GIT_BRANCH="$2"
            shift 2
            ;;
        -p|--push)
            GIT_PUSH="true"
            shift
            ;;
        -d|--dry-run)
            DRY_RUN="true"
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            ;;
    esac
done

# Validate required parameters
if [ -z "$GITOPS_REPO" ]; then
    print_error "GitOps repository URL is required. Use -r or --repo to specify."
    echo "Example: $0 -c test-non-prod -r https://github.com/rich-p-ai/argo-demo.git"
    exit 1
fi

# Print banner
print_header "Red Hat GitOps Bootstrap Script"
echo "Cluster:      ${CLUSTER_NAME}"
echo "Repository:   ${GITOPS_REPO}"
echo "Branch:       ${GIT_BRANCH}"
echo "Git Push:     ${GIT_PUSH}"
echo "Dry Run:      ${DRY_RUN}"

# Check prerequisites
print_step "0" "Checking prerequisites"
check_command "oc"
check_command "envsubst"
if [ "$GIT_PUSH" == "true" ]; then
    check_command "git"
fi

# Verify bootstrap files exist
if [ ! -d "$BOOTSTRAP_DIR" ]; then
    print_error "Bootstrap directory not found: $BOOTSTRAP_DIR"
    exit 1
fi

for file in subscription.yaml cluster-rolebinding.yaml argocd.yaml root-application.yaml; do
    if [ ! -f "${BOOTSTRAP_DIR}/${file}" ]; then
        print_error "Required bootstrap file not found: ${BOOTSTRAP_DIR}/${file}"
        exit 1
    fi
done
print_info "✓ All bootstrap files present"

# Verify cluster configuration exists
if [ ! -d "${REPO_ROOT}/clusters/${CLUSTER_NAME}" ]; then
    print_error "Cluster configuration not found: ${REPO_ROOT}/clusters/${CLUSTER_NAME}"
    exit 1
fi
print_info "✓ Cluster configuration found: clusters/${CLUSTER_NAME}"

# Execute bootstrap steps
verify_cluster_connection
create_gitops_namespace
deploy_gitops_operator
configure_argocd
deploy_root_application
git_commit_and_push
print_summary

print_info "Bootstrap complete!"
