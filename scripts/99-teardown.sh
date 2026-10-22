#!/usr/bin/env bash
# Removes the lab from the shared SNO clusters (they stay up: acm-dr uses them too).
# REMOVE_OPERATOR=true also uninstalls the OpenShift GitOps operator (CRDs are kept).
source "$(dirname "$0")/lib.sh"

log "${HUB_CTX}: Applications, AppProject, ArgoCD CR"
kh -n "${NS}" delete applications --all --ignore-not-found
kh -n "${NS}" delete appproject agent-apps --ignore-not-found
kh -n "${NS}" delete argocd argocd --ignore-not-found --timeout=300s

for spoke in ${SPOKES}; do
  log "${spoke}: ArgoCD CR, workloads, argocd-manager"
  kc "${spoke}" -n "${NS}" delete argocd argocd --ignore-not-found --timeout=300s
  kc "${spoke}" delete namespace guestbook-legacy guestbook-agent guestbook-migrate --ignore-not-found --wait=false
  kc "${spoke}" delete -f "${ROOT_DIR}/spoke/push-access/argocd-manager.yaml" --ignore-not-found
  kc "${spoke}" delete namespace "${NS}" --ignore-not-found --wait=false
done

log "${HUB_CTX}: namespace ${NS} (PKI, cluster secrets)"
kh delete namespace "${NS}" --ignore-not-found --wait=false

if [ "${REMOVE_OPERATOR:-false}" = true ]; then
  for ctx in "${HUB_CTX}" ${SPOKES}; do
    log "${ctx}: removing OpenShift GitOps operator"
    csv="$(kc "${ctx}" -n "${GITOPS_NS}" get subscription openshift-gitops-operator -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)"
    kc "${ctx}" -n "${GITOPS_NS}" delete subscription openshift-gitops-operator --ignore-not-found
    [ -n "${csv}" ] && kc "${ctx}" -n "${GITOPS_NS}" delete csv "${csv}" --ignore-not-found
    kc "${ctx}" delete namespace "${GITOPS_NS}" --ignore-not-found --wait=false
  done
fi
