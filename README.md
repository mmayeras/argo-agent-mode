# Lab: Argo CD agent in hybrid mode (push + pull on the same hub)

Goal: a **single** Argo CD hub that manages, at the same time:
- **legacy apps** with classic push (the hub controller deploys directly),
- **new apps** through **argocd-agent** in *managed* mode (the spoke controller deploys).

Both target **the same spoke cluster**, which is registered twice on the hub. The lab does this for
two spokes.

It runs on three Single Node OpenShift (SNO) clusters, with **OpenShift GitOps** (operator-managed `ArgoCD` CRs).
The apps are deployed with the **app of apps** pattern: one root Application on the hub creates the others from Git.

| Context | Role |
|---|---|
| `sno1` | hub: Argo CD (UI + controller for push) + principal |
| `sno2`, `sno3` | spokes: slim Argo CD (controller, no UI) + agent |

## Architecture

```
 HUB sno1 (ns argocd)                                        SPOKE sno2 / sno3 (ns argocd)
┌──────────────────────────────────────────────┐            ┌────────────────────────────────────────────┐
│ argocd-server (UI, Route)                    │            │                                            │
│   └─► principal redis-proxy (operator wiring)│            │                                            │
│                                              │            │                                            │
│ application-controller (hub)                 │    push    │                                            │
│   ├─► secret <spoke>-direct (no skip) ────────────────────► API :6443                                  │
│   │                                          │   :6443    │   └─► ns argodemo-legacy                  │
│   └─✗ secret <spoke>-agent (skip-reconcile)  │            │       ns argodemo-migrate                 │
│                                              │            │                                            │
│ argocd-agent-principal ◄───────────────────────────────────── argocd-agent-agent (managed)             │
│   Route :443 passthrough                     │    pull    │     └─► local application-controller       │
│   label-selector argocd-agent=true           │ gRPC mTLS  │           └─► ns argodemo-agent           │
│                                              │agent dials │                                            │
└──────────────────────────────────────────────┘            └────────────────────────────────────────────┘
```

Per spoke (`<spoke>` = `sno2`, `sno3`):

| Cluster secret on the hub | URL | `skip-reconcile` | Who deploys |
|---|---|---|---|
| `cluster-<spoke>-direct` | `https://api.<spoke>...:6443` | no | **hub** controller (push) |
| `cluster-<spoke>-agent` | principal resource proxy | **yes** | **spoke** controller (pull) |

| Application (on the hub) | `argocd-agent` label | Destination | Managed by |
|---|---|---|---|
| `root` (app of apps, creates the others from [`gitops/`](gitops/)) | – | in-cluster (hub) | hub (push) |
| `argodemo-legacy-<spoke>` | – | `<spoke>-direct` | hub (push) |
| `argodemo-agent-<spoke>` | `true` | `<spoke>-agent` | agent (pull) |
| `argodemo-migrate-<spoke>` | – then `true` | `<spoke>-direct` then `<spoke>-agent` | push, then migrated by a Git change |

## The 3 safeguards (all in this lab)

1. **`skip-reconcile` on the agent cluster secret** ([module 03](labs/03-spoke-agent.md)): the hub controller ignores apps targeting `<spoke>-agent`.
2. **Label selector** on the principal ([`manifests/hub/argocd.yaml`](manifests/hub/argocd.yaml)) and on the agents ([`manifests/spoke/argocd.yaml.tpl`](manifests/spoke/argocd.yaml.tpl)): they only see resources labeled `argocd-agent=true`.
3. **`ARGOCD_AGENT_IGNORE_UNMANAGED_APPS=true`** (spoke CR): a safety net for apps that already existed on the spoke.

The label selector is the `labelSelector` field of the `ArgoCD` CR (GitOps 1.22). The safety net has no CR field:
it is set through `env`.

With the principal enabled, the operator already points `argocd-server` and `repo-server` to the
principal **redis-proxy**, so the UI shows the resource tree of agent apps. No patch needed.

## Do the lab

Every step is a plain `oc` or `argocd-agentctl` command, with the expected output. Each module ends with a
**checkpoint**: do not move on until it passes.

