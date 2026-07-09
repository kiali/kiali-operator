---
format_version: 1
---

# Security Posture — kiali-operator

## Credential System

Credential fields in the Kiali CR (e.g., usernames, passwords, tokens for Prometheus, Grafana, Tracing, etc.) accept either:

1. **Plain text values** — valid and common for testing and demos
2. **Secret references** — a string matching the pattern `secret:<secretName>:<secretKey>`

When the operator detects a credential value matching `secret:<secretName>:<secretKey>`, it treats it as a reference to a Kubernetes Secret and mounts that secret as a volume for the Kiali pod. Plain text values are passed through as-is.

This means reviewers should **not** flag plain text credential values as a violation — they are explicitly supported. The `secret:` format is a detection pattern, not a mandate.

## `ALLOW_*` Environment Variable Pattern

The operator uses `ALLOW_*` environment variables on the operator pod to gate behaviors that relax security constraints. All default to `false`:

| Variable | Controls |
|----------|---------|
| `ALLOW_AD_HOC_KIALI_NAMESPACE` | Installing Kiali in a namespace different from the CR namespace |
| `ALLOW_AD_HOC_KIALI_IMAGE` | Using a custom Kiali image specified in the CR |
| `ALLOW_AD_HOC_CONTAINERS` | Adding extra containers/initContainers to the Kiali pod |
| `ALLOW_ALL_ACCESSIBLE_NAMESPACES` | Cluster-wide access mode |
| `ALLOW_SECURITY_CONTEXT_OVERRIDE` | Preserving user-provided security contexts on additional containers |

**Recommendation**: New operator behaviors that relax a security constraint should follow this same pattern — gated behind an `ALLOW_*` env var that defaults to `false`. This is a recommendation, not a hard requirement, but deviations should be explicitly justified.

## Changelog
| Date | Change | Trigger |
|------|--------|---------|
| 2026-04-08 | Initial generation | /code-reviewer:setup |
