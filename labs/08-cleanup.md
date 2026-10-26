# 08 - Clean up

The clusters stay up. This removes only what the lab created.

```bash
source ./env.sh
```

## 1. Hub

The root app first, or it recreates its children. Then the children: they carry
`resources-finalizer.argocd.argoproj.io`, so `oc delete` waits until their workloads are gone. Push apps are
cleaned by the hub controller; agent apps by the spoke controller, then the principal removes the hub finalizer.
The AppProject last: a child app cannot finish its cleanup without its project.

```bash
oc --context $HUB -n argocd delete applications.argoproj.io root
oc --context $HUB -n argocd delete applications.argoproj.io --all
oc --context $HUB -n argocd delete appproject agent-apps
oc --context $HUB -n argocd delete argocd argocd
oc --context $HUB delete namespace argocd
# PKI, cluster secrets and the agent registrations go with the namespace
```

## 2. Spokes

```bash
for s in sno2 sno3; do
  oc --context $s -n argocd delete argocd argocd
  oc --context $s delete namespace bgd-legacy bgd-agent bgd-migrate --ignore-not-found
  oc --context $s delete -f manifests/spoke/argocd-manager.yaml
  oc --context $s delete namespace argocd
done
```

## 3. Operator (optional)

```bash
for c in sno1 sno2 sno3; do
  CSV=$(oc --context $c -n openshift-gitops-operator get subscriptions.operators.coreos.com openshift-gitops-operator -o jsonpath='{.status.installedCSV}')
  oc --context $c -n openshift-gitops-operator delete subscriptions.operators.coreos.com openshift-gitops-operator
  oc --context $c -n openshift-gitops-operator delete csv $CSV
  oc --context $c delete namespace openshift-gitops-operator
done
```

The `argoproj.io` CRDs stay. Delete them only if nothing else on the cluster uses Argo CD:

```bash
for c in sno1 sno2 sno3; do oc --context $c get crd -o name | grep argoproj.io; done
```

## Checkpoint

- [ ] No `argocd` namespace on sno1, sno2, sno3
- [ ] No `bgd-*` namespaces on the spokes
- [ ] No `argocd-manager` in `kube-system` on the spokes
