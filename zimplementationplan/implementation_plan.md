# IoT-NAS Capstone — Complete Deployment Plan

> **Goal:** Generate a fully working, deployment-ready codebase that Ashish can push to AWS EC2 and have the entire IoT-Aware AI Event-Driven NAS running for his capstone demo.
>
> **Target:** 3 AWS EC2 nodes (free tier credits, ~$100 budget)
> **Timeline:** ~5 days to full demo-ready state

---

## Project File Structure

Every file below will be generated. Files marked `[NEW]` are created from scratch.

```
d:\IoT_NAS\
├── docker-compose.yml              [NEW] — All Node 1 services (fixed, complete)
├── .env                            [NEW] — Centralized credentials & config
├── init.sql                        [NEW] — PostgreSQL schema auto-setup
├── mosquitto/
│   └── config/
│       └── mosquitto.conf          [NEW] — MQTT broker config
├── prometheus/
│   └── prometheus.yml              [NEW] — Metrics scraping config
├── nginx/
│   └── nginx.conf                  [NEW] — Reverse proxy for all APIs
├── grafana/
│   └── provisioning/
│       ├── datasources/
│       │   └── datasource.yml      [NEW] — Auto-provision Prometheus
│       └── dashboards/
│           ├── dashboard.yml       [NEW] — Dashboard provider config
│           └── iot-nas.json        [NEW] — Pre-built Grafana dashboard
├── services/
│   ├── queue/
│   │   ├── Dockerfile              [NEW] — Queue API container
│   │   ├── main.py                 [NEW] — FastAPI Priority Queue service
│   │   └── requirements.txt        [NEW]
│   ├── inference/
│   │   ├── Dockerfile              [NEW] — Inference API container
│   │   ├── main.py                 [NEW] — FastAPI YOLOv8 + LSTM service
│   │   └── requirements.txt        [NEW]
│   └── forensics/
│       ├── Dockerfile              [NEW] — Forensic Logger container
│       ├── main.py                 [NEW] — FastAPI Ed25519 hash chain
│       └── requirements.txt        [NEW]
├── simulator/
│   ├── simulate.py                 [NEW] — 100-device IoT event simulator
│   └── requirements.txt            [NEW]
├── scripts/
│   ├── setup-node1.sh              [NEW] — Node 1 bootstrap (Docker + services)
│   ├── setup-ceph-nodes.sh         [NEW] — Node 2/3 prep for Ceph
│   ├── setup-ceph-cluster.sh       [NEW] — Ceph bootstrap + OSD + RGW
│   ├── deploy.sh                   [NEW] — Full deploy automation
│   └── demo.sh                     [NEW] — Pre-demo health checks
└── Iotnasfullcontext.md            [EXISTS] — Your context document
```

**Total: ~25 files to generate**

---

## Proposed Changes

### Phase 1 — Foundation Files

#### [NEW] [.env](file:///d:/IoT_NAS/.env)
Centralized environment variables — no more hardcoded credentials scattered across services.

```
POSTGRES_DB=iotnas
POSTGRES_USER=iotnas
POSTGRES_PASSWORD=iotnas2024
REDIS_HOST=redis
REDIS_PORT=6379
MQTT_HOST=mosquitto
MQTT_PORT=1883
GRAFANA_ADMIN_PASSWORD=iotnas2024
QUEUE_API_PORT=8001
INFERENCE_API_PORT=8000
FORENSIC_API_PORT=8002
```

#### [NEW] [docker-compose.yml](file:///d:/IoT_NAS/docker-compose.yml)
Complete Docker Compose with **all 10 services** — fixes every bug from the analysis:
- Proper YAML volumes block
- All 3 FastAPI services included with build contexts
- PostgreSQL healthcheck + init.sql mount
- n8n with correct v1.60+ config (no deprecated auth vars)
- Mosquitto + Prometheus with config mounts
- Grafana with auto-provisioned dashboards
- `restart: unless-stopped` on all services
- No deprecated `version` key
- Proper `depends_on` chains

