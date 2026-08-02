---
title: "Scale Kubernetes to Zero on K3s (Wake on Demand)"
description: "Learn how to scale-to-zero idle k3s apps on a home cluster and wake them on demand with a tiny Flask service, saving about 1.4 GB of RAM for heavier workloads."
slug: "scale-to-zero-k3s-wake-service"
date: 2026-08-01T14:37:07+05:30
draft: false
author: ["Sourish Bhattacharya"]
categories:
    - "DevOps"
    - "How-To Guides"
tags:
    - "k3s"
    - "scale-to-zero"
    - "kubernetes"
    - "home-lab"
    - "traefik"
    - "homepage"
images:
    - "/images/posts/scale-to-zero-k3s-wake-service/featured.png"
thumbnail: "/images/posts/scale-to-zero-k3s-wake-service/featured.png"
---

Here's how I built a tiny Flask wake service that scales idle k3s deployments down to zero replicas and brings them back on demand with a single click from my Homepage dashboard, freeing about 1.4 GB of RAM in the process.
<!--more-->

#### TL;DR - Video Overview
{{< youtube "dsU3LI5jgyE" >}}

### Introduction

I noticed my k3s cluster sat at 1.4 GB of free RAM most of the time, even when nobody was using any of the eight light apps I had deployed. Running eight light apps in a home lab is a real RAM tax, and HPA-style autoscaling is the wrong tool when you don't have CPU pressure, you have *boredom* pressure. So I built a small scale-to-zero system: a wake-on-demand Flask service fronts an idle cron that scales everything to zero after no traffic in the metrics window, and Homepage widgets do the waking. Apps cold-start in about two seconds, the cluster idles around 128 MB, and the UX still feels like "click and go." This post walks through the architecture, the wake service, the scale-down cron, and the Homepage wiring.

{{<audio src="Scale_Kubernetes_clusters_to_zero.mp3" heading="TL;DR - Audio Overview" caption="Listen to this post instead of reading (5 min)" >}}

{{< alert "tip" >}}
**Tested with:** k3s v1.30.x, Traefik v3.7.x (bundled), Homepage v1.x, Python 3.12, Flask 3.0. Multi-node k3s works with caveats — see the multi-node callout in step 4.
{{< /alert >}}

> **All source files** for this post (`app.py`, `Dockerfile`, `k8s.yaml`, `scale-down.sh`, `requirements.txt`, `services.yaml`) are downloadable from the post bundle — see the **Download** link in each section.

### Introduction

I noticed my k3s cluster sat at 1.4 GB of free RAM most of the time, even when nobody was using any of the eight light apps I had deployed. Running eight light apps in a home lab is a real RAM tax, and HPA-style autoscaling is the wrong tool when you don't have CPU pressure, you have *boredom* pressure. So I built a small scale-to-zero system: a wake-on-demand Flask service fronts an idle cron that scales everything to zero after no traffic in the metrics window, and Homepage widgets do the waking. Apps cold-start in about two seconds, the cluster idles around 128 MB, and the UX still feels like "click and go." This post walks through the architecture, the wake service, the scale-down cron, and the Homepage wiring.

### Prerequisites

- A running k3s cluster (a single node is fine, since k3s ships with Traefik by default)
- `kubectl` configured against that cluster
- Homepage already deployed, so you have a dashboard to wire the widgets into
- A small Docker-capable machine for building the wake service image
- Local DNS or a reverse proxy pointing `*.k3s.example.com` at the cluster (use whatever subdomain suffix your Ingress hosts use, e.g. `app1.k3s.example.com`)

