#!/bin/bash
# /usr/local/bin/scale-down.sh
# Scale down idle k3s deployments using Traefik Prometheus metrics.
# Tested with k3s v1.30 + Traefik v3.x.
set -euo pipefail

APPS="app1 app2 app3 app4 app5 app6 app7 app8"
NAMESPACE="apps"
COOLDOWN_SECONDS=840   # skip apps woken in the last 14 min (one minute less than the 15-min cron interval)
ANNOTATION_KEY="wake.example.com/last-wake"
LOG_FILE="/var/log/scale-down.log"
NOW=$(date +%s)

# Traefik's bundled Prometheus metrics endpoint. Reachable from any host
# that can resolve in-cluster DNS. The .svc.cluster.local suffix is the
# synthetic in-cluster domain k3s assigns to every Service; check your
# actual CoreDNS IP with `kubectl get svc -n kube-system kube-dns`
# (10.43.0.10 is the k3s default).
TRAEFIK_METRICS_URL="http://traefik-metrics.kube-system.svc.cluster.local:9100/metrics"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# ── 1. Snapshot Traefik's per-service request counters ───────────────
# traefik_service_requests_bytes_total{service="apps-app1-8080@kubernetes",code="200",method="GET"} N
declare -A LAST_SEEN
metrics=$(curl -s --max-time 10 "$TRAEFIK_METRICS_URL" || echo "")

if [ -z "$metrics" ]; then
    log "ERROR: could not fetch $TRAEFIK_METRICS_URL; bailing out this tick"
    tail -1000 "$LOG_FILE" > /tmp/scale-down-log.tmp 2>/dev/null && mv /tmp/scale-down-log.tmp "$LOG_FILE" || true
    exit 0
fi

# Map service label (apps-<app>-<port>) → total bytes-served counter.
# A service that hasn't received any traffic since the last counter reset
# will keep its old value; we treat "stale counter + replicas>0 + past cooldown"
# as the idle signal.
for app in $APPS; do
    # Match any port for this app, sum across ports.
    bytes=$(echo "$metrics" \
        | grep -E "^traefik_service_requests_bytes_total\{service=\"apps-${app}-" \
        | awk '{sum += $NF} END {print sum+0}')
    LAST_SEEN[$app]=$bytes
done

# ── 2. Loop and decide ───────────────────────────────────────────────
for app in $APPS; do
    replicas=$(kubectl get deploy "$app" -n "$NAMESPACE" -o jsonpath="{.spec.replicas}" 2>/dev/null || echo "0")
    if [ "$replicas" = "0" ] || [ -z "$replicas" ]; then
        continue
    fi

    # Read the wake timestamp the wake service stamped on the Deployment.
    last_wake=$(kubectl get deploy "$app" -n "$NAMESPACE" \
        -o jsonpath="{.metadata.annotations.${ANNOTATION_KEY//./\\.}}" 2>/dev/null || echo "")
    if [ -n "$last_wake" ]; then
        wake_age=$(( NOW - last_wake ))
        if [ "$wake_age" -lt "$COOLDOWN_SECONDS" ]; then
            log "Skipping $app - woken ${wake_age}s ago (cooldown ${COOLDOWN_SECONDS}s)"
            continue
        fi
    fi

    # If Traefik has never seen this service label, the app has had zero
    # traffic in this Prometheus retention window → treat as idle.
    bytes=${LAST_SEEN[$app]:-0}
    if [ "$bytes" = "0" ]; then
        log "Scaling down $app - 0 traffic observed in metrics window"
        kubectl scale deploy "$app" -n "$NAMESPACE" --replicas=0
        continue
    fi

    # We don't track "last byte seen at" from the metrics (Prometheus counters
    # are monotonic; the wake service's /bandwidth widget derives rates from
    # scrape deltas). For a per-app "idle > N minutes" check, snapshot the
    # counter to a file each tick and diff next tick.
    state_dir="/var/lib/scale-down"
    mkdir -p "$state_dir"
    prev_file="$state_dir/${app}.bytes"
    prev=$(cat "$prev_file" 2>/dev/null || echo 0)
    echo "$bytes" > "$prev_file"

    if [ "$bytes" = "$prev" ]; then
        log "Scaling down $app - no new traffic since last tick (counter=$bytes)"
        kubectl scale deploy "$app" -n "$NAMESPACE" --replicas=0
    else
        log "Keeping $app - new traffic since last tick (counter $prev -> $bytes)"
    fi
done

# Keep the log bounded
tail -1000 "$LOG_FILE" > /tmp/scale-down-log.tmp 2>/dev/null && mv /tmp/scale-down-log.tmp "$LOG_FILE" || true
