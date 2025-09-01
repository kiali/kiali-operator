#!/bin/bash

##############################################################################
# verify-crd-defaults.sh
#
# This script verifies that the default values in CRDs match the corresponding
# default values in the Ansible defaults/main.yml files.
#
# WHY THIS MATTERS:
# The Kiali operator uses Ansible to deploy Kiali and OSSMConsole. The defaults
# in the Ansible playbooks should match the defaults defined in the CRDs to
# ensure consistent behavior between what's documented in the CRD schema and
# what actually gets deployed.
#
# WHAT IT CHECKS:
# - Kiali CRD (kiali.io_kialis.yaml) vs kiali-deploy defaults/main.yml
# - OSSMConsole CRD (kiali.io_ossmconsoles.yaml) vs ossmconsole-deploy defaults/main.yml
#
# HOW IT WORKS:
# - Dynamically discovers all defaults in CRDs using yq
# - Automatically builds verification arrays for each CRD
# - Compares CRD defaults with corresponding Ansible defaults
# - No manual maintenance required when CRD schemas change
#
# USAGE:
# - Run directly: ./hack/verify-crd-defaults.sh
# - Run via make: make verify-defaults
# - Runs automatically in CI on PRs that modify CRDs or defaults files
#
# REQUIREMENTS:
# - yq (YAML processor) must be installed
# - Script should be run from the kiali-operator root directory
##############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Counters
ERRORS=0
CHECKS=0

# Arrays to track results for final report
SKIPPED_PROPERTIES=()
FAILED_CHECKS=()
PASSED_CHECKS=()

# Properties to ignore during verification
# Add property names (as discovered by the script) that should be skipped
PROPERTIES_TO_IGNORE=(
    # Deprecated properties that are no longer used
    "external_services.istio.envoy_admin_local_port"
    "external_services.istio.istiod_pod_monitoring_port"
    "external_services.istio.istio_injection_annotation"
    "external_services.istio.istio_sidecar_annotation"

    # Array item defaults that don't have direct Ansible equivalents
    "deployment.custom_secrets.items.optional"
    "extensions.items.enabled"
    "external_services.istio.component_status.components.items.is_core"
    "external_services.istio.component_status.components.items.is_proxy"
    "kiali_feature_flags.ui_defaults.graph.find_options.items.auto_select"
    "kiali_feature_flags.ui_defaults.graph.hide_options.items.auto_select"
    "kiali_feature_flags.ui_defaults.mesh.find_options.items.auto_select"
    "kiali_feature_flags.ui_defaults.mesh.hide_options.items.auto_select"
)

# Function to add a skipped property to the report
add_skipped_property() {
    local property="$1"
    SKIPPED_PROPERTIES+=("$property")
}

# Function to add a failed check to the report
add_failed_check() {
    local property="$1"
    local crd_value="$2"
    local ansible_value="$3"
    local reason="$4"
    FAILED_CHECKS+=("$property|$crd_value|$ansible_value|$reason")
}

# Function to add a passed check to the report
add_passed_check() {
    local property="$1"
    local value="$2"
    PASSED_CHECKS+=("$property|$value")
}

# Function to log messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ERRORS=$((ERRORS + 1))
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to extract default value from CRD
extract_crd_default() {
    local file="$1"
    local path="$2"
    local result

    result=$(yq eval "$path" "$file" 2>/dev/null || echo "null")

    if [ "$result" = "null" ]; then
        echo ""
    else
        echo "$result"
    fi
}

# Function to extract default value from Ansible YAML
extract_ansible_default() {
    local file="$1"
    local path="$2"
    local result

    result=$(yq eval "$path" "$file" 2>/dev/null || echo "null")

    if [ "$result" = "null" ]; then
        echo ""
    else
        echo "$result"
    fi
}

# Function to compare a single default value
compare_default() {
    local name="$1"
    local crd_file="$2"
    local crd_path="$3"
    local ansible_file="$4"
    local ansible_path="$5"

    CHECKS=$((CHECKS + 1))

    local crd_value=$(extract_crd_default "$crd_file" "$crd_path")
    local ansible_value=$(extract_ansible_default "$ansible_file" "$ansible_path")

    # Handle special cases for comparison
    local crd_normalized="$crd_value"
    local ansible_normalized="$ansible_value"

    # Convert empty strings to "null" for comparison
    if [ -z "$crd_normalized" ]; then
        crd_normalized="null"
    fi
    if [ -z "$ansible_normalized" ]; then
        ansible_normalized="null"
    fi

    if [ "$crd_normalized" = "$ansible_normalized" ]; then
        log_info "✓ $name: '$crd_value' (matches)"
        add_passed_check "$name" "$crd_value"
    else
        # Determine failure reason
        local reason="Values differ"
        if [ "$ansible_normalized" = "null" ]; then
            reason="Property missing in Ansible defaults"
        elif [ "$crd_normalized" = "null" ]; then
            reason="Property missing in CRD (unexpected)"
        fi

        log_error "✗ $name: CRD='$crd_value' vs Ansible='$ansible_value'"
        add_failed_check "$name" "$crd_value" "$ansible_value" "$reason"
    fi
}

