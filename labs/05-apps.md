# 05 - Applications: app of apps, push and pull side by side

*Acronyms: UID = unique identifier.*

All Applications live **on the hub**, in `argocd`. Only one is created by hand: the **root** app
([`manifests/hub/root-app.yaml.tpl`](../manifests/hub/root-app.yaml.tpl)). It runs on the hub itself (in-cluster,
push) and creates everything under [`gitops/`](../gitops/) from Git:

```
gitops/
├── appproject-agent-apps.yaml     AppProject for agent apps (sync wave -1)
├── sno2/
│   ├── guestbook-legacy.yaml      push
│   ├── guestbook-agent.yaml       pull
│   └── guestbook-migrate.yaml     push, migrated in module 07
└── sno3/                          same three
```

Two things decide who deploys a child app:

| | Push (hub controller) | Pull (agent) |
|---|---|---|
| `metadata.labels.argocd-agent` | absent | `"true"` (seen by the principal) |
| `spec.destination.name` | `<spoke>-direct` | `<spoke>-agent` (skip-reconcile) |
| `spec.project` | any (`default`) | a **labeled** project (`agent-apps`) |

| Application | Label | Destination | Managed by |
|---|---|---|---|
| `root` | - | in-cluster (hub) | hub (push) |
| `guestbook-legacy-<spoke>` | - | `<spoke>-direct` | hub (push) |
| `guestbook-agent-<spoke>` | `argocd-agent=true` | `<spoke>-agent` | agent (pull) |
| `guestbook-migrate-<spoke>` | - (until module 07) | `<spoke>-direct` | hub (push), then migrated |

The root app has no label: the principal ignores it. It only writes Application objects on the hub; each child
then goes to the hub controller or to the principal on its own.

Why `agent-apps`: an agent app is copied to the spoke **with its project**. The `default` project is not labeled,
so it does not exist on the spoke.

## 1. The root app

```bash
source ./env.sh
echo "$GIT_REPO @ $GIT_BRANCH"
envsubst < manifests/hub/root-app.yaml.tpl | oc --context $HUB apply -f -
```

```bash
oc --context $HUB -n argocd get application root -w
# root   Synced   Healthy   (Ctrl+C)
```

It created the AppProject and the 6 children:

```bash
oc --context $HUB -n argocd get appproject agent-apps
oc --context $HUB -n argocd get applications
# root + 6 guestbook-* apps
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
oc --context $HUB -n argocd get applications \
  -o custom-columns='NAME:.metadata.name,DEST:.spec.destination.name,AGENT-LABEL:.metadata.labels.argocd-agent,SYNC:.status.sync.status,HEALTH:.status.health.status'
# guestbook-agent-sno2     sno2-agent    true     Synced   Healthy
# guestbook-legacy-sno2    sno2-direct   <none>   Synced   Healthy
# guestbook-migrate-sno2   sno2-direct   <none>   Synced   Healthy
# ... same for sno3
# root                     <none>        <none>   Synced   Healthy
```

On each spoke, **only** its agent app, with the `source-uid` annotation that links it to the hub app:

```bash
for s in sno2 sno3; do
  oc --context $s get applications -A \
    -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,SOURCE-UID:.metadata.annotations.argocd\.argoproj\.io/source-uid,SYNC:.status.sync.status'
done
# argocd   guestbook-agent-sno2   <uid>   Synced
# argocd   guestbook-agent-sno3   <uid>   Synced
```

The workloads, all three namespaces on each spoke:

```bash
for s in sno2 sno3; do
  for n in guestbook-legacy guestbook-agent guestbook-migrate; do
    printf '%-6s %-18s ' $s $n
    oc --context $s -n $n get deploy guestbook-ui -o jsonpath='{.status.readyReplicas}/{.spec.replicas} ready{"\n"}'
  done
done
# sno2   guestbook-legacy   1/1 ready   ... (6 lines)
```

The hub controller must not work on the agent apps (safeguard 1):

```bash
oc --context $HUB -n argocd logs statefulset/argocd-application-controller --since=5m \
  | grep -c 'guestbook-agent-'
# 0
oc --context $HUB -n argocd logs statefulset/argocd-application-controller --since=5m \
  | grep -c 'guestbook-legacy-'
# > 0 (push apps are reconciled by the hub)
```

In the UI, open `root`: its tree shows the 6 child Applications. Open `guestbook-agent-sno2`: its resource
tree is served by the principal redis-proxy and resource proxy, from the agent.

## Checkpoint

- [ ] `root` `Synced` / `Healthy`, 6 children created from Git
- [ ] 6 children `Synced` / `Healthy` on the hub
- [ ] Each spoke shows only its `guestbook-agent-<spoke>`, with a `source-uid`
- [ ] 3 `guestbook-ui` deployments ready on each spoke
- [ ] No `guestbook-agent-` lines in the hub controller logs
