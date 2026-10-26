// argodemo: a one-page web app for the argo-agent-mode lab.
// The page is filled with COLOR and shows where it runs, so you can see at a glance
// which namespace and cluster node served it.
package main

import (
	"html/template"
	"log"
	"net/http"
	"os"
	"regexp"
)

var version = "dev" // set at build time: -ldflags "-X main.version=..."

// CSS color values only: names, #hex, rgb()/hsl(). Anything else falls back to the default.
var colorRe = regexp.MustCompile(`^[#a-zA-Z0-9(),.% ]{1,40}$`)

var page = template.Must(template.New("page").Parse(`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{{.Message}}</title>
<style>
  body { margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
         background: {{.Color}}; font-family: system-ui, sans-serif; }
  .card { background: rgba(255,255,255,.92); border-radius: 12px; padding: 28px 36px; min-width: 320px;
          box-shadow: 0 8px 30px rgba(0,0,0,.25); }
  h1 { margin: 0 0 16px; font-size: 28px; }
  dl { display: grid; grid-template-columns: max-content 1fr; gap: 6px 16px; margin: 0; }
  dt { color: #555; }
  dd { margin: 0; font-family: ui-monospace, Menlo, monospace; }
</style>
</head>
<body>
<div class="card">
  <h1>{{.Message}}</h1>
  <dl>
    <dt>color</dt><dd>{{.Color}}</dd>
    <dt>namespace</dt><dd>{{.Namespace}}</dd>
    <dt>pod</dt><dd>{{.Pod}}</dd>
    <dt>node</dt><dd>{{.Node}}</dd>
    <dt>version</dt><dd>{{.Version}}</dd>
  </dl>
</div>
</body>
</html>
`))

type info struct {
	Message, Namespace, Pod, Node, Version string
	Color                                  template.CSS
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func color() template.CSS {
	c := env("COLOR", "steelblue")
	if !colorRe.MatchString(c) {
		c = "steelblue"
	}
	return template.CSS(c) // validated above, safe to inline in the style block
}

func main() {
	http.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Write([]byte("ok\n"))
	})
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		page.Execute(w, info{
			Message:   env("MESSAGE", "Hello from Argo CD"),
			Color:     color(),
			Namespace: env("POD_NAMESPACE", "-"),
			Pod:       env("POD_NAME", "-"),
			Node:      env("NODE_NAME", "-"),
			Version:   version,
		})
	})
	addr := ":" + env("PORT", "8080")
	log.Printf("argodemo %s listening on %s", version, addr)
	log.Fatal(http.ListenAndServe(addr, nil))
}
