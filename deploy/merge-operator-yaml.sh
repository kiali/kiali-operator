#!/bin/bash

##############################################################################
# merge-operator-yaml.sh
#
# Use this script to combine the separate YAML files into a single YAML file.
# This is helpful if you want to provide a single YAML file that can be used
# to create all resources required by the Kiali Operator.
##############################################################################

set -eu

# Where this script is found
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"

# Where the main build output directory is
BUILD_OUTPUT_DIR="${SCRIPT_DIR}/../_output"

# Process command line
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -con|--create-operator-namespace)
      CREATE_OPERATOR_NAMESPACE="$2"
      shift;shift
      ;;
    -crc|--cluster-role-creator)
      CLUSTER_ROLE_CREATOR="$2"
      shift;shift
      ;;
    -f|--file)
      YAML_FILE="$2"
      shift;shift
      ;;
    -hc|--helm-chart)
      HELM_CHART="$2"
      shift;shift
      ;;
    -oin|--operator-image-name)
      OPERATOR_IMAGE_NAME="$2"
      shift;shift
      ;;
    -oipp|--operator-image-pull-policy)
      OPERATOR_IMAGE_PULL_POLICY="$2"
      shift;shift
      ;;
    -oiv|--operator-image-version)
      OPERATOR_IMAGE_VERSION="$2"
      shift;shift
      ;;
    -on|--operator-namespace)
      OPERATOR_NAMESPACE="$2"
      shift;shift
      ;;
    -ovl|--operator-version-label)
      OPERATOR_VERSION_LABEL="$2"
      shift;shift
      ;;
    -own|--operator-watch-namespace)
      OPERATOR_WATCH_NAMESPACE="$2"
      shift;shift
      ;;
    -h|--help)
      cat <<HELPMSG

$0 [option...]

  -con|--create-operator-namespace
      When true, the generated YAML will create the operator namespace.
      When false, it will be assumed the namespace will already exist and that the operator
      will simply be deployed inside it.
      Default: false
  -crc|--cluster-role-creator
      When true, the operator will be given permission to create cluster roles and
      cluster role bindings so it can, in turn, assign Kiali a cluster role and
      cluster role binding to access all namespaces. This is to support the Kiali CR
      setting deployment.accessible_namespaces=['**'] (see the Kiali documentation for
      more details on this setting).
      Default: "false"
  -f|--file
      The file where the output is written to. This will be the file that has the combined YAML.
      Default: ${SCRIPT_DIR}/kiali-operator-all-in-one.yaml
  -hc|--helm-chart
      The Helm chart identifier.
  -oin|--operator-image-name
      Image of the Kiali operator to download and install.
      Default: "quay.io/kiali/kiali-operator"
  -oipp|--operator-image-pull-policy
      The Kubernetes pull policy for the Kiali operator deployment.
      Default: "IfNotPresent"
  -oiv|--operator-image-version
      The version of the Kiali operator to install.
      Can be a version string or "latest".
      Default: "latest"
  -on|--operator-namespace
      The namespace into which the Kiali operator is to be installed.
      Default: "kiali-operator"
  -ovl|--operator-version-label
      A Kubernetes label named "version" will be set on the Kiali operator resources.
      The value of this label is determined by this setting.
      Default: The value given for the operator image version
  -own|--operator-watch-namespace
      The namespace in which the operator looks for the Kiali CR. If '""' then watch all namespaces.
      Default: ""

HELPMSG
      exit 1
      ;;
    *)
      echo "Unknown argument [$key]. Aborting."
      exit 1
      ;;
  esac
done

export CLUSTER_ROLE_CREATOR="${CLUSTER_ROLE_CREATOR:-false}"
export CREATE_OPERATOR_NAMESPACE="${CREATE_OPERATOR_NAMESPACE:-false}"
export OPERATOR_IMAGE_NAME="${OPERATOR_IMAGE_NAME:-quay.io/kiali/kiali-operator}"
export OPERATOR_IMAGE_VERSION="${OPERATOR_IMAGE_VERSION:-latest}"
export OPERATOR_IMAGE_PULL_POLICY="${OPERATOR_IMAGE_PULL_POLICY:-IfNotPresent}"
export OPERATOR_NAMESPACE="${OPERATOR_NAMESPACE:-kiali-operator}"
export OPERATOR_WATCH_NAMESPACE="${OPERATOR_WATCH_NAMESPACE:-\"\"}"

