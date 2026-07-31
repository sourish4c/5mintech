---
title: "Monitor Docker Containers with InfluxDB, Telegraf & Grafana"
description: "Monitor every Docker container with InfluxDB, Telegraf, and Grafana. Capture per-container CPU, memory, network, and block I/O metrics with Flux queries."
slug: "docker-monitoring-influxdb-telegraf-grafana"
date: 2026-07-30T23:15:17+05:30
draft: true
author: ["Sourish Bhattacharya"]
categories:
  - DevOps
  - "How-To Guides"
tags:
  - docker
  - monitoring
  - influxdb
  - telegraf
  - grafana
images:
  - "/images/posts/docker-monitoring-influxdb-telegraf-grafana/featured.png"
thumbnail: "/images/posts/docker-monitoring-influxdb-telegraf-grafana/featured.png"
---

Per-container CPU, memory, network, and block I/O history for every container on every host, with a single Grafana dashboard on top.
<!--more-->

---

### Introduction

Last quarter a single misbehaving container dragged a host's swap to 100% in the middle of the night. By the time I logged in, the `docker stats` view had already cycled past the culprit. I had no per-container history, no Out of Memory (OOM) record, and no way to prove which service was responsible. That was the day I set up InfluxDB, Telegraf, and Grafana as a permanent record for every container on every host.

This guide walks through the exact stack I run in production: Telegraf as a sidecar on each Docker host, InfluxDB v2 as the time-series store, and Grafana on top with Flux queries for CPU, memory, network, and block I/O. The whole thing ships as a single `docker-compose.yml` plus a reusable dashboard.

### Prerequisites

You need InfluxDB v2 and Grafana reachable from each Docker host. The Telegraf sidecar runs locally on every host you want to monitor.

### How the pieces fit

The flow is straightforward. Telegraf talks to the host's Docker socket, scrapes per-container stats every ten seconds, and writes them to InfluxDB. Grafana then queries InfluxDB over Flux and renders the dashboard.

```text
[ Docker Host ] -> [ Telegraf ] -> [ InfluxDB v2 ] -> [ Grafana ]
```

### Implementation

#### 1. Prepare InfluxDB

Start with a dedicated bucket. Keeping Docker metrics isolated makes retention easier to tune later.

```bash
influx bucket create \
  --name docker-metrics \
  --retention 90d \
  --org <YOUR_ORG>
```

Next, generate a write-only API token. In the InfluxDB UI, go to **Load Data → API Tokens → Generate API Token → Custom API Token** and grant read/write on `docker-metrics`. Save the token — you'll paste it into Telegraf next:

```ini
token = "<YOUR_INFLUX_TOKEN>"   # placeholder — paste your generated token here
```

Verify connectivity before moving on:

```bash
curl -sI http://<INFLUXDB_HOST>:8086/ping
# expect: HTTP/1.1 204 No Content
```

#### 2. Deploy Telegraf as a sidecar

I keep all Telegraf config under a single directory and run it with Compose:

```bash
mkdir -p ./telegraf/
```

`docker-compose.yml`:

```yaml
services:
  telegraf:
    image: telegraf:1.39
    container_name: telegraf
    user: root
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./telegraf.conf:/etc/telegraf/telegraf.conf:ro
    group_add:
      - "990"   # your host's docker GID (getent group docker)
    restart: unless-stopped
```

That `group_add` line has bitten me more than once. Without it, Telegraf silently fails with `permission denied` on the Docker socket. Find your host's docker GID with `getent group docker` and drop the number in.

`telegraf.conf`:

```ini
[agent]
  interval = "10s"
  flush_interval = "10s"

[[inputs.docker]]
  endpoint = "unix:///var/run/docker.sock"
  perdevice_include = ["cpu", "blkio", "network"]
  total_include = ["cpu", "blkio", "network"]
  container_name_include = []
  container_name_exclude = []
  container_state_include = ["running"]
  docker_label_include = []

[[outputs.influxdb_v2]]
  urls = ["http://<INFLUXDB_HOST>:8086"]
  token = "<YOUR_INFLUX_TOKEN>"
  organization = "<YOUR_ORG>"
  bucket = "docker-metrics"
```

The `perdevice_include` setting is what gives you per-core CPU and per-interface network metrics. Without it you only get the container totals.

Start it up and confirm data is flowing:

```bash
docker compose pull && docker compose up -d
docker logs telegraf --tail 20
# expect: Loaded inputs: docker
# expect: Loaded outputs: influxdb_v2
```

If points show up in InfluxDB within a minute, you're good.

#### 3. The Flux queries that actually work

These are the queries that survived contact with production.

**Per-container CPU percent:**

```flux
from(bucket: "docker-metrics")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r._measurement == "docker_container_cpu"
    and r._field == "usage_percent"
    and r.cpu == "cpu-total")
  |> filter(fn: (r) => r.container_name =~ /^${container:regex}$/)
  |> aggregateWindow(every: 10s, fn: mean, createEmpty: false)
  |> keep(columns: ["_time", "_value", "container_name"])
```