**Services defined:**
| Service | Port | Image/Build |
|---|---|---|
| redis | 6379 | redis:7-alpine |
| mosquitto | 1883, 9001 | eclipse-mosquitto:2 |
| postgres | 5432 | postgres:16-alpine |
| n8n | 5678 | n8nio/n8n:latest |
| queue-api | 8001 | ./services/queue (FastAPI) |
| inference-api | 8000 | ./services/inference (FastAPI) |
| forensic-api | 8002 | ./services/forensics (FastAPI) |
| prometheus | 9090 | prom/prometheus:latest |
| grafana | 3000 | grafana/grafana:latest |
| nginx | 80 | nginx:alpine |

> [!NOTE]
> `node-exporter` will run directly on the host (not in Docker) since it needs host-level metrics. The setup script installs it.

---

### Phase 2 — Priority Queue API (Port 8001)

#### [NEW] [services/queue/main.py](file:///d:/IoT_NAS/services/queue/main.py)
FastAPI service implementing the paper's priority queue with **corrected scoring formula**:

**Endpoints:**
| Method | Path | Description |
|---|---|---|
| POST | `/enqueue` | ZADD event with correct priority score |
| GET | `/dequeue` | ZPOPMAX highest-priority event |
| GET | `/queue/status` | Queue depth by P1–P4 tier |
| DELETE | `/queue/flush` | Clear queue (testing) |
| GET | `/health` | Redis connectivity check |
| GET | `/metrics` | Prometheus-compatible metrics |

**Key fix — correct scoring formula:**
```python
# Paper says: score = (4 − priority) × 10^9 + unix_timestamp_ns
# Problem: priority prefix (3×10^9) is dwarfed by full ns timestamp (~1.7×10^18)
# Fix: use 10^18 multiplier so priority ALWAYS dominates
score = (4 - priority) * (10**18) + timestamp_ns
```

This guarantees:
- Every P1 event has a higher score than any P2 event, regardless of timestamps
- Within the same priority tier, newer events have higher scores (LIFO within tier, which matches ZPOPMAX)
- No timestamp truncation, no collisions

#### [NEW] [services/queue/Dockerfile](file:///d:/IoT_NAS/services/queue/Dockerfile)
Python 3.11-slim base, pip install, uvicorn entrypoint.

#### [NEW] [services/queue/requirements.txt](file:///d:/IoT_NAS/services/queue/requirements.txt)
```
fastapi==0.115.0
uvicorn[standard]==0.30.0
redis==5.0.0
prometheus-client==0.20.0
```

---

### Phase 3 — Inference API (Port 8000)

#### [NEW] [services/inference/main.py](file:///d:/IoT_NAS/services/inference/main.py)
FastAPI service with two inference endpoints:

**Endpoints:**
| Method | Path | Description |
|---|---|---|
| POST | `/infer/image` | YOLOv8-Nano object detection (file upload) |
| POST | `/infer/sensor` | LSTM anomaly detection (JSON body) |
| GET | `/health` | Model backend status |
| GET | `/metrics` | Prometheus metrics |

**YOLOv8 handling:**
- Auto-downloads `yolov8n.pt` on first run
- Returns detections with class, confidence, bounding boxes
- Reports latency with note about Coral TPU speedup

**LSTM anomaly detection (simulation):**
- Rule-based scoring mimicking LSTM 60-sample window
- Temperature, vibration, pressure thresholds
- **Fix:** anomaly score clamped to [0.0, 1.0]
- Returns priority recommendation, failure ETA

> [!IMPORTANT]
> The inference container will be ~2GB due to PyTorch/Ultralytics dependencies. On t3.large (8GB RAM), this is fine but will take 5-10 minutes to build the first time.

#### [NEW] [services/inference/Dockerfile](file:///d:/IoT_NAS/services/inference/Dockerfile)
Python 3.11-slim, installs ultralytics + dependencies, downloads YOLOv8n model at build time.

