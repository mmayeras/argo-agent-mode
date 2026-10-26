# 01 - Install OpenShift GitOps (hub and spokes)

*Acronyms: CSV = ClusterServiceVersion, CR = Custom Resource.*

The same Subscription goes on the three clusters: [`manifests/operator/gitops-subscription.yaml`](../manifests/operator/gitops-subscription.yaml).

Two settings in `spec.config.env`:

- `DISABLE_DEFAULT_ARGOCD_INSTANCE=true`: no `openshift-gitops` instance. The lab only uses the `argocd` instance it creates.
- `ARGOCD_CLUSTER_CONFIG_NAMESPACES=argocd`: the `argocd` instance is **cluster-scoped**. The doc requires a
  cluster-scoped instance for the principal and the agent; this variable is how OpenShift GitOps grants it.

Cluster-scoped does **not** mean "can deploy anywhere". The operator's ClusterRole gives the application-controller
read access everywhere, write access on namespaces and cluster configuration, but no write on workloads. It can
deploy only in namespaces labeled `argocd.argoproj.io/managed-by: argocd`: the operator then creates an admin Role
for it there. The agent apps set that label on their namespace ([module 05](05-apps.md)).

On clusters with ACM, short resource names are ambiguous (`subscription`, `application`): the lab always uses
the full names `subscriptions.operators.coreos.com` and `applications.argoproj.io`.

## 1. Subscribe

```bash
source ./env.sh
for c in sno1 sno2 sno3; do
  oc --context $c apply -f manifests/operator/gitops-subscription.yaml
done
# namespace/openshift-gitops-operator created
# operatorgroup.operators.coreos.com/openshift-gitops-operator created
# subscription.operators.coreos.com/openshift-gitops-operator created   (x3)
```

## 2. Wait for the operator

```bash
for c in sno1 sno2 sno3; do
  echo "== $c"
  oc --context $c get csv -n openshift-gitops-operator \
    -o custom-columns=NAME:.metadata.name,VERSION:.spec.version,PHASE:.status.phase
done
# == sno1
# openshift-gitops-operator.v1.22.x   1.22.x   Succeeded   (same on sno2, sno3)
```

Run it again until all three are `Succeeded` (2 to 5 minutes).

**The lab is written for 1.22** (Argo CD 3.5), the latest. Two things depend on it:

- `skip-reconcile` on a cluster secret needs Argo CD >= 3.4 (GitOps >= 1.21). Without it the hub controller fights
  the agent ([module 06](06-demo-skip-reconcile.md)).
- `labelSelector` on the principal and the agent is a CR field from GitOps 1.22.

| OpenShift GitOps | Argo CD | argocd-operator |
|---|---|---|
| 1.20 | 3.3 | 0.18 |
| 1.21 | 3.4 | 0.19 |
| **1.22** | **3.5** | 0.20 (adds `labelSelector` fields in the CR) |

If `latest` gives an older version, set `spec.channel` to `gitops-1.22` and apply again.

## 3. Check

```bash
for c in sno1 sno2 sno3; do
  oc --context $c get crd argocds.argoproj.io -o name
  oc --context $c get argocd -A
done
# customresourcedefinition.apiextensions.k8s.io/argocds.argoproj.io
# No resources found   (no default instance)
```

## Checkpoint

- [ ] CSV `Succeeded` on sno1, sno2, sno3, version 1.22.x: `__________`
- [ ] No `ArgoCD` instance anywhere yet
