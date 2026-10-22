# Lab: Argo CD agent in hybrid mode (push + pull on the same hub)

Goal: a **single** Argo CD hub that manages, at the same time:
- **legacy apps** with classic push (the hub controller deploys directly),
- **new apps** through **argocd-agent** in *managed* mode (the spoke controller deploys).

Both target **the same spoke cluster**, which is registered twice on the hub. The lab does this for
two spokes.

It runs on the SNO clusters of the acm-dr lab, with **OpenShift GitOps** (operator-managed `ArgoCD` CRs):

| Context | Role |
|---|---|
| `sno1` | hub: Argo CD (UI + controller for push) + principal |
| `sno2`, `sno3` | spokes: slim Argo CD (controller, no UI) + agent |

## Architecture

> **▶ [Watch the animated flow diagram](diagrams/argo-agent-flow.html)**: setup, push, pull, UI, and the two
> demos, step by step.

```
 HUB sno1 (ns argocd)                                        SPOKE sno2 / sno3 (ns argocd)
┌──────────────────────────────────────────────┐            ┌────────────────────────────────────────────┐
│ argocd-server (UI, Route)                    │            │                                            │
│   └─► principal redis-proxy (operator wiring)│            │                                            │
│                                              │            │                                            │
│ application-controller (hub)                 │    push    │                                            │
│   ├─► secret <spoke>-direct (no skip) ────────────────────► API :6443                                  │
│   │                                          │   :6443    │   └─► ns guestbook-legacy                  │
│   └─✗ secret <spoke>-agent (skip-reconcile)  │            │       ns guestbook-migrate                 │
│                                              │            │                                            │
│ argocd-agent-principal ◄───────────────────────────────────── argocd-agent-agent (managed)             │
│   Route :443 passthrough                     │    pull    │     └─► local application-controller       │
│   label-selector argocd-agent=true           │ gRPC mTLS  │           └─► ns guestbook-agent           │
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
| `guestbook-legacy-<spoke>` | – | `<spoke>-direct` | hub (push) |
| `guestbook-agent-<spoke>` | `true` | `<spoke>-agent` | agent (pull) |
| `guestbook-migrate-<spoke>` | – then `true` | `<spoke>-direct` then `<spoke>-agent` | push, then migrated |

## The 3 safeguards (all in this lab)

1. **`skip-reconcile` on the agent cluster secret** (`scripts/03-spokes.sh`): the hub controller ignores apps targeting `<spoke>-agent`.
2. **Label selector** on the principal (`hub/argocd.yaml`) and on the agents (`spoke/argocd.yaml`): they only see resources labeled `argocd-agent=true`.
3. **`ARGOCD_AGENT_IGNORE_UNMANAGED_APPS=true`** (`spoke/argocd.yaml`): a safety net for apps that already existed on the spoke.

The label selector and the safety net are set through `env` in the `ArgoCD` CR: the `labelSelector`
field only exists from argocd-operator 0.20 (GitOps 1.22).

With the principal enabled, the operator already points `argocd-server` and `repo-server` to the
principal **redis-proxy**, so the UI shows the resource tree of agent apps. No patch needed.

## Prerequisites

- `oc` logged in to the 3 contexts `sno1`, `sno2`, `sno3` (same kubeconfig as acm-dr; tokens expire, `oc login` again if a step says "not logged in")
- `argocd-agentctl` **v0.10.x** ([releases](https://github.com/argoproj-labs/argocd-agent/releases)) in your `PATH`
- `curl`
- Network: spokes reach the hub `*.apps` on `443` (agent), hub reaches the spokes API on `6443` (push)
- OpenShift GitOps **≥ 1.21** in the chosen channel: it ships Argo CD 3.4, and `skip-reconcile` on a
  cluster secret requires **Argo CD ≥ 3.4**. `./lab.sh operator` refuses older versions.

Other contexts: `HUB_CTX=... SPOKES="a b" ./lab.sh up`. Spoke context names are used as name prefixes,
so they must be DNS-safe. GitOps channel: `GITOPS_CHANNEL` (default `latest`).

### What the lab changes on the shared SNOs

- OpenShift GitOps operator in `openshift-gitops-operator`, with `DISABLE_DEFAULT_ARGOCD_INSTANCE=true`
  (no `openshift-gitops` instance) and `ARGOCD_CLUSTER_CONFIG_NAMESPACES=argocd` (cluster-scoped `argocd` instance).
- Namespace `argocd` on all three. On the spokes: `guestbook-*` namespaces and the `argocd-manager`
  ServiceAccount (**cluster-admin**, used by the hub for push) in `kube-system`.
- Nothing in the ACM namespaces. ACM on `sno1` and the klusterlet on `sno3` are left alone.

## Usage

```bash
chmod +x lab.sh
./lab.sh up          # GitOps operator + hub (Argo CD + principal) + spokes (Argo CD + agent) + push secrets + apps
./lab.sh verify      # who manages what (secrets, hub/spoke apps, workloads, hub controller logs)
./lab.sh ui          # hub UI Route (admin / password printed)
```

Step by step: `./lab.sh operator`, then `hub`, `spokes`, `push`, `apps`.

| Step | Script | What it does |
|---|---|---|
| `operator` | `01-operator.sh` | GitOps Subscription on the 3 clusters, waits for the CSV, checks version ≥ 1.21 |
| `hub` | `02-hub.sh` | agent PKI (CA, principal cert for the Route host, resource-proxy cert, JWT key), then `hub/argocd.yaml` |
| `spokes` | `03-spokes.sh` | per spoke: `agentctl agent create` + `skip-reconcile`, client cert, then `spoke/argocd.yaml` |
| `push` | `04-push.sh` | per spoke: `argocd-manager` SA, cluster secret `<spoke>-direct` |
| `apps` | `05-apps.sh` | `agent-apps` AppProject (one destination per agent) + 3 apps per spoke from `apps/` |

The principal certificate is issued **before** the `ArgoCD` CR, for the predictable Route host
`argocd-agent-principal-argocd.<apps domain>`. `02-hub.sh` warns if the real Route host differs.

### What `./lab.sh verify` should show

- 4 cluster secrets, with `skip-reconcile=true` **only** on `sno2-agent` and `sno3-agent`.
- On the **hub**, all 6 apps. On **each spoke**, **only** its `guestbook-agent-<spoke>` (with a `source-uid` annotation).
- All 3 `guestbook-*` namespaces deployed on each spoke.
- No `guestbook-agent-*` lines in the hub controller logs.

## Demos

Both demos take an optional spoke (default: first one, `sno2`).

### 1. Why `skip-reconcile` is required

```bash
./lab.sh demo-skip [sno3]
```

The script removes the annotation from `cluster-<spoke>-agent`, restarts the hub controller pod,
waits 60 s (`WAIT=120 ./lab.sh demo-skip` for longer), then shows:
- the **hub** controller logs as it starts processing `guestbook-agent-<spoke>` (through the resource proxy);
- the app status / conditions on the hub, which become inconsistent (two controllers write the same status).

It then restores the annotation.

Pods are restarted by deleting them, not with `rollout restart`: the operator owns the workloads and
reverts template changes.

### 2. Migrating a legacy app to the agent

```bash
./lab.sh demo-migrate [sno3]
```

Three changes on `guestbook-migrate-<spoke>`:
1. `spec.destination.name: <spoke>-agent`: the hub stops managing it (skip-reconcile);
2. `spec.project: agent-apps`: the `default` project is not labeled, so it is not copied to the spoke;
3. label `argocd-agent=true`: the principal sends it to the agent.

Pods are not recreated: the spoke controller adopts the existing resources.

## Cleanup

```bash
./lab.sh down                        # ArgoCD CRs, argocd + guestbook-* namespaces, argocd-manager
REMOVE_OPERATOR=true ./lab.sh down   # also removes the GitOps Subscription/CSV (CRDs are kept)
```

The clusters stay up (acm-dr uses them).

## Things to watch

- **Never** put `skip-reconcile` on a `*-direct` secret, or the push apps stop.
- A given Kubernetes resource must not belong to both a push app and an agent app. Here, each app has its own namespace.
- Any AppProject or (project-scoped) repo secret used by an agent app **must carry the label**, otherwise it does not exist on the spoke.
- If you create the agent secret other than with `argocd-agentctl agent create` (GitOps, by hand), add the annotation yourself.
- Do not edit the operator-managed Deployments/ConfigMaps (`argocd-agent-params`, `argocd-cmd-params-cm`...): the operator reverts them. Change the `ArgoCD` CR.
- The principal runs as a single replica; HA is out of scope for this lab.

## Quick troubleshooting

```bash
oc --context sno1 -n argocd logs deploy/argocd-agent-principal
oc --context sno2 -n argocd logs deploy/argocd-agent-agent
oc --context sno2 -n argocd logs statefulset/argocd-application-controller
oc --context sno1 -n argocd get argocd argocd -o jsonpath='{.status}'   # operator view of the instance
```

- Agent `x509: certificate is valid for ...`: the principal Route host differs from the cert; rerun `./lab.sh hub` (re-issues with `--upsert`), then delete the principal pod.
- Agent `connection refused` / timeout: check `principalServerAddress` in the spoke `ArgoCD` CR and that the spoke reaches `https://<route host>` on 443.
- Principal `CrashLoopBackOff` with missing secret: PKI not issued in `argocd` on the hub; rerun `./lab.sh hub`.
- No resource tree in the UI for `guestbook-agent-*`: check `argocd-server` runs with `--redis argocd-agent-principal-redisproxy...` and the principal `redisproxy` Service exists.
- `<spoke>-direct` apps `Unknown`: hub cannot reach the spoke API on 6443, or the token secret in `kube-system` was deleted; rerun `./lab.sh push`.

## References

- [argocd-agent: Hybrid Architecture](https://argocd-agent.readthedocs.io/latest/user-guide/hybrid-architecture/)
- [argocd-agent: Getting started on OpenShift (operator)](https://argocd-agent.readthedocs.io/latest/getting-started/openshift/)
- [Argo CD: Skipping cluster reconciliation](https://argo-cd.readthedocs.io/en/latest/operator-manual/cluster-management/)
