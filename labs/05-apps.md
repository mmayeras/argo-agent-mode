# 05 - Applications: app of apps, push and pull side by side

*Acronyms: UID = unique identifier.*

All Applications live **on the hub**, in `argocd`. Only one is created by hand: the **root** app
([`manifests/hub/root-app.yaml.tpl`](../manifests/hub/root-app.yaml.tpl)). It runs on the hub itself (in-cluster,
push) and creates everything under [`gitops/`](../gitops/) from Git:

```
gitops/
├── appproject-agent-apps.yaml     AppProject for agent apps (sync wave -1)
├── sno2/
│   ├── argodemo-legacy.yaml      push
│   ├── argodemo-agent.yaml       pull
│   └── argodemo-migrate.yaml     push, migrated in module 07
└── sno3/                          same three
```

Every child deploys the same app, **argodemo** ([`app/`](../app/), image `quay.io/rh_ee_mmayeras/argodemo`): a page
filled with a color, showing its namespace, pod and node. Its manifests are in
[`workloads/argodemo/`](../workloads/argodemo/), with kustomize:

```
workloads/argodemo/
├── base/                 Deployment (non-root, 8080), Service, edge Route (insecureEdgeTerminationPolicy: Allow),
│                         ConfigMap argodemo (COLOR, MESSAGE) from a configMapGenerator
└── overlays/
    ├── blue/             COLOR=steelblue   <- push apps (legacy, migrate)
    └── green/            COLOR=seagreen    <- agent apps
```

The files have no namespace: each app's `destination.namespace` sets it. The ConfigMap name carries a content hash,
so a color change rolls the pods.

Two things decide who deploys a child app:

| | Push (hub controller) | Pull (agent) |
|---|---|---|
| `metadata.labels.argocd-agent` | absent | `"true"` (seen by the principal) |
| `spec.destination.name` | `<spoke>-direct` | `<spoke>-agent` (skip-reconcile) |
| `spec.project` | any (`default`) | a **labeled** project (`agent-apps`) |

| Application | Label | Destination | Managed by |
|---|---|---|---|
| `root` | - | in-cluster (hub) | hub (push) |
| `argodemo-legacy-<spoke>` | - | `<spoke>-direct` | hub (push) |
| `argodemo-agent-<spoke>` | `argocd-agent=true` | `<spoke>-agent` | agent (pull) |
| `argodemo-migrate-<spoke>` | - (until module 07) | `<spoke>-direct` | hub (push), then migrated |

The root app has no label: the principal ignores it. It only writes Application objects on the hub; each child
then goes to the hub controller or to the principal on its own.

Why `agent-apps`: an agent app is copied to the spoke **with its project**. The `default` project is not labeled,
so it does not exist on the spoke.

Two settings in every child app:

- `finalizers: [resources-finalizer.argocd.argoproj.io]`: deleting the app (or removing its file from Git, the
  root app prunes it) also deletes its workloads. Without it they are left orphaned. For agent apps, the agent
  deletes the spoke copy and its workloads, then the principal removes the hub finalizer.
- Agent apps (and the migrate app, for after module 07) set the label `argocd.argoproj.io/managed-by: argocd` on
  their namespace with `managedNamespaceMetadata`. The spoke Argo CD can only deploy in namespaces with that label
  ([module 01](01-operator.md)). The first sync can be `forbidden` for a few seconds, until the operator creates
  the Role: `retry` covers it.

## 1. The root app

```bash
source ./env.sh
echo "$GIT_REPO @ $GIT_BRANCH"
envsubst < manifests/hub/root-app.yaml.tpl | oc --context $HUB apply -f -
```

```bash
oc --context $HUB -n argocd get applications.argoproj.io root -w
# root   Synced   Healthy   (Ctrl+C)
```

It created the AppProject and the 6 children:

```bash
oc --context $HUB -n argocd get appproject agent-apps
oc --context $HUB -n argocd get applications.argoproj.io
# root + 6 argodemo-* apps
```

The principal sends the labeled AppProject to every agent:

