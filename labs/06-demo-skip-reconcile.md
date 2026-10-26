# 06 - Demo: why `skip-reconcile` is required

Remove the annotation from one agent secret and watch the hub controller step on the agent. Then put it back.

```bash
source ./env.sh
export SPOKE=sno2
```

## 1. Remove the annotation

```bash
oc --context $HUB -n argocd annotate secret cluster-$SPOKE-agent argocd.argoproj.io/skip-reconcile-
```

Restart the hub controller so it rebuilds its cluster cache. Delete the pod, do not use `rollout restart`:
the operator owns the StatefulSet and reverts changes to it.

```bash
oc --context $HUB -n argocd delete pod argocd-application-controller-0
oc --context $HUB -n argocd get pod argocd-application-controller-0 -w
# 1/1 Running   (Ctrl+C)
```

## 2. Watch

Wait one minute. The hub controller now processes `argodemo-agent-$SPOKE`, reaching the spoke through the
resource proxy:

```bash
oc --context $HUB -n argocd logs statefulset/argocd-application-controller --since=2m \
  | grep argodemo-agent-$SPOKE | tail -n 20
# reconciliation lines for argodemo-agent-sno2: the hub is now a second controller
```

Two writers on the same Application status (hub controller and principal):

```bash
oc --context $HUB -n argocd get applications.argoproj.io argodemo-agent-$SPOKE \
  -o jsonpath='{.status.sync.status}{" / "}{.status.health.status}{"\n"}{range .status.conditions[*]}{.type}{": "}{.message}{"\n"}{end}'
oc --context $HUB -n argocd get applications.argoproj.io argodemo-agent-$SPOKE -w
# sync/health flapping, error conditions   (Ctrl+C)
```

## 3. Restore

```bash
oc --context $HUB -n argocd annotate secret cluster-$SPOKE-agent argocd.argoproj.io/skip-reconcile=true --overwrite
oc --context $HUB -n argocd delete pod argocd-application-controller-0
```

## Takeaways

- `skip-reconcile=true` on every agent cluster secret, `argocd-agentctl agent create` sets it.
- Never on a `-direct` secret.
- Requires Argo CD >= 3.4 (OpenShift GitOps >= 1.21). On older versions the annotation is ignored.

## Checkpoint

- [ ] Saw `argodemo-agent-sno2` in the hub controller logs while the annotation was gone
- [ ] Annotation restored, no more `argodemo-agent-` lines after the restart
