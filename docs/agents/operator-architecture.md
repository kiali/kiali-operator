---
scribe:
  scan: "HEAD"
  freshness: 100
  human_input: 1
  completeness: 80
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

Watchers common to all four files:
- `kiali.io/v1alpha1 Kiali` → `playbooks/kiali-deploy.yml` (with finalizer pointing to `kiali-remove.yml`)
- `v1 Secret` with label `kiali.io/kiali-multi-cluster-secret: "true"` → `playbooks/kiali-multi-cluster-secret-detected.yml`

Watchers added only in the namespace-scoped variants (`watches-k8s-ns.yaml`, `watches-os-ns.yaml`):
- `v1 Namespace` → `playbooks/kiali-new-namespace-detected.yml`

Watchers added only in the OpenShift variants (`watches-os.yaml`, `watches-os-ns.yaml`):
- `kiali.io/v1alpha1 OSSMConsole` → `playbooks/ossmconsole-deploy.yml` (with finalizer pointing to `ossmconsole-remove.yml`). This watcher also sets `snakeCaseParameters: False`, which means the OSSMConsole CR spec keys are passed to Ansible as-is (camelCase) rather than being converted to snake_case.

All watchers set `watchDependentResources: False` and `watchClusterScopedResources: False` — the operator does not track child or cluster-scoped resources for cascading reconciliation; each CR event triggers a full playbook run. `watchAnnotationsChanges: True` is set for the Kiali CR so annotation-only changes (without spec changes) also trigger reconciliation.

## Playbook Entry Points

`playbooks/kiali-deploy.yml` is the main reconciliation entry point. Its job is to:
1. Determine which Kiali version to install (from `spec.version`, defaulting to the `default-playbook.yml` pointer)
2. If an **upgrade** is detected (`status.specVersion` differs from the target version), first run the *old* version's `kiali-remove` role to purge the previous installation
3. Load `kiali-default-supported-images.yml` to determine the canonical image for the target version; override from `RELATED_IMAGE_kiali_<version>` env vars if set (used in disconnected/OLM environments)
4. Delegate to the version-specific deploy role: `include_role: name="{{ version }}/kiali-deploy"` — skipped if `skip_reconciliation` is defined and true

`playbooks/kiali-remove.yml` runs under the finalizer. All tasks use `ignore_errors: yes` so teardown always completes. It loads `default-playbook.yml` to determine the version, then delegates unconditionally to `<version>/kiali-remove` (no `skip_reconciliation` guard — removal always runs).

Additional playbooks:
- `kiali-new-namespace-detected.yml` — triggered (in namespace-scoped mode only) when a new Namespace is created. Touches the `kiali.io/reconcile` annotation on any Kiali CRs that were created *before* the new namespace, causing the operator to reconcile them. Those reconciliations then determine whether the new namespace should be accessible. It does not directly provision RBAC.
- `kiali-multi-cluster-secret-detected.yml` — triggered when a Secret with label `kiali.io/kiali-multi-cluster-secret: "true"` changes. Patches the `operator.kiali.io/last-updated` annotation on all Kiali Deployments in the same namespace, forcing a pod restart so the servers pick up the updated remote cluster credentials. Does not touch Kiali CRs or trigger CR reconciliation.
- `ossmconsole-deploy.yml` / `ossmconsole-remove.yml` — OSSMConsole equivalents. OSSMConsole is a **singleton**: only the oldest OSSMConsole CR is active at any time. If multiple CRs exist, the deploy role compares creation timestamps and defers to the oldest; any newer CR triggers `meta: end_play` and is silently ignored. The deploy role also enforces additional runtime gates: (1) the OpenShift Console must be installed and not in `Removed` state, or deployment is aborted; (2) the Kiali Service name/namespace/port are auto-discovered from the Kiali Route if not specified in `spec.kiali`, and the role fails if Kiali cannot be found; (3) the major.minor version of the Kiali Server must match the OSSMC version being installed — this check can be bypassed with `OSSMC_SKIP_VERSION_CHECK=true` on the operator Deployment.
- `kiali-default-supported-images.yml` / `ossmconsole-default-supported-images.yml` — version-to-image mapping files loaded as vars (not playbooks)

## Role Versioning Strategy

Roles are organized under `roles/<version>/`:

