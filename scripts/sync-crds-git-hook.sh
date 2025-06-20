#!/bin/bash

# Git hook script to automatically sync CRD files when the golden copy changes
# This can be used as a pre-commit hook to ensure CRDs are always in sync

set -e

GOLDEN_CRD="kiali-operator/crd-docs/crd/kiali.io_kialis.yaml"

# Check if we're in the root of the kiali repository
if [ ! -f "$GOLDEN_CRD" ]; then
    echo "Error: This script should be run from the root of the kiali repository"
    exit 1
fi

# Check if the golden CRD file has been modified in the staged changes
if git diff --cached --name-only | grep -q "^${GOLDEN_CRD}$"; then
    echo "Golden CRD file has been modified, synchronizing derived copies..."
    
    # Change to the kiali-operator directory
    cd kiali-operator
    
    # Run the sync command
    if make sync-crds; then
        echo "CRD synchronization completed successfully"
        
        # Add the synchronized files to the staging area  
        git add "../helm-charts/kiali-operator/crds/crds.yaml"
        git add "manifests/kiali-ossm/manifests/kiali.crd.yaml"
        git add "manifests/kiali-upstream/2.12.0/manifests/kiali.crd.yaml"
        
        echo "Synchronized CRD files have been added to the commit"
    else
        echo "Error: CRD synchronization failed"
        exit 1
    fi
    
    cd ..
fi

echo "CRD sync check completed" 