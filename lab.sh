#!/usr/bin/env bash
# Lab entry point: ./lab.sh <command>
set -euo pipefail
S="$(cd "$(dirname "$0")" && pwd)/scripts"

case "${1:-help}" in
  up)
    for s in 01-operator 02-hub 03-spokes 04-push 05-apps; do
      bash "$S/$s.sh"
    done
    echo; echo "Lab ready. Give the apps 1-2 min, then: ./lab.sh verify" ;;
  operator)     bash "$S/01-operator.sh" ;;
  hub)          bash "$S/02-hub.sh" ;;
  spokes)       bash "$S/03-spokes.sh" ;;
  push)         bash "$S/04-push.sh" ;;
  apps)         bash "$S/05-apps.sh" ;;
  verify)       bash "$S/verify.sh" ;;
  demo-skip)    bash "$S/demo-skip-reconcile.sh" "${2:-}" ;;
  demo-migrate) bash "$S/demo-migrate.sh" "${2:-}" ;;
  ui)           bash "$S/ui.sh" ;;
  down)         bash "$S/99-teardown.sh" ;;
  *)
    cat <<EOF
Usage: ./lab.sh <command>
  up                     brings up the whole lab (hub sno1, spokes sno2 sno3)
  operator|hub|spokes|push|apps   individual steps
  verify                 shows who manages what
  demo-skip [spoke]      demo: remove/restore skip-reconcile
  demo-migrate [spoke]   demo: migrate push -> agent
  ui                     hub Argo CD UI Route + admin password
  down                   removes the lab (REMOVE_OPERATOR=true also uninstalls GitOps)

Contexts: HUB_CTX (default sno1), SPOKES (default "sno2 sno3").
EOF
    ;;
esac
