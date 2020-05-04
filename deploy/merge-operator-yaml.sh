#!/bin/bash

##############################################################################
# merge-operator-yaml.sh
#
# Use this script to combine the separate YAML files into a single YAML file.
# This is helpful if you want to provide a single YAML file that can be used
# to create all resources required by the Kiali Operator.
##############################################################################

# It is assumed the yaml files are in the same location as this script.
YAML_DIR="$(cd "$(dirname "$0")" && pwd -P)"

# Process command line
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -crc|--cluster-role-creator)
      CLUSTER_ROLE_CREATOR="$2"
      shift;shift
      ;;
    -f|--file)
      YAML_FILE="$2"
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

  -crc|--cluster-role-creator
      When true, the operator will be given permission to create cluster roles and
      cluster role bindings so it can, in turn, assign Kiali a cluster role and
      cluster role binding to access all namespaces. This is to support the Kiali CR
      setting deployment.accessible_namespaces=['**'] (see the Kiali documentation for
      more details on this setting). Therefore, be very careful when setting this value
      to "true" because of the superpowers this will grant to the Kiali operator.
      Default: "false"
  -f|--file
      The file where the output is written to. This will be the file that has the combined YAML.
      Default: ${YAML_DIR}/kiali-operator-all-in-one.yaml
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
      The namespace in which the operator looks for the Kiali CR.
      Default: The configured operator namespace (-on)

HELPMSG
      exit 1
      ;;
    *)
      echo "Unknown argument [$key]. Aborting."
      exit 1
      ;;
  esac
done

export OPERATOR_IMAGE_NAME="${OPERATOR_IMAGE_NAME:-quay.io/kiali/kiali-operator}"
export OPERATOR_IMAGE_VERSION="${OPERATOR_IMAGE_VERSION:-latest}"
export OPERATOR_IMAGE_PULL_POLICY="${OPERATOR_IMAGE_PULL_POLICY:-IfNotPresent}"
export OPERATOR_NAMESPACE="${OPERATOR_NAMESPACE:-kiali-operator}"
export OPERATOR_WATCH_NAMESPACE="${OPERATOR_WATCH_NAMESPACE:-${OPERATOR_NAMESPACE}}"

# If version label is not specified, set it to image version; but if
# image version is "latest" the version label will be set to "master".
if [ -z "${OPERATOR_VERSION_LABEL}" ]; then
  if [ "${OPERATOR_IMAGE_VERSION}" == "latest" ]; then
    OPERATOR_VERSION_LABEL="master"
  else
    OPERATOR_VERSION_LABEL="${OPERATOR_IMAGE_VERSION}"
  fi
fi
export OPERATOR_VERSION_LABEL

# Determine if the operator should be granted permissions to create cluster roles/rolebindings
if [ "${CLUSTER_ROLE_CREATOR}" == "true" ]; then
  export OPERATOR_ROLE_CLUSTERROLES="- clusterroles"
  export OPERATOR_ROLE_CLUSTERROLEBINDINGS="- clusterrolebindings"
else
  export OPERATOR_ROLE_CLUSTERROLES="# Add '- clusterroles' to support accessible_namespaces=['**']"
  export OPERATOR_ROLE_CLUSTERROLEBINDINGS="# Add '- clusterrolebindings' to support accessible_namespaces=['**']"
fi

# Operator and Kiali will not be considered view-only
export OPERATOR_ROLE_CREATE="- create"
export OPERATOR_ROLE_DELETE="- delete"
export OPERATOR_ROLE_PATCH="- patch"

echo OPERATOR_IMAGE_NAME="${OPERATOR_IMAGE_NAME}"
echo OPERATOR_IMAGE_VERSION="${OPERATOR_IMAGE_VERSION}"
echo OPERATOR_IMAGE_PULL_POLICY="${OPERATOR_IMAGE_PULL_POLICY}"
echo OPERATOR_NAMESPACE="${OPERATOR_NAMESPACE}"
echo OPERATOR_VERSION_LABEL="${OPERATOR_VERSION_LABEL}"
echo OPERATOR_WATCH_NAMESPACE="${OPERATOR_WATCH_NAMESPACE}"

YAML_LIST="crd.yaml namespace.yaml role.yaml service_account.yaml role_binding.yaml operator.yaml "
YAML_FILE="${YAML_FILE:-${YAML_DIR}/kiali-operator-all-in-one.yaml}"

# remove any old file that still exists
rm -f ${YAML_FILE}

# output the header comment
echo "# Kiali Operator '${OPERATOR_IMAGE_VERSION}' All-in-One YAML" > ${YAML_FILE}
if [ "${CLUSTER_ROLE_CREATOR}" == "true" ]; then
  echo "# This operator will be granted permission to create cluster roles. Use with caution!" >> ${YAML_FILE}
else
  echo "# This operator will not be able to support deployment.accessible_namespaces=['**']." >> ${YAML_FILE}
fi
echo "# Auto-generated by merge-operator-yaml.sh on $(date)" >> ${YAML_FILE}

# combine the yamls into a single file
for yaml in ${YAML_LIST}
do
  cat ${YAML_DIR}/${yaml} | envsubst >> ${YAML_FILE}
done

echo "Done! Combined yaml file is here: ${YAML_FILE}"
echo "Run this to apply: kubectl apply -n ${OPERATOR_NAMESPACE} -f ${YAML_FILE}"
