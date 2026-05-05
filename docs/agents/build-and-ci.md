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

`build/Dockerfile` layers on top of the `ansible-operator` base image. It installs git (needed for collection installs from GitHub), jmespath (needed for Ansible's `json_query` filter), then copies in `roles/`, `playbooks/`, `watches-*.yaml`, and `requirements.yml`, and runs `ansible-galaxy collection install` so the collections are baked into the image.

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
3. **`verify-kiali-server-permissions`** — `hack/verify-kiali-server-permissions.sh` diffs the ClusterRole definitions in the operator's manifests against the Kiali server's expected permissions
4. **`verify-defaults`** — `hack/verify-crd-defaults.sh` checks CRD `default:` values against `roles/default/kiali-deploy/defaults/main.yml`
5. **kiali-ossm bundle**: `envsubst` populates the CSV template, `opm render` validates the bundle
6. **kiali-upstream bundle**: finds latest version dir, `opm render` validates

All checks must pass before publishing an operator release.

## Deploying the Operator

`deploy/deploy-kiali-operator.sh` is a convenience wrapper around the Kiali operator Helm Chart for manual deployments. It auto-downloads Helm if not in PATH and wraps the most common install options.

Key environment variables controlling the deploy script:

| Variable | Default | Purpose |
|----------|---------|---------|
| `DRY_RUN` | `false` | Perform a Helm dry-run only |
| `HELM_CHART` | — | Path to a `.tgz` chart; set to `source` to build from source |
| `HELM_REPO_CHART_VERSION` | `lastrelease` | Version from `https://kiali.org/helm-charts` |
| `OPERATOR_CLUSTER_ROLE_CREATOR` | `false` | Grant operator permission to create ClusterRoles |
| `OPERATOR_NAMESPACE` | `kiali-operator` | Namespace to install the operator into |
| `OPERATOR_IMAGE_NAME` | `quay.io/kiali/kiali-operator` | Operator image |
| `OPERATOR_VERSION` | `lastrelease` | Operator image tag |

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

# Run molecule tests against a live cluster
export KUBECONFIG=/path/to/kubeconfig
export MOLECULE_KIALI_OPERATOR_IMAGE_NAME=quay.io/myorg/kiali-operator
export MOLECULE_KIALI_OPERATOR_IMAGE_VERSION=my-dev-build
cd molecule && pip install -r requirements.txt
molecule test -s default
```

See [DEVELOPING.adoc](../DEVELOPING.adoc) for the full developer workflow, including how to run the operator locally (outside a container) for faster iteration.
