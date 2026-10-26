# 09 - Troubleshooting

*Acronyms: CR = Custom Resource, TLS = Transport Layer Security, UI = User Interface.*

Logs:

```bash
oc --context $HUB   -n argocd logs deploy/argocd-agent-principal
oc --context $SPOKE -n argocd logs deploy/argocd-agent-agent
oc --context $SPOKE -n argocd logs statefulset/argocd-application-controller
oc --context $HUB   -n argocd get argocd argocd -o jsonpath='{.status}{"\n"}'    # operator view
```

Do not edit the Deployments or ConfigMaps the operator owns (`argocd-agent-params`, `argocd-cmd-params-cm`, ...):
it reverts them. Change the `ArgoCD` CR.

## Agent: `x509: certificate is valid for ..., not argocd-agent-principal-argocd...`

The principal certificate does not match the Route host. Compare:

```bash
oc --context $HUB -n argocd get route argocd-agent-principal -o jsonpath='{.spec.host}{"\n"}'
oc --context $HUB -n argocd get secret argocd-agent-principal-tls -o jsonpath='{.data.tls\.crt}' \
  | base64 -d | openssl x509 -noout -ext subjectAltName
```

Fix `PRINCIPAL_HOST`, re-issue ([module 02](02-hub.md) step 5, `--upsert`), then
`oc --context $HUB -n argocd delete pod -l app.kubernetes.io/name=argocd-agent-principal`.

## Agent: `connection refused` / timeout

- `principalServerAddress` in the spoke CR: `oc --context $SPOKE -n argocd get argocd argocd -o jsonpath='{.spec.argoCDAgent.agent.client}'`
- Spoke -> hub on 443: [module 00](00-prereqs.md) step 5.
- Route termination must be `passthrough` (edge or reencrypt drops the client certificate).

## Principal `CrashLoopBackOff`

- `0/1 Running` and missing secret in the log: PKI not issued yet, do [module 02](02-hub.md) steps 4-8.
- Redis `NOAUTH` errors: some operator versions did not pass the Redis password (`argocd-redis-initial-password`,
  key `admin.password`) to the principal. Create the secret it looks for, then restart it:

```bash
oc --context $HUB -n argocd create secret generic argocd-redis \
  --from-literal=auth="$(oc --context $HUB -n argocd get secret argocd-redis-initial-password -o jsonpath='{.data.admin\.password}' | base64 -d)"
oc --context $HUB -n argocd delete pod -l app.kubernetes.io/name=argocd-agent-principal
```

Same on a spoke if the agent logs `NOAUTH` (use `--context $SPOKE`, restart `argocd-agent-agent`).

## Agent app stuck on the hub, nothing on the spoke

- Label missing: `oc --context $HUB -n argocd get applications.argoproj.io <app> --show-labels`
- Project not labeled or not on the spoke: `oc --context $SPOKE -n argocd get appproject`
  (`app is not allowed in project "default"` in the agent log).
- `destination.name` is not an agent name (`sno2-agent`).

## No resource tree in the UI for an agent app

argocd-server must use the principal redis-proxy ([module 02](02-hub.md) step 8). Agent side, the doc notes that
without RBAC on the target namespaces the agent logs `forbidden` and the UI shows "Resource not found in cluster"
(the spoke instance is cluster-scoped here, see [module 01](01-operator.md)).

```bash
oc --context $HUB -n argocd get svc | grep redisproxy
oc --context $HUB -n argocd get deploy argocd-server -o jsonpath='{.spec.template.spec.containers[0].command}'
```

## Push app `Unknown` / `ComparisonError`

- Hub -> spoke API on 6443 blocked ([module 00](00-prereqs.md) step 5).
- Token secret deleted in `kube-system`, or certificate error: recreate `cluster-<spoke>-direct`
  ([module 04](04-spoke-push.md)), with `"insecure": true` if the API has a custom certificate.

## Hub controller logs show `bgd-agent-*`

`skip-reconcile` missing on `cluster-<spoke>-agent`, or Argo CD < 3.4:

```bash
oc --context $HUB -n argocd get secret -l argocd.argoproj.io/secret-type=cluster \
  -o custom-columns='NAME:.metadata.name,SKIP:.metadata.annotations.argocd\.argoproj\.io/skip-reconcile'
oc --context $HUB -n openshift-gitops-operator get csv -o custom-columns=NAME:.metadata.name,VERSION:.spec.version
```
