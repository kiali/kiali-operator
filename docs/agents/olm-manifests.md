---
scribe:
  scan: "HEAD"
  freshness: 100
  human_input: 1
  completeness: 85
  inferred_sections:
    - id: "s1"
      heading: "Overview"
    - id: "s2"
      heading: "Bundle Variants"
    - id: "s3"
      heading: "Bundle Structure"
    - id: "s4"
      heading: "CSV (ClusterServiceVersion)"
    - id: "s5"
      heading: "Creating a New Version"
    - id: "s6"
      heading: "Bundle Validation"
    - id: "s7"
      heading: "CRD Synchronization"
    - id: "s8"
      heading: "Backward Compatibility Checks"
  watch_paths:
    - manifests/
    - hack/verify-crd-backward-compatibility.sh
    - hack/verify-crd-defaults.sh
  stale_flags: []
---

# OLM Bundle & Manifests

> TL;DR: The `manifests/` directory contains Operator Lifecycle Manager bundles for two distribution channels — `kiali-upstream` (OperatorHub community) and `kiali-ossm` (Red Hat OSSM product) — with versioned ClusterServiceVersion files and shared CRDs propagated from `crd-docs/` golden copies.

## Overview

The Kiali operator is distributed through the Operator Lifecycle Manager (OLM) in two separate flavors. Each has a distinct install target audience, channel configuration, and CSV content, but they share the same underlying CRD files and source logic. They do not share the same operator image reference: upstream CSVs reference `quay.io/kiali/kiali-operator:<version>` while the OSSM CSV uses a templated `${KIALI_OPERATOR}` substituted with the productized image at release time.

