---
scribe:
  scan: "HEAD"
  freshness: 100
  human_input: 12
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
    - id: "sa-token-and-secret-volume-mounts"
      heading: "Secret Volume Mounts and Credential Rotation"
  watch_paths:
    - watches-k8s.yaml
    - watches-os.yaml
    - watches-k8s-ns.yaml
    - watches-os-ns.yaml
    - playbooks/
    - roles/
    - requirements.yml
  stale_flags: []
  review_notes: []
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

When an OSSMConsole CR changes `spec.version`, `ossmconsole-deploy.yml` runs the installed version's remove role before including the requested version's deploy role, as `kiali-deploy.yml` does for Kiali. The helper-enabled default remove role also deletes its TLS profile ServiceAccount and cluster RBAC. An image change within the same `spec.version` follows the normal reconciliation path.

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

## OSSMC Cluster TLS Profile Support

OSSMC's nginx follows the OpenShift cluster TLS profile (`APIServer/cluster` `spec.tlsSecurityProfile`). **All profile logic lives in the OSSMC image**, not in the operator: a Python helper in the image (`/usr/local/bin/ossmc-tls-profile`) reads the profile with the pod's ServiceAccount, renders `/tmp/ossmc/tls.conf`, supervises nginx, and applies profile changes inside the running container (no pod restart, no operator reconcile). The operator has no TLS logic: no filter plugins, no APIServer reads or watches (`watches-os.yaml`/`watches-os-ns.yaml` are unchanged), and no TLS directives in its templates. Its responsibility is limited to static resources, wiring and cleanup in the **default** role:

| Resource / wiring | Where |
|---|---|
| ServiceAccount `ossmconsole-service-account` (CR namespace) | `roles/default/ossmconsole-deploy/templates/openshift/serviceaccount.yaml` |
| ClusterRole `ossmconsole-tls` — exactly `get` on `config.openshift.io` `apiservers`, `resourceNames: [cluster]` | `templates/openshift/clusterrole.yaml` |
| ClusterRoleBinding `ossmconsole-tls` — binds that ClusterRole to the ServiceAccount in the CR namespace | `templates/openshift/clusterrolebinding.yaml` |
| Deployment: `command: ["/usr/local/bin/ossmc-tls-profile"]`, `serviceAccountName`, `automountServiceAccountToken: true`, exec readiness probe `ossmc-tls-profile probe` (`periodSeconds: 5`, `timeoutSeconds: 3`), **no liveness probe** | `templates/openshift/deployment.yaml` |
| `nginx-conf` ConfigMap: `include /tmp/ossmc/tls.conf;` instead of hardcoded `ssl_protocols`/`ssl_ecdh_curve` | `templates/openshift/configmap-nginx.yaml` |

`tasks/openshift/os-main.yml` processes the templates in this order: `serviceaccount`, `clusterrole`, `clusterrolebinding`, `configmap-nginx`, `configmap-plugin`, `deployment`, `service`, `consoleplugin` — the pod's identity and RBAC exist before it starts, and a new pod never mounts an old `nginx.conf`. The final restart block in `tasks/main.yml` restarts the pod once when either `ConfigMap-plugin-conf` or `ConfigMap-nginx-conf` was actually updated (`changed` and `method == update`); an unchanged reconcile does not restart it.

**Cluster-RBAC prerequisite.** Before processing any template, the deploy role runs `SelfSubjectAccessReview`s for `create` on `clusterroles` and `clusterrolebindings`. If either is denied, reconciliation fails with:

> OSSMC requires the operator to be able to create ClusterRoles and ClusterRoleBindings in order to grant the OSSMC ServiceAccount read access to the cluster TLS profile (apiservers/cluster). If the operator was installed with the Helm chart, set clusterRoleCreator=true.

OSSMC installation (including OSSMC without Kiali) therefore requires an operator that can create ClusterRoles/ClusterRoleBindings and holds `get` on `config.openshift.io/apiservers` (it cannot grant what it does not hold). The OSSM OLM bundle grants both. A Helm install with an effective `clusterRoleCreator=false` cannot install OSSMC (Kiali-only installs remain valid).

