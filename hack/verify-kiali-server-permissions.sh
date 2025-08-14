#!/bin/bash

# This script verifies that Kiali Server permissions defined in the operator role templates
# are correctly mirrored in the operator's own permissions (CSV files and helm chart).
# This ensures the operator has the necessary permissions to create the Kiali Server roles.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Will be set after log functions are defined
ROOT_DIR=""
REPO_TYPE=""
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Error counter
ERRORS=0

log_error() {
    echo -e "${RED}ERROR:${NC} $1" >&2
    ((ERRORS++))
}

log_success() {
    echo -e "${GREEN}SUCCESS:${NC} $1"
}

log_info() {
    echo "INFO: $1"
}

# Detect which repository we're running from based on directory structure
detect_repository_type() {
    if [[ -d "${SCRIPT_DIR}/../manifests/kiali-ossm" ]] && [[ -d "${SCRIPT_DIR}/../roles/default" ]]; then
        # Running from kiali-operator repository (has manifests and roles directories)
        ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
        REPO_TYPE="kiali-operator"
        log_info "Detected kiali-operator repository"
    elif [[ -d "${SCRIPT_DIR}/../kiali-server" ]] && [[ -d "${SCRIPT_DIR}/../kiali-operator" ]] && [[ -f "${SCRIPT_DIR}/../Makefile" ]] && grep -q "build-helm-charts" "${SCRIPT_DIR}/../Makefile" 2>/dev/null; then
        # Running from helm-charts repository (has kiali-server and kiali-operator chart directories)
        ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
        REPO_TYPE="helm-charts"
        log_info "Detected helm-charts repository"
    else
        # Fallback: assume kiali-operator for backward compatibility
        ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
        REPO_TYPE="kiali-operator"
        log_info "Unable to detect repository type, assuming kiali-operator"
    fi
}

# Extract permissions from Kiali Server role templates
extract_kiali_server_permissions() {
    local template_file="$1"
    local output_file="$2"

    log_info "Extracting permissions from ${template_file}"

    # Direct extraction to simplified format: apiGroup:resource:verb
    sed -e 's/{%.*%}//g' -e 's/{{.*}}//g' "${template_file}" | \
    python3 -c "
import yaml
import sys

try:
    doc = yaml.safe_load(sys.stdin)
    if doc and 'rules' in doc:
        for rule in doc['rules']:
            if 'apiGroups' in rule and 'resources' in rule and 'verbs' in rule:
                api_groups = rule['apiGroups'] if rule['apiGroups'] else ['']
                resources = rule['resources'] if rule['resources'] else []
                verbs = rule['verbs'] if rule['verbs'] else []

                for ag in api_groups:
                    for res in resources:
                        for verb in verbs:
                            # Include wildcard resources for important API groups like Istio
                            is_important_wildcard = (res == '*' and any(ag.endswith(suffix) for suffix in [
                                'istio.io', 'k8s.io', 'x-k8s.io'
                            ]))
                            if (res != '*' or is_important_wildcard) and not res.startswith('{{') and not res.startswith('{%'):
                                print(f'{ag}:{res}:{verb}')
except Exception:
    pass
" | sort | uniq > "${output_file}"
}

# Extract permissions from CSV files
extract_csv_permissions() {
    local csv_file="$1"
    local output_file="$2"

    log_info "Extracting permissions from ${csv_file}"

    # Direct extraction to simplified format: apiGroup:resource:verb
    python3 -c "
import yaml
import sys

try:
    with open('${csv_file}', 'r') as f:
        doc = yaml.safe_load(f)
        if doc and 'spec' in doc and 'install' in doc['spec'] and 'spec' in doc['spec']['install']:
            cluster_perms = doc['spec']['install']['spec'].get('clusterPermissions', [])
            if cluster_perms and len(cluster_perms) > 0:
                rules = cluster_perms[0].get('rules', [])
                for rule in rules:
                    if 'apiGroups' in rule and 'resources' in rule and 'verbs' in rule:
                        api_groups = rule['apiGroups'] if rule['apiGroups'] else ['']
                        resources = rule['resources'] if rule['resources'] else []
                        verbs = rule['verbs'] if rule['verbs'] else []

                        for ag in api_groups:
                            for res in resources:
                                for verb in verbs:
                                    # Include wildcard resources for important API groups like Istio
                                    is_important_wildcard = (res == '*' and any(ag.endswith(suffix) for suffix in [
                                        'istio.io', 'k8s.io', 'x-k8s.io'
                                    ]))
                                    if (res != '*' or is_important_wildcard) and not res.startswith('{{') and not res.startswith('{%'):
                                        print(f'{ag}:{res}:{verb}')
except Exception:
    pass
" | sort | uniq > "${output_file}"
}

