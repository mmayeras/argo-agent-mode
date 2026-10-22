#!/usr/bin/env bash
# Hub: agent PKI, then one ArgoCD CR with the full Argo CD (push) + the principal (pull).
source "$(dirname "$0")/lib.sh"

kh create namespace "${NS}" --dry-run=client -o yaml | kh apply -f -

if kh -n "${NS}" get secret argocd-agent-ca >/dev/null 2>&1; then
  log "PKI already initialized"
else
  log "Initializing PKI (CA)"
  agentctl pki init
fi

PRINCIPAL_HOST="$(principal_host)"

# Issued before the ArgoCD CR: the Route host is predictable, so the principal starts with its certs.
log "Principal gRPC certificate (reached by the agents at ${PRINCIPAL_HOST}:443)"
agentctl pki issue principal \
  --ip "127.0.0.1" \
  --dns "localhost,${PRINCIPAL_HOST},argocd-agent-principal.${NS}.svc,argocd-agent-principal.${NS}.svc.cluster.local" \
  --upsert

log "Resource proxy certificate (reached by argocd-server)"
agentctl pki issue resource-proxy \
  --ip "127.0.0.1" \
  --dns "localhost,${RESOURCE_PROXY_SVC},${RESOURCE_PROXY_SVC}.${NS}.svc,${RESOURCE_PROXY_SVC}.${NS}.svc.cluster.local" \
  --upsert

log "JWT signing key"
agentctl jwt create-key --upsert

log "ArgoCD CR on the hub (Argo CD + principal)"
kh apply -f "${ROOT_DIR}/hub/argocd.yaml"

log "Waiting for hub Argo CD components"
wait_for "${HUB_CTX}" "${NS}" argocd/argocd
kh -n "${NS}" wait argocd/argocd --for=jsonpath='{.status.phase}'=Available --timeout=600s
for w in deploy/argocd-server deploy/argocd-repo-server statefulset/argocd-application-controller deploy/argocd-agent-principal; do
  wait_for "${HUB_CTX}" "${NS}" "${w}"
  kh -n "${NS}" rollout status "${w}" --timeout=300s
done

wait_for "${HUB_CTX}" "${NS}" "route/${PRINCIPAL_ROUTE}"
actual="$(kh -n "${NS}" get route "${PRINCIPAL_ROUTE}" -o jsonpath='{.spec.host}')"
[ "${actual}" = "${PRINCIPAL_HOST}" ] \
  || warn "Principal Route host is ${actual}, certificate was issued for ${PRINCIPAL_HOST}: agents will fail TLS"
