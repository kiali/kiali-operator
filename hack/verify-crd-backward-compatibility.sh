#!/bin/bash

##############################################################################
# verify-crd-backward-compatibility.sh
#
# This script verifies that CRD schema changes maintain backward compatibility.
# Since Kiali uses v1alpha1 version and commits to never making breaking changes,
# this script ensures all CRD modifications are additive and non-breaking.
#
# WHY THIS MATTERS:
# Breaking changes to CRD schemas would force users to manually update their
# existing Kiali/OSSMConsole resources, potentially causing downtime. By
# maintaining backward compatibility, users can upgrade seamlessly without
# needing to modify their existing CR instances.
#
# WHAT IT CHECKS:
# - No required fields added (new fields must be optional)
# - No existing fields removed (deprecation is OK, removal is not)
# - No field type changes (e.g., string → integer)
# - No enum value removal (can add, cannot remove)
# - No constraint tightening (min/max values, patterns, etc.)
# - No default value changes (defaults affect existing resources)
# - Version remains v1alpha1 (enforces version stability)
#
# USAGE:
# - Run directly: ./hack/verify-crd-backward-compatibility.sh
# - Compare against specific ref: ./hack/verify-crd-backward-compatibility.sh origin/master
# - Run via make: make verify-crd-compatibility
# - Runs automatically in CI on PRs that modify CRDs
#
# REQUIREMENTS:
# - yq (YAML processor) must be installed
# - jq (JSON processor) must be installed
# - git must be available for comparing versions
# - Script should be run from the kiali-operator root directory
##############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Reference commit/branch to compare against (default: origin/master)
REFERENCE_REF="${1:-origin/master}"

# Counters
ERRORS=0
WARNINGS=0

# Arrays to track issues
BREAKING_CHANGES=()
POTENTIAL_ISSUES=()

# CRD files to check (golden copies only)
CRD_FILES=(
    "crd-docs/crd/kiali.io_kialis.yaml"
    "crd-docs/crd/kiali.io_ossmconsoles.yaml"
)

