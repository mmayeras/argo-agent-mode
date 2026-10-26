# 00 - Prerequisites

*Acronyms: SNO = Single Node OpenShift, API = Application Programming Interface.*

## 1. Tools

| Tool | Why |
|---|---|
| `oc` | every command uses `oc --context ...` |
| `argocd-agentctl` **v0.10.x** | agent PKI and agent registration ([releases](https://github.com/argoproj-labs/argocd-agent/releases)) |
| `envsubst` (gettext) | renders the `*.tpl` manifests |
| `curl`, `openssl` | checks |

```bash
oc version --client
argocd-agentctl version
envsubst --version | head -1
```

## 2. Environment

```bash
cp env.example.sh env.sh
source ./env.sh
echo "HUB=$HUB SPOKE=$SPOKE"
# HUB=sno1 SPOKE=sno2
```

Every module starts with `source ./env.sh` in a new shell.

## 3. Contexts

Tokens expire: `oc login` again when a command answers `Unauthorized`.

```bash
for c in sno1 sno2 sno3; do echo "$c -> $(oc --context $c whoami --show-server)"; done
# three different API URLs
```

```bash
for c in sno1 sno2 sno3; do oc --context $c whoami; done
# a user with cluster-admin on each (the lab installs an operator and cluster-scoped RBAC)
```

## 4. No OpenShift GitOps yet

The lab installs a fresh operator with **no default `openshift-gitops` instance**. Do not run it on a cluster
where GitOps is already used.

```bash
for c in sno1 sno2 sno3; do
  oc --context $c get csv -A 2>/dev/null | grep -i gitops || echo "$c: OK, no GitOps"
done
```

## 5. Network

Two paths must be open:

| From | To | Port | Used by |
|---|---|---|---|
| each spoke | hub `*.apps` | 443 | agent -> principal Route (pull) |
| hub | each spoke API | 6443 | hub controller (push) |

Spoke -> hub (throwaway pod on the spoke):

```bash
HUB_APPS=$(oc --context $HUB get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')
oc --context $SPOKE run net-probe -n default --rm -i --restart=Never \
  --image=registry.access.redhat.com/ubi9/ubi-minimal -- \
  curl -sk -o /dev/null -w '%{http_code}\n' "https://console-openshift-console.$HUB_APPS"
# 200 (or 30x). A timeout means the spoke cannot reach the hub routes: fix that first.
```

Hub -> spoke API:

```bash
SPOKE_API=$(oc --context $SPOKE whoami --show-server)
oc --context $HUB run net-probe -n default --rm -i --restart=Never \
  --image=registry.access.redhat.com/ubi9/ubi-minimal -- \
  curl -sk -o /dev/null -w '%{http_code}\n' "$SPOKE_API/version"
# 200 (or 401/403)
```

Run both again with `SPOKE=sno3`.

## Checkpoint

- [ ] `oc`, `argocd-agentctl` v0.10.x, `envsubst` installed
- [ ] `sno1`, `sno2`, `sno3` reachable, cluster-admin
- [ ] No GitOps operator on any of them
- [ ] sno2 and sno3 reach the hub routes on 443, the hub reaches both spoke APIs on 6443
