#!/usr/bin/env bash
# Deploys the agent AppProject + the 3 test applications per spoke on the hub.
source "$(dirname "$0")/lib.sh"

# AppProject for agent-managed apps, one destination per agent.
# The label makes it visible to the principal, which copies it to each spoke.
log "AppProject agent-apps"
{
  cat <<EOF
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: agent-apps
  namespace: ${NS}
  labels:
    ${AGENT_LABEL_KEY}: "true"
spec:
  description: Apps deployed through argocd-agent (pull)
  sourceRepos:
    - "*"
  sourceNamespaces:
    - "*"
  clusterResourceWhitelist:
    - group: "*"
      kind: "*"
  destinations:
EOF
  for spoke in ${SPOKES}; do
    printf '    - name: %s\n      namespace: "*"\n' "$(agent_name "${spoke}")"
  done
} | kh apply -f -

for spoke in ${SPOKES}; do
  log "Applications for ${spoke}"
  for f in "${ROOT_DIR}"/apps/*.yaml; do
    sed "s/__SPOKE__/${spoke}/g" "$f"
    echo "---"
  done | kh apply -f -
done
