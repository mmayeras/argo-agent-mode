#!/usr/bin/env bash
# Demo: removes skip-reconcile from one agent secret to see the hub interfere with agent apps, then restores it.
# Usage: demo-skip-reconcile.sh [spoke]   (default: first spoke)
source "$(dirname "$0")/lib.sh"

SPOKE="${1:-$(first_spoke)}"
SECRET="cluster-$(agent_name "${SPOKE}")"
APP="guestbook-agent-${SPOKE}"
WAIT="${WAIT:-60}"
CONTROLLER="app.kubernetes.io/name=argocd-application-controller"

log "1/3 Removing skip-reconcile from ${SECRET}"
kh -n "${NS}" annotate secret "${SECRET}" argocd.argoproj.io/skip-reconcile-
restart_pods "${HUB_CTX}" "${CONTROLLER}"

log "2/3 Waiting ${WAIT}s, then HUB controller logs for ${APP}"
sleep "${WAIT}"
kh -n "${NS}" logs statefulset/argocd-application-controller --since="${WAIT}s" \
  | grep "${APP}" | tail -n 20 || echo "(no lines)"
echo
echo "${APP} status as seen by the hub (expect flapping / error conditions):"
kh -n "${NS}" get application "${APP}" \
  -o jsonpath='{.status.sync.status}{" / "}{.status.health.status}{"\n"}{range .status.conditions[*]}{.type}{": "}{.message}{"\n"}{end}'

log "3/3 Restoring skip-reconcile"
kh -n "${NS}" annotate secret "${SECRET}" argocd.argoproj.io/skip-reconcile=true --overwrite
restart_pods "${HUB_CTX}" "${CONTROLLER}"
