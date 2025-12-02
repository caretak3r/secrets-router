#!/bin/bash

# K8s-Secrets-Broker Cleanup Script
# Comprehensive cleanup of all resources installed by this project

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default configuration
RELEASE_NAME="secrets-broker"
NAMESPACE="dapr-control-plane"
DRY_RUN=false
FORCE=false
DELETE_CRDS=false
DELETE_NAMESPACE=false

# Parse command line arguments
function show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up all resources installed by the K8s-Secrets-Broker project from a Kubernetes cluster.

OPTIONS:
    -r, --release NAME       Helm release name (default: secrets-broker)
    -n, --namespace NAME     Kubernetes namespace (default: dapr-control-plane)
    --delete-crds           Delete Dapr CRDs (WARNING: Affects all Dapr installations)
    --delete-namespace     Delete the entire namespace (WARNING: Deletes all resources in namespace)
    --force                Skip confirmation prompts
    --dry-run              Show what would be deleted without actually deleting
    -h, --help             Show this help message

WARNING:
    This script will permanently delete:
    - The Helm chart release
    - All Kubernetes resources created by the project
    - Potentially Dapr CRDs (if --delete-crds is specified)
    - Potentially the entire namespace (if --delete-namespace is specified)
    
    Always review with --dry-run first!

EXAMPLES:
    # Show what would be deleted
    $0 --dry-run

    # Clean up just the release
    $0

    # Clean up including Dapr CRDs
    $0 --delete-crds -f

    # Clean up everything including namespace
    $0 --delete-namespace --force

EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --delete-crds)
            DELETE_CRDS=true
            shift
            ;;
        --delete-namespace)
            DELETE_NAMESPACE=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
function log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

function log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

function log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

function log_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

function check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 is required but not installed"
        exit 1
    fi
}

function check_kubernetes() {
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Kubernetes cluster is not accessible"
        exit 1
    fi
}

function dry_run_log() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY RUN] $1"
    else
        log_info "$1"
    fi
}

function dry_run_exec() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY RUN] Would execute: $cmd"
        log_warn "[DRY RUN] Description: $description"
    else
        log_info "Executing: $cmd"
        if eval "$cmd"; then
            log_info "✅ $description - successful"
        else
            log_warn "⚠️  $description - failed (may not exist)"
        fi
    fi
}

echo "🧹 K8s-Secrets-Broker Cleanup Script"
log_header "Configuration"
echo "Release Name: $RELEASE_NAME"
echo "Namespace: $NAMESPACE"
echo "Delete CRDs: $DELETE_CRDS"
echo "Delete Namespace: $DELETE_NAMESPACE"
echo "Dry Run: $DRY_RUN"
echo "Force: $FORCE"
echo "=================================="

# 1. Prerequisites check
log_header "Prerequisites"
log_info "Checking required tools..."
check_command "kubectl"
check_command "helm"

log_info "Checking Kubernetes cluster..."
check_kubernetes

# 2. Show what will be deleted
log_header "Resources to be Deleted"

# Track if any resources were found to delete
resources_found=false

# Check for Helm release
if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
    log_info "📦 Helm release '$RELEASE_NAME' in namespace '$NAMESPACE'"
    resources_found=true
else
    log_warn "❓ Helm release '$RELEASE_NAME' not found in namespace '$NAMESPACE'"
fi

