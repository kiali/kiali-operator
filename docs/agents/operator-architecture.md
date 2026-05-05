---
scribe:
  scan: "HEAD"
  freshness: 70
  human_input: 1
  completeness: 70
  inferred_sections:
    - id: "s1"
      heading: "Overview"
    - id: "s2"
      heading: "Watches Configuration"
    - id: "s3"
      heading: "Playbook Entry Points"
    - id: "s4"
      heading: "Role Versioning Strategy"
    - id: "s5"
      heading: "CR Lifecycle: Deploy Flow"
    - id: "s6"
      heading: "CR Lifecycle: Remove Flow"
    - id: "s7"
      heading: "Ansible Collections"
  watch_paths:
    - watches-k8s.yaml
    - watches-os.yaml
    - watches-k8s-ns.yaml
    - watches-os-ns.yaml
    - playbooks/
    - roles/
    - requirements.yml
  stale_flags: []
---

# Operator Architecture

> TL;DR: The kiali-operator is an Ansible Operator that watches Kiali and OSSMConsole CRs, dispatches to versioned Ansible roles, and handles the full install/upgrade/remove lifecycle for Kiali and the OpenShift Service Mesh Console plugin.

## Overview

The kiali-operator is built on the [ansible-operator-sdk](https://sdk.operatorframework.io/docs/building-operators/ansible/) base image from Operator Framework. Rather than Go controllers, all reconciliation logic is implemented as Ansible playbooks and roles. The operator image packages:

- `watches-*.yaml` — tells the SDK which Kubernetes resource kinds to watch and which playbook to invoke
- `playbooks/` — thin entry-point playbooks that route to version-specific roles
- `roles/` — the actual reconciliation logic, organized per version

Two separate products are managed from this single operator:
- **Kiali** — the Istio service mesh observability dashboard (CR: `kiali.io/v1alpha1 Kiali`)
- **OSSMConsole** — the OpenShift Service Mesh Console plugin (CR: `kiali.io/v1alpha1 OSSMConsole`, OpenShift only)

## Watches Configuration

Four watches files are shipped; the operator selects the appropriate one at startup based on the deployment environment:

| File | Platform | Namespace scope |
|------|----------|-----------------|
| `watches-k8s.yaml` | Kubernetes | cluster-wide |
| `watches-k8s-ns.yaml` | Kubernetes | namespace-scoped |
| `watches-os.yaml` | OpenShift | cluster-wide |
| `watches-os-ns.yaml` | OpenShift | namespace-scoped |

Each watches file registers watchers for:
- `kiali.io/v1alpha1 Kiali` → `playbooks/kiali-deploy.yml` (with finalizer pointing to `kiali-remove.yml`)
- `v1 Secret` with label `kiali.io/kiali-multi-cluster-secret: "true"` → `playbooks/kiali-multi-cluster-secret-detected.yml`
- OpenShift watches also add: `kiali.io/v1alpha1 OSSMConsole` → `playbooks/ossmconsole-deploy.yml`

All watchers set `watchDependentResources: False` — the operator does not track child resources for cascading reconciliation. Instead, each CR event triggers a full playbook run. `watchAnnotationsChanges: True` is set for the Kiali CR so annotation-only changes (without spec changes) also trigger reconciliation.

## Playbook Entry Points

`playbooks/kiali-deploy.yml` is the main reconciliation entry point. Its job is to:
1. Determine which Kiali version to install (from `spec.version`, defaulting to the `default-playbook.yml` pointer)
2. If an **upgrade** is detected (`status.specVersion` differs from the target version), first run the *old* version's `kiali-remove` role to purge the previous installation
3. Load `kiali-default-supported-images.yml` to determine the canonical image for the target version; override from `RELATED_IMAGE_kiali_<version>` env vars if set (used in disconnected/OLM environments)
4. Delegate to the version-specific deploy role: `include_role: name="{{ version }}/kiali-deploy"`

`playbooks/kiali-remove.yml` runs under the finalizer. All tasks use `ignore_errors: yes` so teardown always completes. It delegates to `<version>/kiali-remove`.

Additional playbooks:
- `kiali-new-namespace-detected.yml` — re-runs RBAC provisioning when a new namespace matches the discovery selectors
- `kiali-multi-cluster-secret-detected.yml` — triggers reconciliation when a multi-cluster secret changes
- `ossmconsole-deploy.yml` / `ossmconsole-remove.yml` — OSSMConsole equivalents
- `kiali-default-supported-images.yml` / `ossmconsole-default-supported-images.yml` — version-to-image mapping files loaded as vars (not playbooks)

## Role Versioning Strategy

Roles are organized under `roles/<version>/`:

```
roles/
  default/          # Latest/active version (symlinked or canonical)
  v1.73/            # Older supported version
  v2.4/
  v2.11/
  v2.17/
  v2.22/
```

`playbooks/default-playbook.yml` contains a single `playbook: default` directive that sets which version directory name is the current default. When `spec.version` is not set in the CR, the deploy playbook resolves to `roles/default/`.

Each version directory contains four roles:
- `kiali-deploy` — full Kiali installation
- `kiali-remove` — Kiali teardown
- `ossmconsole-deploy` — OSSMConsole installation
- `ossmconsole-remove` — OSSMConsole teardown

This versioning model allows the operator to support multiple concurrent Kiali versions — a user can pin `spec.version: v2.17` to stay on an older release while the operator is updated.

## CR Lifecycle: Deploy Flow

The `kiali-deploy` role (`roles/default/kiali-deploy/`) executes this sequence:

1. **Snapshot CR** — captures `_kiali_io_kiali` to `current_cr` (preserves camelCase keys for status updates)
2. **Cluster detection** — queries API groups; sets `is_openshift`/`is_k8s` booleans
3. **Variable merging** — `vars/main.yml` performs a deep merge of CR spec fields with defaults from `defaults/main.yml` using the `stripnone` filter plugin; produces the `kiali_vars` dict used throughout the role
4. **Validation** — checks `instance_name` DNS compliance, immutable fields (`instance_name`, `namespace`, `remote_cluster_resources_only`), auth strategy validity, cluster-wide-access permissions
5. **Namespace discovery** — resolves `deployment.discovery_selectors` against live cluster namespaces; applies/removes `kiali.io/<instance>.home` namespace labels
6. **RBAC cleanup** — removes roles from namespaces no longer accessible, removes cluster roles if CWA mode changed
7. **Secrets** — manages the `kiali-signing-key` secret; sets up secret-backed volume mounts for external service credentials
8. **Security guardrails** — enforces mandatory `securityContext` on user-provided `additional_pod_containers_yaml` / `additional_pod_init_containers_yaml`
9. **Platform branch** — includes `openshift/os-main.yml` or `kubernetes/k8s-main.yml` to create the actual Kubernetes resources (ConfigMap, Deployment, RBAC, Routes/Ingress, etc.)
10. **Rolling restart** — if the ConfigMap changed, bumps the `operator.kiali.io/last-updated` deployment annotation to trigger a pod restart
11. **Status update** — writes progress messages and final state to the CR status via `update-status.yml`

## CR Lifecycle: Remove Flow

The `kiali-remove` role is triggered by the finalizer on CR deletion. It removes:
- All cluster-scoped resources (ClusterRoles, ClusterRoleBindings)
- All namespace-scoped resources (ConfigMap, Deployment, Service, ServiceAccount, Roles, RoleBindings)
- OpenShift-specific resources (Routes, OAuthClient)
- Namespace labels applied by the deploy role

Tasks are in `tasks/resources-to-remove.yml` and `tasks/clusterroles-to-remove.yml`. `tasks/os-resources-to-remove.yml` handles OpenShift extras.

## Ansible Collections

`requirements.yml` pins the Ansible collections the operator depends on:

| Collection | Version | Purpose |
|------------|---------|---------|
| `kubernetes.core` | 4.0.0 | `k8s`, `k8s_info` modules for all Kubernetes API calls |
| `community.general` | 9.0.0 | General utility modules |
| `operator_sdk.util` | 0.5.0 | `osdk_handler_status` for CR status management |
| `ansible.posix` | 1.6.2 | POSIX system tasks |

These must match the versions bundled in the base image (`quay.io/operator-framework/ansible-operator` or `registry.redhat.io/openshift4/ose-ansible-rhel9-operator`). Run `ansible-galaxy collection install -r requirements.yml --force-with-deps` to install locally for development.