# Extract permissions from Helm chart
extract_helm_permissions() {
    local helm_file="$1"
    local output_file="$2"

    log_info "Extracting permissions from ${helm_file}"

    # Remove Helm templating and extract rules
    sed -e 's/{{.*}}//g' -e 's/{%-.*-%}//g' -e '/^#/d' "${helm_file}" | \
    python3 -c "
import yaml
import sys

try:
    doc = yaml.safe_load(sys.stdin)
    if doc and 'rules' in doc:
        for rule in doc['rules']:
            if 'apiGroups' in rule and 'resources' in rule and 'verbs' in rule:
                api_groups = rule['apiGroups'] if rule['apiGroups'] else ['']
                resources = rule['resources'] if rule['resources'] else []
                verbs = rule['verbs'] if rule['verbs'] else []

                for ag in api_groups:
                    for res in resources:
                        for verb in verbs:
                            # Include wildcard resources for important API groups like Istio
                            is_important_wildcard = (res == '*' and any(ag.endswith(suffix) for suffix in [
                                'istio.io', 'k8s.io', 'x-k8s.io'
                            ]))
                            if (res != '*' or is_important_wildcard) and not res.startswith('{{') and not res.startswith('{%'):
                                print(f'{ag}:{res}:{verb}')
except Exception:
    pass
" | sort | uniq > "${output_file}"
}

# Normalize permissions for comparison
normalize_permissions() {
    local input_file="$1"
    local output_file="$2"

    # Since extraction functions already output in normalized format, just copy the file
    cp "${input_file}" "${output_file}"
}

# Compare two permission sets and store results
compare_permissions() {
    local file1="$1"
    local file2="$2"
    local name1="$3"
    local name2="$4"

    local missing_in_2="${TEMP_DIR}/missing_in_${name2}"

    # Find permissions in file1 but not in file2
    comm -23 "${file1}" "${file2}" > "${missing_in_2}"

    local missing_count=$(wc -l < "${missing_in_2}")

    # Store result for later reporting
    echo "${name2}:${missing_count}:${missing_in_2}" >> "${TEMP_DIR}/comparison_results"
}

# Report all comparison results
report_results() {
    if [[ ! -f "${TEMP_DIR}/comparison_results" ]]; then
        log_error "No comparison results found"
        return 1
    fi

    while IFS=':' read -r name2 missing_count missing_file; do
        if [[ ${missing_count} -gt 0 ]]; then
            log_error "Missing permissions in ${name2} (found in Kiali-Server):"
            # Group permissions by API group and resource, then collect verbs
            python3 -c "
import sys
from collections import defaultdict

# Group permissions by api:resource
grouped = defaultdict(set)
with open('${missing_file}', 'r') as f:
    for line in f:
        line = line.strip()
        if line:
            parts = line.split(':')
            if len(parts) == 3:
                api_group, resource, verb = parts
                key = f'{api_group}:{resource}'
                grouped[key].add(verb)

# Output grouped permissions
for api_resource, verbs in sorted(grouped.items()):
    verb_list = ','.join(sorted(verbs))
    print(f'  - {api_resource} [{verb_list}]')
"
            echo
        else
            log_success "Kiali-Server and ${name2} permissions match (all required permissions present)"
        fi
    done < "${TEMP_DIR}/comparison_results"
}

# Find the latest kiali-upstream version
find_latest_upstream_version() {
    find "${ROOT_DIR}/manifests/kiali-upstream" -maxdepth 1 -type d -name "[0-9]*" | \
    grep -E '/[0-9]+\.[0-9]+\.[0-9]+$' | \
    sort -V | \
    tail -1
}