#### [NEW] [services/inference/requirements.txt](file:///d:/IoT_NAS/services/inference/requirements.txt)
```
fastapi==0.115.0
uvicorn[standard]==0.30.0
ultralytics==8.2.0
python-multipart==0.0.9
prometheus-client==0.20.0
Pillow==10.4.0
numpy==1.26.4
```

---

### Phase 4 — Forensic Logger API (Port 8002)

#### [NEW] [services/forensics/main.py](file:///d:/IoT_NAS/services/forensics/main.py)
FastAPI service implementing Ed25519 hash chain with **persistence fixes**:

**Endpoints:**
| Method | Path | Description |
|---|---|---|
| POST | `/log` | Sign event, append to hash chain |
| GET | `/chain` | View recent chain entries (paginated) |
| GET | `/verify` | Verify hash chain integrity |
| GET | `/health` | Service status |
| GET | `/metrics` | Prometheus metrics |

**Critical fixes from analysis:**
- Ed25519 signing key **persisted to disk** (survives restarts)
- Hash chain **persisted to disk** (JSON file on Docker volume)
- Chain loaded on startup, key loaded or generated once
- Verify endpoint walks the full chain and checks every hash link

#### [NEW] [services/forensics/Dockerfile](file:///d:/IoT_NAS/services/forensics/Dockerfile)
#### [NEW] [services/forensics/requirements.txt](file:///d:/IoT_NAS/services/forensics/requirements.txt)
```
fastapi==0.115.0
uvicorn[standard]==0.30.0
PyNaCl==1.5.0
prometheus-client==0.20.0
```

---

### Phase 5 — Config Files & Database

#### [NEW] [init.sql](file:///d:/IoT_NAS/init.sql)
PostgreSQL schema auto-executed on first boot:
- `iot_events` table with **UUID primary keys** (per design principles)
- B-tree indexes on priority, created_at, device_id
- `priority_summary` view for demo queries
- `device_registry` table for device trust scores
- `forensic_audit_log` table (mirrors the hash chain for SQL queries)

#### [NEW] [mosquitto/config/mosquitto.conf](file:///d:/IoT_NAS/mosquitto/config/mosquitto.conf)
- Listener on port 1883 (MQTT)
- Listener on port 9001 (WebSocket — for n8n MQTT trigger)
- Anonymous access enabled (demo simplicity)
- Persistence enabled

#### [NEW] [prometheus/prometheus.yml](file:///d:/IoT_NAS/prometheus/prometheus.yml)
Scrape targets:
- queue-api:8001/metrics
- inference-api:8000/metrics
- forensic-api:8002/metrics
- node-exporter:9100/metrics (host)

#### [NEW] [nginx/nginx.conf](file:///d:/IoT_NAS/nginx/nginx.conf)
Reverse proxy on port 80:
- `/api/queue/*` → queue-api:8001
- `/api/infer/*` → inference-api:8000
- `/api/forensic/*` → forensic-api:8002
- `/n8n/*` → n8n:5678
- `/grafana/*` → grafana:3000

#### [NEW] [grafana/provisioning/datasources/datasource.yml](file:///d:/IoT_NAS/grafana/provisioning/datasources/datasource.yml)
Auto-provisions Prometheus as default datasource.

#### [NEW] [grafana/provisioning/dashboards/dashboard.yml](file:///d:/IoT_NAS/grafana/provisioning/dashboards/dashboard.yml)
Dashboard provider config.

#### [NEW] [grafana/provisioning/dashboards/iot-nas.json](file:///d:/IoT_NAS/grafana/provisioning/dashboards/iot-nas.json)
Pre-built Grafana dashboard with panels:
- Event counts by priority (P1–P4 bar chart)
- Queue depth over time
- Inference latency histogram
- System CPU/Memory usage
- Forensic chain length

---

### Phase 6 — IoT Simulator

