#!/usr/bin/env bash
# For each spoke: registers the agent on the hub (cluster secret WITH skip-reconcile),
# issues its client certificate, and deploys Argo CD + agent (managed mode) on the spoke.
source "$(dirname "$0")/lib.sh"

PRINCIPAL_HOST="$(kh -n "${NS}" get route "${PRINCIPAL_ROUTE}" -o jsonpath='{.spec.host}')"
[ -n "${PRINCIPAL_HOST}" ] || die "Principal Route not found on the hub: run ./lab.sh hub first"

for spoke in ${SPOKES}; do
  agent="$(agent_name "${spoke}")"

  if kh -n "${NS}" get secret "cluster-${agent}" >/dev/null 2>&1; then
    log "Agent ${agent} already registered"
  else
    log "Creating agent ${agent} on the hub"
    agentctl agent create "${agent}" \
      --resource-proxy-server "${RESOURCE_PROXY_SVC}.${NS}.svc.cluster.local:9090"
  fi

  # argocd-agentctl already sets the annotation; we (re)apply it to be explicit.
  log "skip-reconcile on cluster-${agent}"
  kh -n "${NS}" annotate secret "cluster-${agent}" argocd.argoproj.io/skip-reconcile=true --overwrite

  log "${spoke}: agent client certificate + CA"
  kc "${spoke}" create namespace "${NS}" --dry-run=client -o yaml | kc "${spoke}" apply -f -
  agentctl pki issue agent "${agent}" \
    --agent-context "${spoke}" --agent-namespace "${NS}" --upsert
  agentctl pki propagate --agent-context "${spoke}" --agent-namespace "${NS}" \
    || warn "propagate skipped (CA probably already propagated by 'pki issue agent')"

  log "${spoke}: ArgoCD CR (agent -> ${PRINCIPAL_HOST}:443)"
  sed "s/__PRINCIPAL_HOST__/${PRINCIPAL_HOST}/" "${ROOT_DIR}/spoke/argocd.yaml" | kc "${spoke}" apply -f -
done

for spoke in ${SPOKES}; do
  log "${spoke}: waiting for Argo CD + agent"
  wait_for "${spoke}" "${NS}" argocd/argocd
  kc "${spoke}" -n "${NS}" wait argocd/argocd --for=jsonpath='{.status.phase}'=Available --timeout=600s
  for w in deploy/argocd-repo-server statefulset/argocd-application-controller deploy/argocd-agent-agent; do
    wait_for "${spoke}" "${NS}" "${w}"
    kc "${spoke}" -n "${NS}" rollout status "${w}" --timeout=300s
  done
done
