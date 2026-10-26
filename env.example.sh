# argo-agent-mode lab - environment
# Copy to env.sh, then:  source ./env.sh
# Every lab command uses explicit --context, so you never act on the wrong cluster by accident.

# kubeconfig contexts
export HUB=sno1           # Argo CD (UI + controller for push) + argocd-agent principal
export SPOKE=sno2         # modules 03 and 04 run once per spoke: then export SPOKE=sno3

# Git repo read by the root app (app of apps, module 05). Use your fork to run the migration demo (module 07).
export GIT_REPO=https://github.com/mmayeras/argo-agent-mode.git
export GIT_BRANCH=main

# Principal Route host, filled in module 02 (step 3)
export PRINCIPAL_HOST=""

# Bonus module 10 (repository credential templates): your private copy of the argodemo manifests
export GH_USER=mmayeras
export PRIVATE_REPO=https://github.com/${GH_USER}/argodemo-private.git