##############################################################################
# Helper Functions
##############################################################################

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_error() {
    echo -e "${RED}✗ ERROR: $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ WARNING: $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

add_breaking_change() {
    BREAKING_CHANGES+=("$1")
    print_error "$1"
    ERRORS=$((ERRORS + 1))
}

add_potential_issue() {
    POTENTIAL_ISSUES+=("$1")
    print_warning "$1"
    WARNINGS=$((WARNINGS + 1))
}

##############################################################################
# Check if required tools are available
##############################################################################

check_requirements() {
    if ! command -v yq &> /dev/null; then
        echo -e "${RED}ERROR: yq is required but not installed.${NC}"
        echo "Please install yq: https://github.com/mikefarah/yq"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        echo -e "${RED}ERROR: jq is required but not installed.${NC}"
        echo "Please install jq: https://stedolan.github.io/jq/"
        exit 1
    fi

    if ! command -v git &> /dev/null; then
        echo -e "${RED}ERROR: git is required but not installed.${NC}"
        exit 1
    fi

    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${RED}ERROR: Not in a git repository.${NC}"
        exit 1
    fi
}

##############################################################################
# Get the old version of a file from git
##############################################################################

get_old_file_content() {
    local file="$1"
    local ref="$2"

    # Check if the file exists in the reference
    if git cat-file -e "${ref}:${file}" 2>/dev/null; then
        git show "${ref}:${file}"
        return 0
    else
        # File doesn't exist in reference (new file)
        return 1
    fi
}

##############################################################################
# Simplify path for display (remove schema prefix)
##############################################################################

simplify_path() {
    local path="$1"
    # Remove the common prefix and make it more readable
    echo "$path" | sed 's/spec\.versions\.0\.schema\.openAPIV3Schema\.properties\.spec\.properties\.//' | sed 's/\.properties\././g'
}

##############################################################################
# Extract all properties with their metadata from a CRD
##############################################################################

extract_all_properties() {
    local yaml_content="$1"

    # Convert YAML to JSON once, then use jq to extract all property definitions
    # We need to find leaf schema objects where .type is a string (indicating a schema type like "string", "integer")
    # Exclude structural containers like "properties", "items", etc which have .type as an object
    echo "$yaml_content" | yq eval -o=json '.' 2>/dev/null | jq -c '
        [paths(type == "object") as $p |
         {path: $p, value: getpath($p)} |
         select(.value | type == "object" and
                ((.type | type == "string") or (.enum | type == "array"))) |
         {
            path: (.path | join(".")),
            type: .value.type,
            enum: .value.enum,
            default: .value.default,
            minimum: .value.minimum,
            maximum: .value.maximum,
            minLength: .value.minLength,
            maxLength: .value.maxLength,
            pattern: .value.pattern
         }
        ] | .[]
    ' 2>/dev/null
}

##############################################################################
# Extract required fields from a CRD
##############################################################################

extract_required_fields() {
    local yaml_content="$1"

    # Convert YAML to JSON once, then use jq to extract all required field arrays
    echo "$yaml_content" | yq eval -o=json '.' 2>/dev/null | jq -c '
        [paths(type == "object") as $p |
         {path: $p, value: getpath($p)} |
         select(.value | type == "object" and has("required")) |
         {
            parent_path: (.path | join(".")),
            required: .value.required
         }
        ] | .[]
    ' 2>/dev/null
}

##############################################################################
# Check for breaking changes between two CRD versions
##############################################################################

check_backward_compatibility() {
    local crd_file="$1"
    local old_content="$2"
    local new_content="$3"

    print_header "Checking: ${crd_file}"

    local checks_performed=0

    # Check 1: Verify version is still v1alpha1
    local old_version=$(echo "$old_content" | yq eval '.spec.versions[0].name' - 2>/dev/null)
    local new_version=$(echo "$new_content" | yq eval '.spec.versions[0].name' - 2>/dev/null)

    if [ "$old_version" = "v1alpha1" ] && [ "$new_version" != "v1alpha1" ]; then
        add_breaking_change "Version changed from v1alpha1 to ${new_version}. Version must remain v1alpha1."
    elif [ "$new_version" = "v1alpha1" ]; then
        print_success "Version correctly remains v1alpha1"
    fi
    checks_performed=$((checks_performed + 1))

    # Check 2: Compare enum values
    echo ""
    echo "Checking enum values..."
    echo "  Extracting enum values from old version..."
    local old_enums=$(extract_all_properties "$old_content" | grep -v '"enum":null' | grep '"enum":')
    echo "  Extracting enum values from new version..."
    local new_enums=$(extract_all_properties "$new_content" | grep -v '"enum":null' | grep '"enum":')
    echo "  Comparing enum values..."

    while IFS= read -r old_enum_line; do
        if [ -z "$old_enum_line" ]; then
            continue
        fi

        local path=$(echo "$old_enum_line" | jq -r '.path')
        local old_values=$(echo "$old_enum_line" | jq -r '.enum | @json')

        # Find the same path in new enums
        local new_enum_line=$(echo "$new_enums" | jq -c --arg path "$path" 'select(.path == $path)')

        if [ -z "$new_enum_line" ]; then
            # Enum was removed entirely
            add_breaking_change "Enum removed at: $(simplify_path "$path")"
            checks_performed=$((checks_performed + 1))
            continue
        fi

        local new_values=$(echo "$new_enum_line" | jq -r '.enum | @json')

        # Check if any old enum values were removed
        local old_array=$(echo "$old_values" | jq -r '.[]')
        while IFS= read -r old_val; do
            if [ -z "$old_val" ]; then
                continue
            fi

            local found=$(echo "$new_values" | jq --arg val "$old_val" 'contains([$val])')
            if [ "$found" = "false" ]; then
                add_breaking_change "Enum value '${old_val}' removed from: $(simplify_path "$path")"
            fi
            checks_performed=$((checks_performed + 1))
        done <<< "$old_array"

    done <<< "$old_enums"

    # Check 3: Compare required fields
    echo ""
    echo "Checking required fields..."
    echo "  Extracting required fields from old version..."
    local old_required=$(extract_required_fields "$old_content")
    echo "  Extracting required fields from new version..."
    local new_required=$(extract_required_fields "$new_content")
    echo "  Comparing required fields..."

    while IFS= read -r new_req_line; do
        if [ -z "$new_req_line" ]; then
            continue
        fi

        local parent_path=$(echo "$new_req_line" | jq -r '.parent_path')
        local new_fields=$(echo "$new_req_line" | jq -r '.required | @json')

        # Find the same parent path in old required fields
        local old_req_line=$(echo "$old_required" | jq -c --arg path "$parent_path" 'select(.parent_path == $path)')

        if [ -z "$old_req_line" ]; then
            # This is a new object with required fields - check if any fields are required
            local required_count=$(echo "$new_fields" | jq 'length' 2>/dev/null || echo "0")
            if [ -n "$required_count" ] && [ "$required_count" -gt 0 ]; then
                local fields=$(echo "$new_fields" | jq -r '.[]' | tr '\n' ', ' | sed 's/,$//')
                add_breaking_change "New required field(s) added at $(simplify_path "$parent_path"): ${fields}"
            fi
            checks_performed=$((checks_performed + 1))
            continue
        fi

        local old_fields=$(echo "$old_req_line" | jq -r '.required | @json')

        # Check if any new required fields were added
        local new_array=$(echo "$new_fields" | jq -r '.[]')
        while IFS= read -r new_field; do
            if [ -z "$new_field" ]; then
                continue
            fi

            local was_required=$(echo "$old_fields" | jq --arg field "$new_field" 'contains([$field])')
            if [ "$was_required" = "false" ]; then
                add_breaking_change "Field '${new_field}' became required at: $(simplify_path "$parent_path")"
            fi
            checks_performed=$((checks_performed + 1))
        done <<< "$new_array"

    done <<< "$new_required"

    # Check 4: Compare property types and constraints
    echo ""
    echo "Checking field types and constraints..."
    echo "  Extracting property types from old version..."
    local old_props=$(extract_all_properties "$old_content" | grep -v '"type":null' | grep '"type":')
    echo "  Extracting property types from new version..."
    local new_props=$(extract_all_properties "$new_content" | grep -v '"type":null' | grep '"type":')
    echo "  Comparing property types and constraints..."

    while IFS= read -r old_prop_line; do
        if [ -z "$old_prop_line" ]; then
            continue
        fi

        local path=$(echo "$old_prop_line" | jq -r '.path')
        local old_type=$(echo "$old_prop_line" | jq -r '.type // ""')
        local old_default=$(echo "$old_prop_line" | jq -r '.default // ""')
        local old_min=$(echo "$old_prop_line" | jq -r '.minimum // ""')
        local old_max=$(echo "$old_prop_line" | jq -r '.maximum // ""')
        local old_min_len=$(echo "$old_prop_line" | jq -r '.minLength // ""')
        local old_max_len=$(echo "$old_prop_line" | jq -r '.maxLength // ""')
        local old_pattern=$(echo "$old_prop_line" | jq -r '.pattern // ""')

        # Find the same path in new properties
        local new_prop_line=$(echo "$new_props" | jq -c --arg path "$path" 'select(.path == $path)')

        if [ -z "$new_prop_line" ]; then
            # Property was removed
            add_breaking_change "Field removed: $(simplify_path "$path")"
            checks_performed=$((checks_performed + 1))
            continue
        fi

        local new_type=$(echo "$new_prop_line" | jq -r '.type // ""')
        local new_default=$(echo "$new_prop_line" | jq -r '.default // ""')
        local new_min=$(echo "$new_prop_line" | jq -r '.minimum // ""')
        local new_max=$(echo "$new_prop_line" | jq -r '.maximum // ""')
        local new_min_len=$(echo "$new_prop_line" | jq -r '.minLength // ""')
        local new_max_len=$(echo "$new_prop_line" | jq -r '.maxLength // ""')
        local new_pattern=$(echo "$new_prop_line" | jq -r '.pattern // ""')

        # Type change
        if [ -n "$old_type" ] && [ "$old_type" != "null" ] && [ "$old_type" != "$new_type" ]; then
            add_breaking_change "Type changed for $(simplify_path "$path"): ${old_type} → ${new_type}"
        fi

        # Default value change
        if [ -n "$old_default" ] && [ "$old_default" != "null" ] && [ "$old_default" != "$new_default" ]; then
            add_potential_issue "Default value changed for $(simplify_path "$path"): ${old_default} → ${new_default}"
        fi

        # Minimum value increased (tightening)
        if [ -n "$old_min" ] && [ "$old_min" != "null" ] && [ -n "$new_min" ] && [ "$new_min" != "null" ]; then
            if [ "$old_min" != "$new_min" ]; then
                # Use bc for comparison if available, otherwise use awk
                if command -v bc &> /dev/null; then
                    local comparison=$(echo "$new_min > $old_min" | bc -l 2>/dev/null || echo "0")
                    if [ "$comparison" = "1" ]; then
                        add_breaking_change "Minimum value increased for $(simplify_path "$path"): ${old_min} → ${new_min}"
                    fi
                else
                    if awk "BEGIN {exit !($new_min > $old_min)}" 2>/dev/null; then
                        add_breaking_change "Minimum value increased for $(simplify_path "$path"): ${old_min} → ${new_min}"
                    fi
                fi
            fi
        fi

        # Maximum value decreased (tightening)
        if [ -n "$old_max" ] && [ "$old_max" != "null" ] && [ -n "$new_max" ] && [ "$new_max" != "null" ]; then
            if [ "$old_max" != "$new_max" ]; then
                if command -v bc &> /dev/null; then
                    local comparison=$(echo "$new_max < $old_max" | bc -l 2>/dev/null || echo "0")
                    if [ "$comparison" = "1" ]; then
                        add_breaking_change "Maximum value decreased for $(simplify_path "$path"): ${old_max} → ${new_max}"
                    fi
                else
                    if awk "BEGIN {exit !($new_max < $old_max)}" 2>/dev/null; then
                        add_breaking_change "Maximum value decreased for $(simplify_path "$path"): ${old_max} → ${new_max}"
                    fi
                fi
            fi
        fi

        # String length constraints
        if [ -n "$old_min_len" ] && [ "$old_min_len" != "null" ] && [ -n "$new_min_len" ] && [ "$new_min_len" != "null" ]; then
            if [ "$new_min_len" -gt "$old_min_len" ] 2>/dev/null; then
                add_breaking_change "Minimum length increased for $(simplify_path "$path"): ${old_min_len} → ${new_min_len}"
            fi
        fi

        if [ -n "$old_max_len" ] && [ "$old_max_len" != "null" ] && [ -n "$new_max_len" ] && [ "$new_max_len" != "null" ]; then
            if [ "$new_max_len" -lt "$old_max_len" ] 2>/dev/null; then
                add_breaking_change "Maximum length decreased for $(simplify_path "$path"): ${old_max_len} → ${new_max_len}"
            fi
        fi

        # Pattern change
        if [ -n "$old_pattern" ] && [ "$old_pattern" != "null" ] && [ "$old_pattern" != "$new_pattern" ]; then
            add_potential_issue "Pattern changed for $(simplify_path "$path")"
        fi

        checks_performed=$((checks_performed + 1))
    done <<< "$old_props"

    echo ""
    echo "Completed $checks_performed checks for this CRD"
    echo ""
}

##############################################################################
# Main execution
##############################################################################

main() {
    cd "$ROOT_DIR"

    print_header "CRD Backward Compatibility Verification"
    echo "Comparing against reference: ${REFERENCE_REF}"
    echo ""

    # Check requirements
    check_requirements

    # Verify reference exists
    if ! git rev-parse --verify "${REFERENCE_REF}" >/dev/null 2>&1; then
        echo -e "${RED}ERROR: Reference '${REFERENCE_REF}' not found in git repository${NC}"
        echo "Please fetch the latest changes: git fetch origin"
        exit 1
    fi

    # Process each CRD file
    for crd_file in "${CRD_FILES[@]}"; do
        # Get old and new content
        old_content=$(get_old_file_content "$crd_file" "$REFERENCE_REF")

        if [ $? -ne 0 ]; then
            # File doesn't exist in reference - this is a new CRD file
            print_header "Checking: ${crd_file}"
            print_success "New CRD file - no backward compatibility issues"
            echo ""
            continue
        fi

        if [ ! -f "$crd_file" ]; then
            # File was deleted
            add_breaking_change "CRD file deleted: ${crd_file}"
            continue
        fi

        new_content=$(cat "$crd_file")

        # Check compatibility
        check_backward_compatibility "$crd_file" "$old_content" "$new_content"
    done

    # Print summary
    print_header "Summary"
    echo "Breaking changes: ${ERRORS}"
    echo "Potential issues: ${WARNINGS}"
    echo ""

    if [ ${ERRORS} -gt 0 ]; then
        echo -e "${RED}========================================"
        echo -e "FAILED: ${ERRORS} breaking change(s) detected"
        echo -e "========================================${NC}"
        echo ""
        echo "Breaking changes detected:"
        for change in "${BREAKING_CHANGES[@]}"; do
            echo -e "  ${RED}✗${NC} $change"
        done
        echo ""
        echo "These changes would break existing Kiali/OSSMConsole CRs."
        echo "CRD schemas must maintain backward compatibility (v1alpha1 forever)."
        echo ""
        echo "Solutions:"
        echo "  - Make new fields optional (not required)"
        echo "  - Deprecate old fields instead of removing them"
        echo "  - Keep existing enum values when adding new ones"
        echo "  - Don't tighten constraints (min/max values, patterns, etc.)"
        echo "  - Don't change default values (can affect existing resources)"
        exit 1
    fi

    if [ ${WARNINGS} -gt 0 ]; then
        echo -e "${YELLOW}========================================"
        echo -e "WARNING: ${WARNINGS} potential issue(s) detected"
        echo -e "========================================${NC}"
        echo ""
        echo "Potential issues:"
        for issue in "${POTENTIAL_ISSUES[@]}"; do
            echo -e "  ${YELLOW}⚠${NC} $issue"
        done
        echo ""
        echo "These changes may affect existing resources. Review carefully."
        echo ""
    fi

    echo -e "${GREEN}========================================"
    echo -e "SUCCESS: CRD schemas are backward compatible"
    echo -e "========================================${NC}"
    exit 0
}

# Run main function
main
