# 02 - Hub: Argo CD + principal (sno1)

*Acronyms: PKI = Public Key Infrastructure, CA = Certificate Authority, JWT = JSON Web Token, CR = Custom Resource, gRPC = Google Remote Procedure Call, mTLS = mutual TLS, TLS = Transport Layer Security, UI = User Interface.*

Doc: [Installing the Principal component](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.22/html/argo_cd_agent_installation/argocd-agent-installation)
(OpenShift GitOps 1.22, section 1.3). Same order: the CR first, then the PKI.

One `ArgoCD` CR, [`manifests/hub/argocd.yaml`](../manifests/hub/argocd.yaml), gives the hub:

- a **full** Argo CD: UI, repo-server, and the application-controller, kept for the push apps;
- the **principal** (`spec.argoCDAgent.principal`): the agents connect to it.

> **Differs from the doc on purpose.** The doc example sets `spec.controller.enabled: false` (agents only) and
> routes apps by namespace (`sourceNamespaces` + one hub namespace per agent, apps in any namespace). This lab is
> **hybrid**: the controller stays on for push, and apps stay in `argocd`, routed by `spec.destination.name`
> (`destinationBasedMapping: true`, an option the doc also shows).

## 1. Namespace

```bash
source ./env.sh
oc --context $HUB create namespace argocd
```

## 2. The hub ArgoCD CR

Read [`manifests/hub/argocd.yaml`](../manifests/hub/argocd.yaml) first. The fields that matter:

| Field | Value | Why |
|---|---|---|
| `principal.auth` | `mtls:CN=([^,]+)` | agent name = client certificate CN (doc value) |
| `principal.destinationBasedMapping` | `true` | `spec.destination.name` picks the agent (needed for hybrid) |
| `principal.namespace.allowedNamespaces` | `argocd` | where the principal watches Applications |
| `principal.server.route.enabled` | `true` | passthrough Route, reached by the agents on 443 |
| `principal.tls/jwt.insecureGenerate` | `false` | use the certificates issued below (doc: avoids handshake failures) |
| `principal.labelSelector` | `argocd-agent=true` | **safeguard 2**: the principal ignores unlabeled apps |

`labelSelector` is a field of the GitOps 1.22 CR, not shown in the installation doc.

```bash
oc --context $HUB apply -f manifests/hub/argocd.yaml
oc --context $HUB -n argocd get pods
# argocd-agent-principal-*           0/1 Running     <- not Ready: no certificates yet (expected)
# argocd-application-controller-0    1/1 Running
# argocd-redis-*                     1/1 Running
# argocd-repo-server-*               1/1 Running
# argocd-server-*                    1/1 Running
```

Services and Route created by the operator (names are `<CR name>-agent-principal*`):

```bash
oc --context $HUB -n argocd get svc,route | grep agent-principal
# service/argocd-agent-principal                  443
# service/argocd-agent-principal-healthz
# service/argocd-agent-principal-metrics
# service/argocd-agent-principal-redisproxy       6379
# service/argocd-agent-principal-resource-proxy   9090
# route/argocd-agent-principal   argocd-agent-principal-argocd.apps.<hub domain>   passthrough
```

## 3. Principal Route host

```bash
export PRINCIPAL_HOST=$(oc --context $HUB -n argocd get route argocd-agent-principal -o jsonpath='{.spec.host}')
echo $PRINCIPAL_HOST
sed -i.bak "s|^export PRINCIPAL_HOST=.*|export PRINCIPAL_HOST=$PRINCIPAL_HOST|" env.sh
```

Passthrough matters: the agent client certificate must reach the principal (mTLS), the router cannot terminate TLS.

## 4. PKI: the agent CA

```bash
argocd-agentctl pki init --principal-context $HUB --principal-namespace argocd
oc --context $HUB -n argocd get secret argocd-agent-ca
# argocd-agent-ca   kubernetes.io/tls
```

The doc's own warning: this CLI PKI (CA key stored in the cluster) is for development and testing. Use your
organization's CA in production.

## 5. Principal gRPC certificate

`--dns` must match the Route host: the agents check it.

```bash
argocd-agentctl pki issue principal --principal-context $HUB --principal-namespace argocd \
  --dns "$PRINCIPAL_HOST" --upsert
```

## 6. Resource proxy certificate

argocd-server reaches the agent clusters through the principal resource proxy (Service
`argocd-agent-principal-resource-proxy`, port 9090):

```bash
argocd-agentctl pki issue resource-proxy --principal-context $HUB --principal-namespace argocd \
  --dns "argocd-agent-principal-resource-proxy" --upsert
```

## 7. JWT signing key

```bash
argocd-agentctl jwt create-key --principal-context $HUB --principal-namespace argocd --upsert
```

```bash
oc --context $HUB -n argocd get secrets | grep argocd-agent
# argocd-agent-ca
# argocd-agent-jwt
# argocd-agent-principal-tls
# argocd-agent-resource-proxy-tls
```

## 8. Principal ready

```bash
oc --context $HUB -n argocd get pods -l app.kubernetes.io/name=argocd-agent-principal -w
# argocd-agent-principal-*   1/1 Running   (Ctrl+C)
```

Still `0/1` after a minute: restart it so it reads the new secrets.

```bash
oc --context $HUB -n argocd delete pod -l app.kubernetes.io/name=argocd-agent-principal
```

```bash
oc --context $HUB -n argocd logs deploy/argocd-agent-principal | tail -n 20
# no "error" lines; gRPC server and resource proxy started
```

The operator also points argocd-server to the principal **redis-proxy**, so the UI can show the resource tree
of agent apps:

```bash
oc --context $HUB -n argocd get deploy argocd-server -o jsonpath='{.spec.template.spec.containers[0].command}' \
  | tr ',' '\n' | grep -A1 redis
# "--redis"
# "argocd-agent-principal-redisproxy.argocd.svc.cluster.local:6379"
```

## 9. UI

```bash
oc --context $HUB -n argocd get route argocd-server -o jsonpath='https://{.spec.host}{"\n"}'
oc --context $HUB -n argocd get secret argocd-cluster -o jsonpath='{.data.admin\.password}' | base64 -d; echo
# login: admin / <password>
```

## Checkpoint

- [ ] `ArgoCD` `argocd` applied, Route `argocd-agent-principal` is `passthrough`
- [ ] 4 `argocd-agent-*` secrets in `argocd`
- [ ] Principal pod `1/1 Running`, no errors in its log
- [ ] `PRINCIPAL_HOST` saved in `env.sh`
- [ ] UI login works