# Check for namespace
if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    resources_found=true
    # List resources in namespace
    log_info "📋 Resources in namespace '$NAMESPACE':"
    
    # Get all resource types that might exist
    resources=("pods" "deployments" "services" "configmaps" "secrets" "serviceaccounts" "roles" "rolebindings" "component" "configurations" "subscriptions")
    
    for resource in "${resources[@]}"; do
        local count=$(kubectl get "$resource" -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
        if [[ $count -gt 0 ]]; then
            log_info "  - $resource: $count items"
        fi
    done
else
    log_warn "❓ Namespace '$NAMESPACE' not found"
fi

# Check for Dapr CRDs
log_info "🔧 Dapr CRDs:"
crds_found=false
dapr_crds=()

# Discover all CRDs with dapr.io group
if command -v jq >/dev/null 2>&1; then
    # Use jq for JSON parsing if available
    all_crds=$(kubectl get crd -o json 2>/dev/null || echo '{"items": []}')
    dapr_crds=$(echo "$all_crds" | jq -r '.items[] | select(.spec.group == "dapr.io") | .metadata.name' 2>/dev/null || true)
    
    # Debug: Show all CRDs found
    echo "  [DEBUG] All CRDs in cluster: $(echo "$all_crds" | jq -r '.items[].metadata.name' 2>/dev/null | tr '\n' ' ' || echo 'none')"
    echo "  [DEBUG] CRDs with dapr.io group: $(echo "$dapr_crds" | tr '\n' ' ' || echo 'none')"
else
    # Fallback to text processing
    all_crds_text=$(kubectl get crd --no-headers 2>/dev/null || echo "")
    echo "  [DEBUG] CRDs in cluster: $(echo "$all_crds_text" | head -5 | wc -l) total"
    dapr_crds=$(echo "$all_crds_text" | awk '$2 == "dapr.io" {print $1}' 2>/dev/null || true)
    echo "  [DEBUG] dapr.io CRDs found: $(echo "$dapr_crds" | tr '\n' ' ' || echo 'none')"
fi

if [[ -n "$dapr_crds" ]]; then
    # Convert to array and iterate
    IFS=$'\n' read -r -a crd_array <<< "$dapr_crds"
    log_info "  Found ${#crd_array[@]} CRDs with dapr.io group:"
    for crd in "${crd_array[@]}"; do
        if [[ -n "$crd" ]]; then
            log_info "  - $crd (will be deleted if --delete-crds is specified)"
            resources_found=true
            crds_found=true
            dapr_crds+=("$crd")
        fi
    done
else
    log_warn "  No Dapr CRDs (.dapr.io group) found in cluster"
fi

# Exit early if no resources found and not in dry run mode
if [[ "$resources_found" == "false" ]]; then
    log_info "✨ No resources found to clean up!"
    log_info "The cluster appears to be clean of K8s-Secrets-Broker resources."
    exit 0
fi

# 3. Confirmation prompt
if [[ "$DRY_RUN" == "false" && "$FORCE" == "false" ]]; then
    echo ""
    log_warn "⚠️  WARNING: This will permanently delete the resources listed above!"
    if [[ "$DELETE_CRDS" == "true" ]]; then
        log_warn "⚠️  Dapr CRDs will be deleted - this will affect ALL Dapr installations in the cluster!"
    fi
    if [[ "$DELETE_NAMESPACE" == "true" ]]; then
        log_warn "⚠️  The entire namespace '$NAMESPACE' will be deleted - this affects ALL resources in it!"
    fi
    echo ""
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
elif [[ "$FORCE" == "true" ]]; then
    log_warn "⚠️  Skipping confirmation due to --force flag"
fi

# 4. Cleanup operations
log_header "Cleanup Operations"

# Step 1: Remove Helm release
log_info "Step 1: Removing Helm release"
if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
    dry_run_exec "helm uninstall $RELEASE_NAME --namespace $NAMESPACE" "Uninstall Helm release"
else
    log_warn "Helm release '$RELEASE_NAME' not found, skipping uninstall"
fi

# Step 2: Remove remaining resources in namespace
if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    log_info "Step 2: Removing remaining resources in namespace '$NAMESPACE'"
    
    # Remove Dapr components
    dry_run_exec "kubectl delete components --all -n $NAMESPACE --ignore-not-found=true" "Delete Dapr components"
    
    # Remove configurations
    dry_run_exec "kubectl delete configurations --all -n $NAMESPACE --ignore-not-found=true" "Delete Dapr configurations"
    
    # Remove subscriptions
    dry_run_exec "kubectl delete subscriptions --all -n $NAMESPACE --ignore-not-found=true" "Delete Dapr subscriptions"
    
    # Remove standard Kubernetes resources
    dry_run_exec "kubectl delete deployments --all -n $NAMESPACE --ignore-not-found=true" "Delete deployments"
    dry_run_exec "kubectl delete services --all -n $NAMESPACE --ignore-not-found=true" "Delete services"
    dry_run_exec "kubectl delete pods --all -n $NAMESPACE --ignore-not-found=true" "Delete pods"
    dry_run_exec "kubectl delete configmaps --all -n $NAMESPACE --ignore-not-found=true" "Delete configmaps"
    dry_run_exec "kubectl delete secrets --all -n $NAMESPACE --ignore-not-found=true" "Delete secrets"
    dry_run_exec "kubectl delete serviceaccounts --all -n $NAMESPACE --ignore-not-found=true" "Delete service accounts"
    dry_run_exec "kubectl delete roles --all -n $NAMESPACE --ignore-not-found=true" "Delete roles"
    dry_run_exec "kubectl delete rolebindings --all -n $NAMESPACE --ignore-not-found=true" "Delete role bindings"
    
    # Wait for resources to be deleted
    if [[ "$DRY_RUN" == "false" ]]; then
        log_info "Waiting for resources to be cleaned up..."
        sleep 5
    fi
fi

# Step 3: Remove namespace (if requested)
if [[ "$DELETE_NAMESPACE" == "true" ]]; then
    log_info "Step 3: Removing namespace '$NAMESPACE'"
    dry_run_exec "kubectl delete namespace $NAMESPACE --ignore-not-found=true" "Delete namespace"
else
    log_info "Step 3: Skipping namespace deletion (use --delete-namespace to remove it)"
fi

# Step 4: Remove Dapr CRDs (if requested)
if [[ "$DELETE_CRDS" == "true" && ${#dapr_crds[@]} -gt 0 ]]; then
    log_info "Step 4: Removing Dapr CRDs (${#dapr_crds[@]} found)"
    for crd in "${dapr_crds[@]}"; do
        if [[ -n "$crd" ]]; then
            dry_run_exec "kubectl delete crd $crd --ignore-not-found=true" "Delete CRD $crd"
        fi
    done
elif [[ "$DELETE_CRDS" == "true" ]]; then
    log_info "Step 4: Skipping Dapr CRD deletion (no Dapr CRDs found)"
else
    log_info "Step 4: Skipping Dapr CRD deletion (use --delete-crds to remove them)"
fi

# Step 5: Remove orphaned Dapr system resources (if --delete-crds was used)
if [[ "$DELETE_CRDS" == "true" ]]; then
    log_info "Step 5: Cleaning up orphaned Dapr system resources"
    
    # Remove Dapr system resources in any namespace
    log_info "Checking for Dapr resources in all namespaces..."
    
    # Get all namespaces
    namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
    
    for ns in $namespaces; do
        # Clean up Dapr components in this namespace
        if kubectl get components -n "$ns" --no-headers 2>/dev/null | head -1 | grep -q .; then
            log_info "  Cleaning components in namespace '$ns'..."
            dry_run_exec "kubectl delete components --all -n $ns --ignore-not-found=true" "Delete Dapr components in $ns"
        fi
        
        # Clean up Dapr configurations
        if kubectl get configurations -n "$ns" --no-headers 2>/dev/null | head -1 | grep -q .; then
            log_info "  Cleaning configurations in namespace '$ns'..."
            dry_run_exec "kubectl delete configurations --all -n $ns --ignore-not-found=true" "Delete Dapr configurations in $ns"
        fi
        
        # Clean up Dapr subscriptions
        if kubectl get subscriptions -n "$ns" --no-headers 2>/dev/null | head -1 | grep -q .; then
            log_info "  Cleaning subscriptions in namespace '$ns'..."
            dry_run_exec "kubectl delete subscriptions --all -n $ns --ignore-not-found=true" "Delete Dapr subscriptions in $ns"
        fi
        
        # Clean up Dapr resiliencies (CRD-specific, even if no instances exist)
        if command -v kubectl >/dev/null 2>&1 && kubectl api-resources | grep -q "resiliencies.*dapr.io"; then
            if kubectl get resiliencies -n "$ns" --no-headers 2>/dev/null | head -1 | grep -q .; then
                log_info "  Cleaning resiliencies in namespace '$ns'..."
                dry_run_exec "kubectl delete resiliencies --all -n $ns --ignore-not-found=true" "Delete Dapr resiliencies in $ns"
            fi
        fi
    done
    
    # Step 5.1: Clean up Dapr RBAC resources (cluster-scoped and namespaced)
    log_info "Step 5.1: Cleaning up Dapr RBAC resources"
    
    # Clean up Dapr ClusterRoles
    dapr_cluster_roles=$(kubectl get clusterroles --no-headers 2>/dev/null | grep "dapr\|Dapr" | awk '{print $1}' || true)
    if [[ -n "$dapr_cluster_roles" ]]; then
        log_info "  Found Dapr ClusterRoles to clean"
        for role in $dapr_cluster_roles; do
            dry_run_exec "kubectl delete clusterrole $role --ignore-not-found=true" "Delete ClusterRole $role"
        done
    else
        log_info "  No Dapr ClusterRoles found"
    fi
    
    # Clean up Dapr ClusterRoleBindings
    dapr_cluster_rolebindings=$(kubectl get clusterrolebindings --no-headers 2>/dev/null | grep "dapr\|Dapr" | awk '{print $1}' || true)
    if [[ -n "$dapr_cluster_rolebindings" ]]; then
        log_info "  Found Dapr ClusterRoleBindings to clean"
        for binding in $dapr_cluster_rolebindings; do
            dry_run_exec "kubectl delete clusterrolebinding $binding --ignore-not-found=true" "Delete ClusterRoleBinding $binding"
        done
    else
        log_info "  No Dapr ClusterRoleBindings found"
    fi
    
    # Clean up Dapr Roles in all namespaces
    for ns in $namespaces; do
        dapr_roles=$(kubectl get roles -n "$ns" --no-headers 2>/dev/null | grep "dapr\|Dapr" | awk '{print $1}' || true)
        if [[ -n "$dapr_roles" ]]; then
            log_info "  Found Dapr Roles in namespace '$ns' to clean"
            for role in $dapr_roles; do
                dry_run_exec "kubectl delete role $role -n $ns --ignore-not-found=true" "Delete Role $role in $ns"
            done
        fi
        
        # Clean up Dapr RoleBindings in all namespaces
        dapr_rolebindings=$(kubectl get rolebindings -n "$ns" --no-headers 2>/dev/null | grep "dapr\|Dapr" | awk '{print $1}' || true)
        if [[ -n "$dapr_rolebindings" ]]; then
            log_info "  Found Dapr RoleBindings in namespace '$ns' to clean"
            for binding in $dapr_rolebindings; do
                dry_run_exec "kubectl delete rolebinding $binding -n $ns --ignore-not-found=true" "Delete RoleBinding $binding in $ns"
            done
        fi
    done
    
    # Step 5.2: Clean up Dapr ServiceAccounts
    log_info "Step 5.2: Cleaning up Dapr ServiceAccounts"
    for ns in $namespaces; do
        dapr_serviceaccounts=$(kubectl get serviceaccounts -n "$ns" --no-headers 2>/dev/null | grep "dapr\|Dapr" | awk '{print $1}' || true)
        if [[ -n "$dapr_serviceaccounts" ]]; then
            log_info "  Found Dapr ServiceAccounts in namespace '$ns' to clean"
            for sa in $dapr_serviceaccounts; do
                dry_run_exec "kubectl delete serviceaccount $sa -n $ns --ignore-not-found=true" "Delete ServiceAccount $sa in $ns"
            done
        fi
    done
    
    # Step 5.3: Clean up Dapr ConfigMaps and Secrets
    log_info "Step 5.3: Cleaning up Dapr ConfigMaps and Secrets"
    for ns in $namespaces; do
        # Clean up Dapr ConfigMaps
        dapr_configmaps=$(kubectl get configmaps -n "$ns" --no-headers 2>/dev/null | grep "dapr\|Dapr" | awk '{print $1}' || true)
        if [[ -n "$dapr_configmaps" ]]; then
            log_info "  Found Dapr ConfigMaps in namespace '$ns' to clean"
            for cm in $dapr_configmaps; do
                dry_run_exec "kubectl delete configmap $cm -n $ns --ignore-not-found=true" "Delete ConfigMap $cm in $ns"
            done
        fi
        
        # Clean up Dapr Secrets
        dapr_secrets=$(kubectl get secrets -n "$ns" --no-headers 2>/dev/null | grep "dapr\|Dapr" | awk '{print $1}' || true)
        if [[ -n "$dapr_secrets" ]]; then
            log_info "  Found Dapr Secrets in namespace '$ns' to clean"
            for secret in $dapr_secrets; do
                dry_run_exec "kubectl delete secret $secret -n $ns --ignore-not-found=true" "Delete Secret $secret in $ns"
            done
        fi
    done
    
    # Step 5.4: Clean up Dapr Services and Deployments
    log_info "Step 5.4: Cleaning up Dapr Services and Deployments"
    for ns in $namespaces; do
        # Clean up Dapr Services
        dapr_services=$(kubectl get services -n "$ns" --no-headers 2>/dev/null | grep "dapr\|Dapr" | awk '{print $1}' || true)
        if [[ -n "$dapr_services" ]]; then
            log_info "  Found Dapr Services in namespace '$ns' to clean"
            for svc in $dapr_services; do
                dry_run_exec "kubectl delete service $svc -n $ns --ignore-not-found=true" "Delete Service $svc in $ns"
            done
        fi
        
        # Clean up Dapr Deployments
        dapr_deployments=$(kubectl get deployments -n "$ns" --no-headers 2>/dev/null | grep "dapr\|Dapr" | awk '{print $1}' || true)
        if [[ -n "$dapr_deployments" ]]; then
            log_info "  Found Dapr Deployments in namespace '$ns' to clean"
            for deploy in $dapr_deployments; do
                dry_run_exec "kubectl delete deployment $deploy -n $ns --ignore-not-found=true" "Delete Deployment $deploy in $ns"
            done
        fi
        
        # Clean up Dapr StatefulSets
        dapr_statefulsets=$(kubectl get statefulsets -n "$ns" --no-headers 2>/dev/null | grep "dapr\|Dapr" | awk '{print $1}' || true)
        if [[ -n "$dapr_statefulsets" ]]; then
            log_info "  Found Dapr StatefulSets in namespace '$ns' to clean"
            for sts in $dapr_statefulsets; do
                dry_run_exec "kubectl delete statefulset $sts -n $ns --ignore-not-found=true" "Delete StatefulSet $sts in $ns"
            done
        fi
        
        # Clean up Dapr DaemonSets
        dapr_daemonsets=$(kubectl get daemonsets -n "$ns" --no-headers 2>/dev/null | grep "dapr\|Dapr" | awk '{print $1}' || true)
        if [[ -n "$dapr_daemonsets" ]]; then
            log_info "  Found Dapr DaemonSets in namespace '$ns' to clean"
            for ds in $dapr_daemonsets; do
                dry_run_exec "kubectl delete daemonset $ds -n $ns --ignore-not-found=true" "Delete DaemonSet $ds in $ns"
            done
        fi
    done
    
    # Try to remove Dapr system namespace if it's empty or if force is used
    if kubectl get namespace dapr-system &> /dev/null; then
        if [[ "$FORCE" == "true" ]]; then
            # Force delete namespace even if it has resources
            dry_run_exec "kubectl delete namespace dapr-system --ignore-not-found=true --grace-period=0 --force" "Force delete Dapr system namespace"
        else
            # Check if namespace is empty
            resource_count=$(kubectl api-resources --verbs=list --namespaced -o name | tr '\n' ' ' | xargs -I {} kubectl get {} -n dapr-system --no-headers 2>/dev/null | wc -l)
            if [[ $resource_count -eq 0 ]]; then
                dry_run_exec "kubectl delete namespace dapr-system --ignore-not-found=true" "Delete empty Dapr system namespace"
            else
                log_info "  Dapr system namespace has $resource_count resources, skipping deletion (use --force to force delete)"
            fi
        fi
    fi
fi

# 6. Verification
log_header "Cleanup Verification"
if [[ "$DRY_RUN" == "false" ]]; then
    log_info "Verifying cleanup..."
    
    # Check if release still exists
    if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
        log_warn "⚠️  Helm release '$RELEASE_NAME' still exists"
    else
        log_info "✅ Helm release '$RELEASE_NAME' cleaned up"
    fi
    
    # Check if namespace still exists
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        if [[ "$DELETE_NAMESPACE" == "true" ]]; then
            log_warn "⚠️  Namespace '$NAMESPACE' still exists"
        else
            log_info "ℹ️  Namespace '$NAMESPACE' still exists (as requested)"
        fi
    else
        log_info "✅ Namespace '$NAMESPACE' cleaned up"
    fi
    
    # Check remaining resources
    if kubectl get namespace "$NAMESPACE" &> /dev/null && [[ "$DELETE_NAMESPACE" == "false" ]]; then
        local remaining_resources=$(kubectl api-resources --verbs=list --namespaced -o name | tr '\n' ' ' | xargs -I {} kubectl get {} -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
        if [[ $remaining_resources -gt 0 ]]; then
            log_warn "⚠️  $remaining_resources resources still exist in namespace '$NAMESPACE'"
        else
            log_info "✅ No resources remain in namespace '$NAMESPACE'"
        fi
    fi
fi

# Final summary
log_header "Cleanup Summary"
if [[ "$DRY_RUN" == "true" ]]; then
    log_info "🔍 Dry run completed - no actual changes were made"
    log_info "   To perform the actual cleanup, run the same command without --dry-run"
else
    log_info "✨ Cleanup completed successfully!"
    if [[ "$DELETE_CRDS" == "true" ]]; then
        log_warn "⚠️  Warning: Dapr CRDs were deleted - other Dapr installations may be affected"
    fi
fi

echo ""
log_info "Next steps:"
if [[ "$DRY_RUN" == "true" ]]; then
    echo "  1. Review the dry run output above"
    echo "  2. Run: $0"
else
    echo "  1. Verify the cluster is clean: kubectl get all -A"
    echo "  2. Reinstall with: ./scripts/helm-install.sh"
    if [[ "$DELETE_CRDS" == "true" ]]; then
        echo "  3. If needed, reinstall Dapr: helm repo add dapr https://dapr.github.io/helm-charts/ && helm install dapr dapr/dapr --namespace dapr-system --create-namespace"
    fi
fi

echo ""
log_info "🎉 Script completed!"
