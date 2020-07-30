#!/bin/bash

##############################################################################
# deploy-kiali-operator.sh
#
# This script can be used to deploy the Kiali operator into an OpenShift
# or Kubernetes cluster. It is merely a convienence wrapper around the
# Kiali operator Helm Chart. It is recommended you use 'helm' directly
# rather than use this script - this script does not provide all
# the functionality that the helm CLI provides.
#
# To use this script, either "oc" or "kubectl" must be in your PATH.
#
# To customize the behavior of this script, you can set one or more of the
# following environment variables or pass in their associated command
# line arguments (run the script with "--help" for details on the command
# line arguments available).
#
# -----------
# Environment variables that affect the overall behavior of this script:
#
# DRY_RUN
#    If true, helm will be instructed to perform a dry run and thus
#    will not create any objects in the cluster.
#    Default: "false"
#
# HELM_CHART
#    The Helm Chart to be used when installing the operator.
#    If specified, this must be a Helm Chart tarball whose filename
#    ends with .tgz or tar.gz. When specified, it will be
#    installed and the HELM_REPO_CHART_VERSION is ignored.
#    If set to "source" this will download the Kiali Operator source
#    and build the latest Helm Chart and use that.
#    If not specified, HELM_REPO_CHART_VERSION is used.
#
# HELM_REPO_CHART_VERSION
#    Use the Kiali Operator Helm Chart repo to obtain the Helm Chart.
#    When specified, this must be the version of the Chart to install.
#    If "lastrelease" is specified, the same version as the last
#    Kiali Operator release will be assumed.
#    The chart repo is: https://kiali.org/kiali-operator/charts
#    Default: "lastrelease" if HELM_CHART is not specified; ignored otherwise
#
# Environment variables that affect the Kiali operator installation:
#
# OPERATOR_CLUSTER_ROLE_CREATOR
#    When true, the operator will be given permission to create cluster roles and
#    cluster role bindings so it can, in turn, assign Kiali a cluster role and
#    cluster role binding to access all namespaces. This is to support the Kiali CR
#    setting deployment.accessible_namespaces=['**'] (see the Kiali documentation for
#    more details on this setting).
#    This is overridden to "true" if you are installing Kiali with accessible namespaces
#    set to ** (i.e. -an '**' -oik true).
#    Default: "false"
#
# OPERATOR_IMAGE_NAME
#    Determines which image of the operator to download and install.
#    To control what image name of Kiali to install, see KIALI_IMAGE_NAME.
#    Default: "quay.io/kiali/kiali-operator"
#
# OPERATOR_IMAGE_PULL_POLICY
#    The Kubernetes pull policy for the Kiali operator deployment.
#    This is overridden to be "Always" if OPERATOR_IMAGE_VERSION is set to "latest".
#    Default: "IfNotPresent"
#
# OPERATOR_IMAGE_VERSION
#    Determines which version of the operator to install.
#    To control what image version of Kiali to install, see KIALI_IMAGE_VERSION.
#    This can be set to "latest" in which case the latest image is installed (which may or
#    may not be a released version of Kiali operator).
#    This can be set to "lastrelease" in which case the last Kiali operator release is installed.
#    Otherwise, you can set to this any valid Kiali version (such as "v0.12").
#    Default: "lastrelease"
#
# OPERATOR_INSTALL_KIALI
#    If "true" this script will immediately command the operator to install Kiali as configured
#    by the other environment variables (as documented below).
#    Default: "true"
#
# OPERATOR_NAMESPACE
#    The namespace into which Kiali operator is to be installed.
#    Default: "kiali-operator"
#
# OPERATOR_VIEW_ONLY_MODE
#    Setting this to true will ensure the operator only has the necessary permissions to deploy Kiali with
#    view_only_mode=true. If Kiali is also to be deployed via this deploy script, Kiali will be put into
#    view_only_mode. If the operator is later told to deploy Kiali with view_only_mode set to false, the
#    operator will be unable to do so.
#    Default: "false"
#
# OPERATOR_WATCH_NAMESPACE
#    The namespace in which the operator looks for a Kiali CR. When a Kiali CR is touched (i.e. created,
#    modified, or deleted) in a watched namespace, the operator will perform all necessary tasks in order
#    to deploy Kiali with the configuration specified in the Kiali CR (this is called "reconciling").
#    If specified as "**" (or, alternatively, literally two double-quotes "") then the operator will
#    watch all namespaces. Note that if you specify a specific watch namespace, and a user changes
#    some of the Kiali resources that exist outside of that watched namespace (e.g. deletes or modifies
#    the Kiali Deployment) the operator will be unable to reconcile those changes (e.g. it will not
#    be able to redeploy the Deployment resource) unless and until the Kiali CR is touched again.
#    Default: "" (literally two double-quotes)
#
# -----------
# Environment variables that affect Kiali installation:
#
# ACCESSIBLE_NAMESPACES
#   These are the namespaces that Kiali will be granted access to. These should be the namespaces
#   that make up the service mesh - it will be those namespaces Kiali will observe and manage.
#   The format of the value of this environment variable is a space-separated list (no commas).
#   The namespaces can be regular expressions or explicit namespace names.
#   NOTE! If this is the special value of "**" (two asterisks), that will denote you want Kiali to be
#   given access to all namespaces. When given this value, the operator will
#   be given permission to create cluster roles and cluster role bindings so it can in turn
#   assign Kiali a cluster role and cluster role binding to access all namespaces. Therefore,
#   be very careful when setting this value to "**" because of the superpowers this will grant
#   to the Kiali operator.
#   Default: "^((?!(istio-operator|kube.*|openshift.*|ibm.*|kiali-operator)).)*$"
#
# AUTH_STRATEGY
#    Determines what authentication strategy to use.
#    Default: "openshift" (when using OpenShift), "token" (when using Kubernetes)
#
# KIALI_CR
#    A local file containing a customized Kiali CR that you want to install once the operator
#    is deployed. This will override most all other settings because you are declaring
#    to this script that you want to control the Kiali configuration through this file
#    and not through the command line options or environment variables.
#    Default: ""
#
# KIALI_CR_NAMESPACE
#    Determines the namespace where the Kiali CR will be created. If not specified,
#    the OPERATOR_WATCH_NAMESPACE is used. If the operator is to watch all namespaces
#    (i.e. OPERATOR_WATCH_NAMESPACE is "" (two double-quotes) or "**")
#    then the fallback default is NAMESPACE.
#
# KIALI_IMAGE_NAME
#    Determines which image of Kiali to download and install.
#    If you set this, you must make sure that image is supported by the operator.
#    If left empty (the default), the operator will use a known supported image.
#    Default: ""
#
# KIALI_IMAGE_PULL_POLICY
#    The Kubernetes pull policy for the Kiali deployment.
#    The operator will overide this to be "Always" if KIALI_IMAGE_VERSION is set to "latest".
#    Default: "IfNotPresent"
#
# KIALI_IMAGE_VERSION
#    Determines which version of Kiali to install.
#    This can be set to "latest" in which case the latest image is installed (which may or
#    may not be a released version of Kiali). This is normally for developer use only.
#    This can be set to "lastrelease" in which case the last Kiali release is installed.
#    This can be set to "operator_version" in which case the version of Kiali to be
#    installed will be the same version as that of the operator. Use with care - the
#    operator version may not be the version of Kiali you want.
#    Otherwise, you can set this to any valid Kiali version (such as "v1.0").
#    NOTE: If this is set to "latest" then the KIALI_IMAGE_PULL_POLICY will be "Always".
#    If you set this, you must make sure that image is supported by the operator.
#    If left empty (the default), the operator will use the last Kiali release.
#    Default: ""
#
# ISTIO_NAMESPACE
#    The namespace where Istio is installed. If empty, assumes the value of NAMESPACE.
#    Default: ""
#
# NAMESPACE
#    The namespace into which Kiali is to be installed.
#    Default: "istio-system"
#
# VERSION
#    This is the value that will be passed directly to the Kiali CR's "version"
#    setting when installing Kiali. This is a named version or product name.
#    If not specified, a default version of Kiali will be installed which will
#    be the same version as that of the Kiali operator. See the --help output
#    for the --version option for more details.
#
##############################################################################

