#!/usr/bin/env bash
# Installs the OpenShift GitOps operator on the hub and on every spoke.
source "$(dirname "$0")/lib.sh"
require oc argocd-agentctl curl

for ctx in "${HUB_CTX}" ${SPOKES}; do
  kc "${ctx}" whoami >/dev/null 2>&1 || die "Context ${ctx}: not logged in (oc login, then retry)"
done

for ctx in "${HUB_CTX}" ${SPOKES}; do
  log "${ctx}: OpenShift GitOps operator (channel ${GITOPS_CHANNEL})"
  sed "s/__CHANNEL__/${GITOPS_CHANNEL}/" "${ROOT_DIR}/operator/gitops-operator.yaml" | kc "${ctx}" apply -f -
done

for ctx in "${HUB_CTX}" ${SPOKES}; do
  log "${ctx}: waiting for the operator CSV"
  csv=""
  for _ in $(seq 1 60); do
    csv="$(kc "${ctx}" -n "${GITOPS_NS}" get subscription openshift-gitops-operator -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)"
    [ -n "${csv}" ] && break
    sleep 5
  done
  [ -n "${csv}" ] || die "${ctx}: no installedCSV on the Subscription after 5 min"
  kc "${ctx}" -n "${GITOPS_NS}" wait "csv/${csv}" --for=jsonpath='{.status.phase}'=Succeeded --timeout=600s
  kc "${ctx}" wait crd/argocds.argoproj.io --for=condition=Established --timeout=120s

  version="$(kc "${ctx}" -n "${GITOPS_NS}" get "csv/${csv}" -o jsonpath='{.spec.version}')"
  lowest="$(printf '%s\n%s\n' "${GITOPS_MIN_VERSION}" "${version}" | sort -V | head -n1)"
  [ "${lowest}" = "${GITOPS_MIN_VERSION}" ] \
    || die "${ctx}: OpenShift GitOps ${version} < ${GITOPS_MIN_VERSION} (Argo CD 3.4 needed for skip-reconcile). Set GITOPS_CHANNEL."
  log "${ctx}: OpenShift GitOps ${version} ready"
done
