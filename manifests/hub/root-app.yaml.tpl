# App of apps: the only Application created by hand.
# It runs on the hub itself (in-cluster, push) and creates, from Git, everything under gitops/:
#   - AppProject agent-apps (sync wave -1)
#   - 3 Applications per spoke (gitops/sno2, gitops/sno3)
# It has no argocd-agent label: the principal ignores it. Its children decide push or pull by themselves.
# ${GIT_REPO} and ${GIT_BRANCH} come from env.sh, rendered with envsubst (labs/05-apps.md).
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${GIT_REPO}
    targetRevision: ${GIT_BRANCH}
    path: gitops
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