set -eu

# process command line args to override environment
_CMD=""
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -an|--accessible-namespaces)
      ACCESSIBLE_NAMESPACES="$2"
      shift;shift
      ;;
    -as|--auth-strategy)
      AUTH_STRATEGY="$2"
      shift;shift
      ;;
    -dr|--dry-run)
      if [ "${2:-}" != "true" -a "${2:-}" != "false" ]; then echo "--dry-run must be true or false"; exit 1; fi
      DRY_RUN="$2"
      shift;shift
      ;;
    -hc|--helm-chart)
      HELM_CHART="$2"
      shift;shift
      ;;
    -hrcv|--helm-repo-chart-version)
      HELM_REPO_CHART_VERSION="$2"
      shift;shift
      ;;
    -kcn|--kiali-cr-namespace)
      KIALI_CR_NAMESPACE="$2"
      shift;shift
      ;;
    -kcr|--kiali-cr)
      KIALI_CR="$2"
      shift;shift
      ;;
    -kin|--kiali-image-name)
      KIALI_IMAGE_NAME="$2"
      shift;shift
      ;;
    -kipp|--kiali-image-pull-policy)
      KIALI_IMAGE_PULL_POLICY="$2"
      shift;shift
      ;;
    -kiv|--kiali-image-version)
      KIALI_IMAGE_VERSION="$2"
      shift;shift
      ;;
    -in|--istio-namespace)
      ISTIO_NAMESPACE="$2"
      shift;shift
      ;;
    -n|--namespace)
      NAMESPACE="$2"
      shift;shift
      ;;
    -ocrc|--operator-cluster-role-creator)
      if [ "${2:-}" != "true" -a "${2:-}" != "false" ]; then echo "--operator-cluster-role-creator must be true or false"; exit 1; fi
      OPERATOR_CLUSTER_ROLE_CREATOR="$2"
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
    -oik|--operator-install-kiali)
      OPERATOR_INSTALL_KIALI="$2"
      shift;shift
      ;;
    -on|--operator-namespace)
      OPERATOR_NAMESPACE="$2"
      shift;shift
      ;;
    -ovom|--operator-view-only-mode)
      if [ "${2:-}" != "true" -a "${2:-}" != "false" ]; then echo "--operator-view-only-mode must be true or false"; exit 1; fi
      OPERATOR_VIEW_ONLY_MODE="$2"
      shift;shift
      ;;
    -own|--operator-watch-namespace)
      OPERATOR_WATCH_NAMESPACE="$2"
      shift;shift
      ;;
    -v|--version)
      VERSION="$2"
      shift;shift
      ;;
    -h|--help)
      cat <<HELPMSG

