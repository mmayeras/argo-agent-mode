#!/usr/bin/env bash
# Shows who manages what.
source "$(dirname "$0")/lib.sh"

log "Cluster secrets on the hub (each spoke, twice)"
printf '%-24s %-14s %-90s %s\n' SECRET NAME SERVER SKIP-RECONCILE
for s in $(kh -n "${NS}" get secret -l argocd.argoproj.io/secret-type=cluster -o name); do
  name="$(kh -n "${NS}" get "$s" -o jsonpath='{.data.name}' | base64 -d)"
  server="$(kh -n "${NS}" get "$s" -o jsonpath='{.data.server}' | base64 -d)"
  skip="$(kh -n "${NS}" get "$s" -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/skip-reconcile}')"
  printf '%-24s %-14s %-90s %s\n' "${s#secret/}" "$name" "$server" "${skip:-<absent>}"
done

log "Applications on the HUB (${HUB_CTX})"
kh -n "${NS}" get applications \
  -o custom-columns='NAME:.metadata.name,DEST:.spec.destination.name,LABEL-AGENT:.metadata.labels.argocd-agent,SYNC:.status.sync.status,HEALTH:.status.health.status'

for spoke in ${SPOKES}; do
  log "Applications on SPOKE ${spoke} (only those coming from the principal)"
  kc "${spoke}" get applications -A \
    -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,DEST:.spec.destination.name,SOURCE-UID:.metadata.annotations.argocd\.argoproj\.io/source-uid,SYNC:.status.sync.status'

  log "Workloads deployed on ${spoke}"
  for n in guestbook-legacy guestbook-agent guestbook-migrate; do
    printf '%-20s ' "$n"
    kc "${spoke}" -n "$n" get deploy guestbook-ui -o jsonpath='{.status.readyReplicas}/{.spec.replicas} ready{"\n"}' 2>/dev/null || echo "missing"
  done
done

log "The HUB controller must NOT be working on guestbook-agent-*"
kh -n "${NS}" logs statefulset/argocd-application-controller --since=5m \
  | grep -E 'guestbook-(agent|legacy)-' | tail -n 10 || echo "(no lines)"

log "Agent images (principal / agents)"
printf '%-8s %s\n' "${HUB_CTX}" "$(kh -n "${NS}" get deploy argocd-agent-principal -o jsonpath='{.spec.template.spec.containers[0].image}')"
for spoke in ${SPOKES}; do
  printf '%-8s %s\n' "${spoke}" "$(kc "${spoke}" -n "${NS}" get deploy argocd-agent-agent -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo missing)"
done

log "Agent connections"
agentctl agent list || true
