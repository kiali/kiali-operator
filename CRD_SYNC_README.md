# CRD Synchronization

This document explains how the Kiali CRD files are maintained across different locations in the project.

**Labels**: All CRDs include these labels:
- `app: kiali-operator`
- `app.kubernetes.io/name: kiali-operator`

## Golden Copies

The **single source of truth** for the Kiali CRD is:

```
kiali-operator/crd-docs/crd/kiali.io_kialis.yaml
```

The **single source of truth** for the OSSMConsole CRD is:

```
kiali-operator/crd-docs/crd/kiali.io_ossmconsoles.yaml
```

These files contain the complete CRD schemas with full validation and documentation.

## Derived Copies

All other CRD files are automatically generated from the golden copies:

| Location | Purpose | Differences from golden copy |
|----------|---------|------------------------------|
| `../helm-charts/kiali-operator/crds/crds.yaml` | Helm chart Kiali CRD | Wrapped with `---` and `...` YAML document separators |
| `manifests/kiali-ossm/manifests/kiali.crd.yaml` | OSSM bundle CRD | Identical copy |
| `manifests/kiali-ossm/manifests/ossmconsole.crd.yaml` | OSSM bundle CRD | Identical copy |
| `manifests/kiali-upstream/*/manifests/kiali.crd.yaml` | Upstream bundle CRD | Identical copy |

## Maintenance

### Synchronizing CRDs

To update all derived CRD files from the golden copies:

```bash
cd kiali-operator
make sync-crds
```

This command will:
1. Copy the golden copies to all other locations
2. Apply necessary transformations (YAML separators for Helm chart only)
3. Preserve the full schema in all copies
4. Handle missing helm-charts directory gracefully (skips if not present)

### Validating Synchronization

To check if all CRD files are in sync:

```bash
cd kiali-operator
make validate-crd-sync
```

This validation is also included in the main `make validate` target.

### When to Sync

You should run `make sync-crds` whenever:

- The golden copies (`crd-docs/crd/kiali.io_*.yaml`) are modified
- You notice CRD validation failures in CI
- You are preparing a release

### CI Integration

The CI pipeline automatically validates CRD synchronization. If the validation fails, run `make sync-crds` and commit the changes.

## Important Notes

1. **Never edit derived copies directly** - they will be overwritten by `make sync-crds`
2. **Always edit the golden copies** when making CRD schema changes
3. **Run sync after golden copies change** to keep everything in sync
4. **All CRDs now include the full schema** (no more minimal versions)

## Troubleshooting

If you see errors like "CRD is out of sync":

1. Run `make sync-crds` to regenerate all derived copies
2. Commit the changes
3. Run `make validate-crd-sync` to verify the fix

If synchronization fails:

1. Check that the "golden" files exists and are valid YAML
2. Verify file permissions allow writing to the target locations