Both bundles follow the OLM [bundle format](https://olm.operatorframework.io/docs/tasks/creating-operator-bundle/) (`registry+v1` mediatype) with a `manifests/` and `metadata/` subdirectory inside each bundle.

## Bundle Variants

| Variant | Directory | Package name | Channels | Audience |
|---------|-----------|-------------|---------|----------|
| Community upstream | `manifests/kiali-upstream/` | `kiali` | `alpha`, `stable` | OperatorHub.io, vanilla Kubernetes |
| Red Hat OSSM | `manifests/kiali-ossm/` | `kiali-ossm` | `stable` | OpenShift Container Platform customers |

A third variant (`kiali-community`) is documented in `manifests/README.adoc` as targeting OKD, but its directory is not present in the repo (managed separately).

## Bundle Structure

### kiali-upstream (Community)

Versioned bundles are stored as individual directories:

```
manifests/
  create-new-version.sh                # Script to create a new upstream version dir
  convert-to-bundle.sh                 # One-time migration: package → bundle format
  prepare-community-prs.sh             # Helper to open PRs to community-operators repos
  kiali-upstream/
    1.47.0/
      manifests/
        kiali.crd.yaml                 # Kiali CRD (synced from crd-docs/)
        kiali.v1.47.0.clusterserviceversion.yaml
      metadata/
        annotations.yaml               # OLM channel/mediatype annotations
    ...
    2.26.0/
      manifests/
        kiali.crd.yaml
        kiali.v2.26.0.clusterserviceversion.yaml
      metadata/
        annotations.yaml
    ci.yaml                            # CI-specific overrides
```

The latest version directory is the one with the highest semver; `make validate` automatically finds it via `ls -1 | grep -E "^[0-9]+\.[0-9]+\.[0-9]+$" | sort -V | tail -n 1`. Note that `make sync-crds` only updates the CRD in the **latest** version directory — historical version directories are not rewritten.

### kiali-ossm (Red Hat)

Unlike upstream, the OSSM bundle uses a **single non-versioned directory** whose CSV contains `${KIALI_OPERATOR}`, `${KIALI_OPERATOR_VERSION}`, and `${CREATED_AT}` environment variable placeholders. These are substituted at release time using `envsubst` during the OLM validation step in `make validate`.

```
manifests/kiali-ossm/
  manifests/
    kiali.clusterserviceversion.yaml   # Template CSV with ${VAR} placeholders
    kiali.crd.yaml                     # Kiali CRD (synced from crd-docs/)
    ossmconsole.crd.yaml               # OSSMConsole CRD (synced from crd-docs/)
  metadata/
    annotations.yaml
```

## CSV (ClusterServiceVersion)

Each bundle includes a ClusterServiceVersion that describes the operator to OLM.

**kiali-ossm CSV highlights:**
- `name`: `kiali-operator.v${KIALI_OPERATOR_VERSION}` (populated at release)
- `containerImage`: `${KIALI_OPERATOR}` (the operator image reference)
- `categories`: `Monitoring,Logging & Tracing`
- `capabilities`: `Deep Insights`
- Disconnected/FIPS support annotations for OpenShift
- Valid subscription annotations: `["OpenShift Container Platform", "OpenShift Platform Plus"]`
- Manages both `Kiali` and `OSSMConsole` CRDs

**kiali-upstream CSV highlights:**
- Versioned name: `kiali-operator.v<version>`
- `replaces` field points to the previous version (enabling OLM upgrade graph)
- `channels`: `alpha` and `stable`

## Creating a New Version

Use `manifests/create-new-version.sh` to create a new upstream bundle version:

```bash
# Run from the repo root; --old-manifest and --new-manifest are directory names
# relative to manifests/ (not paths), and version numbers are separate arguments.
./manifests/create-new-version.sh \
  --old-manifest kiali-upstream \
  --new-manifest kiali-upstream \
  --old-version 2.25.0 \
  --new-version 2.26.0 \
  --operator-image quay.io/kiali/kiali-operator:v2.26.0 \
  --replace-version 2.25.0
```

The `-ki` / `--kiali-image` flag can optionally update the Kiali server image reference in the new CSV (separate from the operator image); omit it to keep the existing image specifier with only the version tag updated.

The script:
1. Copies the previous version directory to the new version directory
2. Updates image references and version strings throughout the CSV
3. Sets the `replaces:` field to the previous version
4. Optionally verifies the resulting bundle with `opm`

After running, execute `make sync-crds` to update the CRD in the new version directory with the latest golden copy.

## Bundle Validation

`make validate` runs this pipeline (all steps are part of the single target):

**Phony prerequisite targets** (independently callable):
- `make validate-crd-sync` — confirms all CRD copies are identical to the golden copies in `crd-docs/crd/`
- `make verify-crd-compatibility` — diffs CRD schema against `origin/master` to catch breaking changes
- `make verify-kiali-server-permissions` — verifies operator RBAC grants match Kiali Server's actual needs
- `make verify-defaults` — checks CRD default values match Ansible role defaults

**Inline bundle checks** (only run as part of `make validate`, not separately):
- **kiali-ossm bundle**: substitutes env vars into the CSV template via `envsubst`, then runs `opm render` to verify the bundle can be parsed by OLM
- **kiali-upstream bundle**: finds the latest version directory, renders it with `opm render`, verifies the output is valid YAML

**Note:** `make validate-cr` (CR schema validation against example CRs) is a **separate target** not called by `make validate`. Run it explicitly when modifying CRD schema or example CRs.

The `opm` binary is auto-downloaded to `_output/opm-install/opm` if not found in PATH (version from GitHub API, fallback to `v1.56.0`).

## CRD Synchronization

CRDs in the manifests bundles are not edited directly. Instead:

1. Edit `crd-docs/crd/kiali.io_kialis.yaml` or `kiali.io_ossmconsoles.yaml` (golden copies)
2. Run `make sync-crds` to propagate changes to all bundle locations
3. Run `make validate-crd-sync` to verify sync is complete

See the [CRD & API Surface](crd-and-api.md) topic for full details on the CRD schema and validation.

## Backward Compatibility Checks

`hack/verify-crd-backward-compatibility.sh` compares the current CRD against a base branch (typically `origin/master`) and flags:
- Removed required fields
- Type changes on existing fields
- Enum value removals
- Other schema narrowing that would break existing CRs

Run automatically via `make verify-crd-compatibility` which passes `origin/master` as the base. The check is skipped gracefully if `origin/master` is not available (e.g., in a fresh checkout without the remote configured).