```bash
for s in sno2 sno3; do oc --context $s -n argocd get appproject agent-apps; done
# agent-apps   (on both spokes)
```

Give the children 1 to 2 minutes.

## 2. Who manages what

On the hub, all 7:

```bash
oc --context $HUB -n argocd get applications.argoproj.io \
  -o custom-columns='NAME:.metadata.name,DEST:.spec.destination.name,AGENT-LABEL:.metadata.labels.argocd-agent,SYNC:.status.sync.status,HEALTH:.status.health.status'
# argodemo-agent-sno2     sno2-agent    true     Synced   Healthy
# argodemo-legacy-sno2    sno2-direct   <none>   Synced   Healthy
# argodemo-migrate-sno2   sno2-direct   <none>   Synced   Healthy
# ... same for sno3
# root                     <none>        <none>   Synced   Healthy
```

On each spoke, **only** its agent app, with the `source-uid` annotation that links it to the hub app:

```bash
for s in sno2 sno3; do
  oc --context $s get applications.argoproj.io -A \
    -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,SOURCE-UID:.metadata.annotations.argocd\.argoproj\.io/source-uid,SYNC:.status.sync.status'
done
# argocd   argodemo-agent-sno2   <uid>   Synced
# argocd   argodemo-agent-sno3   <uid>   Synced
```

The workloads, all three namespaces on each spoke:

```bash
for s in sno2 sno3; do
  for n in argodemo-legacy argodemo-agent argodemo-migrate; do
    printf '%-6s %-18s ' $s $n
    oc --context $s -n $n get deploy argodemo -o jsonpath='{.status.readyReplicas}/{.spec.replicas} ready{"\n"}'
  done
done
# sno2   argodemo-legacy   1/1 ready   ... (6 lines)
```

Each app has its own Route (edge TLS, plain http allowed too). Push apps show a blue page, agent apps a green one:

```bash
for s in sno2 sno3; do
  for n in argodemo-legacy argodemo-agent argodemo-migrate; do
    oc --context $s -n $n get route argodemo -o jsonpath='https://{.spec.host}{"\n"}'
  done
done
```

The hub controller must not work on the agent apps (safeguard 1):

```bash
oc --context $HUB -n argocd logs statefulset/argocd-application-controller --since=5m \
  | grep -c 'argodemo-agent-'
# 0
oc --context $HUB -n argocd logs statefulset/argocd-application-controller --since=5m \
  | grep -c 'argodemo-legacy-'
# > 0 (push apps are reconciled by the hub)
```

In the UI, open `root`: its tree shows the 6 child Applications. Open `argodemo-agent-sno2`: its resource
tree is served by the principal redis-proxy and resource proxy, from the agent.

## 3. Color trick: change an agent app from Git

Everything about an agent app is changed on the hub, through Git: the spoke follows. Point `argodemo-agent-sno2`
at the blue overlay in [`gitops/sno2/argodemo-agent.yaml`](../gitops/sno2/argodemo-agent.yaml):

```yaml
    path: workloads/argodemo/overlays/blue      # was overlays/green
```

```bash
git commit -am "argodemo-agent-sno2: blue" && git push
oc --context $HUB -n argocd annotate applications.argoproj.io root argocd.argoproj.io/refresh=normal --overwrite
oc --context sno2 -n argodemo-agent get pods -w
# new pod (new ConfigMap hash), old one terminates   (Ctrl+C)
```

The page turns blue. Path: Git -> root app (hub) -> child app spec (hub) -> principal -> agent -> spoke controller.
The hub controller never touched it. Put it back to `overlays/green` the same way.

## Checkpoint

- [ ] `root` `Synced` / `Healthy`, 6 children created from Git
- [ ] 6 children `Synced` / `Healthy` on the hub
- [ ] Each spoke shows only its `argodemo-agent-<spoke>`, with a `source-uid`
- [ ] 3 `argodemo` deployments ready on each spoke, pages blue / green / blue
- [ ] No `argodemo-agent-` lines in the hub controller logs
- [ ] `argodemo-agent` namespace on each spoke labeled `argocd.argoproj.io/managed-by=argocd`
