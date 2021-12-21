#!/bin/bash

##############################################################################
# validate-kiali-cr.sh
#
# This script can be used to validate a Kiali CR.
#
# To use this script, either "oc" or "kubectl" must be in your PATH and
# you must be connected to the cluster where the Kiali CR is located
# and you must have cluster-admin rights.
#
# This script maintains a CRD with a schema that it will use for validation.
#
##############################################################################

########## START CRD DEFINITION ##########

crd() {
cat << EOF
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: testkialis.kiali.io
spec:
  group: kiali.io
  names:
    kind: TestKiali
    listKind: TestKialiList
    plural: testkialis
    singular: testkiali
  scope: Namespaced
  versions:
  - name: v1alpha1
    served: true
    storage: true
    subresources:
      status: {}
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              additional_display_details:
                type: array
                items:
                  required: ["title", "annotation"]
                  type: object
                  properties:
                    title:
                      type: string
                    annotation:
                      type: string
                    icon_annotation:
                      type: string

              installation_tag:
                type: string

              istio_namespace:
                type: string

              version:
                type: string

              api:
                type: object
                properties:
                  namespaces:
                    type: object
                    properties:
                      exclude:
                        type: array
                        items:
                          type: string
                      label_selector:
                        type: string

              auth:
                type: object
                properties:
                  strategy:
                    type: string
                  openid:
                    type: object
                    properties:
                      additional_request_params:
                        type: object
                        x-kubernetes-preserve-unknown-fields: true
                      allowed_domains:
                        type: array
                        items:
                          type: string
                      api_proxy:
                        type: string
                      api_proxy_ca_data:
                        type: string
                      api_token:
                        type: string
                      authentication_timeout:
                        type: integer
                      authorization_endpoint:
                        type: string
                      client_id:
                        type: string
                      disable_rbac:
                        type: boolean
                      http_proxy:
                        type: string
                      https_proxy:
                        type: string
                      insecure_skip_verify_tls:
                        type: boolean
                      issuer_uri:
                        type: string
                      scopes:
                        type: array
                        items:
                          type: string
                      username_claim:
                        type: string
                  openshift:
                    type: object
                    properties:
                      client_id_prefix:
                        type: string

              custom_dashboards:
                type: array
                items:
                  type: object
                  x-kubernetes-preserve-unknown-fields: true

              deployment:
                type: object
                properties:
                  accessible_namespaces:
                    type: array
                    items:
                      type: string
                  additional_service_yaml:
                    type: object
                    x-kubernetes-preserve-unknown-fields: true
                  affinity:
                    type: object
                    properties:
                      node:
                        type: object
                        x-kubernetes-preserve-unknown-fields: true
                      pod:
                        type: object
                        x-kubernetes-preserve-unknown-fields: true
                      pod_anti:
                        type: object
                        x-kubernetes-preserve-unknown-fields: true
                  custom_secrets:
                    type: array
                    items:
                      type: object
                      properties:
                        name:
                          type: string
                        mount:
                          type: string
                        optional:
                          type: boolean
                  hpa:
                    type: object
                    properties:
                      api_version:
                        type: string
                      spec:
                        type: object
                        x-kubernetes-preserve-unknown-fields: true
                  host_aliases:
                    type: array
                    items:
                      type: object
                      properties:
                        ip:
                          type: string
                        hostnames:
                          type: array
                          items:
                            type: string
                  image_digest:
                    type: string
                  image_name:
                    type: string
                  image_pull_policy:
                    type: string
                  image_pull_secrets:
                    type: array
                    items:
                      type: string
                  image_version:
                    type: string
                  ingress:
                    type: object
                    properties:
                      additional_labels:
                        type: object
                        x-kubernetes-preserve-unknown-fields: true
                      class_name:
                        type: string
                      enabled:
                        type: boolean
                      override_yaml:
                        type: object
                        properties:
                          metadata:
                            type: object
                            properties:
                              annotations:
                                type: object
                                x-kubernetes-preserve-unknown-fields: true
                          spec:
                            type: object
                            x-kubernetes-preserve-unknown-fields: true
                  instance_name:
                    type: string
                  logger:
                    type: object
                    properties:
                      log_level:
                        type: string
                      log_format:
                        type: string
                      sampler_rate:
                        type: string
                      time_field_format:
                        type: string
                  namespace:
                    type: string
                  node_selector:
                    type: object
                    x-kubernetes-preserve-unknown-fields: true
                  pod_annotations:
                    type: object
                    x-kubernetes-preserve-unknown-fields: true
                  pod_labels:
                    type: object
                    x-kubernetes-preserve-unknown-fields: true
                  priority_class_name:
                    type: string
                  replicas:
                    type: integer
                  resources:
                    type: object
                    x-kubernetes-preserve-unknown-fields: true
                  secret_name:
                    type: string
                  service_annotations:
                    type: object
                    x-kubernetes-preserve-unknown-fields: true
                  service_type:
                    type: string
                  tolerations:
                    type: array
                    items:
                      type: object
                      x-kubernetes-preserve-unknown-fields: true
                  verbose_mode:
                    type: string
                  version_label:
                    type: string
                  view_only_mode:
                    type: boolean

              extensions:
                type: object
                properties:
                  iter_8:
                    type: object
                    properties:
                      enabled:
                        type: boolean

              external_services:
                type: object
                properties:
                  custom_dashboards:
                    type: object
                    properties:
                      discovery_auto_threshold:
                        type: integer
                      discovery_enabled:
                        type: string
                      enabled:
                        type: boolean
                      is_core:
                        type: boolean
                      namespace_label:
                        type: string
                      prometheus:
                        type: object
                        properties:
                          auth:
                            type: object
                            properties:
                              ca_file:
                                type: string
                              insecure_skip_verify:
                                type: boolean
                              password:
                                type: string
                              token:
                                type: string
                              type:
                                type: string
                              use_kiali_token:
                                type: boolean
                              username:
                                type: string
                          cache_duration:
                            type: integer
                          cache_enabled:
                            type: boolean
                          cache_expiration:
                            type: integer
                          custom_headers:
                            type: object
                            x-kubernetes-preserve-unknown-fields: true
                          health_check_url:
                            type: string
                          is_core:
                            type: boolean
                          thanos_proxy:
                            type: object
                            properties:
                              enabled:
                                type: boolean
                              retention_period:
                                type: string
                              scrape_interval:
                                type: string
                          url:
                            type: string
                  grafana:
                    type: object
                    properties:
                      auth:
                        type: object
                        properties:
                          ca_file:
                            type: string
                          insecure_skip_verify:
                            type: boolean
                          password:
                            type: string
                          token:
                            type: string
                          type:
                            type: string
                          use_kiali_token:
                            type: boolean
                          username:
                            type: string
                      dashboards:
                        type: array
                        items:
                          type: object
                          properties:
                            name:
                              type: string
                            variables:
                              type: object
                              x-kubernetes-preserve-unknown-fields: true
                      enabled:
                        type: boolean
                      health_check_url:
                        type: string
                      in_cluster_url:
                        type: string
                      is_core:
                        type: boolean
                      url:
                        type: string
                  istio:
                    type: object
                    properties:
                      component_status:
                        type: object
                        properties:
                          components:
                            type: array
                            items:
                              type: object
                              properties:
                                app_label:
                                  type: string
                                is_core:
                                  type: boolean
                                is_proxy:
                                  type: boolean
                                namespace:
                                  type: string
                          enabled:
                            type: boolean
                      config_map_name:
                        type: string
                      envoy_admin_local_port:
                        type: integer
                      istio_canary_revision:
                        type: object
                        properties:
                          current:
                            type: string
                          upgrade:
                            type: string
                      istio_identity_domain:
                        type: string
                      istio_injection_annotation:
                        type: string
                      istio_sidecar_annotation:
                        type: string
                      istio_sidecar_injector_config_map_name:
                        type: string
                      istiod_deployment_name:
                        type: string
                      istiod_pod_monitoring_port:
                        type: integer
                      root_namespace:
                        type: string
                      url_service_version:
                        type: string
                  prometheus:
                    type: object
                    properties:
                      auth:
                        type: object
                        properties:
                          ca_file:
                            type: string
                          insecure_skip_verify:
                            type: boolean
                          password:
                            type: string
                          token:
                            type: string
                          type:
                            type: string
                          use_kiali_token:
                            type: boolean
                          username:
                            type: string
                      cache_duration:
                        type: integer
                      cache_enabled:
                        type: boolean
                      cache_expiration:
                        type: integer
                      custom_headers:
                        type: object
                        x-kubernetes-preserve-unknown-fields: true
                      health_check_url:
                        type: string
                      is_core:
                        type: boolean
                      thanos_proxy:
                        type: object
                        properties:
                          enabled:
                            type: boolean
                          retention_period:
                            type: string
                          scrape_interval:
                            type: string
                      url:
                        type: string
                  tracing:
                    type: object
                    properties:
                      auth:
                        type: object
                        properties:
                          ca_file:
                            type: string
                          insecure_skip_verify:
                            type: boolean
                          password:
                            type: string
                          token:
                            type: string
                          type:
                            type: string
                          use_kiali_token:
                            type: boolean
                          username:
                            type: string
                      enabled:
                        type: boolean
                      in_cluster_url:
                        type: string
                      is_core:
                        type: boolean
                      namespace_selector:
                        type: boolean
                      url:
                        type: string
                      use_grpc:
                        type: boolean
                      whitelist_istio_system:
                        type: array
                        items:
                          type: string

              health_config:
                type: object
                properties:
                  rate:
                    type: array
                    items:
                      type: object
                      properties:
                        namespace:
                          type: string
                        kind:
                          type: string
                        name:
                          type: string
                        tolerations:
                          type: array
                          items:
                            type: object
                            properties:
                              protocol:
                                type: string
                              direction:
                                type: string
                              code:
                                type: string
                              degraded:
                                type: string
                              failure:
                                type: string

              identity:
                type: object
                properties:
                  cert_file:
                    type: string
                  private_key_file:
                    type: string

              istio_labels:
                type: object
                properties:
                  app_label_name:
                    type: string
                  injection_label_name:
                    type: string
                  injection_label_rev:
                    type: string
                  version_label_name:
                    type: string

              kiali_feature_flags:
                type: object
                properties:
                  certificates_information_indicators:
                    type: object
                    properties:
                      enabled:
                        type: boolean
                      secrets:
                        type: array
                        items:
                          type: string
                  clustering:
                    type: object
                    properties:
                      enabled:
                        type: boolean
                  istio_injection_action:
                    type: boolean
                  istio_upgrade_action:
                    type: boolean
                  ui_defaults:
                    type: object
                    properties:
                      graph:
                        type: object
                        properties:
                          find_options:
                            type: array
                            items:
                              type: object
                              properties:
                                description:
                                  type: string
                                expression:
                                  type: string
                          hide_options:
                            type: array
                            items:
                              type: object
                              properties:
                                description:
                                  type: string
                                expression:
                                  type: string
                          traffic:
                            type: object
                            properties:
                              grpc:
                                type: string
                              http:
                                type: string
                              tcp:
                                type: string
                      metrics_per_refresh:
                        type: string
                      metrics_inbound:
                        type: object
                        properties:
                          aggregations:
                            type: array
                            items:
                              type: object
                              properties:
                                display_name:
                                  type: string
                                label:
                                  type: string
                      metrics_outbound:
                        type: object
                        properties:
                          aggregations:
                            type: array
                            items:
                              type: object
                              properties:
                                display_name:
                                  type: string
                                label:
                                  type: string
                      namespaces:
                        type: array
                        items:
                          type: string
                      refresh_interval:
                        type: string
                      validations:
                        type: object
                        properties:
                          ignore:
                            type: array
                            items:
                              type: string

              kubernetes_config:
                type: object
                properties:
                  burst:
                    type: integer
                  cache_duration:
                    type: integer
                  cache_enabled:
                    type: boolean
                  cache_istio_types:
                    type: array
                    items:
                      type: string
                  cache_namespaces:
                    type: array
                    items:
                      type: string
                  cache_token_namespace_duration:
                    type: integer
                  excluded_workloads:
                    type: array
                    items:
                      type: string
                  qps:
                    type: integer

              login_token:
                type: object
                properties:
                  expiration_seconds:
                    type: integer
                  signing_key:
                    type: string

              server:
                type: object
                properties:
                  address:
                    type: string
                  audit_log:
                    type: boolean
                  cors_allow_all:
                    type: boolean
                  gzip_enabled:
                    type: boolean
                  metrics_enabled:
                    type: boolean
                  metrics_port:
                    type: integer
                  port:
                    type: integer
                  web_fqdn:
                    type: string
                  web_history_mode:
                    type: string
                  web_port:
                    type: string
                  web_root:
                    type: string
                  web_schema:
                    type: string
EOF
}

