# shellcheck shell=bash
# Shared variables and helpers for all lab scripts.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# kubeconfig contexts: same SNO clusters as the acm-dr lab.
# Spoke context names are also used as name prefixes, so keep them DNS-safe.
HUB_CTX="${HUB_CTX:-sno1}"
SPOKES="${SPOKES:-sno2 sno3}"
NS="argocd"

# OpenShift GitOps. >= 1.21 required: it ships Argo CD 3.4 (skip-reconcile on a cluster secret).
GITOPS_CHANNEL="${GITOPS_CHANNEL:-latest}"
GITOPS_MIN_VERSION="1.21.0"
GITOPS_NS="openshift-gitops-operator"

# Label shared by the principal and the agents (isolation 2)
AGENT_LABEL_KEY="argocd-agent"

# Resource names created by the operator for an ArgoCD CR named "argocd"
PRINCIPAL_ROUTE="argocd-agent-principal"
RESOURCE_PROXY_SVC="argocd-agent-principal-resource-proxy"

# Each spoke is registered twice on the hub:
#   <spoke>-agent  -> principal resource proxy, WITH skip-reconcile (pull)
#   <spoke>-direct -> spoke API on :6443, WITHOUT skip-reconcile (push)
agent_name()  { echo "$1-agent"; }
direct_name() { echo "$1-direct"; }
first_spoke() { set -- ${SPOKES}; echo "$1"; }

kh() { oc --context "${HUB_CTX}" "$@"; }
kc() { local ctx="$1"; shift; oc --context "${ctx}" "$@"; }

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warn] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[error] %s\033[0m\n' "$*" >&2; exit 1; }

require() {
  for bin in "$@"; do
    command -v "$bin" >/dev/null 2>&1 || die "Missing tool: $bin"
  done
}

agentctl() {
  argocd-agentctl --principal-context "${HUB_CTX}" --principal-namespace "${NS}" "$@"
}

# Route host of the principal, derived from the hub ingress domain (OpenShift default: <name>-<ns>.<domain>).
# Known before the Route exists, so the principal certificate can be issued up front.
principal_host() {
  echo "${PRINCIPAL_ROUTE}-${NS}.$(kh get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')"
}

# wait_for <ctx> <namespace> <kind/name> [timeout_s]: waits until an object created by the operator exists.
wait_for() {
  local ctx="$1" ns="$2" obj="$3" timeout="${4:-300}" i=0
  until kc "${ctx}" -n "${ns}" get "${obj}" >/dev/null 2>&1; do
    i=$((i + 5)); [ "${i}" -ge "${timeout}" ] && die "${ctx}: ${obj} not found in ${ns} after ${timeout}s"
    sleep 5
  done
}

# restart_pods <ctx> <label-selector>: delete pods instead of "rollout restart",
# because the operator reverts template changes on the workloads it owns.
restart_pods() {
  local ctx="$1" label="$2"
  kc "${ctx}" -n "${NS}" delete pod -l "${label}" --wait=false
  sleep 5
  kc "${ctx}" -n "${NS}" wait pod -l "${label}" --for=condition=Ready --timeout=180s
}