$0 [option...]

Valid options for overall script behavior:
  -dr|--dry-run
      If true, helm will be instructed to perform a dry run and thus
      will not create any objects in the cluster.
      Default: "false"

  -hc|--helm-chart
      The Helm Chart to be used when installing the operator.
      If specified, this must be a Helm Chart tarball whose filename
      ends with .tgz or tar.gz. When specified, it will be
      installed and the HELM_REPO_CHART_VERSION is ignored.
      If set to "source" this will download the Kiali Operator source
      and build the latest Helm Chart and use that.
      If not specified, HELM_REPO_CHART_VERSION is used.

  -hrcv|--helm-repo-chart-version
      Use the Kiali Operator Helm Chart repo to obtain the Helm Chart.
      When specified, this must be the version of the Chart to install.
      If "lastrelease" is specified, the same version as the last
      Kiali Operator release will be assumed.
      The chart repo is: https://kiali.org/kiali-operator/charts
      Default: "lastrelease" if --helm-chart is not specified; ignored otherwise

Valid options for the operator installation:
  -ocrc|--operator-cluster-role-creator
      When true, the operator will be given permission to create cluster roles and
      cluster role bindings so it can, in turn, assign Kiali a cluster role and
      cluster role binding to access all namespaces. This is to support the Kiali CR
      setting deployment.accessible_namespaces=['**'] (see the Kiali documentation for
      more details on this setting).
      This is overridden to "true" if you are installing Kiali with accessible namespaces
      set to ** (i.e. -an '**' -oik true).
      Default: "false"
  -oin|--operator-image-name
      Image of the Kiali operator to download and install.
      Default: "quay.io/kiali/kiali-operator"
  -oipp|--operator-image-pull-policy
      The Kubernetes pull policy for the Kiali operator deployment.
      Default: "IfNotPresent"
  -oiv|--operator-image-version
      The version of the Kiali operator to install.
      Can be a version string or "latest" or "lastrelease".
      Default: "lastrelease"
  -oik|--operator-install-kiali
      If "true" this script will immediately command the Kiali operator to install Kiali.
      Default: "true"
  -on|--operator-namespace
      The namespace into which the Kiali operator is to be installed.
      Default: "kiali-operator"
  -ovom|--operator-view-only-mode
      Setting this to true will ensure the operator only has the necessary permissions to deploy Kiali with
      view_only_mode=true. If Kiali is also to be deployed via this deploy script, Kiali will be put into
      view_only_mode. If the operator is later told to deploy Kiali with view_only_mode set to false, the
      operator will be unable to do so.
      Default: "false"
  -own|--operator-watch-namespace
      The namespace in which the operator looks for a Kiali CR. When a Kiali CR is touched (i.e. created,
      modified, or deleted) in a watched namespace, the operator will perform all necessary tasks in order
      to deploy Kiali with the configuration specified in the Kiali CR (this is called "reconciling").
      If specified as "**" (or, alternatively, literally two double-quotes "") then the operator will
      watch all namespaces. Note that if you specify a specific watch namespace, and a user changes
      some of the Kiali resources that exist outside of that watched namespace (e.g. deletes or modifies
      the Kiali Deployment) the operator will be unable to reconcile those changes (e.g. it will not
      be able to redeploy the Deployment resource) unless and until the Kiali CR is touched again.
      Default: "" (two double-quotes)

