# Push app from the same PRIVATE repo, in project default, deployed by the HUB controller to sno3.
# Same repo-creds secret: Argo CD picks a credential template by URL prefix only, whatever the project.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argodemo-private-sno3
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${PRIVATE_REPO}
    targetRevision: main
    path: workloads/argodemo/overlays/blue
  destination:
    name: sno3-direct
    namespace: argodemo-private
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