#### [NEW] [simulator/simulate.py](file:///d:/IoT_NAS/simulator/simulate.py)
Complete simulator with fixes:
- 100 virtual IoT devices (cameras, motors, sensors, gateways, wearables)
- Paper-accurate distribution: 8% P1, 22% P2, 60% P3, 10% P4
- Publishes via MQTT to `iot/events/p{priority}` topics
- Also POSTs to Queue API (with **try/except** — won't crash on API failure)
- Rich event payloads (zone, confidence, temperature, vibration, pressure)
- Device trust scores (0.5–1.0 range)
- Configurable event rate via CLI args
- Colored terminal output for demo visibility

#### [NEW] [simulator/requirements.txt](file:///d:/IoT_NAS/simulator/requirements.txt)
```
paho-mqtt==2.1.0
requests==2.31.0
```

---

### Phase 7 — AWS Deployment Scripts

#### [NEW] [scripts/setup-node1.sh](file:///d:/IoT_NAS/scripts/setup-node1.sh)
Run on Node 1 (t3.large) after SSH:
1. Install Docker + Docker Compose v2
2. Install node-exporter (host-level)
3. Clone/copy project files
4. Format and mount EBS volume for Ceph OSD
5. `docker compose up -d`
6. Wait for healthchecks
7. Print status summary

#### [NEW] [scripts/setup-ceph-nodes.sh](file:///d:/IoT_NAS/scripts/setup-ceph-nodes.sh)
Run on Node 2 and Node 3 (t3.medium):
1. Install Docker
2. Enable root SSH (required by cephadm)
3. Format EBS volume for Ceph OSD
4. Install cephadm dependencies

#### [NEW] [scripts/setup-ceph-cluster.sh](file:///d:/IoT_NAS/scripts/setup-ceph-cluster.sh)
Run on Node 1 after all nodes are ready:
1. Install cephadm
2. `cephadm bootstrap --mon-ip <NODE1_PRIVATE_IP>`
3. Copy SSH key to Node 2/3
4. `ceph orch host add` for Node 2/3
5. `ceph orch daemon add osd` for each node's EBS
6. Create pools: `iot-p1-nvme`, `iot-p3-replicated`, `iot-forensic-logs`
7. **Deploy RGW correctly:** `ceph orch apply rgw iotnas` (not the broken `mgr module enable rgw`)
8. Create S3 user + bucket
9. Verify HEALTH_OK

#### [NEW] [scripts/deploy.sh](file:///d:/IoT_NAS/scripts/deploy.sh)
One-shot deployment orchestrator:
1. SCP project files to Node 1
2. SSH → run setup-node1.sh
3. SCP setup scripts to Node 2/3
4. SSH → run setup-ceph-nodes.sh on each
5. SSH Node 1 → run setup-ceph-cluster.sh
6. Run health checks

#### [NEW] [scripts/demo.sh](file:///d:/IoT_NAS/scripts/demo.sh)
Pre-demo health check script (matches §6.10 checklist):
```bash
# Checks all services, prints colored ✓/✗ status
curl localhost:8001/health  → Redis connected?
curl localhost:8000/health  → YOLOv8 loaded?
curl localhost:8002/health  → Forensic chain ready?
ceph status                 → HEALTH_OK?
docker compose ps           → All containers Up?
psql → iot_events table?    → Schema ready?
```

---

## n8n Workflows

> [!IMPORTANT]
> n8n workflows cannot be pre-configured via files — they must be imported through the n8n UI or API. I will provide:
> 1. **Detailed step-by-step instructions** for creating all 3 workflows manually in the UI
> 2. **Exportable JSON workflow files** that can be imported via n8n's import feature
>
> The 3 workflows:
> - **Workflow 1:** MQTT Event Ingestor (MQTT trigger → parse → score → enqueue → PostgreSQL insert)
> - **Workflow 2:** Priority Queue Consumer (Schedule 500ms → dequeue → route by priority → process)
> - **Workflow 3:** Demo P1 Burst Injector (manual trigger → inject 10 P1 events)

---

## AWS Cost Estimate

| Resource | Spec | Cost/Week |
|---|---|---|
| EC2 t3.large (Node 1) | 2 vCPU, 8GB, on-demand | ~$5.85 |
| EC2 t3.medium × 2 (Nodes 2-3) | 2 vCPU, 4GB each | ~$5.85 |
| EBS gp3 70GB total (30+20+20) | 3,000 IOPS each | ~$1.10 |
| Data transfer | ~5GB/week | ~$0.50 |
| **Total** | | **~$13.30/week** |

With $100 in credits, you have ~7+ weeks of runway. More than enough.

> [!TIP]
> **Stop instances when not working** — EC2 charges are per-hour. Stopping overnight saves ~40% of compute cost.

---

## Verification Plan

### Automated (scripts/demo.sh)
After deployment, the demo script checks:
- [ ] All Docker containers are `Up` and healthy
- [ ] Redis ping responds
- [ ] Queue API `/health` returns `{"status":"ok","redis":"connected"}`
- [ ] Inference API `/health` returns `{"status":"ok","backend":"YOLOv8n-ultralytics-CPU"}`
- [ ] Forensic API `/health` returns `{"status":"ok"}`
- [ ] PostgreSQL `iot_events` table and `priority_summary` view exist
- [ ] Ceph `ceph status` returns `HEALTH_OK` with 3 OSDs
- [ ] Mosquitto accepts MQTT publish/subscribe
- [ ] Simulator runs for 10 seconds without errors

### Manual (Demo rehearsal)
- [ ] Start simulator → see P1🔴 P2🟠 P3🟢 P4⚪ events in terminal
- [ ] n8n UI → workflows executing, no errors
- [ ] Queue status → P1 events processed first regardless of arrival order
- [ ] Upload test image → YOLOv8 returns detections
- [ ] POST sensor data → LSTM flags anomaly
- [ ] `ceph status` → stop Node 3 OSD → HEALTH_WARN → restart → HEALTH_OK
- [ ] `curl /chain` → see Ed25519 signatures and hash chain
- [ ] Grafana dashboard → live metrics updating

---

## Execution Order

| Phase | What | Files | Est. Time |
|---|---|---|---|
| 1 | Foundation (compose, env, configs) | 8 files | 1 hour |
| 2 | Queue API service | 3 files | 30 min |
| 3 | Inference API service | 3 files | 30 min |
| 4 | Forensic Logger service | 3 files | 30 min |
| 5 | Database + monitoring configs | 4 files | 30 min |
| 6 | Simulator | 2 files | 20 min |
| 7 | AWS deploy scripts + demo | 5 files | 40 min |
| **Total** | | **~25 files** | **~4 hours coding** |

After I generate all files, you'll:
1. Push to a GitHub repo
2. SSH into Node 1, `git clone`, run `scripts/setup-node1.sh`
3. Set up Nodes 2/3 for Ceph
4. Run `scripts/setup-ceph-cluster.sh`
5. Import n8n workflows
6. Run `scripts/demo.sh` to verify
7. 🎉 Demo ready

---

## User Review Required

> [!IMPORTANT]
> **Approve this plan** and I'll generate all ~25 files with complete, working code. Every bug from the analysis is pre-fixed. You'll have a `git push` → `docker compose up` deployment path.

> [!WARNING]
> **One architecture decision:** The current plan runs ALL services on Node 1 (t3.large, 8GB RAM). The inference container alone needs ~2GB. With Redis, PostgreSQL, n8n, Mosquitto, Prometheus, Grafana, Nginx, and 3 FastAPI services — 8GB is tight. If you experience OOM issues during the demo:
> - Option A: Upgrade Node 1 to t3.xlarge (16GB) — costs ~$3 more/week
> - Option B: Move Prometheus + Grafana to Node 2 or Node 3
> - I'll optimize container memory limits in the compose file to stay under 8GB, but flagging this as a risk.
