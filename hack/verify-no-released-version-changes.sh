#!/bin/bash

##############################################################################
# verify-no-released-version-changes.sh
#
# This script verifies that a PR does not modify the OLM bundle manifests
# of a kiali-upstream version that has already been released (i.e. a version
# for which a "vX.Y.Z" git tag already exists).
#
# WHY THIS MATTERS:
# Each directory under manifests/kiali-upstream/<version>/ is supposed to be
# an immutable, point-in-time snapshot of what was actually released as
# vX.Y.Z. If a later PR sneaks a change into an already-tagged version's
# directory (usually because the "Prepare for next version" PR hadn't been
# merged yet, or by simple copy/paste mistake), that change silently ships
# as if it had been part of the original release - even though nobody
# tagged, tested, or released it that way. This has happened more than
# once (see PRs #1074 and #1076/#1080), and the leaked changes even made
# their way into the community-operators bundle sync before being noticed.
#
# WHAT IT CHECKS:
# - For every manifests/kiali-upstream/<version>/ directory changed by this
#   PR, if a git tag "v<version>" already exists, the change is rejected -
#   UNLESS this same PR also introduces at least one brand-new version
#   directory. That combination (bump the old version's release timestamp
#   + create the next version directory) is exactly what the automated
#   "Prepare for next version" PR does, and is the only legitimate reason
#   to touch an already-released version's files.
#
# ESCAPE HATCH:
# In the rare case a change genuinely must be backported into an
# already-released version's manifests, add a trailer to a commit message
# in the PR naming the exact version, e.g.:
#
#   Allow-Released-Version-Edit: 2.29.0
#
# The version must match exactly (this is intentionally not a blanket
# bypass) and will show up permanently in git history, so it is auditable
# after the fact.
#
# USAGE:
# - Run directly: ./hack/verify-no-released-version-changes.sh
# - Compare against specific ref: ./hack/verify-no-released-version-changes.sh origin/master
# - Run via make: make verify-no-released-version-changes
# - Runs automatically in CI on every PR
#
# REQUIREMENTS:
# - git must be available
# - Script should be run from the kiali-operator root directory
##############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

REFERENCE_REF="${1:-origin/master}"
UPSTREAM_DIR="manifests/kiali-upstream"

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

main() {
    cd "$ROOT_DIR"

    print_header "Verify No Changes To Already-Released Versions"
    echo "Comparing against reference: ${REFERENCE_REF}"
    echo ""

    if ! command -v git &> /dev/null; then
        echo -e "${RED}ERROR: git is required but not installed.${NC}"
        exit 1
    fi

    if ! git rev-parse --verify "${REFERENCE_REF}" >/dev/null 2>&1; then
        echo "Skipping check - reference '${REFERENCE_REF}' not available"
        exit 0
    fi

    local merge_base
    merge_base="$(git merge-base "${REFERENCE_REF}" HEAD 2>/dev/null || echo "${REFERENCE_REF}")"

    # Versions that exist at the merge-base vs. versions that exist now - any
    # version present now but not at the merge-base is brand new in this PR.
    local base_versions
    local head_versions
    local new_versions
    base_versions="$(git ls-tree -d --name-only "${merge_base}:${UPSTREAM_DIR}" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true)"
    head_versions="$(ls -1 "${UPSTREAM_DIR}" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true)"
    new_versions="$(comm -13 <(echo "$base_versions" | sort -V) <(echo "$head_versions" | sort -V))"

    if [ -n "$new_versions" ]; then
        print_header "This PR introduces new version director(y/ies)"
        echo "$new_versions" | sed 's/^/  + /'
        echo ""
        echo -e "${GREEN}✓ This looks like a \"Prepare for next version\" release PR - skipping the check.${NC}"
        exit 0
    fi

    local changed_files
    changed_files="$(git diff --name-only "${merge_base}" HEAD -- "${UPSTREAM_DIR}/" 2>/dev/null || true)"

    if [ -z "$changed_files" ]; then
        echo -e "${GREEN}✓ No changes under ${UPSTREAM_DIR}/ - nothing to check.${NC}"
        exit 0
    fi

    local commit_messages
    commit_messages="$(git log --format='%B' "${merge_base}..HEAD" 2>/dev/null || true)"

    local errors=0
    local flagged_versions=""

    while IFS= read -r file; do
        [ -z "$file" ] && continue

        local version
        version="$(echo "$file" | sed -nE "s#^${UPSTREAM_DIR}/([0-9]+\.[0-9]+\.[0-9]+)/.*#\1#p")"
        [ -z "$version" ] && continue

        # Already reported this version - don't spam the same error per file.
        if echo "$flagged_versions" | grep -qx "$version"; then
            continue
        fi

        if ! git rev-parse --verify -q "refs/tags/v${version}" >/dev/null; then
            # Not tagged yet - this version is still under development, which is fine.
            continue
        fi

        if echo "$commit_messages" | grep -qiE "^Allow-Released-Version-Edit:[[:space:]]*${version}\$"; then
            echo -e "${YELLOW}⚠ WARNING: ${file} modifies already-released version ${version}, but an${NC}"
            echo -e "${YELLOW}  'Allow-Released-Version-Edit: ${version}' trailer was found, so this is allowed.${NC}"
            echo -e "${YELLOW}  Make sure this is really intentional!${NC}"
            flagged_versions="${flagged_versions}${version}\n"
            continue
        fi

        echo -e "${RED}✗ ERROR: ${file}${NC}"
        echo -e "${RED}  modifies manifests/kiali-upstream/${version}, but v${version} was already released${NC}"
        echo -e "${RED}  (git tag v${version} exists). Released version manifests must not change.${NC}"
        flagged_versions="${flagged_versions}${version}\n"
        errors=$((errors + 1))
    done <<< "$changed_files"

    echo ""

    if [ ${errors} -gt 0 ]; then
        echo -e "${RED}========================================"
        echo -e "FAILED: change(s) detected in already-released version manifests"
        echo -e "========================================${NC}"
        echo ""
        echo "This usually means your branch was created before the current"
        echo "\"in development\" version directory existed, or you copy/pasted"
        echo "a change into the wrong version directory."
        echo ""
        echo "To fix:"
        echo "  1. Revert the change(s) in the already-released version director(y/ies) listed above."
        echo "  2. Re-apply the same change to the current in-development version instead."
        echo "  3. If the change is CRD-derived, run 'make sync-crds' to regenerate it there."
        echo ""
        echo "If you genuinely need to backport a change into an already-released"
        echo "version, add a commit message trailer naming the exact version, e.g.:"
        echo ""
        echo "  Allow-Released-Version-Edit: 2.29.0"
        echo ""
        exit 1
    fi

    echo -e "${GREEN}========================================"
    echo -e "SUCCESS: no changes to already-released version manifests"
    echo -e "========================================${NC}"
    exit 0
}

main
