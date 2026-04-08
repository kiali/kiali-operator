---
base_branch: master
languages:
  - ansible
  - yaml
  - python
  - bash
key_paths:
  - roles/default/
  - molecule/
  - crd-docs/crd/
  - manifests/
  - hack/
  - .github/workflows/
---

# Project Context — kiali-operator

Ansible-based Kubernetes Operator for Kiali (a service mesh observability UI). The operator manages the lifecycle of Kiali and OSSMConsole custom resources on Kubernetes and OpenShift clusters.

Primary concerns during review:
- Ansible role correctness and idiomatic task structure
- CRD schema changes (golden copy, sync, backward compat, defaults parity)
- Molecule test coverage — especially `config-values-test` when config settings change
- RBAC and security guardrail integrity