### Architecture
```text
User clicks an app in Homepage
        │
        ▼
Homepage widget → GET /wake/<app> via NodePort 30080
        │
        ▼
Wake service pod (k3s "apps" namespace, always on)
        │
        ├── If app is stopped (0 replicas):
        │     PATCH k8s API → scale deploy/<app> replicas=1
        │     Stamp wake.example.com/last-wake annotation
        │     Return HTML "Starting..." page → JS polls /status/<app> → redirect when status=="running"
        │
        └── If app is running (≥1 replicas):
              302 redirect → https://<app>.k3s.example.com (directly)

Scale-down cron (runs every 15 min, host-side):
  For each app with replicas > 0 and last-wake > 14 min ago:
    → Snapshot traefik_service_requests_bytes_total{service=apps-<app>-*}
    → If counter unchanged since last tick → kubectl scale --replicas=0
```

Two moving parts talk to the k3s API. The wake service runs in-cluster with RBAC scoped to the `apps` namespace, and a host-side cron job scales things back down when the Traefik request counters stop moving. Homepage is the only thing the user actually clicks on.

### Implementation

#### 1. Build the wake service

The wake service is a small Flask app. The two core routes that power the wake flow are `/wake/<app>` and `/status/<app>`. The full implementation also exposes `/status`, `/node-health`, and `/bandwidth` for dashboard use. For already-running apps the `/wake` route returns a `302` redirect directly to the target URL. For stopped apps it returns a tiny "Starting…" HTML page whose JavaScript polls `/status/<app>` every second and only redirects once the API reports `status == "running"`, with a 30-second timeout. This is more reliable than a fixed sleep: the browser lands on the URL only when the Pod is actually ready (the `spec.replicas >= 1` check from the K8s API is our proxy for "ready" here, since Traefik's IngressRoute will start 503-ing as soon as `replicas=0` flips back, so the app's own health endpoints don't help during a cold start).

The key helpers in `app.py` are:

- `k8s_api()` — wraps the in-cluster ServiceAccount token, CA cert, and `urllib`. All K8s calls go through it, so the rest of the file doesn't see HTTP plumbing.
- `get_deployment(name)` — `GET /apis/apps/v1/.../deployments/<name>`. Used by `/status/<app>` to read `spec.replicas`.
- `scale_deployment(name, replicas)` — `PATCH /apis/apps/v1/.../deployments/<name>/scale` with `application/merge-patch+json`. Used by `/wake/<app>` to flip replicas from 0 to 1.
- `stamp_wake(name)` — `PATCH .../deployments/<name>` with `{"metadata": {"annotations": {ANNOTATION_KEY: now}}}`. Writes a unix timestamp to `wake.example.com/last-wake` so the scale-down cron can skip recently-woken apps. **This is the only reason the wake service needs `patch` on the parent `deployments` resource** (not just `deployments/scale`).
- The `/wake/<app>` route — returns a 302 if `replicas > 0`, otherwise calls `scale_deployment` + `stamp_wake` and returns the spinner page. The JS in `WAKING_HTML` polls `/status/<app>` every 1s and `window.location.replace`s to the target URL once the status flips to `running`.

> **Scope note.** The status check is `spec.replicas >= 1`, not Pod readiness. That means the redirect fires as soon as the ReplicaSet bumps replicas — *before* the Pod is actually serving. On a cold image pull this can be tens of seconds. If you need true Pod-readiness, add a `/status/<app>/ready` endpoint that calls `GET /api/v1/namespaces/apps/pods?labelSelector=app=<app>` and looks for at least one container with `ready=True` in `status.containerStatuses`. The trade-off is the redirect path becomes a 5–10s wait; the upside is no white-page-while-actually-loading UI.

**Download** → [app.py](app.py)

The `Dockerfile` is a two-stage build: stage 1 installs Flask into `/install` from a slim Python base, stage 2 copies the compiled site-packages in and switches to a non-root `wake` user. The `groupadd`/`useradd` step is required — `python:3.12-slim` doesn't ship UID 65532 in `/etc/passwd`, so a bare `USER 65532:65532` will fail to start with exit code 137.

**Download** → [Dockerfile](Dockerfile), [requirements.txt](requirements.txt)

Build the image on any Docker-capable host (replace `<SRC>` with the path to your checkout) and pipe it straight into the k3s containerd:

```bash
docker build -t wake-service:latest <SRC>/
docker save wake-service:latest | ssh <YOUR_USER>@<YOUR_K3S_HOST> "k3s ctr images import -"
```

That avoids standing up a private registry for one tiny image. Pin the tag to a git SHA in production — e.g. `image: wake-service:$(git rev-parse --short HEAD)` — so a redeploy without a tag bump actually pulls the new image. With `imagePullPolicy: IfNotPresent`, k3s only re-pulls on a tag change, so an unchanging `:latest` quietly serves stale code. For **multi-node clusters**, `k3s ctr images import` only seeds the image on the host you ran it on; either repeat it on every node, or push to a real registry and reference it via `image: registry.example.com/wake-service:latest`.

#### 2. Deploy the wake service with RBAC

The wake service talks to the Kubernetes API directly using the pod's mounted ServiceAccount token — it does **not** shell out to `kubectl`. The `Role` therefore needs to cover everything the service reads or mutates: `get`/`list`/`patch` on `deployments` (for `/status/<app>` and for `stamp_wake` writing the wake-timestamp annotation), `get`/`list`/`patch` on `deployments/scale` (the service PATCHes the `/scale` subresource, not the deployment itself), and `get`/`list` on `services` and `pods` (for `/node-health`). A tight `32Mi` request / `64Mi` limit (with `25m` / `100m` CPU) keeps the "always on" pod from eating the RAM you just freed.

The manifest has six pieces: a `ServiceAccount` named `wake-sa`, a `Role` granting the above permissions, a `RoleBinding` to link them, a `Deployment`, and **two** Services. A `NodePort` Service (`wake-nodeport`, port 30080) is what Homepage hits on the LAN; a `ClusterIP` Service (`wake`) is what in-cluster callers like `/node-health` and any future in-cluster automation would use. A `NodePort` Service is *also* allocated a `ClusterIP` automatically — but the ClusterIP-only Service lets you swap the NodePort and its selector without touching the in-cluster DNS name.

**Download** → [k8s.yaml](k8s.yaml)

```bash
kubectl apply -f k8s.yaml
```

> **Auth on the NodePort.** The NodePort is unauthenticated and any LAN client can hit `/wake/<app>` to spin up workloads. Three ways to harden it: (a) add a tiny bearer-token check at the top of every route and store the token in a Secret that Homepage reads; (b) front the wake service with Traefik as an Ingress on `wake.k3s.example.com` with `traefik-forward-auth` pointing at Authelia/Authentik; (c) lock the NodePort to the dashboard's IP with a `NetworkPolicy` that only allows ingress from `podSelector: {app: homepage}` (or a specific CIDR if Homepage runs on a separate host). Pick (c) for the lowest-effort, highest-value fix:
>
> ```yaml
> apiVersion: networking.k8s.io/v1
> kind: NetworkPolicy
> metadata:
>   name: wake-allow-homepage
>   namespace: apps
> spec:
>   podSelector:
>     matchLabels:
>       app: wake
>   policyTypes: ["Ingress"]
>   ingress:
>     - from:
>         - podSelector:
>             matchLabels:
>               app: homepage
>       ports:
>         - protocol: TCP
>           port: 8080
> ```

You'll also need a wildcard DNS record for `*.k3s.example.com` pointing at the cluster so the HTTPS routes resolve once apps wake up (the `APPS_HOST` constant in the wake service must match this suffix).

#### 3. Wire up the Homepage dashboard

Homepage reads its config from a `ConfigMap`. Add a `CustomAPI` widget per app so the tile shows `running` or `stopped` and the click goes through the wake URL (replace `<YOUR_K3S_SERVER_IP>` with your cluster's LAN address):

**Download** → [services.yaml](services.yaml)

```bash
kubectl create configmap homepage-config -n apps \
  --from-file=services.yaml --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deploy/homepage -n apps
```

The `kubectl create ... --dry-run=client` trick is the easiest way to set or replace a multi-line YAML value in a `ConfigMap` — much cleaner than `kubectl patch` with escaped JSON.

#### 4. Add the scale-down cron

The scale-down lives on the k3s host as a bash script. The key insight: **don't grep Traefik access logs**. By default k3s Traefik doesn't even write access logs to stdout (and even when enabled, the default CLF format puts the timestamp in brackets, not at the start of the line). Instead, query Traefik's built-in Prometheus metrics endpoint for `traefik_service_requests_bytes_total` deltas, which is what the wake service already exposes for its `/bandwidth` widget.

Two more things this script has to handle, both non-obvious:

1. **Wake/scale-down race.** The wake service stamps `wake.example.com/last-wake: <unix-ts>` on the Deployment's `metadata.annotations` whenever it scales an app from 0 to 1. The scale-down script reads that annotation and skips any Deployment that was woken in the last `COOLDOWN_SECONDS` (default 14 min — just under one cron interval) — otherwise the cron can race the cold start and kill the Pod before it's ready.
2. **Single-replica scope.** This whole scheme assumes each app runs as `replicas: 1` and isn't being managed by an HPA. If you set `replicas: 3` or attach an HPA, scale-to-zero will fight both. (See the **Scope and caveats** callout below.)

**Download** → [scale-down.sh](scale-down.sh)

> **Why not grep Traefik logs?** Two reasons. (1) k3s Traefik doesn't enable access logs by default — `kubectl logs -l app.kubernetes.io/name=traefik` shows startup lines only, so the `last_access` empty branch always fires and every app gets force-scaled on the first cron tick. (2) Even if you turn access logs on with `--accesslog=true --accesslog.format=common`, the timestamp lives in `[brackets]` mid-line, so the `^\d{4}-…` anchor never matches. The Prometheus metrics endpoint at `http://traefik-metrics.kube-system.svc.cluster.local:9100/metrics` is always on and gives you per-service request totals, which is what we actually want. (The `.svc.cluster.local` is the synthetic in-cluster domain k3s assigns to every `Service` — the metrics endpoint works from any host on the cluster network.)

> **Multi-node caveat.** The metrics query above is in-cluster (it goes through the `traefik-metrics` Service), so it sees the aggregate counter regardless of which node ingress traffic lands on — this part already works on multi-node. What doesn't work is `k3s ctr images import`: that only seeds the image on the host you ran it on, so repeat the import on every node or push to a real registry. The log-grep approach is also a dead end on multi-node, since a request that lands on node B won't appear in node A's Traefik logs.

Then schedule it to run every 15 minutes (drop it into `/etc/cron.d/scale-down` so you can edit it without `crontab -e`):

```bash
chmod +x /usr/local/bin/scale-down.sh
sudo mkdir -p /var/lib/scale-down
sudo tee /etc/cron.d/scale-down >/dev/null <<'EOF'
*/15 * * * * root /usr/local/bin/scale-down.sh >/dev/null 2>&1
EOF
```

#### 5. Verify the full flow

Run these from anywhere on the LAN to confirm everything is wired up (replace `<YOUR_K3S_SERVER_IP>` and `app1` with your values):

```bash
# Should report "stopped"
curl http://<YOUR_K3S_SERVER_IP>:30080/status/app1

# Wakes the app, returns the "Starting..." HTML page
curl http://<YOUR_K3S_SERVER_IP>:30080/wake/app1

# After ~2s, reports "running"
curl http://<YOUR_K3S_SERVER_IP>:30080/status/app1
```

A stopped app returning the spinner page means the redirect chain works. A running one returning a `302` means the fast path is healthy. The same URLs are what Homepage hits (it defaults to a 5-minute refresh) to keep the tile labels current.

#### 6. Add new apps to the system

Three lines of glue per app:

1. Append the deployment name to `APPS` in `scale-down.sh`.
2. Add a Homepage widget to the `homepage-config` ConfigMap, pointing at the same wake service.
3. Make sure there's a `*.k3s.example.com` DNS record resolving to the cluster (or whatever suffix you picked — the wake service's `APPS_HOST` must match your Ingress host).

After that the new app gets the same auto-wake and idle-scale-down treatment, and you'll see the RAM headroom grow as more apps go cold.

#### 7. Scope and caveats

A few things this design intentionally does *not* handle, and what to do if you need them:

- **Single-replica Deployments only.** This whole scheme assumes each managed app has `spec.replicas: 1`. If you set a higher replica count, the script still scales to zero, undoing your configuration. If you attach an **HPA**, both controllers will fight each other — the HPA will keep bumping replicas back up and the cron will keep scaling them down. Either disable the HPA or remove the app from `APPS`.
- **Synthetic monitoring counts as activity.** Uptime probes, kuma push checks, Homepage's own ping — anything that hits the app's Ingress will increment `traefik_service_requests_bytes_total` and keep the app awake. For apps you want to actually idle, either whitelist their `/health` path in Traefik (so it never reaches the Service) or filter `code="200"` plus a real client user-agent out of the script. The current implementation treats any byte delta as activity.
- **Multi-node k3s clusters.** The script runs on one host and queries Traefik's in-cluster metrics endpoint, which is fine on a single-node cluster. On multi-node, ingress may land on a different node than the cron, but since we go through the in-cluster Service it still sees the aggregate counter — so this part actually works. What doesn't work is `k3s ctr images import`: that only seeds the image on the host you ran it on, so repeat the import on every node or use a real registry.
- **No readiness check on the redirect.** The "Starting…" page polls `/status/<app>`, which returns `running` as soon as `spec.replicas >= 1` — before the new Pod is actually accepting connections. On a warm cache this is fine; on a cold image pull, the browser can hit the URL a few hundred ms before the Pod is ready and get a 502 from Traefik. Refresh once and it works. The scope note in step 1 has a `/status/<app>/ready` upgrade path if you need it.
- **Wake / scale-down race protection.** The wake service stamps `wake.example.com/last-wake: <unix-ts>` on the Deployment and the cron skips anything woken in the last 14 minutes. The cooldown is enforced entirely by the cron (`COOLDOWN_SECONDS` in `scale-down.sh`) — if your apps take longer than 14 minutes to come up, bump that value. The cooldown is intentionally one minute shorter than the cron interval, so a freshly-woken app gets exactly one full cron tick of breathing room before it's eligible to scale down.

#### 8. Conclusion

The numbers in my home lab were the motivator: with all eight managed apps running I was sitting on 1.6–2.4 GB of RAM, and with everything scaled down the cluster idles around 128 MB. Wake-from-cold is about two seconds because the images are already pulled, and the wake service itself is the only thing always running. I've been running this for months and the headroom is enough to throw a few heavier workloads (transcoding, photo libraries) at the same node without touching swap.

For a multi-node k3s cluster the wake service and RBAC work as-is; the two changes are pushing the image to a registry (so all nodes can pull it) and running the scale-down script on whichever node is least loaded (the metrics query is in-cluster, so it doesn't matter which host runs the cron). Happy to share an HA setup with a leader-elected cron in a follow-up. If you also run container monitoring at home, the [TIG stack walkthrough](/posts/docker-monitoring-influxdb-telegraf-grafana/) is the closest sibling post on this blog.

#### 9. References

- [k3s documentation](https://docs.k3s.io/) — official k3s docs and quickstart.
- [Kubernetes Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) — official Kubernetes docs on Deployment objects and scaling.
- [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) — official Kubernetes docs on Roles, RoleBindings, and ServiceAccounts.
- [Homepage Custom API widget](https://gethomepage.dev/widgets/services/customapi/) — official Homepage docs for the `customapi` widget used for the status tiles.

---

{{< alert "twitter" >}}
Thank you for visiting 5 Minutes Tech. [Follow us](https://x.com/sourish4c) for new Updates 🚀
{{< /alert >}}
