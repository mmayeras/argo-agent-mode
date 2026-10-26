# 07 - Demo: migrate a push app to the agent

`argodemo-migrate-sno2` was deployed by the hub (push). Move it to the agent without redeploying the pods.

The app comes from Git (root app, [module 05](05-apps.md)), and the root app has `selfHeal`: an `oc patch`
would be reverted. The migration is a **Git change**. You need push access to `$GIT_REPO` (use your fork).

```bash
source ./env.sh
export SPOKE=sno2
```

## 1. Before

```bash
oc --context $SPOKE -n argodemo-migrate get pods -o wide
# note the pod names and ages
```

## 2. Edit the child app in Git

In [`gitops/sno2/argodemo-migrate.yaml`](../gitops/sno2/argodemo-migrate.yaml), three changes:

```yaml
metadata:
  name: argodemo-migrate-sno2
  namespace: argocd
  labels:
    argocd-agent: "true"        # 1. the principal picks it up
spec:
  project: agent-apps           # 2. labeled project, exists on the spoke (default does not)
  ...
  destination:
    name: sno2-agent            # 3. skip-reconcile: the hub controller lets go
    namespace: argodemo-migrate
```

```bash
git add gitops/sno2/argodemo-migrate.yaml
git commit -m "Migrate argodemo-migrate-sno2 to the agent"
git push
```

The three changes land in one sync, so the hub controller lets go (destination) at the same time the principal
takes over (label). Never add the label alone: the app would be sent to the agent while the hub still pushes it,
two controllers again ([module 06](06-demo-skip-reconcile.md)).

## 3. Sync

The root app polls Git (about 3 minutes). To go faster, refresh it:

```bash
oc --context $HUB -n argocd annotate applications.argoproj.io root argocd.argoproj.io/refresh=normal --overwrite
oc --context $HUB -n argocd get applications.argoproj.io argodemo-migrate-$SPOKE \
  -o jsonpath='{.spec.destination.name}{"  "}{.metadata.labels.argocd-agent}{"\n"}'
# sno2-agent  true
```

The principal sends the app to the agent:

```bash
oc --context $SPOKE -n argocd get applications.argoproj.io argodemo-migrate-$SPOKE -w
# argodemo-migrate-sno2   Synced   Healthy   (Ctrl+C)
```

## 4. After

```bash
oc --context $SPOKE -n argodemo-migrate get pods -o wide
# same names, same ages: the spoke controller adopted the existing resources

oc --context $HUB -n argocd get applications.argoproj.io argodemo-migrate-$SPOKE \
  -o jsonpath='{.spec.destination.name}{"  "}{.status.sync.status}{" / "}{.status.health.status}{"\n"}'
# sno2-agent  Synced / Healthy
```

## 5. Prove the agent owns it (optional)

Point it at the green overlay, like the agent apps:

```yaml
    path: workloads/argodemo/overlays/green     # in gitops/sno2/argodemo-migrate.yaml
```

```bash
git commit -am "argodemo-migrate-sno2: green" && git push
oc --context $HUB -n argocd annotate applications.argoproj.io root argocd.argoproj.io/refresh=normal --overwrite
```

This time the pods **are** replaced (new ConfigMap hash), by the spoke controller: the page turns green. This app
also sets the `managed-by` label on its namespace, so the spoke Argo CD can write there.

## Checkpoint

- [ ] Same pods before and after
- [ ] App now on the spoke with a `source-uid`, `Synced` / `Healthy` on the hub
- [ ] `root` still `Synced` (Git and cluster agree)

To replay the demo, revert the commit and push: the app goes back to push.
