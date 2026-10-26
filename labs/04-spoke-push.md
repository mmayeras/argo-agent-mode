# 04 - Spoke: register it again for push

*Acronyms: API = Application Programming Interface, SA = ServiceAccount, CA = Certificate Authority.*

**Run this module once per spoke**: `SPOKE=sno2`, then `SPOKE=sno3`.

The same spoke gets a **second** cluster secret on the hub, `cluster-$SPOKE-direct`, pointing straight to its API.
The hub application-controller deploys through it, like any classic Argo CD cluster.

| Secret on the hub | Server | `skip-reconcile` | Who deploys |
|---|---|---|---|
| `cluster-$SPOKE-agent` (module 03) | principal resource proxy | **true** | spoke controller (pull) |
| `cluster-$SPOKE-direct` (this module) | `$SPOKE` API :6443 | **none** | hub controller (push) |

```bash
source ./env.sh
export SPOKE=sno2     # second pass: export SPOKE=sno3
```

## 1. Account on the spoke

[`manifests/spoke/argocd-manager.yaml`](../manifests/spoke/argocd-manager.yaml): ServiceAccount `argocd-manager`
in `kube-system`, bound to **cluster-admin**, and a long-lived token Secret.

```bash
oc --context $SPOKE apply -f manifests/spoke/argocd-manager.yaml
oc --context $SPOKE -n kube-system get secret argocd-manager-token -o jsonpath='{.data.token}' | wc -c
# > 0 (token filled in by the token controller after a few seconds)
```

## 2. Collect token, CA and API URL

```bash
TOKEN=$(oc --context $SPOKE -n kube-system get secret argocd-manager-token -o jsonpath='{.data.token}' | base64 -d)
CA=$(oc --context $SPOKE -n kube-system get secret argocd-manager-token -o jsonpath='{.data.ca\.crt}')
SPOKE_API=$(oc --context $SPOKE whoami --show-server)
echo $SPOKE_API
```

Is the API certificate signed by that CA? (Not the case if the cluster has a custom API certificate.)

```bash
echo "$CA" | base64 -d > /tmp/$SPOKE-ca.crt
curl -s -o /dev/null -w '%{http_code}\n' --cacert /tmp/$SPOKE-ca.crt "$SPOKE_API/version"
# 200       -> keep "insecure": false
# 000 (exit 60, certificate problem) -> use "tlsClientConfig": {"insecure": true} below
```

## 3. Cluster secret on the hub

```bash
oc --context $HUB -n argocd create secret generic cluster-$SPOKE-direct \
  --from-literal=name=$SPOKE-direct \
  --from-literal=server=$SPOKE_API \
  --from-literal=config="{\"bearerToken\":\"$TOKEN\",\"tlsClientConfig\":{\"insecure\":false,\"caData\":\"$CA\"}}"

oc --context $HUB -n argocd label secret cluster-$SPOKE-direct argocd.argoproj.io/secret-type=cluster
```

**Never** add `skip-reconcile` to this one: the push apps would stop.

## 4. Check

```bash
for s in $(oc --context $HUB -n argocd get secret -l argocd.argoproj.io/secret-type=cluster -o name); do
  printf '%-28s %-14s %s\n' "${s#secret/}" \
    "$(oc --context $HUB -n argocd get $s -o jsonpath='{.data.name}' | base64 -d)" \
    "$(oc --context $HUB -n argocd get $s -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/skip-reconcile}')"
done
# cluster-sno2-agent    sno2-agent    true
# cluster-sno2-direct   sno2-direct
# (+ sno3 after the second pass)
```

## Checkpoint

- [ ] `cluster-$SPOKE-direct` labeled `secret-type=cluster`, **no** annotation
- [ ] `cluster-$SPOKE-agent` still `skip-reconcile=true`

Done for sno2? `export SPOKE=sno3` and run this module again. After both spokes: 4 cluster secrets.
