#!/usr/bin/env bash
# Prints the hub Argo CD UI Route and admin password.
source "$(dirname "$0")/lib.sh"

HOST="$(kh -n "${NS}" get route argocd-server -o jsonpath='{.spec.host}')"
PASS="$(kh -n "${NS}" get secret argocd-cluster -o jsonpath='{.data.admin\.password}' | base64 -d)"
log "UI: https://${HOST}  (admin / ${PASS})"