Valid options for Kiali installation (if Kiali is to be installed):
  -an|--accessible-namespaces
      The namespaces that Kiali will be given permission to observe and manage.
      The format of the value of this option is a space-separated list (no commas).
      The namespaces can be regular expressions or explicit namespace names.
      NOTE! If this is the special value of "**" (two asterisks), that will denote you want
      Kiali to be given access to all namespaces via a single cluster role. When given this
      value, the operator will be given permission to create cluster roles and cluster
      role bindings so it can in turn assign Kiali a cluster role to access all namespaces.
      Therefore, be very careful when setting this value to "**" because of the
      superpowers this will grant to the Kiali operator.
      Default: "^((?!(istio-operator|kube.*|openshift.*|ibm.*|kiali-operator)).)*$"
  -as|--auth-strategy
      Determines what authentication strategy to use.
      Default: "openshift" (when using OpenShift), "token" (when using Kubernetes)
  -kcn|--kiali-cr-namespace
      Determines the namespace where the Kiali CR will be created. If not specified,
      the operator watch namespace (-own) is used. If the operator is to watch all namespaces
      (i.e. -own is "" (two double-quotes) or "**") then the fallback default is the
      value for --namespace.
  -kcr|--kiali-cr
      A local file containing a customized Kiali CR that you want to install once the operator
      is deployed. This will override most all other settings because you are declaring
      to this script that you want to control the Kiali configuration through this file
      and not through the command line options or environment variables.
      Default: ""
  -kin|--kiali-image-name
      Determines which image of Kiali to download and install.
      If left empty (the default), the operator will use a known supported image.
      Default: ""
  -kipp|--kiali-image-pull-policy
      The Kubernetes pull policy for the Kiali deployment.
      Default: "IfNotPresent"
  -kiv|--kiali-image-version
      Determines which version of Kiali to install.
      Can be a version string or "latest" or "lastrelease".
      If left empty (the default), the operator will use a known supported image.
      Default: ""
  -in|--istio-namespace
      The namespace where Istio is installed.
      If empty, assumes the value of the namespace option.
  -n|--namespace
      The namespace into which Kiali is to be installed.
      Default: "istio-system"
  -v|--version
      The version of Kiali to install. This is a named version or product name.
      If not specified, a default version of Kiali will be installed which will be
      the same version as that of the Kiali operator.
      This version setting affects the defaults of the --kiali-image-name and
      --kiali-image-version settings such that this version will
      dictate which version of the Kiali image will be deployed by default.
      Note that if you explicitly set --kiali-image-name and/or
      --kiali-image-version you are responsible for ensuring those settings
      are compatible with this version setting (i.e. the Kiali image must be compatible
      with the rest of the configuration and resources the operator will install).

HELPMSG
      exit 1
      ;;
    *)
      echo "Unknown argument [$key]. Aborting."
      exit 1
      ;;
  esac
done

# Determine what cluster client tool we are using.
# While we have this knowledge here, determine some information about auth_strategy we might need later.
CLIENT_EXE=$(which oc 2>/dev/null)
if [ "$?" == "0" ]; then
  echo "Using 'oc' located here: ${CLIENT_EXE}"
  _AUTH_STRATEGY_DEFAULT="openshift"
  _AUTH_STRATEGY_PROMPT="Choose a login strategy of either 'openshift', 'token', or 'anonymous'. Use 'anonymous' at your own risk. [${_AUTH_STRATEGY_DEFAULT}]: "
else
  CLIENT_EXE=$(which kubectl 2>/dev/null)
  if [ "$?" == "0" ]; then
    echo "Using 'kubectl' located here: ${CLIENT_EXE}"
    _AUTH_STRATEGY_DEFAULT="token"
    _AUTH_STRATEGY_PROMPT="Choose a login strategy of either 'token', 'openid' or 'anonymous'. Use 'anonymous' at your own risk. [${_AUTH_STRATEGY_DEFAULT}]: "
  else
    echo "ERROR: You do not have 'oc' or 'kubectl' in your PATH. Please install it and retry."
    exit 1
  fi
fi

# Some environment variables we need set to their defaults if not set already
NAMESPACE="${NAMESPACE:-istio-system}"
VERSION="${VERSION:-default}"
HELM_CHART="${HELM_CHART:-}"
HELM_REPO_CHART_VERSION="${HELM_REPO_CHART_VERSION:-lastrelease}"

if [ "${DRY_RUN:-}" == "true" ]; then
  DRY_RUN_ARG="--dry-run"
else
  DRY_RUN_ARG=""
fi

# The YAML really needs an empty string denoted with two double-quote characters.
# We just support "**" because its easier to specify on the command line.
if [ "${OPERATOR_WATCH_NAMESPACE:-}" == "**" ]; then
  OPERATOR_WATCH_NAMESPACE='""'
fi

# Export all possible variables for envsubst to be able to process operator resources
export OPERATOR_CLUSTER_ROLE_CREATOR="${OPERATOR_CLUSTER_ROLE_CREATOR:-false}"
export OPERATOR_IMAGE_NAME="${OPERATOR_IMAGE_NAME:-quay.io/kiali/kiali-operator}"
export OPERATOR_IMAGE_PULL_POLICY="${OPERATOR_IMAGE_PULL_POLICY:-IfNotPresent}"
export OPERATOR_IMAGE_VERSION="${OPERATOR_IMAGE_VERSION:-lastrelease}"
export OPERATOR_INSTALL_KIALI=${OPERATOR_INSTALL_KIALI:-true}
export OPERATOR_NAMESPACE="${OPERATOR_NAMESPACE:-kiali-operator}"
export OPERATOR_VIEW_ONLY_MODE="${OPERATOR_VIEW_ONLY_MODE:-false}"
export OPERATOR_WATCH_NAMESPACE="${OPERATOR_WATCH_NAMESPACE:-\"\"}"

