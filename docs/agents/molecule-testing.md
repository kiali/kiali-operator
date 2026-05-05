---
scribe:
  scan: "HEAD"
  freshness: 65
  human_input: 1
  completeness: 65
  inferred_sections:
    - id: "s1"
      heading: "Overview"
    - id: "s2"
      heading: "Test Scenarios"
    - id: "s3"
      heading: "Scenario Structure"
    - id: "s4"
      heading: "Common Infrastructure"
    - id: "s5"
      heading: "Shared Asserts"
    - id: "s6"
      heading: "Environment Variables"
    - id: "s7"
      heading: "Running Tests"
  watch_paths:
    - molecule/
  stale_flags: []
---

# Molecule Test Suite

> TL;DR: The `molecule/` directory holds integration test scenarios that run against a live Kubernetes/OpenShift cluster; each scenario installs the operator, applies a Kiali CR, asserts on resulting cluster state, and tears down — with shared `common/` tasks and `asserts/` playbooks for reuse.

## Overview

[Molecule](https://github.com/ansible-community/molecule) is the test framework used to integration-test the Kiali operator. Tests are **not unit tests** — they require a running cluster (Kubernetes or OpenShift) with Istio installed, and they exercise the full operator reconciliation loop.

Each scenario:
1. **Prepares** — installs the operator via Helm or OLM (configurable)
2. **Converges** — applies a Kiali CR and waits for Kiali to become ready
3. **Verifies** — asserts on ConfigMap contents, pod state, RBAC resources, etc.
4. **Destroys** — removes the CR and operator, cleans up cluster state

The test framework is configured for the driver selected by `$DORP` (docker or podman), but actual cluster interaction uses `kubernetes.core` Ansible modules against a remote cluster.

## Test Scenarios

| Scenario | What it tests |
|----------|--------------|
| `default` | Basic install with `cluster_wide_access: true`, anonymous auth |
| `accessible-namespaces-test` | Namespace discovery via discovery selectors; label management |
| `affinity-tolerations-resources-test` | Pod affinity, tolerations, and resource limits/requests |
| `cluster-wide-access-test` | CWA=true vs CWA=false RBAC mode transitions |
| `config-values-test` | Various CR spec values produce correct ConfigMap entries |
| `containers-test` | Additional pod containers and initContainers with security guardrails |
| `default-namespace-test` | Installing Kiali in the same namespace as the CR |
| `external-auth-rotation-test` | External auth secret rotation triggers reconciliation |
| `grafana-test` | Grafana integration settings propagated correctly |
| `header-auth-test` | Header-based authentication strategy |
| `instance-name-test` | Custom `deployment.instance_name` values |
| `jaeger-test` | Jaeger/Tempo tracing integration settings |
| `metrics-test` | Kiali metrics endpoint configuration |
| `null-cr-values-test` | Null/empty CR spec values fall back to defaults |
| `only-view-only-mode-test` | `deployment.view_only_mode: true` produces viewer-only RBAC |
| `openid-test` | OpenID Connect auth strategy (Kubernetes) |
| `openid-openshift-test` | OpenID Connect auth strategy on OpenShift |
| `os-console-links-test` | OpenShift ConsoleLink resources created correctly |
| `remote-cluster-resources-test` | `remote_cluster_resources_only: true` mode |
| `roles-test` | Per-namespace Role/RoleBinding creation |
| `rolling-restart-test` | ConfigMap changes trigger rolling restart of Kiali pod |
| `tls-profile-test` | TLS configuration and certificate handling |
| `token-test` | Token-based auth strategy |
| `ossmconsole-*` | OSSMConsole CR deploy/remove on OpenShift |

## Scenario Structure

Each scenario follows a standard Molecule directory layout:

```
molecule/<scenario>/
  molecule.yml      # Driver config, test sequence, group_vars
  converge.yml      # Apply CR and run operator (main test body)
  prepare-*.yml     # Optional: cluster setup before converge (e.g., create namespaces)
  destroy-*.yml     # Optional: scenario-specific cleanup
  kiali-cr.yaml     # The Kiali CR to apply in this scenario
```

The `molecule.yml` defines:
- `driver.name: $DORP` — container runtime (docker or podman)
- `provisioner.playbooks` — maps phases to playbooks in `molecule/default/` (shared destroy/prepare/cleanup)
- `scenario.test_sequence: [prepare, converge, destroy]`
- `group_vars.all` — default values for scenario variables

## Common Infrastructure

`molecule/common/` contains reusable task files included by scenarios:

| File | Purpose |
|------|---------|
| `tasks.yml` | Collects CR, ConfigMap, Pod, and Deployment state into facts |
| `manage-operator.yml` | Installs/patches the operator deployment with env vars, waits for readiness |
| `manage-operator-olm.yml` | Operator install via OLM SubscriptionObject |
| `wait_for_kiali_running.yml` | Polls until Kiali pod is running and CR status is `Successful` |
| `wait_for_kiali_cr_changes.yml` | Waits for CR reconciliation to complete after a spec change |
| `set_kiali_cr.yml` | Applies a Kiali CR patch |
| `set_auth_strategy.yml` | Changes the auth strategy in the running CR |
| `set_view_only_mode.yml` / `unset_view_only_mode.yml` | Toggles view-only mode |
| `cluster-info.yml` | Detects OpenShift vs Kubernetes, sets `is_openshift` fact |
| `set_discovery_selectors_to_all.yml` | Sets discovery selectors to match all namespaces |
| `set_discovery_selectors_to_list.yml` | Sets discovery selectors to a specific namespace list |
| `purge-prometheus-data.yml` | Clears Prometheus data between test phases |
| `query-prometheus.yml` | Queries Prometheus for metric assertions |

## Shared Asserts

`molecule/asserts/` contains assertion playbooks reused across scenarios:

| File | Asserts |
|------|---------|
| `pod_asserts.yml` | Kiali pod is Running, has correct image, security context |
| `configmap_asserts.yml` | Kiali ConfigMap has expected keys and values |
| `accessible_namespaces_contains.yml` | Discovery-resolved namespaces match expected list |
| `assert-api-namespaces-result.yml` | Kiali API returns expected namespace list |

## Environment Variables

Molecule tests are controlled entirely by environment variables — no test code changes needed to switch configurations:

| Variable | Default | Purpose |
|----------|---------|---------|
| `DORP` | `docker` | Container runtime (`docker` or `podman`) |
| `MOLECULE_OPERATOR_INSTALLER` | `helm` | How to install the operator: `helm`, `olm`, `skip` |
| `MOLECULE_KIALI_OPERATOR_IMAGE_NAME` | `quay.io/kiali/kiali-operator` | Operator image; set to `dev` to use in-cluster registry |
| `MOLECULE_KIALI_OPERATOR_IMAGE_VERSION` | `latest` | Operator image tag |
| `MOLECULE_KIALI_IMAGE_NAME` | `quay.io/kiali/kiali` | Kiali server image |
| `MOLECULE_KIALI_IMAGE_VERSION` | `latest` | Kiali server image tag |
| `MOLECULE_KIALI_CR_SPEC_VERSION` | `default` | `spec.version` to set in the CR |
| `MOLECULE_WAIT_RETRIES` | `360` | Number of polling retries when waiting for readiness |
| `ALLOW_AD_HOC_KIALI_NAMESPACE` | `false` | Allow CR namespace ≠ install namespace |
| `ALLOW_AD_HOC_KIALI_IMAGE` | `false` | Allow custom image in CR |
| `ALLOW_ALL_ACCESSIBLE_NAMESPACES` | `false` | Allow `cluster_wide_access: true` |

## Running Tests

Molecule tests **must be run from the `kiali/kiali` parent repo** (`~/source/kiali/kiali`), not from this repo. The `hack/run-molecule-tests.sh` script there handles building the driver container, mounting the operator repo, and injecting the kubeconfig. Running `molecule` directly is not supported.

**Prerequisites:** a running cluster (minikube, KinD, or OpenShift) with Istio installed, and no existing Kiali deployment.

### Minikube

```bash
export CLUSTER_TYPE=minikube
export MINIKUBE_PROFILE=ci
export DORP=podman
export CLIENT_EXE=kubectl

# Start cluster with Hydra (required for some tests)
./hack/k8s-minikube.sh --hydra-enabled true -mp ci start
./hack/istio/install-istio-via-istioctl.sh --client-exe ${CLIENT_EXE}

# Build and push dev images (if testing local changes)
make CLUSTER_TYPE=minikube MINIKUBE_PROFILE=ci build-ui build test cluster-push

# Run tests (-udi true = use dev images, -hcrp false = skip helm-charts pull, -at = which tests)
./hack/run-molecule-tests.sh \
  --client-exe "$(which kubectl)" \
  --cluster-type minikube \
  --minikube-profile ci \
  -udi true \
  -hcrp false \
  -at "token-test"
```

### KinD

```bash
export CLUSTER_TYPE=kind
export KIND_NAME=ci
export DORP=docker
export CLIENT_EXE=kubectl

./hack/start-kind.sh --name ${KIND_NAME} --enable-hydra true
./hack/istio/install-istio-via-istioctl.sh --client-exe ${CLIENT_EXE}
make CLUSTER_TYPE=kind KIND_NAME=ci build-ui build test cluster-push

./hack/run-molecule-tests.sh \
  --client-exe "$(which kubectl)" \
  --cluster-type kind \
  -udi true \
  -hcrp false \
  -at "token-test"
```

### OpenShift

```bash
export CLUSTER_TYPE=openshift
export DORP=podman
export CLIENT_EXE=oc

./hack/crc-openshift.sh start
./hack/istio/install-istio-via-istioctl.sh -c ${CLIENT_EXE}
make CLUSTER_TYPE=openshift build-ui build test cluster-push

./hack/run-molecule-tests.sh \
  --client-exe "$(which oc)" \
  --cluster-type openshift \
  -udi true \
  -hcrp false \
  -at "token-test"
```

### Key flags for `run-molecule-tests.sh`

| Flag | Purpose |
|------|---------|
| `-at` / `--all-tests` | Scenario name(s) to run (space-separated) |
| `-udi` / (implied) `--use-dev-images` | `true` = use locally pushed dev builds; `false` = use latest quay.io images |
| `-hcrp` / `--helm-charts-repo-pull` | `false` if your local helm-charts branch has no remote (avoids git pull errors) |
| `--cluster-type` | `minikube`, `kind`, or `openshift` |
| `--minikube-profile` | Minikube profile name (minikube only) |
| `-nd` / `--never-destroy` | Keep cluster resources after failure for debugging |
| `-d` / `--debug` | Enable Ansible debug output |

Under the hood the script runs tests inside a Podman container built from `molecule/docker/Dockerfile` in this repo — that image extends `quay.io/ansible/creator-ee` with jmespath, the `kubernetes` Python library, the Ansible collections from `requirements.yml`, and Helm. The operator repo is mounted into the container; KUBECONFIG is injected as a volume.
