# Agent (pull) app from a PRIVATE repo, in project agent-apps.
# Its credentials come from a repo-creds secret whose "project" is repo-creds, not agent-apps.
# ${PRIVATE_REPO} from env.sh (labs/10-bonus-repo-creds.md).
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argodemo-private-sno2
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  labels:
    argocd-agent: "true"
spec:
  project: agent-apps
  source:
    repoURL: ${PRIVATE_REPO}
    targetRevision: main
    path: workloads/argodemo/overlays/green
  destination:
    name: sno2-agent
    namespace: argodemo-private
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
    managedNamespaceMetadata:
      labels:
        argocd.argoproj.io/managed-by: argocd
    retry:
      limit: 5
      backoff:
        duration: 10s
        factor: 2
        maxDuration: 2m
