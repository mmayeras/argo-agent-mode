#!/usr/bin/env bash
# Registers EACH spoke a second time on the hub, with direct API access (classic push, WITHOUT skip-reconcile).
source "$(dirname "$0")/lib.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT

for spoke in ${SPOKES}; do
  direct="$(direct_name "${spoke}")"

  log "${spoke}: argocd-manager account"
  kc "${spoke}" apply -f "${ROOT_DIR}/spoke/push-access/argocd-manager.yaml"

  TOKEN_B64=""
  for _ in $(seq 1 30); do
    TOKEN_B64="$(kc "${spoke}" -n kube-system get secret argocd-manager-token -o jsonpath='{.data.token}' 2>/dev/null || true)"
    [ -n "${TOKEN_B64}" ] && break
    sleep 2
  done
  [ -n "${TOKEN_B64}" ] || die "${spoke}: ServiceAccount token was not generated"

  TOKEN="$(printf '%s' "${TOKEN_B64}" | base64 -d)"
  CA="$(kc "${spoke}" -n kube-system get secret argocd-manager-token -o jsonpath='{.data.ca\.crt}')"
  API="$(kc "${spoke}" whoami --show-server)"

  # The SA CA bundle covers the default API certs. A custom API certificate (named certificate)
  # is not in it: then fall back to insecure, it is a lab.
  printf '%s' "${CA}" | base64 -d > "${TMP}/${spoke}-ca.crt"
  if curl -s -o /dev/null --cacert "${TMP}/${spoke}-ca.crt" "${API}/version"; then
    TLS="\"insecure\": false, \"caData\": \"${CA}\""
  else
    warn "${spoke}: API certificate not signed by the SA CA bundle, using insecure TLS for ${direct}"
    TLS="\"insecure\": true"
  fi

  log "Cluster secret ${direct} -> ${API} (push)"
  cat <<EOF | kh apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: cluster-${direct}
  namespace: ${NS}
  labels:
    argocd.argoproj.io/secret-type: cluster
  # NO skip-reconcile annotation here: the hub controller must manage these apps
type: Opaque
stringData:
  name: ${direct}
  server: ${API}
  config: |
    {
      "bearerToken": "${TOKEN}",
      "tlsClientConfig": { ${TLS} }
    }
EOF
done