# Determine what tool to use to download files. This supports environments that have either wget or curl.
# After return, $downloader will be a command to stream a URL's content to stdout.
get_downloader() {
  if [ ! "${downloader:-}" ] ; then
    # Use wget command if available, otherwise try curl
    if which wget > /dev/null 2>&1 ; then
      downloader="wget -q -O -"
    fi
    if [ ! "$downloader" ] ; then
      if which curl > /dev/null 2>&1 ; then
        downloader="curl -s"
      fi
    fi
    if [ ! "$downloader" ] ; then
      echo "ERROR: You must install either curl or wget to allow downloading"
      exit 1
    else
      echo "Using downloader: $downloader"
    fi
  fi
}

resolve_latest_kiali_release() {
  if [ -z "${kiali_version_we_want:-}" ]; then
    get_downloader
    github_api_url="https://api.github.com/repos/kiali/kiali/releases"
    kiali_version_we_want=$(${downloader} ${github_api_url} 2> /dev/null |\
      grep  "tag_name" | \
      sed -e 's/.*://' -e 's/ *"//' -e 's/",//' | \
      grep -v "snapshot" | \
      sort -t "." -k 1.2g,1 -k 2g,2 -k 3g | \
      tail -n 1)
    if [ -z "${kiali_version_we_want}" ]; then
      echo "ERROR: Failed to determine latest Kiali release."
      echo "Make sure this URL is accessible and returning valid results:"
      echo ${github_api_url}
      exit 1
    fi
  fi
}

resolve_latest_kiali_operator_release() {
  if [ -z "${kiali_operator_version_we_want:-}" ]; then
    get_downloader
    github_api_url="https://api.github.com/repos/kiali/kiali-operator/releases"
    kiali_operator_version_we_want=$(${downloader} ${github_api_url} 2> /dev/null |\
      grep  "tag_name" | \
      sed -e 's/.*://' -e 's/ *"//' -e 's/",//' | \
      grep -v "snapshot" | \
      sort -t "." -k 1.2g,1 -k 2g,2 -k 3g | \
      tail -n 1)
    if [ -z "${kiali_operator_version_we_want}" ]; then
      echo "ERROR: Failed to determine latest Kiali Operator release."
      echo "Make sure this URL is accessible and returning valid results:"
      echo ${github_api_url}
      exit 1
    fi
  fi
}

get_operator_source_from_github() {
  if [ -z "${KIALI_OP_SRC:-}" ]; then
    local script_dir="$(cd "$(dirname "$0")" && pwd -P)"
    if [ -f "${script_dir}/../watches.yaml" -a -f "${script_dir}/../playbooks/kiali-deploy.yml" ]; then
      # we are already in github source - use our location
      KIALI_OP_SRC="$(cd "${script_dir}/.." && pwd -P)"
    else
      KIALI_OP_SRC=$(mktemp -d)
      resolve_latest_kiali_operator_release
      ${downloader} https://github.com/kiali/kiali-operator/archive/${kiali_operator_version_we_want}.tar.gz | tar xz --directory ${KIALI_OP_SRC}
      KIALI_OP_SRC="${KIALI_OP_SRC}/$(ls -1 ${KIALI_OP_SRC})"
    fi
  fi
}

get_helm() {
  if [ -z "${HELM:-}" ]; then
    if which helm > /dev/null 2>&1; then
      HELM="$(which helm)"
    else
      echo "You do not have helm in your PATH. Will attempt to download it now..."
      get_operator_source_from_github
      make -C "${KIALI_OP_SRC}" .download-helm-if-needed
      if [ -x "${KIALI_OP_SRC}/_output/helm-install/helm" ]; then
        HELM="${KIALI_OP_SRC}/_output/helm-install/helm"
      else
        echo "You do not have helm in PATH and it could not be downloaded. Install helm manually and try again."
        exit 1
      fi
    fi
    echo "Using helm found here: ${HELM}"
  fi
}

get_helm_chart() {
  if [ "${HELM_CHART}" == "source" ]; then
    get_operator_source_from_github
    if ! ls ${KIALI_OP_SRC}/_output/charts/kiali-operator*.tgz > /dev/null 2>&1; then
      echo "There is no Helm Chart from source - will build it now"
      make -C "${KIALI_OP_SRC}" build-helm-chart
    fi
    HELM_CHART="$(ls -1 ${KIALI_OP_SRC}/_output/charts/kiali-operator*.tgz)"
    echo "Using the Helm Chart from source found here: ${HELM_CHART}"
  else
    if [ -z "${HELM_CHART}" ]; then
      if [ "${HELM_REPO_CHART_VERSION}" == "lastrelease" ]; then
        resolve_latest_kiali_operator_release
        HELM_REPO_CHART_VERSION="${kiali_operator_version_we_want}"
      fi
      echo "Will obtain the Helm Chart version [${HELM_REPO_CHART_VERSION}] from the Kiali Operator Helm Repo"
      if ! ${HELM} repo list -o yaml | grep -q "name: kiali-operator"; then
        echo "Adding kiali-operator repo to Helm"
        ${HELM} repo add kiali-operator https://kiali.org/kiali-operator/charts
      else
        ${HELM} repo update
      fi
      HELM_CHART="--version ${HELM_REPO_CHART_VERSION} kiali-operator/kiali-operator"
    else
      if [[ "${HELM_CHART}" != *".tgz" && "${HELM_CHART}" != *".tar.gz" ]]; then
        echo "The Helm Chart must be specified with an extension of either .tgz or .tar.gz [You specified: ${HELM_CHART}]"
        exit 1
      fi
      echo "Using the Helm Chart found here: ${HELM_CHART}"
    fi
  fi
}