main() {
    # Detect repository type first
    detect_repository_type

    log_info "Starting Kiali Server permissions verification..."
    echo

    # Check required tools
    for tool in yq python3; do
        if ! command -v "${tool}" &> /dev/null; then
            log_error "Required tool '${tool}' is not installed"
            exit 1
        fi
    done

    # Define file paths based on repository type
    local kiali_k8s_role=""
    local kiali_os_role=""
    local kiali_ossm_csv=""
    local kiali_upstream_csv=""
    local helm_chart=""

    if [[ "${REPO_TYPE}" == "helm-charts" ]]; then
        # Running from helm-charts repository - compare helm server vs helm operator
        kiali_k8s_role="${ROOT_DIR}/kiali-server/templates/role.yaml"
        kiali_os_role="${ROOT_DIR}/kiali-server/templates/role.yaml"  # Same file for both
        helm_chart="${ROOT_DIR}/kiali-operator/templates/clusterrole.yaml"
        # Skip CSV files when running from helm-charts
        kiali_ossm_csv=""
        kiali_upstream_csv=""
    else
        # Running from kiali-operator repository - original behavior
        kiali_k8s_role="${ROOT_DIR}/roles/default/kiali-deploy/templates/kubernetes/role.yaml"
        kiali_os_role="${ROOT_DIR}/roles/default/kiali-deploy/templates/openshift/role.yaml"
        kiali_ossm_csv="${ROOT_DIR}/manifests/kiali-ossm/manifests/kiali.clusterserviceversion.yaml"
        helm_chart="${ROOT_DIR}/../helm-charts/kiali-operator/templates/clusterrole.yaml"
    fi

    # Find latest upstream version (only for kiali-operator repo)
    if [[ "${REPO_TYPE}" == "kiali-operator" ]]; then
        local latest_upstream_dir
        latest_upstream_dir=$(find_latest_upstream_version)
        if [[ -z "${latest_upstream_dir}" ]]; then
            log_error "Could not find latest kiali-upstream version"
            exit 1
        fi
        kiali_upstream_csv="${latest_upstream_dir}/manifests/kiali.v*.clusterserviceversion.yaml"
        kiali_upstream_csv=$(echo ${kiali_upstream_csv}) # Expand glob

        log_info "Using latest upstream CSV: ${kiali_upstream_csv}"
        echo
    fi

    # Check if required files exist
    local required_files=("${kiali_k8s_role}")
    if [[ "${kiali_os_role}" != "${kiali_k8s_role}" ]]; then
        required_files+=("${kiali_os_role}")
    fi

    # Add CSV files only for kiali-operator repo
    if [[ "${REPO_TYPE}" == "kiali-operator" ]]; then
        if [[ -n "${kiali_ossm_csv}" ]]; then
            required_files+=("${kiali_ossm_csv}")
        fi
        if [[ -n "${kiali_upstream_csv}" ]]; then
            required_files+=("${kiali_upstream_csv}")
        fi
    fi

    for file in "${required_files[@]}"; do
        if [[ ! -f "${file}" ]]; then
            log_error "File not found: ${file}"
            exit 1
        fi
    done

    # Check if helm chart exists (optional)
    local check_helm_chart=true
    if [[ -n "${helm_chart}" ]] && [[ ! -f "${helm_chart}" ]]; then
        echo "DEBUG: Helm chart not found at ${helm_chart} - skipping helm chart permission check"
        check_helm_chart=false
    elif [[ -z "${helm_chart}" ]]; then
        echo "DEBUG: Helm chart path not defined for ${REPO_TYPE} repository - skipping helm chart permission check"
        check_helm_chart=false
    fi

    # Extract permissions from each source (already normalized)
    local kiali_k8s_perms="${TEMP_DIR}/kiali_k8s_perms.txt"
    local kiali_os_perms="${TEMP_DIR}/kiali_os_perms.txt"
    local ossm_csv_perms="${TEMP_DIR}/ossm_csv_perms.txt"
    local upstream_csv_perms="${TEMP_DIR}/upstream_csv_perms.txt"
    local helm_perms="${TEMP_DIR}/helm_perms.txt"

    extract_kiali_server_permissions "${kiali_k8s_role}" "${kiali_k8s_perms}"
    if [[ "${kiali_os_role}" != "${kiali_k8s_role}" ]]; then
        extract_kiali_server_permissions "${kiali_os_role}" "${kiali_os_perms}"
    else
        # Use same permissions for both when it's the same file
        cp "${kiali_k8s_perms}" "${kiali_os_perms}"
    fi

    # Extract CSV permissions only for kiali-operator repo
    if [[ "${REPO_TYPE}" == "kiali-operator" ]]; then
        if [[ -n "${kiali_ossm_csv}" ]]; then
            extract_csv_permissions "${kiali_ossm_csv}" "${ossm_csv_perms}"
        fi
        if [[ -n "${kiali_upstream_csv}" ]]; then
            extract_csv_permissions "${kiali_upstream_csv}" "${upstream_csv_perms}"
        fi
    fi

    if [[ "${check_helm_chart}" == "true" ]]; then
        extract_helm_permissions "${helm_chart}" "${helm_perms}"
    fi

    # Combine Kiali server permissions (union of k8s and openshift)
    local combined_kiali_perms="${TEMP_DIR}/combined_kiali_perms.txt"
    cat "${kiali_k8s_perms}" "${kiali_os_perms}" | sort | uniq > "${combined_kiali_perms}"

    echo
    log_info "Comparing permissions..."
    echo

    # Initialize results file
    > "${TEMP_DIR}/comparison_results"

    # Compare Kiali server permissions against operator permissions (collect results)
    if [[ "${REPO_TYPE}" == "kiali-operator" ]]; then
        if [[ -n "${kiali_ossm_csv}" ]]; then
            compare_permissions "${combined_kiali_perms}" "${ossm_csv_perms}" "Kiali-Server" "OSSM-CSV"
        fi
        if [[ -n "${kiali_upstream_csv}" ]]; then
            compare_permissions "${combined_kiali_perms}" "${upstream_csv_perms}" "Kiali-Server" "Upstream-CSV"
        fi
    fi

    if [[ "${check_helm_chart}" == "true" ]]; then
        compare_permissions "${combined_kiali_perms}" "${helm_perms}" "Kiali-Server" "Helm-Chart"
    fi

    # Report all results
    report_results

    # Summary
    echo "=============================================="
    if [[ ${ERRORS} -eq 0 ]]; then
        log_success "All permission checks passed!"
        exit 0
    else
        log_error "Some permissions are missing"
        echo
        echo "Action required: Add missing permissions to the operator roles."
        echo "The operator needs all Kiali Server permissions to be able to create the server roles."
        exit 1
    fi
}

main "$@"
