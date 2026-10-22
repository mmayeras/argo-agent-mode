#!/usr/bin/env bash
# Demo: migrates guestbook-migrate-<spoke> from push (hub) to pull (agent) without redeploying pods.
# Usage: demo-migrate.sh [spoke]   (default: first spoke)
source "$(dirname "$0")/lib.sh"

SPOKE="${1:-$(first_spoke)}"
APP="guestbook-migrate-${SPOKE}"
WORKLOAD_NS="guestbook-migrate"

log "Before: pods on ${SPOKE}"
kc "${SPOKE}" -n "${WORKLOAD_NS}" get pods -o wide

log "1) Labeled project + destination = agent cluster (hub stops managing it: skip-reconcile)"
# The 'default' project is not labeled so it is not copied to the spoke: switch to agent-apps.
kh -n "${NS}" patch application "${APP}" --type merge \
  -p "{\"spec\":{\"project\":\"agent-apps\",\"destination\":{\"name\":\"$(agent_name "${SPOKE}")\"}}}"

log "2) Label argocd-agent=true (the principal picks it up and sends it to the agent)"
kh -n "${NS}" label application "${APP}" argocd-agent=true --overwrite

log "Waiting for the app to appear on ${SPOKE}"
for _ in $(seq 1 30); do
  kc "${SPOKE}" -n "${NS}" get application "${APP}" >/dev/null 2>&1 && break
  sleep 2
done
kc "${SPOKE}" get applications -A

log "After: same pods (same names/ages = no redeploy)"
sleep 20
kc "${SPOKE}" -n "${WORKLOAD_NS}" get pods -o wide
kh -n "${NS}" get application "${APP}" -o jsonpath='{.status.sync.status}{" / "}{.status.health.status}{"\n"}'