| Step | Module | Cluster |
|---|---|---|
| Tools, contexts, network | [00 - Prerequisites](labs/00-prereqs.md) | all |
| OpenShift GitOps operator (1.22) | [01 - Operator](labs/01-operator.md) | sno1, sno2, sno3 |
| Agent PKI, Argo CD + principal | [02 - Hub](labs/02-hub.md) | sno1 |
| Register the agent, Argo CD + agent | [03 - Spoke: agent (pull)](labs/03-spoke-agent.md) | sno2, then sno3 |
| Register the same spoke for push | [04 - Spoke: push](labs/04-spoke-push.md) | sno2, then sno3 |
| Root app (app of apps), who manages what | [05 - Applications](labs/05-apps.md) | sno1 |
| Remove `skip-reconcile`, watch the conflict | [06 - Demo: skip-reconcile](labs/06-demo-skip-reconcile.md) | sno1 |
| Move a push app to the agent with a Git change | [07 - Demo: migrate](labs/07-demo-migrate.md) | Git, sno1, sno2 |
| Remove the lab | [08 - Clean up](labs/08-cleanup.md) | all |
| **Bonus:** one credential template for many repos and projects | [10 - Repo-creds](labs/10-bonus-repo-creds.md) | sno1, GitHub |
| When something is stuck | [09 - Troubleshooting](labs/09-troubleshooting.md) | |

```bash
cp env.example.sh env.sh && source ./env.sh     # HUB=sno1, SPOKE=sno2
```

## What you need

- `oc` with the contexts `sno1`, `sno2`, `sno3`, cluster-admin on each
- `argocd-agentctl` **v0.10.x** ([releases](https://github.com/argoproj-labs/argocd-agent/releases)), `envsubst`, `curl`, `openssl`
- Network: spokes reach the hub `*.apps` on `443` (agent), the hub reaches the spoke APIs on `6443` (push)
- A Git repo the root app reads: this one by default (`GIT_REPO` in `env.sh`). Push access (your fork) for the
  migration demo
- OpenShift GitOps **1.22** (latest, Argo CD 3.5): `labelSelector` in the CR, and `skip-reconcile` on a cluster secret requires
  **Argo CD >= 3.4**

### What the lab changes on the shared SNOs

- OpenShift GitOps operator in `openshift-gitops-operator`, with `DISABLE_DEFAULT_ARGOCD_INSTANCE=true`
  (no `openshift-gitops` instance) and `ARGOCD_CLUSTER_CONFIG_NAMESPACES=argocd` (cluster-scoped `argocd` instance).
- Namespace `argocd` on all three. On the spokes: `argodemo-*` namespaces and the `argocd-manager`
  ServiceAccount (**cluster-admin**, used by the hub for push) in `kube-system`.

## Things to watch

- **Never** put `skip-reconcile` on a `*-direct` secret, or the push apps stop.
- A given Kubernetes resource must not belong to both a push app and an agent app. Here, each app has its own namespace.
- Any AppProject or (project-scoped) repo secret used by an agent app **must carry the label**, otherwise it does not exist on the spoke.
- If you create the agent secret other than with `argocd-agentctl agent create` (GitOps, by hand), add the annotation yourself.
- Do not edit the operator-managed Deployments/ConfigMaps (`argocd-agent-params`, `argocd-cmd-params-cm`...): the operator reverts them. Change the `ArgoCD` CR.
- The principal runs as a single replica; HA is out of scope for this lab.

## Where things are

- [`labs/`](labs/): the guided modules, every command with its expected output.
- [`manifests/`](manifests/): applied by hand: operator Subscription, hub and spoke `ArgoCD` CRs, `argocd-manager`,
  root app (`*.tpl` are rendered with `envsubst`).
- [`gitops/`](gitops/): read by the root app from Git: AppProject `agent-apps` and 3 Applications per spoke.
- [`app/`](app/): **argodemo**, the web app every child deploys (Go, Hummingbird images, `quay.io/rh_ee_mmayeras/argodemo`).
- [`workloads/argodemo/`](workloads/argodemo/): its manifests, kustomize base + `blue` / `green` overlays (page color).

## References

- [Using Argo CD Agent with OpenShift GitOps](https://developers.redhat.com/blog/2025/10/06/using-argo-cd-agent-openshift-gitops)
  (Red Hat Developer, GitOps 1.17 tech preview). This lab follows the same steps, with what newer operators
  changed: the principal Route, resource-proxy Service, NetworkPolicies and redis-proxy wiring are now created by
  the operator, and destination-based mapping replaces one hub namespace per agent.
- [argocd-agent: Hybrid Architecture](https://argocd-agent.readthedocs.io/latest/user-guide/hybrid-architecture/)
- [argocd-agent: Getting started on OpenShift (operator)](https://argocd-agent.readthedocs.io/latest/getting-started/openshift/)
- [Argo CD: Skipping cluster reconciliation](https://argo-cd.readthedocs.io/en/latest/operator-manual/cluster-management/)