**Template/image pairing.** The default role requires an OSSMC image that contains the helper. On `master`, `ossmconsole-default-supported-images.yml` maps `default` to `operator_version`, which resolves to the plugin's `latest` image. The image keeps its legacy default `CMD /usr/libexec/s2i/run`, so historical templates (which set no command) keep running nginx with their static TLS configuration on a new image, without cluster-profile support; upgrading the image alone does not enable the feature. Conversely, the default role with an image that lacks the helper fails at container start (missing executable). A custom image override (`ALLOW_AD_HOC_OSSMCONSOLE_IMAGE` with `spec.deployment.imageName`/`imageVersion`) used with the default role must implement the same helper/include/probe contract; otherwise the pod fails to start or never becomes ready. The new command, include, probe and RBAC are deliberately **not** copied into the historical `roles/v*/ossmconsole-*` roles.

**Removal and version switches.** The cluster-scoped ClusterRole/ClusterRoleBinding cannot be cleaned up by namespaced owner references. The helper-enabled default remove role deletes ClusterRoleBinding `ossmconsole-tls`, ClusterRole `ossmconsole-tls` and ServiceAccount `ossmconsole-service-account` in the CR namespace along with its other resources. Both CR deletion and a `spec.version` change away from default invoke that remove role. The old installation is removed before the new version is deployed, so a downgrade to a legacy version leaves no helper wiring or TLS RBAC behind; an upgrade to a helper-enabled version creates them anew. Historical roles do not create these TLS resources. Remove roles end the play for ignored (non-oldest) CRs before cleanup.

**Molecule coverage.** `ossmconsole-default` checks that the three resources exist and are removed. `ossmconsole-tls-profile-test` verifies the wiring, the helper's readiness, the real TLS behavior against the cluster's current profile (without changing cluster configuration) and the ServiceAccount's least privilege. `ossmconsole-lite-test` verifies the helper works without Kiali and checks that downgrading to a historical version removes its helper RBAC before deleting the CR. See [Molecule Test Suite](molecule-testing.md) for how to run them (OpenShift only).

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

## CA Bundle ConfigMap (OpenShift)

On OpenShift, the operator creates a `<instance-name>-cabundle-openshift` ConfigMap in the Kiali namespace during every reconciliation (`templates/openshift/cabundle.yaml`). The ConfigMap carries a single annotation:

```yaml
annotations:
  service.beta.openshift.io/inject-cabundle: "true"
```

This annotation instructs OpenShift's **service-ca-operator** to inject the cluster-internal service CA certificate into the ConfigMap's `service-ca.crt` key automatically. The operator does not write any certificate data itself — it only creates the ConfigMap shell; OpenShift fills it in.

The Kiali pod `deployment.yaml` (OpenShift variant) then mounts `/kiali-cabundle` as a **projected volume** that merges three ConfigMaps:

```yaml
volumes:
- name: kiali-cabundle
  projected:
    sources:
    - configMap:
        name: <instance>-cabundle-openshift        # operator-created; OpenShift injects service CA
    - configMap:
        name: <instance>-cabundle                  # optional; user-managed custom CAs
        optional: true
    - configMap:
        name: <instance>-oauth-cabundle            # optional; OAuth CA bundle
        optional: true
```

On **vanilla Kubernetes**, there is no operator-created cabundle ConfigMap. The deployment template mounts a single `configMap` volume pointing to `<instance>-cabundle` (the user-managed ConfigMap) and marks it `optional: true`.

**Connection to Kiali's CredentialManager:** The Kiali server's `CredentialManager` (in `config/credentials.go`) watches `/kiali-cabundle/` for file changes. When OpenShift's service-ca-operator rotates the cluster CA, it updates the ConfigMap, which Kubernetes propagates to the projected volume mount. The CredentialManager detects the `..data` symlink change and rebuilds its cert pool — no pod restart required. The specific files picked up are:

| File path in pod | Source |
|---|---|
| `/kiali-cabundle/service-ca.crt` | Injected by OpenShift service-ca-operator |
| `/kiali-cabundle/additional-ca-bundle.pem` | From `<instance>-cabundle` ConfigMap (user-managed) |
| `/kiali-cabundle/openid-server-ca.crt` | From `<instance>-cabundle` ConfigMap (OpenID CA) |
| `/kiali-cabundle/oauth-server-ca.crt` | From `<instance>-oauth-cabundle` ConfigMap |

The two ConfigMaps have distinct ownership: the operator **owns and manages** `<instance>-cabundle-openshift` (it creates, updates, and removes it during reconciliation), while the user **owns** `<instance>-cabundle` (the operator never writes to it). This separation is intentional — the operator must not overwrite user-managed CA content on every reconciliation.

The `cabundle-openshift` ConfigMap is skipped when `deployment.remote_cluster_resources_only: true` (no Kiali server is deployed to that cluster, so there is nothing to mount).

## Secret Volume Mounts and Credential Rotation

The operator implements a **`secret:name:key` URI scheme** that allows any credential field in the Kiali CR to reference a Kubernetes Secret rather than storing the value inline. The deploy role (`tasks/main.yml`) scans all enabled external service auth blocks for fields matching the pattern `secret:<secretName>:<secretKey>` and builds a dict `kiali_deployment_secret_volumes` that maps each logical volume name (e.g. `grafana-username`) to its Secret name and key.

**Coverage:** The following CR fields support the `secret:` prefix (the secret expansion only runs for enabled services — `secret:` fields under `prometheus.auth` are ignored when `prometheus.enabled: false`; this is intentional to avoid mounting secrets that Kiali won't use, keeping RBAC requirements minimal):
- `external_services.prometheus.auth.{username, password, token, cert_file, key_file}`
- `external_services.tracing.auth.{username, password, token, cert_file, key_file}`
- `external_services.grafana.auth.{username, password, token, cert_file, key_file}`
- `external_services.custom_dashboards.prometheus.auth.{username, password, token, cert_file, key_file}`
- `external_services.perses.auth.{username, password, cert_file, key_file}`
- `login_token.signing_key`
- `ai.chat.providers[*].key` and `ai.chat.providers[*].models[*].key` (only when `enabled: true`)

For each matched field, the deployment template creates a Secret volume and mounts it at `/kiali-override-secrets/<volume-name>/` with `readOnly: true`. The Kiali server reads the file from disk via `conf.GetCredential("/kiali-override-secrets/...")`, which is watched by `CredentialManager` for rotation.

**Fixed volumes always mounted** (regardless of CR config):

| Volume | Mount path | Source |
|---|---|---|
| `kiali-configuration` | `/kiali-configuration` | ConfigMap `<instance>` |
| `kiali-secret` | `/kiali-secret` | Secret named by `deployment.secret_name` (default: `kiali`); optional; carries OIDC client secret at key `oidc-secret` |
| `kiali-cabundle` | `/kiali-cabundle` | Projected volume (see above) |
| `kiali-multi-cluster-secret` | `/kiali-remote-cluster-secrets/kiali-multi-cluster-secret` | Secret `kiali-multi-cluster-secret`; optional |

**Security guardrail:** Any user-provided `additional_pod_containers_yaml` or `additional_pod_init_containers_yaml` that attempts to mount a secret-backed volume as read-write causes an immediate task failure. The deploy role (`tasks/main.yml`) identifies all secret-backed volume names and force-sets `readOnly: true` on any matching mounts in additional containers.

**Propagation timing:** Kubernetes propagates Secret/ConfigMap changes to mounted volumes with up to ~60 seconds delay (kubelet sync period). The `external-auth-rotation-test` molecule scenario accounts for this by pausing 90 seconds after rotating Secrets before asserting that Kiali uses the new credentials.