**Memory usage percent (native field):**

```flux
from(bucket: "docker-metrics")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r._measurement == "docker_container_mem"
    and r._field == "usage_percent")
  |> filter(fn: (r) => r.container_name =~ /^${container:regex}$/)
  |> aggregateWindow(every: 10s, fn: mean, createEmpty: false)
  |> keep(columns: ["_time", "_value", "container_name"])
```

Telegraf already computes `usage_percent` from cgroup stats, with page cache excluded — the same way `docker stats` reports it. Doing this manually as `usage / limit * 100` over-reports for containers doing heavy file I/O, because raw cgroup `usage` includes page cache that the kernel can reclaim at any time.

**Network throughput:**

```flux
from(bucket: "docker-metrics")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r._measurement == "docker_container_net")
  |> filter(fn: (r) => r.container_name =~ /^${container:regex}$/)
  |> filter(fn: (r) => r._field == "rx_bytes" or r._field == "tx_bytes")
  |> aggregateWindow(every: 10s, fn: last, createEmpty: false)
  |> derivative(unit: 1s, nonNegative: true)
```

**Block I/O throughput:**

```flux
from(bucket: "docker-metrics")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r._measurement == "docker_container_blkio")
  |> filter(fn: (r) => r.container_name =~ /^${container:regex}$/)
  |> filter(fn: (r) => r._field == "io_service_bytes_recursive_read" or r._field == "io_service_bytes_recursive_write")
  |> aggregateWindow(every: 10s, fn: last, createEmpty: false)
  |> derivative(unit: 1s, nonNegative: true)
```

Both the network and block I/O queries use `derivative()` to convert cumulative byte counters into per-second rates — that's what produces the spike-shaped lines on the graph. Flux also has a `rate()` function, but it computes a *windowed* rate (last-minus-first divided by window duration), not a per-point counter delta. For the per-second throughput graph you actually want to read, stick with `derivative()`.

#### 4. Things that will bite you

A short list of the failures I actually hit:

- **`=~` versus `==~`**: Flux uses `=~` for regex matching. `==~` looks like JavaScript and silently returns no rows.
- **Uptime in nanoseconds**: Telegraf emits `uptime_ns`. Divide by 1,000,000 in the query and set the Grafana unit to `dtdurations`, or you'll see "74117 years" of uptime.
- **OOM as a boolean**: The `oomkilled` field is a bool. Map it to `0` or `1` first, then add a Grafana value mapping (`0 → OK` in green, `1 → OOM` in red).
- **Stale overrides**: When iterating on panels, old `hideSeriesFrom` field overrides can hide series you actually want. Clear them under **Panel → Overrides** if a panel mysteriously drops containers.

#### 5. Dashboard layout that works

I lay out a 24-column grid like this:

- **Row 1**: Stat panels for running, paused, stopped, total, and OOM count.
- **Row 2**: Timeseries for CPU percent and memory percent, one line per container.
- **Row 3**: Timeseries for network rx/tx and block I/O read/write, with `bps` units.
- **Row 4**: A table panel with uptime, PID, image, and OOM status, plus a Merge transformation to join the three queries by `container_name`.

Add a `container` template variable that pulls `container_name` tag values, set **Multi-value** and **Include All** to on, and you've got a dashboard you can drop on any host.

#### 6. Conclusion

If you're running this across multiple hosts, the next step is to add a `host` tag. Either run one Telegraf per host and prefix the bucket, or drop a `global_tags` block into `telegraf.conf` with `host = "$(HOSTNAME)"`. From there, a single Grafana dashboard can slice every container across your fleet.

If you're scaling up further, I'm planning a follow-up on tuning InfluxDB retention across multiple hosts — happy to share the Terraform for the cluster setup once it's written.

Want the dashboard JSON to drop straight into Grafana? That's another follow-up I'm writing. In the meantime, the layout in Section 5 is enough to recreate the four rows from scratch, and the Flux queries in this section are what goes in each panel.

#### 7. References

- [Telegraf Docker input plugin](https://docs.influxdata.com/telegraf/v1/input-plugins/docker/) — official InfluxData docs for the input plugin, including every measurement field and tag.
- [InfluxDB v2 documentation](https://docs.influxdata.com/influxdb/v2/) — covers bucket creation, API tokens, and the HTTP query API used in step 1.
- [Grafana InfluxDB data source](https://grafana.com/docs/grafana/latest/datasources/influxdb/) — official Grafana docs for configuring the Flux data source and template variables.
- [Flux query language](https://docs.influxdata.com/flux/) — reference for every function used in the panel queries.

---

{{< alert "twitter" >}}
Thank you for visiting 5 Minutes Tech. [Follow us](https://x.com/sourish4c) for new Updates 🚀
{{< /alert >}}
