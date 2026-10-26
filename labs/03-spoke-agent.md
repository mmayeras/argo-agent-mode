# 03 - Spoke: Argo CD + agent (pull)

*Acronyms: CR = Custom Resource, CN = certificate Common Name, CA = Certificate Authority, mTLS = mutual TLS, TLS = Transport Layer Security, UI = User Interface.*

Doc: OpenShift GitOps 1.22 [Argo CD Agent installation](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.22/html/argo_cd_agent_installation/argocd-agent-installation),
sections 1.3 (agent registration, PKI), 1.4 and 1.6 (agent through the `ArgoCD` CR, not the Helm chart).

**Run this module once per spoke**: first `SPOKE=sno2`, then `SPOKE=sno3`.

```bash
source ./env.sh
export SPOKE=sno2     # second pass: export SPOKE=sno3
echo "HUB=$HUB SPOKE=$SPOKE PRINCIPAL_HOST=$PRINCIPAL_HOST"
```

The agent name is `$SPOKE-agent`. It is also the name of the cluster on the hub, so it is what an Application
puts in `spec.destination.name` to be deployed by the agent.

## 1. Register the agent on the hub

```bash
argocd-agentctl agent create $SPOKE-agent --principal-context $HUB --principal-namespace argocd \
  --resource-proxy-server argocd-agent-principal-resource-proxy:9090
```

This creates the cluster secret `cluster-$SPOKE-agent`. Its server is the resource proxy, not the spoke API:

```bash
oc --context $HUB -n argocd get secret cluster-$SPOKE-agent -o jsonpath='{.data.server}' | base64 -d; echo
# https://argocd-agent-principal-resource-proxy:9090?agentName=sno2-agent
```

## 2. Safeguard 1: `skip-reconcile`

```bash
oc --context $HUB -n argocd annotate secret cluster-$SPOKE-agent \
  argocd.argoproj.io/skip-reconcile=true --overwrite
oc --context $HUB -n argocd get secret cluster-$SPOKE-agent \
  -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/skip-reconcile}{"\n"}'
# true
```

With it, the **hub** application-controller ignores every app whose destination is `$SPOKE-agent`. Only the
spoke controller manages them. `argocd-agentctl` already sets it; annotating again makes it explicit, and you
need it if you ever create this secret another way (GitOps, by hand).

## 3. CA and agent client certificate

Same order as the doc: copy the CA to the spoke, then issue the client certificate.

```bash
oc --context $SPOKE create namespace argocd

argocd-agentctl pki propagate --principal-context $HUB --principal-namespace argocd \
  --agent-context $SPOKE --agent-namespace argocd

argocd-agentctl pki issue agent $SPOKE-agent --principal-context $HUB --principal-namespace argocd \
  --agent-context $SPOKE --agent-namespace argocd --upsert
```

```bash
oc --context $SPOKE -n argocd get secret argocd-agent-client-tls argocd-agent-ca
oc --context $SPOKE -n argocd get secret argocd-agent-client-tls -o jsonpath='{.data.tls\.crt}' \
  | base64 -d | openssl x509 -noout -subject
# subject=CN=sno2-agent      <- the principal maps the connection to this agent
```

## 4. The spoke ArgoCD CR

[`manifests/spoke/argocd.yaml.tpl`](../manifests/spoke/argocd.yaml.tpl):

| Field | Value | Why |
|---|---|---|
| `server.enabled` | `false` | no UI on the spoke |
| `agent.client.principalServerAddress` | `$PRINCIPAL_HOST` | the principal Route, port 443 |
| `agent.client.mode` | `managed` | the hub is the source of truth for the apps |
| `agent.creds` | `mtls:any` | authenticate with the client certificate |
| `agent.tls` | `argocd-agent-client-tls`, `argocd-agent-ca`, `insecure: false` | the secrets from step 3 |
| `agent.redis.serverAddress` | `argocd-redis:6379` | the local Redis (`<CR name>-redis`) |
| `agent.destinationBasedMapping` | `enabled`, `createNamespace` | apps keep their namespace (`argocd`) on the spoke |
| `agent.labelSelector` | `argocd-agent=true` | **safeguard 2**, same label as the principal (not in the doc) |
| env `ARGOCD_AGENT_IGNORE_UNMANAGED_APPS` | `true` | **safeguard 3**: never touch apps the agent did not create (no CR field, not in the doc) |

The doc's custom Redis NetworkPolicy is for the Helm install only. With the CR, the operator already lets the
agent pod reach `argocd-redis`.

```bash
envsubst < manifests/spoke/argocd.yaml.tpl | oc --context $SPOKE apply -f -
oc --context $SPOKE -n argocd get argocd argocd -w
# argocd   Available   (Ctrl+C)
```

```bash
oc --context $SPOKE -n argocd get pods
# argocd-agent-agent-*              1/1 Running
# argocd-application-controller-0   1/1 Running
# argocd-redis-*                    1/1 Running
# argocd-repo-server-*              1/1 Running
# (no argocd-server)
```

## 5. Check the connection

The agent opens the connection: spoke -> hub Route :443. Nothing on the hub calls the spoke for pull.

```bash
oc --context $SPOKE -n argocd logs deploy/argocd-agent-agent | grep -i -E 'connect|error' | tail -n 5
# ... connected to principal ...
```

```bash
oc --context $HUB -n argocd logs deploy/argocd-agent-principal | grep $SPOKE-agent | tail -n 5
# level=info msg="An agent connected to the subscription stream" client=sno2-agent ...
```

```bash
argocd-agentctl agent list --principal-context $HUB --principal-namespace argocd
# sno2-agent   ...
```

## Checkpoint

- [ ] `cluster-$SPOKE-agent` exists on the hub, annotation `skip-reconcile=true`
- [ ] `argocd-agent-client-tls` on the spoke, CN = `$SPOKE-agent`
- [ ] Spoke `ArgoCD` `Available`, no argocd-server pod
- [ ] Principal log: agent `$SPOKE-agent` connected

Done for sno2? `export SPOKE=sno3` and run this module again.
