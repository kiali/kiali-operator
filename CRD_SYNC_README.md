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

### Validating Backward Compatibility

To ensure CRD schema changes maintain backward compatibility:

```bash
cd kiali-operator
make verify-crd-compatibility
```

This checks that:
- No required fields are added (new fields must be optional)
- No existing fields are removed (deprecate instead)
- No field types change (e.g., string → integer)
- No enum values are removed (adding is OK)
- No constraints are tightened (min/max values, patterns, etc.)
- No default values change (affects existing resources)
- Version remains v1alpha1 (enforces stability commitment)

This validation is included in `make validate` and runs automatically in CI on PRs that modify CRD files.

### When to Sync and Validate

You should run `make sync-crds` whenever:

- The golden copies (`crd-docs/crd/kiali.io_*.yaml`) are modified
- You notice CRD validation failures in CI
- You are preparing a release

You should run `make verify-crd-compatibility` whenever:

- Modifying CRD schemas (happens automatically in CI)
- Before committing CRD changes
- To verify your changes won't break existing users

### CI Integration

The CI pipeline (`.github/workflows/ci.yml`) automatically validates:
1. **CRD synchronization** - Ensures all CRD copies match the golden files
2. **Backward compatibility** - Ensures schema changes don't break existing users

Both checks are included in the `make validate` target that runs on every PR and push to master.

If CRD sync validation fails, run `make sync-crds` and commit the changes.

If backward compatibility validation fails, you must revise your changes to maintain compatibility:
- Make new fields optional instead of required
- Deprecate fields in descriptions rather than removing them
- Add enum values without removing existing ones
- Relax constraints rather than tightening them

## Important Notes

1. **Never edit derived copies directly** - they will be overwritten by `make sync-crds`
2. **Always edit the golden copies** when making CRD schema changes
3. **Run sync after golden copies change** to keep everything in sync
4. **All CRDs now include the full schema** (no more minimal versions)
5. **Maintain backward compatibility** - CRD version is v1alpha1 forever; all changes must be non-breaking

## Troubleshooting

### CRD Sync Errors

If you see errors like "CRD is out of sync":

1. Run `make sync-crds` to regenerate all derived copies
2. Commit the changes
3. Run `make validate-crd-sync` to verify the fix

If synchronization fails:

1. Check that the "golden" files exist and are valid YAML
2. Verify file permissions allow writing to the target locations

### Backward Compatibility Errors

If you see errors like "Breaking changes detected":

1. Review the specific errors reported by the script
2. Modify your CRD changes to maintain compatibility:
   - Make new fields optional (don't add to `required` array)
   - Add deprecation notices instead of removing fields
   - Keep existing enum values when adding new ones
   - Don't tighten validation constraints
3. Re-run `make verify-crd-compatibility` to verify the fix

Common solutions:
- **"New required field added"** → Remove the field from the `required` array
- **"Field removed"** → Add the field back and mark as deprecated in description
- **"Enum value removed"** → Keep the old value and add new values alongside it
- **"Type changed"** → Revert to original type or use a new field name
- **"Constraint tightened"** → Relax the constraint to original value or wider
