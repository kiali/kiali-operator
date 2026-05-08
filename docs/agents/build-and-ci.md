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
      heading: "Dockerfile"
    - id: "s3"
      heading: "Makefile Targets"
    - id: "s4"
      heading: "Multi-Arch Builds"
    - id: "s5"
      heading: "OPM Tooling"
    - id: "s6"
      heading: "Validation Pipeline"
    - id: "s7"
      heading: "Deploying the Operator"
    - id: "s8"
      heading: "Local Development Setup"
  watch_paths:
    - Makefile
    - build/
    - hack/verify-kiali-server-permissions.sh
    - deploy/deploy-kiali-operator.sh
    - requirements.yml
    - dev-playbook-config/
  stale_flags: []
---

# Build & CI

> TL;DR: The operator image is built from `build/Dockerfile` on top of the `ansible-operator` base image; `make build` / `make push` handle single-arch builds while `make container-multi-arch-push-kiali-operator-quay` uses `docker buildx` for multi-arch (amd64/arm64/s390x/ppc64le) publishing to Quay.io.

## Overview

The kiali-operator build is intentionally minimal — no Go compilation, no test runners in the Makefile (those are in the parent `kiali/kiali` repo). The Makefile's primary jobs are:
1. Build and push the operator container image
2. Validate OLM bundle manifests and CRD correctness
3. Generate CRD documentation

The operator image is derived from the Operator Framework's `ansible-operator` base image, which provides the SDK runtime, Python, Ansible, and the kubernetes.core collection pre-installed.

## Dockerfile

