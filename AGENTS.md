# Kiali Operator

Ansible-based Kubernetes operator that manages Kiali (service mesh observability UI) and the OpenShift Service Mesh Console plugin via Custom Resource Definitions.

## Documentation

Topic files live in [docs/agents/](docs/agents/).

| Topic | Description |
|-------|-------------|
| [Operator Architecture](docs/agents/operator-architecture.md) | How the Ansible operator is structured — watches files, entry-point playbooks, role versioning strategy, and CR lifecycle (deploy/remove). |
| [CRD & API Surface](docs/agents/crd-and-api.md) | The Kiali and OSSMConsole Custom Resource Definitions — schema, defaults, doc-generation pipeline, validation scripts, and CRD sync across manifests. |
| [OLM Bundle & Manifests](docs/agents/olm-manifests.md) | Operator Lifecycle Manager bundles for kiali-upstream (community) and kiali-ossm (Red Hat) — versioned CSV generation and the convert/release scripts. |
| [Molecule Test Suite](docs/agents/molecule-testing.md) | Integration test scenarios (accessible-namespaces, config-values, auth, multi-cluster, etc.), shared asserts/common tasks, and how to run tests against a live cluster. |
| [Build & CI](docs/agents/build-and-ci.md) | Container image build (Dockerfile, multi-arch), Makefile targets, OPM tooling, CRD sync/validate pipeline, and the deploy script. |
