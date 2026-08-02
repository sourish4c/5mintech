#!/usr/bin/env python3
"""Wake service - scale k3s deployments + node health + bandwidth stats."""

import os
import json
import ssl
import time
from urllib.request import Request, urlopen
from urllib.error import URLError
from flask import Flask, jsonify, redirect, Response

app = Flask(__name__)

NAMESPACE = "apps"
APPS_HOST = "k3s.example.com"      # matches your Ingress host suffix
ANNOTATION_KEY = "wake.example.com/last-wake"

# ── K8s API ─────────────────────────────────────────────────────────

def k8s_api(method, path, body=None, content_type="application/json"):
    token = open("/var/run/secrets/kubernetes.io/serviceaccount/token").read()
    ca_cert = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
    host = os.environ.get("KUBERNETES_SERVICE_HOST", "kubernetes.default.svc")
    port = os.environ.get("KUBERNETES_SERVICE_PORT", "443")

    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
        "Content-Type": content_type,
    }
    ctx = ssl.create_default_context(cafile=ca_cert)
    data = json.dumps(body).encode() if body else None
    req = Request(f"https://{host}:{port}{path}", data=data, headers=headers, method=method)
    try:
        resp = urlopen(req, context=ctx, timeout=15)
        return json.loads(resp.read())
    except URLError as e:
        if hasattr(e, "code") and e.code == 404:
            return None
        raise


def get_deployment(name):
    return k8s_api("GET", f"/apis/apps/v1/namespaces/{NAMESPACE}/deployments/{name}")


def scale_deployment(name, replicas):
    return k8s_api(
        "PATCH",
        f"/apis/apps/v1/namespaces/{NAMESPACE}/deployments/{name}/scale",
        {"spec": {"replicas": replicas}},
        content_type="application/merge-patch+json",
    )


def stamp_wake(name):
    """Write a wake timestamp into the Deployment's annotations so the
    scale-down cron can skip recently-woken apps (avoids wake/scale races)."""
    now = str(int(time.time()))
    k8s_api(
        "PATCH",
        f"/apis/apps/v1/namespaces/{NAMESPACE}/deployments/{name}",
        {"metadata": {"annotations": {ANNOTATION_KEY: now}}},
        content_type="application/merge-patch+json",
    )


# ── Routes ──────────────────────────────────────────────────────────

@app.route("/status/<app_name>")
def get_status(app_name):
    deploy = get_deployment(app_name)
    if deploy is None:
        return jsonify(app=app_name, status="not-found", replicas=0), 404
    replicas = deploy["spec"].get("replicas", 0)
    status = "running" if replicas and replicas > 0 else "stopped"
    return jsonify(app=app_name, status=status, replicas=replicas)


@app.route("/wake/<app_name>")
def wake(app_name):
    deploy = get_deployment(app_name)
    if deploy is None:
        return jsonify(error=f"Deployment {app_name} not found"), 404
    replicas = deploy["spec"].get("replicas", 0) or 0
    if replicas > 0:
        return redirect(f"https://{app_name}.{APPS_HOST}", code=302)
    scale_deployment(app_name, 1)
    stamp_wake(app_name)
    # JS-polls /status/<app_name> every second, redirects when status == "running".
    return Response(
        WAKING_HTML.format(
            app_name=app_name,
            app_name_json=json.dumps(app_name),
            redirect_url=f"https://{app_name}.{APPS_HOST}",
            redirect_url_json=json.dumps(f"https://{app_name}.{APPS_HOST}"),
        ),
        mimetype="text/html",
    )


WAKING_HTML = """<!DOCTYPE html>
<html>
<head>
<title>Waking {app_name}...</title>
<style>
body {{ font-family: sans-serif; text-align: center; padding: 3em; background: #111; color: #eee; }}
.spinner {{ border: 4px solid #333; border-top: 4px solid #4ade80;
            border-radius: 50%; width: 40px; height: 40px;
            animation: spin 1s linear infinite; margin: 2em auto; }}
@keyframes spin {{ 0% {{ transform: rotate(0deg); }} 100% {{ transform: rotate(360deg); }} }}
</style>
</head>
<body>
<h2>Starting {app_name}...</h2>
<div class="spinner"></div>
<p id="msg">Redirecting to <a href="{redirect_url}">{app_name}</a> when ready.</p>
<script>
const APP = {app_name_json};
const URL_OK = {redirect_url_json};
const TIMEOUT_MS = 30000;
const POLL_MS = 1000;
const t0 = Date.now();

(async () => {{
  while (Date.now() - t0 < TIMEOUT_MS) {{
    try {{
      const r = await fetch(`/status/${{APP}}`);
      const j = await r.json();
      if (j.status === "running") {{ window.location.replace(URL_OK); return; }}
    }} catch (e) {{ /* keep polling */ }}
    await new Promise(r => setTimeout(r, POLL_MS));
  }}
  document.getElementById("msg").innerText =
    "Timed out waiting for " + APP + ". Check the wake service logs.";
}})();
</script>
</body>
</html>
"""

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port)
