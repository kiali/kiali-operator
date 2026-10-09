---
format_version: 1
---

# Testing Practices — kiali-operator

## Framework

All operator testing is done via **Molecule integration tests**. No unit test frameworks are used. Any new operator tests must be implemented as Molecule tests.

Molecule uses the Ansible provisioner and runs against a real Kubernetes or OpenShift cluster.

### OSSMC nginx TLS filter plugins

Pure-Python TLS mapping logic is validated with **Ansible `assert` tasks** that invoke the filter plugins (see `molecule/ossmconsole-common/ossmconsole_nginx_tls_filter_asserts.yml`). Run via:

- `molecule/ossmconsole-nginx-tls-filter-test` — role and playbook `filter_plugins` copies (CI when OSSMC TLS playbooks/filters change)
- `molecule/ossmconsole-config-values-test` — same asserts plus rendered `nginx-conf` on OpenShift

## Scenario Structure

Each test scenario lives in `molecule/<name>-test/` and must contain:

| File | Purpose |
|------|---------|
| `molecule.yml` | Driver config, provisioner settings, inventory vars |
| `converge.yml` | The test playbook — imports tasks and runs assertions |
| `prepare.yml` | Pre-test setup (may be shared from `molecule/default/` or scenario-specific) |
| `destroy.yml` | Post-test teardown (may be shared from `molecule/default/` or scenario-specific) |

### Test Sequence
All scenarios must use the `prepare → converge → destroy` sequence in `molecule.yml`:

```yaml
scenario:
  test_sequence:
  - prepare
  - converge
  - destroy
```

## Naming

- Scenario directories must use kebab-case and end with `-test` (see style guide)
- Examples: `config-values-test`, `accessible-namespaces-test`, `cluster-wide-access-test`

## CI Behavior

- **`config-values-test` always runs** in CI on every PR that touches `molecule/`, `roles/default/`, or the molecule CI workflow. It is the baseline smoke test and must always pass.
- **`ossmconsole-nginx-tls-filter-test`** runs when OSSMC nginx TLS filter/playbook files change (see `molecule-tests.yml`).
- Additional scenarios run automatically in CI only when their files are modified in the PR.

### config-values-test coverage requirement
When new configuration settings are added to the operator, `config-values-test` must be updated to cover them. This test serves as the primary verification that operator config values are correctly applied.

## Changelog
| Date | Change | Trigger |
|------|--------|---------|
| 2026-04-08 | Initial generation | /code-reviewer:setup |
| 2026-10-09 | Document OSSMC nginx TLS filter Molecule asserts | OSSMC cluster TLS profile work |
