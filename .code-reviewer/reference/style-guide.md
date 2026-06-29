---
format_version: 1
---

# Style Guide — kiali-operator

## File Naming

### Ansible Task Files
- Must use **kebab-case** with **`.yml`** extension
- Examples: `update-status.yml`, `remove-roles.yml`, `get-discovery-selector-namespaces.yml`

### Ansible Template Files
- Must use **kebab-case** with **`.yaml`** extension (distinct from task files)
- Examples: `role-viewer.yaml`, `rolebinding.yaml`, `configmap.yaml`

### Molecule Scenario Directories
- Must use **kebab-case** and end with **`-test`**
- Examples: `config-values-test`, `accessible-namespaces-test`, `cluster-wide-access-test`

### Shell Scripts (`hack/`)
- Must use **kebab-case** with **`.sh`** extension
- Examples: `verify-crd-defaults.sh`, `verify-crd-backward-compatibility.sh`

### Python Filter Plugins
- Filenames and filter function names must use **`snake_case`**
- Examples: `stripnone.py` / `strip_none()`, `parse_selectors.py` / `parse_selectors()`

## Ansible Variable Naming

- All variable names must use **`snake_case`**
- Examples: `kiali_vars`, `role_binding_kind`, `discovery_selector_namespaces`, `kiali_resource_metadata_labels`

## Task Structure

### `name:` field
- All tasks must have an explicit `name:` field
- Exception: simple anonymous `set_fact` or `debug` tasks may omit it

### `when:` clause placement
- The `when:` clause must always be the **last field** in a task block, after all module arguments

```yaml
# Correct
- name: Do something
  set_fact:
    my_var: "value"
  when:
  - condition_one
  - condition_two

# Wrong — when: is not last
- name: Do something
  when:
  - condition_one
  set_fact:
    my_var: "value"
```

## Ansible Code Patterns

### Nested Variable Updates — `combine({...}, recursive=True)`
- Nested Ansible variable updates must use `combine({...}, recursive=True)`
- Never use direct assignment or non-recursive combine for nested dicts

```yaml
# Correct
kiali_vars: "{{ kiali_vars | combine({'deployment': {'namespace': my_ns}}, recursive=True) }}"

# Wrong
kiali_vars.deployment.namespace: "{{ my_ns }}"
```

### Complex Variable Computation — Jinja2 `{% set %}` blocks
- Complex computed defaults that can't be expressed with simple `combine()` calls should use multi-line Jinja2 `{% set %}` blocks inside a `set_fact` vars block, rendered via `| from_yaml`

```yaml
- name: Compute complex defaults
  vars:
    result_yaml: |
      {% set kv = kiali_vars %}
      {% if kv.some.value is not defined %}
      {% set kv = kv | combine({'some': {'value': 'default'}}, recursive=True) %}
      {% endif %}
      {{ kv | to_nice_yaml }}
  set_fact:
    kiali_vars: "{{ result_yaml | from_yaml }}"
```

### `include_tasks` vs `import_tasks` in Roles
- In roles, always use **`include_tasks`** (not `import_tasks`) when the included file is conditionally executed via `when:`
- This ensures `when:` gates the entire file rather than being copied to each task inside
- Molecule tests may use whichever is appropriate

```yaml
# Correct in roles — when: gates the entire file
- name: Remove obsolete roles
  include_tasks: remove-roles.yml
  when:
  - namespaces_no_longer_accessible is defined

# Wrong in roles — import_tasks copies when: to every task inside
- name: Remove obsolete roles
  import_tasks: remove-roles.yml
  when:
  - namespaces_no_longer_accessible is defined
```

### `ignore_errors: yes`
- Must only be used on tasks that are **explicitly expected to fail** in certain cluster environments (e.g., looking up OpenShift-specific resources on a plain Kubernetes cluster)
- Must not be used as a general error-suppression mechanism

## Changelog
| Date | Change | Trigger |
|------|--------|---------|
| 2026-04-08 | Initial generation | /code-reviewer:setup |