# Function to check if required tools are available
check_dependencies() {
    if ! command -v yq &> /dev/null; then
        log_error "yq is required but not installed."
        log_error "Please install yq from: https://github.com/mikefarah/yq/releases"
        log_error "Or use the GitHub workflow which automatically installs it."
        exit 1
    fi

    # Verify yq version is compatible
    local yq_version=$(yq --version 2>/dev/null | head -1)
    log_info "Using yq: $yq_version"
}

# Function to check if a property should be ignored
is_property_ignored() {
    local property="$1"

    for ignored_property in "${PROPERTIES_TO_IGNORE[@]}"; do
        if [ "$property" = "$ignored_property" ]; then
            return 0  # Property should be ignored
        fi
    done

    return 1  # Property should not be ignored
}

# Function to dynamically discover all defaults in a CRD and build the defaults array
discover_crd_defaults() {
    local crd_file="$1"
    local defaults_prefix="$2"  # e.g., "kiali_defaults" or "ossmconsole_defaults"
    local array_name="$3"       # e.g., "KIALI_DEFAULTS" or "OSSMCONSOLE_DEFAULTS"

    log_info "Discovering defaults in CRD: $(basename "$crd_file")"

    # Find all paths that have a "default:" key in the CRD
    # This uses yq to find all paths ending with ".default"
    # Filter out schema property definitions (e.g., properties.default which is a property name, not a default value)
    local default_paths
    default_paths=$(yq eval '.. | select(has("default")) | path | join(".")' "$crd_file" 2>/dev/null | grep -v "^$" | grep -v "\.properties$" | sort -u)

    local discovered_count=0
    local skipped_count=0
    local -n array_ref="$array_name"
    array_ref=()

    while IFS= read -r yaml_path; do
        if [ -z "$yaml_path" ]; then
            continue
        fi

        # Extract the property name from the path
        # Convert from yq path format to property name
        local property_name
        property_name=$(echo "$yaml_path" | sed 's/^spec\.versions\.0\.schema\.openAPIV3Schema\.properties\.spec\.properties\.//' | sed 's/\.properties\./\./g' | sed 's/\.items\.properties\./.[]./g' | sed 's/\.default$//')

        # Skip if this is not a spec property (safety check)
        if [[ ! "$yaml_path" =~ ^spec\.versions\.0\.schema\.openAPIV3Schema\.properties\.spec\.properties\. ]]; then
            continue
        fi

        # Check if this property should be ignored
        if is_property_ignored "$property_name"; then
            log_info "  Skipped: $property_name (ignored)"
            add_skipped_property "$property_name"
            skipped_count=$((skipped_count + 1))
            continue
        fi

        # Build the CRD path for yq (using the versioned schema path)
        local crd_path=".${yaml_path}.default"

        # Build the Ansible path
        local ansible_path=".${defaults_prefix}.${property_name}"

        # Add to array
        array_ref+=("${property_name}|${crd_path}|${ansible_path}")
        discovered_count=$((discovered_count + 1))

        log_info "  Found: $property_name"
    done <<< "$default_paths"

    log_info "Discovered $discovered_count defaults in $(basename "$crd_file") (skipped $skipped_count)"
}

# Dynamic arrays that will be populated by discover_crd_defaults function
KIALI_DEFAULTS=()
OSSMCONSOLE_DEFAULTS=()

