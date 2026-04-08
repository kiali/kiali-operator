---
format_version: 1
---

# CRD Conventions — kiali-operator

## Golden Copy — Source of Truth

`crd-docs/crd/` contains the authoritative CRD files:
- `crd-docs/crd/kiali.io_kialis.yaml`
- `crd-docs/crd/kiali.io_ossmconsoles.yaml`

**CRDs must only ever be edited in `crd-docs/crd/`.** All other copies are generated and must never be edited directly:
- `manifests/kiali-ossm/manifests/kiali.crd.yaml`
- `manifests/kiali-upstream/<version>/manifests/kiali.crd.yaml`
- `../helm-charts/kiali-operator/crds/crds.yaml`

After editing a CRD in `crd-docs/crd/`, run `make sync-crds` to propagate changes. CI validates sync with `make validate-crd-sync`.

## CRD Defaults Must Match Ansible Defaults

Every default value defined in the CRD schema must match the corresponding default in the Ansible `defaults/main.yml` file:
- Kiali CRD ↔ `roles/default/kiali-deploy/defaults/main.yml`
- OSSMConsole CRD ↔ `roles/default/ossmconsole-deploy/defaults/main.yml`

When adding a new field with a default value, both files must be updated together. CI enforces this via `make verify-defaults` (`hack/verify-crd-defaults.sh`).

## Backward Compatibility

CRD schema changes must maintain backward compatibility with existing CRs. CI validates this by comparing against `origin/master` via `hack/verify-crd-backward-compatibility.sh`. Breaking changes should be avoided by design, not just caught by CI.

## Changelog
| Date | Change | Trigger |
|------|--------|---------|
| 2026-04-08 | Initial generation | /code-reviewer:setup |
