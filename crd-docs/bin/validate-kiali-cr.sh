#!/bin/bash

##############################################################################
# validate-kiali-cr.sh
#
# This script can be used to validate a Kiali CR.
#
# To use this script, you must:
# * Have "oc" or "kubectl"
# * Be connected to a cluster
# * Have cluster-admin rights
#
##############################################################################

set -u

crd() {
SCRIPT_ROOT="$(cd "$(dirname "$0")" ; pwd -P)"
cat "${SCRIPT_ROOT}/../crd/kiali.io_kialis.yaml" | sed 's/ name: kialis.kiali.io/ name: testkialis.kiali.io/g' | sed 's/ kind: Kiali/ kind: TestKiali/g' | sed 's/ listKind: KialiList/ listKind: TestKialiList/g' | sed 's/ plural: kialis/ plural: testkialis/g' | sed 's/ singular: kiali/ singular: testkiali/g'
}

# process command line args to override environment
_CMD=""
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -ce|--client-exe)      CLIENT_EXE="$2"           ; shift;shift ;;
    -crd|--crd-location)   KIALI_CRD_LOCATION="$2"   ; shift;shift ;;
    -kcf|--kiali-cr-file)  KIALI_CR_FILE="$2"        ; shift;shift ;;
    -kcn|--kiali-cr-name)  KIALI_CR_NAME="$2"        ; shift;shift ;;
    -n|--namespace)        NAMESPACE="$2"            ; shift;shift ;;
    -pc|--print-crd)       PRINT_CRD="$2"            ; shift;shift ;;
    -h|--help)
      cat <<HELPMSG

$0 [option...]

  -ce|--client-exe
      The path to the client executable. Should be a path to either a "oc" or "kubectl" executable.
  -crd|--crd-location
      The file or URL location where the Kiali CRD is. This CRD must include the schema.
      If not specified, the internally defined CRD is used.
  -kcf|--kiali-cr-file
      The file of the Kiali CR to test.
  -kcn|--kiali-cr-name
      The name of an existing Kiali CR to test.
  -n|--namespace
      The namespace where the existing CR is or where the test CR will be created.
      Default: "default"
  -pc|--print-crd
      If true, then this script will just print the CRD used to validate. It will not validate anything.
      Default "false"
HELPMSG
      exit 1
      ;;
    *)
      echo "Unknown argument [$key]. Aborting."
      exit 1
      ;;
  esac
done

# Set up some defaults

: ${NAMESPACE:=default}
: ${PRINT_CRD:=false}

# If we are to print the CRD, do it now immediately and then exit. Nothing else to do.
if [ "${PRINT_CRD}" == "true" ]; then
  if [ -n "${KIALI_CRD_LOCATION:-}" ]; then
    [ -f "${KIALI_CRD_LOCATION}" ] && cat "${KIALI_CRD_LOCATION}" || curl "${KIALI_CRD_LOCATION}"
  else
    echo "$(crd)"
  fi
  exit $?
fi

echo "=== SETTINGS ==="
echo KIALI_CRD_LOCATION=${KIALI_CRD_LOCATION:-}
echo KIALI_CR_FILE=${KIALI_CR_FILE:-}
echo KIALI_CR_NAME=${KIALI_CR_NAME:-}
echo NAMESPACE=${NAMESPACE}
echo PRINT_CRD=${PRINT_CRD}
echo "=== SETTINGS ==="

# Determine what cluster client tool we are using.
if [ -z "${CLIENT_EXE:-}" ]; then
  if which oc &>/dev/null; then
    CLIENT_EXE="$(which oc)"
    echo "Using 'oc' located here: ${CLIENT_EXE}"
  else
    if which kubectl &>/dev/null; then
      CLIENT_EXE="$(which kubectl)"
      echo "Using 'kubectl' located here: ${CLIENT_EXE}"
    else
      echo "ERROR! You do not have 'oc' or 'kubectl' in your PATH. Please install it and retry."
      exit 1
    fi
  fi
else
  echo "Client executable: ${CLIENT_EXE}"
fi

if [ -z "${KIALI_CR_FILE:-}" -a -z "${KIALI_CR_NAME:-}" ]; then
  echo "ERROR! You must specify one of either --kiali-cr-file or --kiali-cr-name"
  exit 1