# If version label is not specified, set it to image version; but if
# image version is "latest" the version label will be set to "master".
if [ -z "${OPERATOR_VERSION_LABEL:-}" ]; then
  if [ "${OPERATOR_IMAGE_VERSION}" == "latest" ]; then
    OPERATOR_VERSION_LABEL="master"
  else
    OPERATOR_VERSION_LABEL="${OPERATOR_IMAGE_VERSION}"
  fi
fi
export OPERATOR_VERSION_LABEL

# make sure we have Helm
if which helm > /dev/null 2>&1; then
  HELM="$(which helm)"
else
  echo "You do not have helm in your PATH. Will attempt to download it now..."
  make -C "${BUILD_OUTPUT_DIR}/.." .download-helm-if-needed
  if [ -x "${BUILD_OUTPUT_DIR}/helm-install/helm" ]; then
    HELM="${BUILD_OUTPUT_DIR}/helm-install/helm"
  else
    echo "You do not have helm in PATH and it could not be downloaded. Install helm manually and try again."
    exit 1
  fi
fi
echo "Using helm found here: ${HELM}"

# make sure we have the Helm Chart
if [ -z "${HELM_CHART:-}" ]; then
  if ! ls ${BUILD_OUTPUT_DIR}/charts/kiali-operator*.tgz > /dev/null 2>&1; then
    echo "There is no Helm Chart - will build it now"
    make -C "${BUILD_OUTPUT_DIR}/.." build-helm-chart
  fi
  HELM_CHART="$(ls -1 ${BUILD_OUTPUT_DIR}/charts/kiali-operator*.tgz)"
fi
echo "Using the Helm Chart found here: ${HELM_CHART}"

YAML_FILE="${YAML_FILE:-${SCRIPT_DIR}/kiali-operator-all-in-one.yaml}"

echo CLUSTER_ROLE_CREATOR="${CLUSTER_ROLE_CREATOR}"
echo CREATE_OPERATOR_NAMESPACE="${CREATE_OPERATOR_NAMESPACE}"
echo OPERATOR_IMAGE_NAME="${OPERATOR_IMAGE_NAME}"
echo OPERATOR_IMAGE_VERSION="${OPERATOR_IMAGE_VERSION}"
echo OPERATOR_IMAGE_PULL_POLICY="${OPERATOR_IMAGE_PULL_POLICY}"
echo OPERATOR_NAMESPACE="${OPERATOR_NAMESPACE}"
echo OPERATOR_VERSION_LABEL="${OPERATOR_VERSION_LABEL}"
echo OPERATOR_WATCH_NAMESPACE="${OPERATOR_WATCH_NAMESPACE}"
echo YAML_FILE="${YAML_FILE}"

# remove any old output file that still exists
rm -f ${YAML_FILE}

echo "---" > ${YAML_FILE}
echo "# Kiali Operator '${OPERATOR_IMAGE_VERSION}' All-in-One YAML" >> ${YAML_FILE}
if [ "${CLUSTER_ROLE_CREATOR}" == "true" ]; then
  echo "# This operator will be granted permission to create cluster roles. Use with caution!" >> ${YAML_FILE}
else
  echo "# This operator will not be able to support deployment.accessible_namespaces=['**']." >> ${YAML_FILE}
fi

# put the namespace as the first resource, if we were asked it be created
if [ "${CREATE_OPERATOR_NAMESPACE}" == "true" ]; then
  cat <<EOF >> ${YAML_FILE}
---
apiVersion: v1
kind: Namespace
metadata:
  name: ${OPERATOR_NAMESPACE}
...
EOF
fi

# combine the yamls into a single file
${HELM} template \
  --include-crds \
  --namespace ${OPERATOR_NAMESPACE} \
  --set cr.create=false \
  --set clusterRoleCreator="${CLUSTER_ROLE_CREATOR}" \
  kiali-operator ${HELM_CHART} \
  >> ${YAML_FILE}

echo "Done! All-in-one yaml file is here: ${YAML_FILE}"
echo "Run this to apply:"
if [ "${CREATE_OPERATOR_NAMESPACE}" != "true" ]; then
  echo "  if ! kubectl get namespace ${OPERATOR_NAMESPACE} 2>/dev/null; then kubectl create namespace ${OPERATOR_NAMESPACE}; fi && \\"
fi
echo "  kubectl apply -n ${OPERATOR_NAMESPACE} -f ${YAML_FILE}"
echo "WARNING! It is recommended you use helm and the Kiali Operator Helm Chart rather than this all-in-one yaml. This is only provided as an unsupported convienence."