# If asking for the last release of operator (which is the default), then pick up the latest release.
# Note that you could ask for "latest" - that would pick up the current image built from master.
if [ "${OPERATOR_IMAGE_VERSION}" == "lastrelease" ]; then
  resolve_latest_kiali_operator_release
  echo "Will use the last Kiali operator release: ${kiali_operator_version_we_want}"
  OPERATOR_IMAGE_VERSION=${kiali_operator_version_we_want}
else
  if [ "${OPERATOR_IMAGE_VERSION}" == "latest" ]; then
    echo "Will use the latest Kiali operator image from master branch - pull policy will be Always"
    OPERATOR_IMAGE_PULL_POLICY="Always"
  fi
fi

# If asking for the last release of Kiali (which is the default), then pick up the latest release.
# Note that you could ask for "latest" - that would pick up the current image built from master.
if [ "${OPERATOR_INSTALL_KIALI}" == "true" ]; then
  if [ "${KIALI_IMAGE_VERSION:-}" == "lastrelease" ]; then
    resolve_latest_kiali_release
    echo "Will use the last Kiali release: ${kiali_version_we_want}"
    KIALI_IMAGE_VERSION=${kiali_version_we_want}
  else
    if [ "${KIALI_IMAGE_VERSION:-}" == "latest" ]; then
      echo "Will use the latest Kiali image from master branch - pull policy will be Always"
      KIALI_IMAGE_PULL_POLICY="Always"
    fi
  fi
fi

# Courtesy of https://github.com/jasperes/bash-yaml
parse_yaml() {
    local yaml_file=$1
    local prefix=$2
    local s
    local w
    local fs

    s='[[:space:]]*'
    w='[a-zA-Z0-9_.-]*'
    fs="$(echo @|tr @ '\034')"

    (
        sed -e '/- [^\“]'"[^\']"'.*: /s|\([ ]*\)- \([[:space:]]*\)|\1-\'$'\n''  \1\2|g' |

        sed -ne '/^--/s|--||g; s|\"|\\\"|g; s/[[:space:]]*$//g;' \
            -e "/#.*[\"\']/!s| #.*||g; /^#/s|#.*||g;" \
            -e "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
            -e "s|^\($s\)\($w\)${s}[:-]$s\(.*\)$s\$|\1$fs\2$fs\3|p" |

        awk -F"$fs" '{
            indent = length($1)/2;
            if (length($2) == 0) { conj[indent]="+";} else {conj[indent]="";}
            vname[indent] = $2;
            for (i in vname) {if (i > indent) {delete vname[i]}}
                if (length($3) > 0) {
                    vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
                    printf("%s%s%s%s=(\"%s\")\n", "'"$prefix"'",vn, $2, conj[indent-1],$3);
                }
            }' |

        sed -e 's/_=/+=/g' |

        awk 'BEGIN {
                FS="=";
                OFS="="
            }
            /(-|\.).*=/ {
                gsub("-|\\.", "_", $1)
            }
            { print }'
    ) < "$yaml_file"
}

# If the user provided a customized CR, make sure it exists and parse the yaml to determine some settings.
if [ "${KIALI_CR:-}" != "" ]; then
  if [ ! -f "${KIALI_CR}" ]; then
    echo "The given Kiali CR file does not exist [${KIALI_CR}]. Aborting."
    exit 1
  fi

  # parse the auth strategy value which may be wrapped with double-quotes, single-quotes, or not wrapped at all
  AUTH_STRATEGY=$(parse_yaml "${KIALI_CR}" | grep -E 'auth[_]+strategy' | sed -e 's/^.*strategy=("\(.*\)")/\1/' | tr -d "\\\'\"")
  if [ "${AUTH_STRATEGY}" == "" ]; then
    # If auth strategy isn't in the yaml, then we need to fallback to the known default the operator will use
    # which is based on cluster type.
    if [[ "${CLIENT_EXE}" = *"oc" ]]; then
      AUTH_STRATEGY="openshift"
    else
      AUTH_STRATEGY="token"
    fi
  fi

  # Depending how the accessible_namespace list is indented, the parser might be producing different lines.
  # To detect the "**" value regardless how the indentation is done, just look for ** after deployment_ (since we
  # know "**" isn't a valid value for anything other than accessible_namespace its fine to test it like this)
  parse_yaml "${KIALI_CR}" | grep -E 'deployment.*=.*\*\*' 2>&1 > /dev/null
  if [ "$?" == "0" ]; then
    ACCESSIBLE_NAMESPACES="**"
  fi
