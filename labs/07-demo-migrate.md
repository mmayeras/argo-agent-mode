# 07 - Demo: migrate a push app to the agent

`bgd-migrate-sno2` was deployed by the hub (push). Move it to the agent without redeploying the pods.

The app comes from Git (root app, [module 05](05-apps.md)), and the root app has `selfHeal`: an `oc patch`
would be reverted. The migration is a **Git change**. You need push access to `$GIT_REPO` (use your fork).

```bash
source ./env.sh
export SPOKE=sno2
```

## 1. Before

```bash
oc --context $SPOKE -n bgd-migrate get pods -o wide
# note the pod names and ages
```

## 2. Edit the child app in Git

In [`gitops/sno2/bgd-migrate.yaml`](../gitops/sno2/bgd-migrate.yaml), three changes:

```yaml
metadata:
  name: bgd-migrate-sno2
  namespace: argocd
  labels:
    argocd-agent: "true"        # 1. the principal picks it up
spec:
  project: agent-apps           # 2. labeled project, exists on the spoke (default does not)
  ...
  destination:
    name: sno2-agent            # 3. skip-reconcile: the hub controller lets go
    namespace: bgd-migrate
```

```bash
git add gitops/sno2/bgd-migrate.yaml
git commit -m "Migrate bgd-migrate-sno2 to the agent"
git push
```

The three changes land in one sync, so the hub controller lets go (destination) at the same time the principal
takes over (label). Never add the label alone: the app would be sent to the agent while the hub still pushes it,
two controllers again ([module 06](06-demo-skip-reconcile.md)).

## 3. Sync

The root app polls Git (about 3 minutes). To go faster, refresh it:

```bash
oc --context $HUB -n argocd annotate applications.argoproj.io root argocd.argoproj.io/refresh=normal --overwrite
oc --context $HUB -n argocd get applications.argoproj.io bgd-migrate-$SPOKE \
  -o jsonpath='{.spec.destination.name}{"  "}{.metadata.labels.argocd-agent}{"\n"}'
# sno2-agent  true
```

The principal sends the app to the agent:

```bash
oc --context $SPOKE -n argocd get applications.argoproj.io bgd-migrate-$SPOKE -w
# bgd-migrate-sno2   Synced   Healthy   (Ctrl+C)
```

## 4. After

```bash
oc --context $SPOKE -n bgd-migrate get pods -o wide
# same names, same ages: the spoke controller adopted the existing resources

oc --context $HUB -n argocd get applications.argoproj.io bgd-migrate-$SPOKE \
  -o jsonpath='{.spec.destination.name}{"  "}{.status.sync.status}{" / "}{.status.health.status}{"\n"}'
# sno2-agent  Synced / Healthy
```

## Checkpoint

- [ ] Same pods before and after
- [ ] App now on the spoke with a `source-uid`, `Synced` / `Healthy` on the hub
- [ ] `root` still `Synced` (Git and cluster agree)

To replay the demo, revert the commit and push: the app goes back to push.