########## START SCRIPT ##########

set -u

# process command line args to override environment
_CMD=""
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -crd|--crd-location)   KIALI_CRD_LOCATION="$2"   ; shift;shift ;;
    -kcf|--kiali-cr-file)  KIALI_CR_FILE="$2"        ; shift;shift ;;
    -kcn|--kiali-cr-name)  KIALI_CR_NAME="$2"        ; shift;shift ;;
    -n|--namespace)        NAMESPACE="$2"            ; shift;shift ;;
    -pc|--print-crd)       PRINT_CRD="$2"            ; shift;shift ;;
    -h|--help)
      cat <<HELPMSG

$0 [option...]

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

echo "Validating ..."

# install the test CRD with the schema
if [ -n "${KIALI_CRD_LOCATION:-}" ]; then
  if ! ${CLIENT_EXE} apply --wait=true -f "${KIALI_CRD_LOCATION}" &> /dev/null ; then
    echo "ERROR! Failed to install the test CRD from [${KIALI_CRD_LOCATION}]"
    exit 1
  fi
else
  if ! echo "$(crd)" | ${CLIENT_EXE} apply --wait=true -f - &> /dev/null ; then
    echo "ERROR! Failed to install the test CRD"
    exit 1
  fi
fi

# validate the CR by creating a test version of it
if [ -n "${KIALI_CR_FILE:-}" ]; then
  if ! cat "${KIALI_CR_FILE}" | sed 's/kind: Kiali/kind: TestKiali/g' | kubectl apply -n ${NAMESPACE} -f - ; then
    echo "ERROR! Validation failed for Kiali CR [${KIALI_CR_FILE}]"
  else
    echo "Kiali CR [${KIALI_CR_FILE}] is valid."
  fi
else
  if ! ${CLIENT_EXE} get -n "${NAMESPACE}" kiali "${KIALI_CR_NAME}" -o yaml | sed 's/kind: Kiali/kind: TestKiali/g' | kubectl apply -n "${NAMESPACE}" -f - ; then
    echo "ERROR! Validation failed for Kiali CR [${KIALI_CR_NAME}] in namespace [${NAMESPACE}]"
  else
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