```
roles/
  default/          # Latest/active version (real directory)
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

**Before any tasks run:** Ansible automatically loads `vars/main.yml`, which deep-merges CR spec fields with defaults from `defaults/main.yml` using the `stripnone` filter plugin, producing the initial `kiali_vars` dict. This is not a task step — it is a role-startup prerequisite that cannot be reordered.

1. **Snapshot CR** — captures `_kiali_io_kiali` to `current_cr` (preserves camelCase keys for status updates)
2. **Cluster detection** — queries API groups; sets `is_openshift`/`is_k8s` booleans
3. **Pre-phase-2 validation** — several structural checks run before the phase 2 `set_fact`, using the initial `kiali_vars` from `vars/main.yml`: deprecated `ingress_enabled` migration, snake_case→camelCase conversion, default namespace assignment, immutable field enforcement (`instance_name`, `namespace`, `remote_cluster_resources_only`), ad-hoc access guards (`ALLOW_AD_HOC_KIALI_NAMESPACE`, `ALLOW_AD_HOC_CONTAINERS`, `ALLOW_AD_HOC_KIALI_IMAGE`), DNS label compliance check, CWA duplicate `instance_name` conflict check, and `web_schema`/`web_history_mode` validation.
4. **Variable merging (phase 2)** — a large Jinja2 `set_fact` applies runtime-derived defaults based on live cluster state: Prometheus/Grafana/Tracing URLs derived from the deployment namespace, auth strategy defaulted by cluster type, ingress enabled/disabled by cluster type, TLS cert paths, image version resolution, etc. Produces the final `kiali_vars` used for all resource creation.
5. **Post-phase-2 validation** — value-semantic checks that depend on cluster type: auth strategy validity (OpenShift vs Kubernetes allowed values), OpenID config completeness, OpenShift-auth-requires-ingress check, image version resolution (`lastrelease`, `operator_version`).
6. **Namespace discovery** — resolves `deployment.discovery_selectors` against live cluster namespaces to build `discovery_selector_namespaces`.
7. **Secrets** — validates signing key length if user-supplied (must be 16, 24, or 32 bytes); generates and stores a random signing key in the `kiali-signing-key` secret if absent; sets up secret-backed volume mounts for external service credentials and remote cluster secrets.
8. **Security guardrails** — enforces mandatory `securityContext` (including `seccompProfile: {type: RuntimeDefault}`) on user-provided `additional_pod_containers_yaml` and `additional_pod_init_containers_yaml`; force-sets `readOnly: true` on any volume mounts targeting secret-backed volumes; fails immediately if a user container tries to mount a secret-backed volume as read-write; logs a per-container privilege analysis. Overridable via `ALLOW_SECURITY_CONTEXT_OVERRIDE=true`.
9. **Read current state** — reads existing ConfigMap (to detect view-only/auth/CWA/image changes) and checks which namespaces currently carry the `kiali.io/<instance>.home` label.
10. **RBAC cleanup** — removes roles from namespaces no longer accessible; removes cluster roles if CWA mode changed; removes and recreates roles if `view_only_mode` or auth strategy changed (role bindings are immutable).
11. **Namespace label management** — removes `kiali.io/<instance>.home` label from namespaces that Kiali no longer has access to; adds it to all newly accessible namespaces.
12. **Deployment deletion on image change** — if the currently running image name or version differs from the desired values, the existing Deployment is deleted so no stale pod continues running.
13. **Platform branch** — includes `openshift/os-main.yml` or `kubernetes/k8s-main.yml` to create the actual Kubernetes resources (ConfigMap, Deployment, RBAC, Routes/Ingress, etc.)
14. **Rolling restart** — if the ConfigMap changed, bumps the `operator.kiali.io/last-updated` deployment annotation to trigger a pod restart.
15. **Status update** — progress and final state are written to the CR status throughout via repeated includes of `update-status-progress.yml`, which calls `operator_sdk.util.k8s_status` directly.

## CR Lifecycle: Remove Flow

The `kiali-remove` role is triggered by the finalizer on CR deletion. It uses a separate, lighter variable dict `kiali_vars_remove` (defined in its own `vars/main.yml` and `defaults/main.yml`) rather than the full `kiali_vars` from the deploy role. `kiali_vars_remove` carries only the deployment settings needed to identify resources to delete, falling back to values from the CR's `status.deployment` fields when CR spec fields are absent. Changes to defaults in the deploy role's `defaults/main.yml` do not automatically affect the remove role.

It removes:
- All cluster-scoped resources (ClusterRoles, ClusterRoleBindings) — `tasks/clusterroles-to-remove.yml`
- All namespace-scoped resources (ConfigMap, Deployment, Service, ServiceAccount, Roles, RoleBindings) — `tasks/resources-to-remove.yml`
- OpenShift-specific resources (Routes, OAuthClient) — `tasks/os-resources-to-remove.yml`
- OpenShift ConsoleLinks — removed directly in `tasks/main.yml`
- The `kiali.io/<instance>.home` label from the `kiali-signing-key` secret (indicating this instance no longer uses it); if no other instance labels remain on the secret, the secret itself is also deleted
- The `kiali.io/<instance>.home` namespace labels applied by the deploy role

## Ansible Collections

`requirements.yml` pins the Ansible collections the operator depends on:

| Collection | Version | Purpose |
|------------|---------|---------|
| `kubernetes.core` | 4.0.0 | `k8s`, `k8s_info` modules for all Kubernetes API calls |
| `community.general` | 9.0.0 | General utility modules |
| `operator_sdk.util` | v0.5.0 | `k8s_status` for writing status conditions back to the CR |
| `ansible.posix` | 1.6.2 | POSIX system tasks |

These must match the versions bundled in the base image (`quay.io/operator-framework/ansible-operator` or `registry.redhat.io/openshift4/ose-ansible-rhel9-operator`). Run `ansible-galaxy collection install -r requirements.yml --force-with-deps` to install locally for development.

The operator image also ships an opt-in Ansible task profiler config at `${HOME}/ansible-profiler.cfg` (baked in by the Dockerfile's final step). Set `ANSIBLE_CONFIG=/opt/ansible/ansible-profiler.cfg` in the operator Deployment to enable per-task timing output after each reconciliation.