`build/Dockerfile` layers on top of the `ansible-operator` base image. It: removes `subscription-manager` and `python3-subscription-manager-rhsm` (a required workaround for an operator-sdk conflict); runs a full `yum update` for security patching; installs git (needed for collection installs from GitHub) and jmespath (needed for Ansible's `json_query` filter); copies in `roles/`, `playbooks/`, `watches-*.yaml`, and `requirements.yml`; runs `ansible-galaxy collection install` so the collections are baked into the image; and creates an opt-in Ansible task profiler config at `${HOME}/ansible-profiler.cfg` (the standard config with `callbacks_enabled = profile_tasks` appended).

Build args `OPERATOR_BASE_IMAGE_REPO` and `OPERATOR_BASE_IMAGE_VERSION` select the base image; their defaults are set in the Makefile. Collections are installed from the GitHub source refs pinned in `requirements.yml` rather than from Galaxy to avoid outage dependencies.

## Makefile Targets

| Target | Description |
|--------|-------------|
| `build` | Build the operator image locally using docker or podman |
| `push` | Push the image to `quay.io/kiali/kiali-operator:<version>` |
| `validate` | Run the full validation pipeline (OLM bundles, CRDs, permissions) |
| `validate-cr` | Validate example CRs against their CRD schemas |
| `validate-crd-sync` | Check all CRD copies match the golden copies in `crd-docs/` |
| `verify-defaults` | Verify CRD defaults match Ansible role defaults |
| `verify-crd-compatibility` | Check for backward-incompatible CRD schema changes |
| `verify-kiali-server-permissions` | Verify operator RBAC matches Kiali Server needs |
| `sync-crds` | Propagate CRDs from `crd-docs/crd/` to all bundle locations |
| `gen-crd-doc` | Generate HTML CRD documentation using the crd-docs-generator container |
| `get-opm` | Download the `opm` CLI binary if not already in PATH |
| `container-multi-arch-push-kiali-operator-quay` | Build and push multi-arch image via docker buildx |
| `clean` | Remove the `_output/` directory |

### Key variables

| Variable | Default | Override |
|----------|---------|---------|
| `VERSION` | `v2.26.0-SNAPSHOT` | `make build VERSION=v2.26.0` |
| `DORP` | `docker` | `make build DORP=podman` |
| `OPERATOR_IMAGE_ORG` | `kiali` | Change image org |
| `OPERATOR_BASE_IMAGE_VERSION` | `v1.37.2` | Pin base image version |
| `TARGET_ARCHS` | `amd64 arm64 s390x ppc64le` | Multi-arch targets |

## Multi-Arch Builds

For official releases, the operator image is published as a multi-architecture manifest using `docker buildx`:

```bash
make container-multi-arch-push-kiali-operator-quay
```

This target:
1. Ensures `docker buildx` is installed (min version 0.4.2) — downloads if missing
2. Creates a `kiali-builder` buildx builder instance using `moby/buildkit:v0.13.2`
3. On Linux, installs QEMU via `tonistiigi/binfmt` for cross-compilation
4. Runs `docker buildx build --push --platform linux/amd64,linux/arm64,linux/s390x,linux/ppc64le`

The multi-arch push writes to `quay.io/kiali/kiali-operator:<version>` as a Docker manifest list.

## OPM Tooling

Several `make validate` sub-targets use the `opm` (Operator Package Manager) CLI to validate OLM bundle structure. The Makefile auto-downloads `opm` if not in PATH:

```bash
make get-opm
# Downloads to _output/opm-install/opm
```

The version is auto-discovered from the GitHub API (`operator-framework/operator-registry/releases/latest`) with a fallback of `v1.56.0` if the API is unreachable. Override with:

```bash
make validate OPM_VERSION=v1.50.0
```

`opm render <bundle-dir> --output yaml` is used to validate that a bundle's manifests are syntactically valid and can be ingested by OLM's catalog machinery.

## Validation Pipeline

`make validate` orchestrates these checks in order:

1. **`validate-crd-sync`** — all CRD copies match golden copies in `crd-docs/crd/`
2. **`verify-crd-compatibility`** — no breaking CRD schema changes vs `origin/master`
3. **`verify-kiali-server-permissions`** — `hack/verify-kiali-server-permissions.sh` unions Kiali Server role permissions from the operator's role templates and compares them against the operator's own distribution manifests (OSSM CSV, latest upstream CSV, and the helm chart if present), ensuring the operator has the necessary permissions to create Kiali Server roles
4. **`verify-defaults`** — `hack/verify-crd-defaults.sh` checks CRD `default:` values against both `roles/default/kiali-deploy/defaults/main.yml` (Kiali CRD) and `roles/default/ossmconsole-deploy/defaults/main.yml` (OSSMConsole CRD)
5. **kiali-ossm bundle**: `envsubst` populates the CSV template, `opm render` validates the bundle
6. **kiali-upstream bundle**: finds latest version dir, `opm render` validates

All checks must pass before publishing an operator release.

**Note:** `make validate-cr` (validates example CRs against the CRD schema) is a **separate target** not invoked by `make validate`. Run it explicitly when modifying the CRD schema or example CRs in `crd-docs/cr/`.

## Deploying the Operator

`deploy/deploy-kiali-operator.sh` is a convenience wrapper around the Kiali operator Helm Chart for manual deployments. It auto-downloads Helm if not in PATH and wraps the most common install options.

The script documents ~20 environment variables in its header block. Key ones:

| Variable | Default | Purpose |
|----------|---------|---------|
| `DRY_RUN` | `false` | Perform a Helm dry-run only |
| `HELM` | auto-detected | Path to the `helm` binary |
| `HELM_CHART` | — | Path to a `.tgz` chart; set to `source` to build from source |
| `HELM_REPO_CHART_VERSION` | `lastrelease` | Version from `https://kiali.org/helm-charts` |
| `OPERATOR_CLUSTER_ROLE_CREATOR` | `false` | Grant operator permission to create ClusterRoles. **Auto-set to `true`** when `CLUSTER_WIDE_ACCESS=true` and `OPERATOR_INSTALL_KIALI=true` — so the default run (both true) implicitly grants this permission. |
| `OPERATOR_NAMESPACE` | `kiali-operator` | Namespace to install the operator into |
| `OPERATOR_IMAGE_NAME` | `quay.io/kiali/kiali-operator` | Operator image |
| `OPERATOR_IMAGE_VERSION` | `lastrelease` | Operator image tag |
| `OPERATOR_IMAGE_PULL_POLICY` | `IfNotPresent` | Kubernetes pull policy for the operator pod; forced to `Always` when `OPERATOR_IMAGE_VERSION=latest` |
| `OPERATOR_INSTALL_KIALI` | `true` | If `true`, also installs a Kiali CR immediately after the operator |
| `OPERATOR_VIEW_ONLY_MODE` | `false` | Deploy operator with view-only RBAC only |
| `OPERATOR_WATCH_NAMESPACE` | `""` | Namespace(s) the operator watches for Kiali CRs |
| `CLUSTER_WIDE_ACCESS` | `true` | Whether Kiali gets cluster-wide access |
| `AUTH_STRATEGY` | — | Kiali auth strategy when `OPERATOR_INSTALL_KIALI=true` |
| `NAMESPACE` | `istio-system` | Namespace for the Kiali CR when `OPERATOR_INSTALL_KIALI=true` |

Run `./deploy/deploy-kiali-operator.sh --help` for the full list.

For production installs, prefer using Helm directly or OLM (OperatorHub / Red Hat Catalog).

## Local Development Setup

To work with the operator locally:

```bash
# Install Ansible collections matching the base image
ansible-galaxy collection install -r requirements.yml --force-with-deps

# Build the image
make build VERSION=my-dev-build DORP=podman

# Push to local registry or quay.io
make push VERSION=my-dev-build DORP=podman

# Run molecule tests — must be done from the kiali/kiali parent repo
# See molecule-testing.md for full instructions
```

See [DEVELOPING.adoc](../../DEVELOPING.adoc) for the full developer workflow, including how to run the operator locally (outside a container) for faster iteration.
