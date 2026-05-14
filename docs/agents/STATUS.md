# Documentation Status

| Topic | Freshness | Human | Complete | Claims | File |
|-------|-----------|-------|----------|--------|------|
| Operator Architecture | 100 | 1 | 80 | 10 | [operator-architecture.md](operator-architecture.md) |
| CRD & API Surface | 100 | 1 | 85 | 8 | [crd-and-api.md](crd-and-api.md) |
| OLM Bundle & Manifests | 100 | 1 | 85 | 6 | [olm-manifests.md](olm-manifests.md) |
| Molecule Test Suite | 100 | 1 | 90 | 7 | [molecule-testing.md](molecule-testing.md) |
| Build & CI | 100 | 1 | 75 | 6 | [build-and-ci.md](build-and-ci.md) |

## Stale Flags

None.

## Quality Notes

All 5 topics use domain-specific headings rather than the canonical scribe headings (`Key Entry Points`, `Patterns & Conventions`, `Gotchas`, `Dependencies & Context`, `Links`). This is not an error — the headings reflect the operator's architecture domains and are more useful in context. Consider adding a `Gotchas` section to each topic on the next draft pass.

`build-and-ci.md` covers `dev-playbook-config/` in its watch_paths but does not describe the directory's contents (`kiali/`, `ossmconsole/` subdirs) in the doc body. Completeness score reflects this gap.

## Contradictions

None detected.

---
*Last maintained: 2026-05-14*
