# Documentation Status

| Topic | Freshness | Human | Complete | Claims | File |
|-------|-----------|-------|----------|--------|------|
| Operator Architecture | 100 | 12 | 82 | 16 | [operator-architecture.md](operator-architecture.md) |
| CRD & API Surface | 100 | 1 | 85 | 8 | [crd-and-api.md](crd-and-api.md) |
| OLM Bundle & Manifests | 100 | 1 | 85 | 6 | [olm-manifests.md](olm-manifests.md) |
| Molecule Test Suite | 100 | 9 | 90 | 13 | [molecule-testing.md](molecule-testing.md) |
| Build & CI | 100 | 1 | 75 | 6 | [build-and-ci.md](build-and-ci.md) |

## Stale Flags

None.

## Quality Notes

All 5 topics use domain-specific headings rather than the canonical scribe headings (`Key Entry Points`, `Patterns & Conventions`, `Gotchas`, `Dependencies & Context`, `Links`). This is not an error — the headings reflect the operator's architecture domains and are more useful in context.

`build-and-ci.md` covers `dev-playbook-config/` in its watch_paths but does not describe the directory's contents (`kiali/`, `ossmconsole/` subdirs) in the doc body. Completeness score reflects this gap.

`operator-architecture.md` — two new sections added (2026-05-26): CA Bundle ConfigMap (OpenShift) and Secret Volume Mounts and Credential Rotation, covering how the operator provisions cabundles and secret-backed credentials that feed Kiali's CredentialManager.

`molecule-testing.md` — new section added (2026-05-26): external-auth-rotation-test Scenario, documenting the full rotation test flow and ChatAI secret gating assertions.

## Contradictions

None detected.

---
*Updated by codebase-scribe — 2026-05-26. Scan SHA: cd9714f4b3d7b83b5470d0ee3ae07e768ae6d905. Focus run: operator-architecture and molecule-testing enriched with certificate manager and token rotation content.*
