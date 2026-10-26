# 10 - Bonus: repository credential templates (repo-creds)

*Acronyms: PAT = Personal Access Token, URL = Uniform Resource Locator.*

A **credential template** (`argocd.argoproj.io/secret-type: repo-creds`) holds credentials for every repository
whose URL starts with a prefix, for example `https://github.com/<you>`. One secret instead of one per repository.

Doc: [argocd-agent, Repository Credential Templates](https://argocd-agent.readthedocs.io/latest/user-guide/managed-agent/repository/#repository-credential-templates).

## Does it work with managed agents?

Yes, from argocd-agent 0.9 (this lab runs 0.10, check: `oc --context $HUB -n argocd logs deploy/argocd-agent-principal | grep Starting`).
You create the secret **on the hub**; the principal copies it to the agents, which keep it in sync (updates and
deletion included). You never create it on a spoke.

## Is a credential tied to one project?

The secret has **one** `project` field, and argocd-agent requires it. But it does two different things depending on
who reads it:

| Who | What `project` does |
|---|---|
| **argocd-agent** (principal) | **Routing only.** The secret goes to the agents that match the destinations of that one AppProject (destination-based mapping: `.spec.destinations[].name`). No `project` field = never sent. |
| **Argo CD** (hub controller, spoke controller) | **Nothing** for repo-creds. A template is picked by the **longest URL prefix**, whatever the Application's project (`getRepositoryCredentialIndex` in `util/db/repository_secrets.go`). |

So:

- **Several projects share one credential**, as long as the secret reaches the cluster that fetches the repo. On a
  spoke, every app (any project) whose repo URL matches the prefix uses it. On the hub, the push apps do too.
- **What the project controls is where the secret lands.** If your projects target different agents, point the
  secret at a project whose destinations cover all of them. This module uses a small "carrier" project,
  `repo-creds`, with the two agents as destinations and no `sourceRepos`: it routes credentials and cannot deploy
  anything.
- Do not create a second repo-creds secret with the **same URL** for another project: on a cluster that gets both,
  Argo CD logs `Found multiple credentials` and uses one of them.

Different from a plain **repository** secret (`secret-type: repository`): there, Argo CD does honor `project`
(project-scoped repository, only that project's apps use it).

Two lab-specific requirements, from the principal code: the secret must carry the label `argocd-agent=true` (the
principal `labelSelector` filters secrets too), and so must the AppProject it names.

## 1. A private repository

Copy the argodemo manifests to a new **private** GitHub repo:

```bash
source ./env.sh
echo "$GH_USER  $PRIVATE_REPO"
gh repo create $GH_USER/argodemo-private --private

rm -rf /tmp/argodemo-private && mkdir -p /tmp/argodemo-private
cp -r workloads /tmp/argodemo-private/
git -C /tmp/argodemo-private init -b main
git -C /tmp/argodemo-private add .
git -C /tmp/argodemo-private commit -m "argodemo manifests, private copy"
git -C /tmp/argodemo-private remote add origin $PRIVATE_REPO
git -C /tmp/argodemo-private push -u origin main
```

Create a **fine-grained PAT** on GitHub (Settings > Developer settings > Fine-grained tokens): repository access
"Only select repositories" = `argodemo-private`, permission **Contents: Read-only**. Keep it out of files and
history:

```bash
read -s GIT_TOKEN && export GIT_TOKEN
```

## 2. Without credentials: the app fails

[`manifests/bonus/argodemo-private-agent.yaml.tpl`](../manifests/bonus/argodemo-private-agent.yaml.tpl): agent app,
project `agent-apps`, destination `sno2-agent`, source = the private repo.

```bash
envsubst < manifests/bonus/argodemo-private-agent.yaml.tpl | oc --context $HUB apply -f -
sleep 30
oc --context $HUB -n argocd get applications.argoproj.io argodemo-private-sno2 \
  -o jsonpath='{range .status.conditions[*]}{.type}: {.message}{"\n"}{end}'
# ComparisonError: ... authentication required ...
```

The error comes from the **spoke** repo-server (sno2 fetches the repo), reported to the hub by the agent.

## 3. The carrier AppProject

[`manifests/bonus/appproject-repo-creds.yaml`](../manifests/bonus/appproject-repo-creds.yaml): labeled, destinations
`sno2-agent` and `sno3-agent`, `sourceRepos: []`.

```bash
oc --context $HUB apply -f manifests/bonus/appproject-repo-creds.yaml
for s in sno2 sno3; do oc --context $s -n argocd get appproject repo-creds; done
# repo-creds   (on both spokes)
```

## 4. The credential template, on the hub only

The URL is a **prefix** (the GitHub user or organization), not a repository:

```bash
oc --context $HUB -n argocd create secret generic repo-creds-github \
  --from-literal=type=git \
  --from-literal=url=https://github.com/$GH_USER \
  --from-literal=username=git \
  --from-literal=password="$GIT_TOKEN" \
  --from-literal=project=repo-creds

oc --context $HUB -n argocd label secret repo-creds-github \
  argocd.argoproj.io/secret-type=repo-creds argocd-agent=true
```

| Field / label | Why |
|---|---|
| `url` | prefix: every `https://github.com/<you>/...` repo matches |
| `username` | any non-empty value with a GitHub PAT |
| `project=repo-creds` | routing: sent to the agents of the `repo-creds` project |
| `secret-type=repo-creds` | a credential template, not a single repository |
| `argocd-agent=true` | the principal's `labelSelector` |

The prefix also matches this lab's public repo (`github.com/<you>/argo-agent-mode`): Argo CD now sends the token
for it too. Harmless; use a narrower prefix (`https://github.com/<you>/argodemo-`) to avoid it.

## 5. The principal copies it to both agents

```bash
for s in sno2 sno3; do
  printf '%-5s ' $s
  oc --context $s -n argocd get secret repo-creds-github \
    -o jsonpath='{.metadata.labels.argocd\.argoproj\.io/secret-type}  source-uid={.metadata.annotations.argocd\.argoproj\.io/source-uid}{"\n"}'
done
# sno2  repo-creds  source-uid=<uid of the hub secret>
# sno3  repo-creds  source-uid=<uid of the hub secret>
```

The app (project `agent-apps`) syncs with a secret scoped to project `repo-creds`: the project did not restrict it.

```bash
oc --context $HUB -n argocd annotate applications.argoproj.io argodemo-private-sno2 argocd.argoproj.io/refresh=hard --overwrite
oc --context $HUB -n argocd get applications.argoproj.io argodemo-private-sno2 -w
# argodemo-private-sno2   Synced   Healthy   (Ctrl+C)
oc --context sno2 -n argodemo-private get route argodemo -o jsonpath='https://{.spec.host}{"\n"}'
# green page
```

## 6. Same secret, push app, another project

[`manifests/bonus/argodemo-private-push.yaml.tpl`](../manifests/bonus/argodemo-private-push.yaml.tpl): project
`default`, destination `sno3-direct`. This time the **hub** fetches the repo, with the hub copy of the same secret.

```bash
envsubst < manifests/bonus/argodemo-private-push.yaml.tpl | oc --context $HUB apply -f -
oc --context $HUB -n argocd get applications.argoproj.io argodemo-private-sno3 -w
# argodemo-private-sno3   Synced   Healthy   (Ctrl+C)
```

One credential, three projects involved (`repo-creds` for routing, `agent-apps` and `default` for the apps), push
and pull.

## 7. Rotate, then revoke, from the hub

Rotate: create a second PAT (same settings), change the secret on the hub only, the agents follow:

```bash
read -s GIT_TOKEN && export GIT_TOKEN      # the new PAT
oc --context $HUB -n argocd patch secret repo-creds-github --type merge -p "{\"stringData\":{\"password\":\"$GIT_TOKEN\"}}"
for s in sno2 sno3; do oc --context $s -n argocd get secret repo-creds-github -o jsonpath='{.metadata.resourceVersion}{"\n"}'; done
# new resourceVersion on both spokes
```

Revoke: delete it on the hub, it disappears from the agents:

```bash
oc --context $HUB -n argocd delete secret repo-creds-github
for s in sno2 sno3; do oc --context $s -n argocd get secret repo-creds-github; done
# NotFound on both
oc --context $HUB -n argocd annotate applications.argoproj.io argodemo-private-sno2 argocd.argoproj.io/refresh=hard --overwrite
# back to ComparisonError: authentication required (running pods stay, new syncs fail)
```

Recreate it (step 4) before cleaning up.

## 8. Clean up

```bash
oc --context $HUB -n argocd delete applications.argoproj.io argodemo-private-sno2 argodemo-private-sno3
oc --context $HUB -n argocd delete secret repo-creds-github --ignore-not-found
oc --context $HUB -n argocd delete appproject repo-creds
oc --context sno2 delete namespace argodemo-private
oc --context sno3 delete namespace argodemo-private
gh repo delete $GH_USER/argodemo-private      # optional; also revoke the PAT on GitHub
```

## Checkpoint

- [ ] Without credentials: `authentication required` on the agent app
- [ ] `repo-creds-github` on both spokes, with a `source-uid`, never created there by hand
- [ ] Agent app (project `agent-apps`) and push app (project `default`) both `Synced` with one secret
- [ ] Rotation and deletion on the hub reach both spokes
