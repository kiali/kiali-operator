#!/bin/bash

################################################
# NOTE: AS OF NOVEMBER, 2024, THIS NO LONGER
# PERFORMS ANY WORK FOR THE COMMUNITY OPERATOR.
# ANYTHING ABOUT THE REDHAT COMMUNITY CATALOG
# OR THE community-operators-prod IS IGNORED.
# ONLY OperatorHub.io UPSTREAM CATALOG WORK
# IS PERFORMED NOW BY THIS SCRIPT.
#
# THE CODE IS STILL HERE IN THIS SCRIPT (SOME
# OF WHICH IS COMMENTED OUT) IN THE OFF CHANCE
# WE NEED TO RESURRECT THE COMMUNITY OPERATOR.
################################################
#
# This script prepares new branches in the two
# community operator git repos. You can create
# PRs based on the branches this script creates.
# This prepares OLM metadata for both upstream
# and community Kiali operator.
#
# You must have forked the following two repos:
# * https://github.com/k8s-operatorhub/community-operators
# * https://github.com/redhat-openshift-ecosystem/community-operators-prod
#
# This script uses legacy terminology.
# Where you see "upstream", that means the OperatorHub (community-operators) metadata.
# Where you see "community", that means the Red Hat (community-operators-prod) metadata.
################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"

DEFAULT_GIT_REPO_OPERATORHUB=${SCRIPT_DIR}/../../../community-operators/community-operators
DEFAULT_GIT_REPO_REDHAT=${SCRIPT_DIR}/../../../community-operators/community-operators-prod
GIT_REPO_OPERATORHUB=${DEFAULT_GIT_REPO_OPERATORHUB}
GIT_REPO_REDHAT=${DEFAULT_GIT_REPO_REDHAT}

while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -go|--gitrepo-operatorhub) GIT_REPO_OPERATORHUB="$2" ; shift;shift ;;
    -gr|--gitrepo-redhat)      GIT_REPO_REDHAT="$2"      ; shift;shift ;;
    -h|--help)
      cat <<HELPMSG
$0 [option...]

Valid options:
  -go|--gitrepo-operatorhub <directory>
      The directory where the local community-operators git repo is located.
      This is the location where you git cloned the repo https://github.com/k8s-operatorhub/community-operators
      Default: ${DEFAULT_GIT_REPO_OPERATORHUB}
      which resolves to:
      $(readlink -f ${DEFAULT_GIT_REPO_OPERATORHUB} || echo '<git repo does not exist at the default location>')
  -gr|--gitrepo-redhat <directory>
      THIS IS NO LONGER USED!
      The directory where the local community-operators-prod git repo is located.
      This is the location where you git cloned the repo https://github.com/redhat-openshift-ecosystem/community-operators-prod
      Default: ${DEFAULT_GIT_REPO_REDHAT}
      which resolves to:
      $(readlink -f ${DEFAULT_GIT_REPO_REDHAT} || echo '<git repo does not exist at the default location>')
HELPMSG
      exit 1
      ;;
    *)
      echo "Unknown argument [$key].  Aborting."
      exit 1
      ;;
  esac
done

# Validate some things before trying to do anything

if [ ! -d "${GIT_REPO_OPERATORHUB}" ]; then
  echo "You must specify a valid community-operators git repo: ${GIT_REPO_OPERATORHUB}"
  exit 1
fi

### DO NOT PERFORM COMMUNITY CATALOG WORK
### if [ ! -d "${GIT_REPO_REDHAT}" ]; then
###  echo "You must specify a valid community-operators-prod git repo: ${GIT_REPO_REDHAT}"
###  exit 1
### fi
###

COMMUNITY_MANIFEST_DIR="${SCRIPT_DIR}/kiali-community"
UPSTREAM_MANIFEST_DIR="${SCRIPT_DIR}/kiali-upstream"

### DO NOT PERFORM COMMUNITY CATALOG WORK
### if [ ! -d "${COMMUNITY_MANIFEST_DIR}" ]; then
###  echo "Did not find the community manifest directory: ${COMMUNITY_MANIFEST_DIR}"
###  exit 1
### fi
###

if [ ! -d "${UPSTREAM_MANIFEST_DIR}" ]; then
  echo "Did not find the upstream manifest directory: ${UPSTREAM_MANIFEST_DIR}"
  exit 1
fi

# Determine branch names to use for the new data.

DATETIME_NOW="$(date --utc +'%F-%H-%M-%S')"
GIT_REPO_COMMUNITY_BRANCH_NAME="kiali-community-${DATETIME_NOW}"
GIT_REPO_UPSTREAM_BRANCH_NAME="kiali-upstream-${DATETIME_NOW}"

### DO NOT PERFORM COMMUNITY CATALOG WORK
### cd ${GIT_REPO_REDHAT}
### git fetch origin --verbose
### git checkout -b ${GIT_REPO_COMMUNITY_BRANCH_NAME} origin/main
### cp -R ${COMMUNITY_MANIFEST_DIR}/* ${GIT_REPO_REDHAT}/operators/kiali
### git add -A
### git commit --signoff -m '[kiali] update kiali'
###

cd ${GIT_REPO_OPERATORHUB}
git fetch origin --verbose
git checkout -b ${GIT_REPO_UPSTREAM_BRANCH_NAME} origin/main
cp -R ${UPSTREAM_MANIFEST_DIR}/* ${GIT_REPO_OPERATORHUB}/operators/kiali
git add -A
git commit --signoff -m '[kiali] update kiali'

# Completed!
echo "New Kiali metadata has been added. Create a PR from here:"
echo "*** cd ${GIT_REPO_OPERATORHUB} && git push <your git remote name> ${GIT_REPO_UPSTREAM_BRANCH_NAME}"

### DO NOT PERFORM COMMUNITY CATALOG WORK
### echo "*** cd ${GIT_REPO_REDHAT} && git push <your git remote name> ${GIT_REPO_COMMUNITY_BRANCH_NAME}"