fi

# Determine if the operator needs to create cluster roles for Kiali to be installed
if [ "${ACCESSIBLE_NAMESPACES:-}" == "**" -a "${OPERATOR_INSTALL_KIALI}" == "true" -a "${OPERATOR_CLUSTER_ROLE_CREATOR}" != "true" ]; then
  echo "NOTE! The operator will be granted cluster role creator rights because you are installing Kiali with accessible namespaces of '**'"
  OPERATOR_CLUSTER_ROLE_CREATOR="true"
fi

# Get all things helm
get_helm
get_helm_chart

echo "=== OPERATOR SETTINGS ==="
echo DRY_RUN_ARG=$DRY_RUN_ARG
echo HELM=$HELM
echo HELM_CHART=$HELM_CHART
echo HELM_REPO_CHART_VERSION=$HELM_REPO_CHART_VERSION
echo OPERATOR_CLUSTER_ROLE_CREATOR=$OPERATOR_CLUSTER_ROLE_CREATOR
echo OPERATOR_IMAGE_NAME=$OPERATOR_IMAGE_NAME
echo OPERATOR_IMAGE_PULL_POLICY=$OPERATOR_IMAGE_PULL_POLICY
echo OPERATOR_IMAGE_VERSION=$OPERATOR_IMAGE_VERSION
echo OPERATOR_INSTALL_KIALI=$OPERATOR_INSTALL_KIALI
echo OPERATOR_NAMESPACE=$OPERATOR_NAMESPACE
echo OPERATOR_WATCH_NAMESPACE=$OPERATOR_WATCH_NAMESPACE
echo "=== OPERATOR SETTINGS ==="

# Now deploy all the Kiali operator components.
echo "Deploying Kiali operator to namespace [${OPERATOR_NAMESPACE}]"

${HELM} upgrade \
  --install \
  --create-namespace \
  --atomic \
  --cleanup-on-fail \
  --namespace ${OPERATOR_NAMESPACE} \
  --set cr.create=false \
  --set image.repo=${OPERATOR_IMAGE_NAME} \
  --set image.pullPolicy=${OPERATOR_IMAGE_PULL_POLICY} \
  --set image.tag=${OPERATOR_IMAGE_VERSION} \
  --set watchNamespace=${OPERATOR_WATCH_NAMESPACE} \
  --set clusterRoleCreator=${OPERATOR_CLUSTER_ROLE_CREATOR} \
  --set onlyViewOnlyMode=${OPERATOR_VIEW_ONLY_MODE} \
  --debug \
  ${DRY_RUN_ARG} \
  kiali-operator \
  ${HELM_CHART}

if [ "$?" != "0" ]; then
  echo "ERROR: Failed to deploy Kiali operator. Aborting."
  exit 1
fi

# Wait for the operator to start up so we can confirm it is OK.
if [ "${DRY_RUN:-}" != "true" ]; then
  echo "Waiting for the operator to start..."
  ${CLIENT_EXE} wait --timeout=120s --for=condition=Ready -n ${OPERATOR_NAMESPACE} $(${CLIENT_EXE} get pods -l 'app.kubernetes.io/name=kiali-operator' -n ${OPERATOR_NAMESPACE} -o name) && _OPERATOR_STARTED="true"

  if [ -z ${_OPERATOR_STARTED:-} ]; then
    echo "ERROR: The Kiali operator is not running yet. Please make sure it was deployed successfully."
    exit 1
  else
    echo "The Kiali operator is installed!"
  fi
fi

# Now deploy Kiali if we were asked to do so.

# If the user did not specify where to put the Kiali CR, the default is the operator watch namespace.
# If the operator watch namespace is "all namespaces" then use the Kiali namespace.
if [ -z "${KIALI_CR_NAMESPACE:-}" ]; then
  if [ "${OPERATOR_WATCH_NAMESPACE}" != '""' ]; then
    KIALI_CR_NAMESPACE="${OPERATOR_WATCH_NAMESPACE}"
  else
    KIALI_CR_NAMESPACE="${NAMESPACE}"
  fi
fi

print_skip_kiali_create_msg() {
  local _ns="${OPERATOR_WATCH_NAMESPACE}"
  if [ "${_ns}" == '""' ]; then
    _ns="<any namespace you choose>"
  fi
  echo "=========================================="
  echo "Skipping the automatic Kiali installation."
  echo "To install Kiali, create a Kiali custom resource in the namespace [$_ns]."
  echo "An example Kiali CR with all settings documented can be found here:"
  echo "  https://raw.githubusercontent.com/kiali/kiali-operator/master/deploy/kiali/kiali_cr.yaml"
  echo "To install Kiali with all default settings, an example command would be:"
  echo "  ${CLIENT_EXE} apply -n ${_ns} -f https://raw.githubusercontent.com/kiali/kiali-operator/master/deploy/kiali/kiali_cr.yaml"
  echo "=========================================="
}

