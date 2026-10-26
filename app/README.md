# argodemo

One-page web app deployed by every Application of the lab. The page is filled with `COLOR` and shows the
namespace, pod and node that served it.

| Env | Default | Set by |
|---|---|---|
| `COLOR` | `steelblue` | ConfigMap `argodemo` (kustomize overlay). Names, `#hex`, `rgb()`, `hsl()` |
| `MESSAGE` | `Hello from Argo CD` | ConfigMap `argodemo` |
| `POD_NAME`, `POD_NAMESPACE`, `NODE_NAME` | `-` | downward API |
| `PORT` | `8080` | |

`/healthz` returns `ok` (probes).

Images: [Hummingbird](https://quay.io/organization/hummingbird) (minimal, hardened). `go:*-builder` compiles a
static binary, `static` runs it as a non-root user. About 25 MB.

## Build and push

The SNO clusters are x86_64: build for `linux/amd64`, also from an Apple Silicon Mac.

```bash
podman build --platform linux/amd64 --build-arg VERSION=1.0.0 \
  -t quay.io/rh_ee_mmayeras/argodemo:1.0.0 app/
podman login quay.io
podman push quay.io/rh_ee_mmayeras/argodemo:1.0.0
```

Make the quay.io repository **public**, or the clusters cannot pull it.

Another registry or tag: change `images` in [`workloads/argodemo/base/kustomization.yaml`](../workloads/argodemo/base/kustomization.yaml).

## Run locally

```bash
podman run --rm -p 8080:8080 -e COLOR='#ff8800' -e MESSAGE='local test' quay.io/rh_ee_mmayeras/argodemo:1.0.0
# http://localhost:8080
```