fi

if [ -n "${KIALI_CR_FILE:-}" -a -n "${KIALI_CR_NAME:-}" ]; then
  echo "ERROR! You must specify only one of either --kiali-cr-file or --kiali-cr-name"
  exit 1
fi

if [ -n "${KIALI_CR_FILE:-}" -a ! -f "${KIALI_CR_FILE:-}" ]; then
  echo "ERROR! Kiali CR file is not found: [${KIALI_CR_FILE:-}]"
  exit 1
fi

if [ -n "${KIALI_CR_NAME:-}" ]; then
  if ! ${CLIENT_EXE} get -n "${NAMESPACE}" kiali "${KIALI_CR_NAME}" &> /dev/null; then
    echo "ERROR! Kiali CR [${KIALI_CR_NAME}] does not exist in namespace [${NAMESPACE}]"
    exit 1
  fi
fi

# Make sure we have admin rights to some cluster
if ! ${CLIENT_EXE} get namespaces &> /dev/null ; then
  echo "ERROR! You must be connected to/logged into a cluster"
  exit 1
fi
if [ "$(${CLIENT_EXE} auth can-i create crd --all-namespaces)" != "yes" ]; then
  echo "ERROR! You must have cluster-admin permissions"
  exit 1
fi

# install the test CRD with the schema
if [ -n "${KIALI_CRD_LOCATION:-}" ]; then
  if ! ${CLIENT_EXE} apply --validate=true --wait=true -f "${KIALI_CRD_LOCATION}" &> /dev/null ; then
    echo "ERROR! Failed to install the test CRD from [${KIALI_CRD_LOCATION}]"
    exit 1
  fi
else
  if ! echo "$(crd)" | ${CLIENT_EXE} apply --validate=true --wait=true -f - &> /dev/null ; then
    echo "ERROR! Failed to install the test CRD"
    exit 1
  fi
fi

# wait for the test CRD to be established and then give k8s a few more seconds.
# if we don't do this, the validation test may report a false negative.
if ! ${CLIENT_EXE} wait --for condition=established --timeout=60s crd/testkialis.kiali.io &> /dev/null ; then
  echo "WARNING! Test CRD is not established yet. The validation test may not produce accurate results."
else
  for s in 3 2 1; do echo -n "." ; sleep 1 ; done
  echo
fi

# validate the CR by creating a test version of it
echo "Validating the CR:"
echo "----------"
if [ -n "${KIALI_CR_FILE:-}" ]; then
  if ! cat "${KIALI_CR_FILE}" | sed 's/kind: Kiali/kind: TestKiali/g' | sed 's/- kiali.io\/finalizer//g' | kubectl apply -n ${NAMESPACE} -f - ; then
    echo "----------"
    echo "ERROR! Validation failed for Kiali CR [${KIALI_CR_FILE}]"
  else
    echo "----------"
    echo "Kiali CR [${KIALI_CR_FILE}] is valid."
  fi
else
  if ! ${CLIENT_EXE} get -n "${NAMESPACE}" kiali "${KIALI_CR_NAME}" -o yaml | sed 's/kind: Kiali/kind: TestKiali/g' | sed 's/- kiali.io\/finalizer//g' | kubectl apply -n "${NAMESPACE}" -f - ; then
    echo "----------"
    echo "ERROR! Validation failed for Kiali CR [${KIALI_CR_NAME}] in namespace [${NAMESPACE}]"
  else
    echo "----------"
    echo "Kiali CR [${KIALI_CR_NAME}] in namespace [${NAMESPACE}] is valid."
  fi
fi

# delete the test CRD (which deletes the test CR along with it)
if [ -n "${KIALI_CRD_LOCATION:-}" ]; then
  if ! ${CLIENT_EXE} delete --wait=true -f "${KIALI_CRD_LOCATION}" &> /dev/null ; then
    echo "ERROR! Failed to delete the test CRD [${KIALI_CRD_LOCATION}]. You should remove it manually."
  fi
else
  if ! echo "$(crd)" | ${CLIENT_EXE} delete --wait=true -f - &> /dev/null ; then
    echo "ERROR! Failed to delete the test CRD"
    exit 1
  fi
fi