if [ "${OPERATOR_INSTALL_KIALI}" != "true" ]; then
  print_skip_kiali_create_msg
  echo "Done."
  exit 0
else
  echo "Kiali will now be installed."
fi

# Ensure we are told which auth strategy to use.
if [ "${AUTH_STRATEGY:-}" == "" ]; then
  AUTH_STRATEGY=$(read -p "${_AUTH_STRATEGY_PROMPT}" val && echo -n $val)
  AUTH_STRATEGY=${AUTH_STRATEGY:-${_AUTH_STRATEGY_DEFAULT}}
fi

# Verify the AUTH_STRATEGY is a proper known value
if [ "${AUTH_STRATEGY}" != "openshift" ] && [ "${AUTH_STRATEGY}" != "anonymous" ] && [ "${AUTH_STRATEGY}" != "token" ] && [ "${AUTH_STRATEGY}" != "openid" ]; then
  echo "ERROR: unknown AUTH_STRATEGY [$AUTH_STRATEGY] must be either 'openshift', 'token', 'openid' or 'anonymous'"
  exit 1
fi

echo "=== KIALI SETTINGS ==="
echo ACCESSIBLE_NAMESPACES=$ACCESSIBLE_NAMESPACES
echo AUTH_STRATEGY=$AUTH_STRATEGY
echo DRY_RUN_ARG=$DRY_RUN_ARG
echo KIALI_CR=${KIALI_CR:-}
echo KIALI_CR_NAMESPACE=$KIALI_CR_NAMESPACE
echo KIALI_IMAGE_NAME=${KIALI_IMAGE_NAME:-}
echo KIALI_IMAGE_PULL_POLICY=${KIALI_IMAGE_PULL_POLICY:-}
echo KIALI_IMAGE_VERSION=${KIALI_IMAGE_VERSION:-}
echo ISTIO_NAMESPACE=${ISTIO_NAMESPACE:-}
echo NAMESPACE=$NAMESPACE
echo VERSION=$VERSION
echo "=== KIALI SETTINGS ==="

# Now deploy Kiali

echo "Deploying Kiali CR to namespace [${KIALI_CR_NAMESPACE}]"

build_spec_value() {
  local var_name=${1}
  local var_value=${!2-_undefined_}
  local var_show_empty=${3:-false}
  if [ "${var_value}" == "_undefined_" -a "${var_show_empty}" == "false" ]; then
    return
  else
    if [ "${var_value}" == "" -o "${var_value}" == "_undefined_" ]; then
      var_value='""'
    fi
    echo "$var_name: $var_value"
  fi
}

build_spec_list_value() {
  local var_name=${1}
  local var_value=${!2-_undefined_}
  local var_show_empty=${3:-false}
  if [ "${var_value}" == "_undefined_" -a "${var_show_empty}" == "false" ]; then
    return
  else
    if [ "${var_value}" == "" -o "${var_value}" == "_undefined_" ]; then
      echo "$var_name: []"
    else
      local nl=$'\n'
      local var_name_value="${var_name}:"

      # turn off pathname expansion (set -f) because the namespace regexs may have patterns like ** and *
      set -f
      for item in $var_value
      do
        var_name_value="${var_name_value}${nl}    - \"${item}\""
      done
      set +f

      echo "$var_name_value"
    fi
  fi
}

if [ "${KIALI_CR:-}" != "" ]; then
  ${CLIENT_EXE} apply ${DRY_RUN_ARG} -n ${KIALI_CR_NAMESPACE} -f "${KIALI_CR}"
  if [ "$?" != "0" ]; then
    echo "ERROR: Failed to deploy Kiali from custom Kiali CR [${KIALI_CR}]. Aborting."
    exit 1
  else
    echo "Deployed Kiali via custom Kiali CR [${KIALI_CR}]"
  fi
else
  _KIALI_CR_YAML=$(cat <<EOF | sed '/^[ ]*$/d'
---
apiVersion: kiali.io/v1alpha1
kind: Kiali
metadata:
  name: kiali
spec:
  $(build_spec_value istio_namespace ISTIO_NAMESPACE)
  $(build_spec_value version VERSION)
  auth:
    $(build_spec_value strategy AUTH_STRATEGY)
  deployment:
    $(build_spec_list_value accessible_namespaces ACCESSIBLE_NAMESPACES)
    $(build_spec_value image_name KIALI_IMAGE_NAME)
    $(build_spec_value image_pull_policy KIALI_IMAGE_PULL_POLICY)
    $(build_spec_value image_version KIALI_IMAGE_VERSION)
    $(build_spec_value namespace NAMESPACE)
    $(build_spec_value view_only_mode OPERATOR_VIEW_ONLY_MODE)
EOF
)

  echo "${_KIALI_CR_YAML}" | ${CLIENT_EXE} apply ${DRY_RUN_ARG} -n ${KIALI_CR_NAMESPACE} -f -
  if [ "$?" != "0" ]; then
    echo "ERROR: Failed to deploy Kiali. Aborting."
    exit 1
  fi
fi

echo "Done."