# Function to verify Kiali CRD defaults
verify_kiali_defaults() {
    local crd_file="$ROOT_DIR/crd-docs/crd/kiali.io_kialis.yaml"
    local ansible_file="$ROOT_DIR/roles/default/kiali-deploy/defaults/main.yml"

    log_info "Verifying Kiali CRD defaults against Ansible defaults..."

    if [ ! -f "$crd_file" ]; then
        log_error "Kiali CRD file not found: $crd_file"
        return
    fi

    if [ ! -f "$ansible_file" ]; then
        log_error "Kiali Ansible defaults file not found: $ansible_file"
        return
    fi

    # Dynamically discover all defaults in the Kiali CRD
    discover_crd_defaults "$crd_file" "kiali_defaults" "KIALI_DEFAULTS"

    # Process all discovered Kiali defaults
    for default_spec in "${KIALI_DEFAULTS[@]}"; do
        IFS='|' read -r name crd_path ansible_path <<< "$default_spec"
        compare_default "$name" "$crd_file" "$crd_path" "$ansible_file" "$ansible_path"
    done
}

# Function to verify OSSMConsole CRD defaults
verify_ossmconsole_defaults() {
    local crd_file="$ROOT_DIR/crd-docs/crd/kiali.io_ossmconsoles.yaml"
    local ansible_file="$ROOT_DIR/roles/default/ossmconsole-deploy/defaults/main.yml"

    log_info "Verifying OSSMConsole CRD defaults against Ansible defaults..."

    if [ ! -f "$crd_file" ]; then
        log_error "OSSMConsole CRD file not found: $crd_file"
        return
    fi

    if [ ! -f "$ansible_file" ]; then
        log_error "OSSMConsole Ansible defaults file not found: $ansible_file"
        return
    fi

    # Dynamically discover all defaults in the OSSMConsole CRD
    discover_crd_defaults "$crd_file" "ossmconsole_defaults" "OSSMCONSOLE_DEFAULTS"

    # Process all discovered OSSMConsole defaults
    for default_spec in "${OSSMCONSOLE_DEFAULTS[@]}"; do
        IFS='|' read -r name crd_path ansible_path <<< "$default_spec"
        compare_default "$name" "$crd_file" "$crd_path" "$ansible_file" "$ansible_path"
    done
}

# Function to generate final report
generate_report() {
    echo
    echo "========================================"
    echo "           VERIFICATION REPORT"
    echo "========================================"

    # Report skipped properties
    echo
    if [ ${#SKIPPED_PROPERTIES[@]} -gt 0 ]; then
        echo -e "${YELLOW}SKIPPED PROPERTIES (${#SKIPPED_PROPERTIES[@]}):${NC}"
        echo "----------------------------------------"
        for property in "${SKIPPED_PROPERTIES[@]}"; do
            echo "  • $property"
        done
    else
        echo -e "${GREEN}SKIPPED PROPERTIES: None${NC}"
    fi

    # Report failed checks
    echo
    if [ ${#FAILED_CHECKS[@]} -gt 0 ]; then
        echo -e "${RED}FAILED CHECKS (${#FAILED_CHECKS[@]}):${NC}"
        echo "----------------------------------------"
        for failed_check in "${FAILED_CHECKS[@]}"; do
            IFS='|' read -r property crd_value ansible_value reason <<< "$failed_check"
            echo -e "  ${RED}✗${NC} $property"
            echo "    Reason: $reason"
            echo "    CRD value: '$crd_value'"
            echo "    Ansible value: '$ansible_value'"
            echo
        done
    else
        echo -e "${GREEN}FAILED CHECKS: None${NC}"
    fi

    # Report summary
    echo
    echo "========================================"
    echo "               SUMMARY"
    echo "========================================"
    echo "Total properties discovered: $((${#SKIPPED_PROPERTIES[@]} + ${#PASSED_CHECKS[@]} + ${#FAILED_CHECKS[@]}))"
    echo "Properties verified: ${#PASSED_CHECKS[@]}"
    echo "Properties skipped: ${#SKIPPED_PROPERTIES[@]}"
    echo "Properties failed: ${#FAILED_CHECKS[@]}"
    echo

    if [ ${#FAILED_CHECKS[@]} -eq 0 ]; then
        echo -e "${GREEN}✅ ALL VERIFIED PROPERTIES MATCH SUCCESSFULLY!${NC}"
    else
        echo -e "${RED}❌ ${#FAILED_CHECKS[@]} PROPERTIES HAVE MISMATCHED DEFAULTS${NC}"
    fi
    echo "========================================"
}

# Main execution
main() {
    log_info "Starting CRD defaults verification..."

    check_dependencies

    verify_kiali_defaults
    echo
    verify_ossmconsole_defaults

    echo
    log_info "Verification complete. Total checks: $CHECKS, Errors: $ERRORS"

    # Generate detailed report
    generate_report

    if [ $ERRORS -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"
