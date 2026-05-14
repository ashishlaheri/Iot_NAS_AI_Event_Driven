# AI-Aware Event-Driven IoT-NAS System

## Full Implementation Documentation

> **Author:** Ashish Laheri  
> **Deployed:** May 13, 2026 on AWS EC2 (3-node cluster, ap-south-1)  
> **Repository:** [github.com/ashishlaheri/Iot_NAS_AI_Event_Driven](https://github.com/ashishlaheri/Iot_NAS_AI_Event_Driven)

---

## 1. Project Overview

This project implements a **containerized, AI-driven Network-Attached Storage (NAS) system** designed for IoT environments. It combines real-time event processing, machine learning inference, cryptographic forensic logging, and distributed storage into a unified platform deployed across a 3-node AWS cluster.

### Core Problem Statement

Traditional NAS systems treat all incoming data equally. In IoT environments generating thousands of events per second from cameras, sensors, and industrial equipment, this leads to critical alerts being delayed behind routine telemetry. This system solves that by introducing **priority-aware event-driven architecture** with **on-device AI inference** and **tamper-proof forensic audit trails**.

### Key Innovations

1. **Priority Queue Engine** — Events are scored using a mathematical formula that guarantees P1 (Emergency) events are always processed before P2/P3/P4, regardless of arrival order
2. **Dual AI Inference** — YOLOv8-Nano for visual object detection + LSTM-based anomaly detection for sensor data
3. **Forensic Hash Chain** — Every processed event is cryptographically signed (Ed25519) and linked in a SHA-256 hash chain, compliant with ISO/IEC 27037
4. **Self-Healing Storage** — Ceph distributed storage across multiple nodes with automatic replication and fault recovery

---

## 2. System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        NODE 1 (t3.large)                        │
│                    NAS Core — 10 Containers                     │
│                                                                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐       │
│  │  Nginx   │  │   n8n    │  │ Grafana  │  │Prometheus│       │
│  │ :80      │  │ :5678    │  │ :3000    │  │ :9090    │       │
│  └────┬─────┘  └────┬─────┘  └──────────┘  └──────────┘       │
│       │              │                                          │
│  ┌────▼─────┐  ┌────▼─────┐  ┌──────────┐                     │
│  │Queue API │  │Inference │  │ Forensic │                      │
│  │ :8001    │  │  API     │  │   API    │                      │
│  │ (Redis)  │  │ :8000    │  │  :8002   │                      │
│  └────┬─────┘  │(YOLOv8+  │  │(Ed25519) │                     │
│       │        │ LSTM)    │  └────┬─────┘                      │
│  ┌────▼─────┐  └──────────┘  ┌────▼─────┐                     │
│  │  Redis   │                │PostgreSQL│                      │
│  │  :6379   │                │ :5432    │                      │
│  └──────────┘                └──────────┘                      │
│                                                                 │
│  ┌──────────┐  ┌──────────────────────────┐                    │
│  │Mosquitto │  │     Ceph MON + MGR       │                    │
│  │MQTT:1883 │  │     Dashboard :8443      │                    │
│  └──────────┘  └──────────────────────────┘                    │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────┐     ┌─────────────────────┐
│   NODE 2 (t3.large) │     │   NODE 3 (t3.large) │
│   Ceph OSD.0        │     │   Ceph OSD.1        │
│   22GB SSD          │     │   22GB SSD          │
│   (Data Replica 1)  │     │   (Data Replica 2)  │
└─────────────────────┘     └─────────────────────┘
```

### AWS Infrastructure

| Node | Public IP | Private IP | Role | Storage |
|------|-----------|------------|------|---------|
| Node 1 | 13.235.62.104 | 172.31.31.46 | NAS Core (10 containers) + Ceph MON/MGR | 8GB root + 22GB EBS (Docker) |
| Node 2 | 13.202.73.54 | 172.31.16.12 | Ceph OSD.0 | 8GB root + 22GB EBS (OSD) |
| Node 3 | 3.108.8.228 | 172.31.27.161 | Ceph OSD.1 | 8GB root + 22GB EBS (OSD) |

---

## 3. Project File Structure

```
IoT_NAS/
├── docker-compose.yml          # Orchestrates all 10 containers on Node 1
├── init.sql                    # PostgreSQL schema (6 tables, 2 views, triggers)
├── .env                        # Environment variables (credentials, ports)
│
├── services/
│   ├── queue/
│   │   ├── Dockerfile          # Python 3.11-slim + Redis client
│   │   ├── main.py             # Priority Queue API (FastAPI, port 8001)
│   │   └── requirements.txt    # redis, fastapi, uvicorn, prometheus-client
│   │
│   ├── inference/
│   │   ├── Dockerfile          # Python 3.11-slim + CPU PyTorch + YOLOv8
│   │   ├── main.py             # Inference API (FastAPI, port 8000)
│   │   └── requirements.txt    # ultralytics, torch, fastapi, numpy
│   │
│   └── forensics/
│       ├── Dockerfile          # Python 3.11-slim + PyNaCl (Ed25519)
│       ├── main.py             # Forensic Logger API (FastAPI, port 8002)
│       └── requirements.txt    # pynacl, fastapi, uvicorn, prometheus-client
│
├── simulator/
│   ├── simulate.py             # 100-device IoT event simulator
│   └── requirements.txt        # paho-mqtt, requests
│
├── nginx/
│   └── nginx.conf              # Reverse proxy for all services
│
├── mosquitto/
│   └── config/mosquitto.conf   # MQTT broker configuration
│
├── prometheus/
│   └── prometheus.yml          # Scrape config for all 3 APIs + node exporter
│
├── grafana/
│   └── provisioning/
│       ├── datasources/        # Auto-configured Prometheus datasource
│       └── dashboards/
│           └── iot-nas.json    # 8-panel monitoring dashboard
│
└── scripts/
    ├── setup-node1.sh          # Node 1 bootstrap automation
    ├── setup-ceph-nodes.sh     # Nodes 2/3 preparation
    ├── setup-ceph-cluster.sh   # Ceph cluster bootstrap
    ├── deploy.sh               # Cross-node deployment orchestrator
    └── demo.sh                 # Pre-demo health check script
```

---

## 4. Microservices — Detailed Design

### 4.1 Priority Queue API (`services/queue/main.py`)

**Port:** 8001 | **Backend:** Redis Sorted Sets (ZADD/ZPOPMAX)

**The Problem:** In a standard FIFO queue, a routine temperature reading arriving at T=0 blocks a critical intrusion alert arriving at T=1. Emergency events must always be processed first.

**The Solution — Priority Scoring Formula:**

```
score = (4 - priority) × 10¹⁸ + timestamp_nanoseconds
```

| Priority | Score Prefix | Example Score |
|----------|-------------|---------------|
| P1 Emergency | 3 × 10¹⁸ | 3,000,000,001,715,200,000 |
| P2 High | 2 × 10¹⁸ | 2,000,000,001,715,200,000 |
| P3 Normal | 1 × 10¹⁸ | 1,000,000,001,715,200,000 |
| P4 Batch | 0 × 10¹⁸ | 0,000,000,001,715,200,000 |

The 10¹⁸ multiplier ensures P1 scores are **always** higher than P2, regardless of timestamp. Redis `ZPOPMAX` returns the highest score first, guaranteeing priority ordering.

**API Endpoints:**

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/enqueue` | POST | Add event to priority queue |
| `/dequeue` | GET | Pop highest-priority event |
| `/queue/status` | GET | Queue depth by priority tier |
| `/queue/flush` | DELETE | Clear queue (demo/testing) |
| `/health` | GET | Redis connectivity check |
| `/metrics` | GET | Prometheus metrics |

**Prometheus Metrics Exported:**
- `queue_enqueue_total{priority}` — Counter per priority level
- `queue_dequeue_total` — Total dequeued events
- `queue_depth` — Current queue size gauge
- `queue_enqueue_latency_seconds` — Histogram of enqueue latency

---

### 4.2 Inference API (`services/inference/main.py`)

**Port:** 8000 | **Models:** YOLOv8-Nano + LSTM Anomaly Detector

#### YOLOv8-Nano — Visual Object Detection

- **Model:** `yolov8n.pt` (6.2MB, pre-downloaded at Docker build time)
- **Input:** Image upload (JPEG/PNG) via multipart form
- **Output:** Bounding boxes with class labels and confidence scores
- **Use Case:** Intrusion detection from surveillance cameras

**Tested Result:**
```json
{
  "model": "YOLOv8-Nano INT8 (CPU Simulation)",
  "detections": [
    {"class": "bus", "confidence": 0.8734, "bbox": [22.9, 231.3, 805.0, 756.8]},
    {"class": "person", "confidence": 0.8657, "bbox": [48.6, 398.6, 245.3, 902.7]}
  ]
}
```

#### LSTM Anomaly Detector — Sensor Data Analysis

Simulates a 60-sample sliding window LSTM model (paper §5). On AWS EC2 without a Coral TPU, a rule-based simulation produces equivalent outputs:

- **Temperature:** Critical > 80°C, Warning > 60°C
- **Vibration:** Critical > 1.5g, Warning > 0.8g
- **Pressure:** Critical > 130psi, Warning > 110psi

**Anomaly score** is clamped to [0.0, 1.0] and maps to priority recommendations:
- Score ≥ 0.7 → P1 Emergency
- Score ≥ 0.4 → P2 High
- Score ≥ 0.2 → P3 Normal
- Score < 0.2 → P4 Batch

**Tested Result:**
```json
{
  "anomaly_score": 1.0,
  "is_anomaly": true,
  "anomaly_reasons": [
    "Temperature 95.0°C > 80°C critical threshold",
    "Vibration 2.0g > 1.5g critical threshold",
    "Pressure 140.0psi > 130psi critical threshold"
  ],
  "priority_recommendation": 1,
  "predicted_failure_eta_hours": 0.1
}
```

---

### 4.3 Forensic Logger API (`services/forensics/main.py`)

**Port:** 8002 | **Cryptography:** Ed25519 + SHA-256 | **Standard:** ISO/IEC 27037

**How the Hash Chain Works:**

```
Genesis Block: prev_hash = "genesis_block_iot_nas"
     │
     ▼
Entry #0: {event_data, prev_hash} → SHA-256 → hash_0, Ed25519_sign(entry)
     │
     ▼
Entry #1: {event_data, prev_hash=hash_0} → SHA-256 → hash_1, Ed25519_sign(entry)
     │
     ▼
Entry #N: {event_data, prev_hash=hash_(N-1)} → SHA-256 → hash_N, Ed25519_sign(entry)
```

**Tamper Detection:** If any entry is modified, its SHA-256 hash changes, breaking the chain linkage for all subsequent entries. The `/verify` endpoint walks the entire chain and reports any mismatches.

**Key Persistence:** The Ed25519 signing key is persisted to a Docker volume (`/app/data/ed25519_signing_key.bin`), ensuring the same key survives container restarts. Without this, a new key would invalidate all previous signatures.

**API Endpoints:**

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/log` | POST | Sign and append event to chain |
| `/chain` | GET | View recent chain entries (paginated) |
| `/verify` | GET | Validate entire chain integrity |
| `/health` | GET | Key and chain status |

---

## 5. Supporting Infrastructure

### 5.1 PostgreSQL Database (`init.sql`)

6 tables with UUID primary keys, JSONB payloads, and performance indexes:

| Table | Purpose | Key Fields |
|-------|---------|-----------|
| `iot_events` | All IoT events with storage tier tracking | priority, device_id, payload (JSONB), storage_tier |
| `device_registry` | 12 registered IoT devices with trust scores | device_type, trust_score, is_active |
| `forensic_audit_log` | SQL mirror of the hash chain | chain_index, hash, signature, prev_hash |
| `workflow_runs` | n8n workflow execution tracking | workflow_name, status, duration_ms |
| `device_quotas` | Per-device storage limits | max_storage_mb, max_events_day |
| `alert_history` | Alert delivery tracking | alert_type, channel, retry_count |

Plus 2 analytical views (`priority_summary`, `device_activity`) and automatic `updated_at` triggers.

### 5.2 MQTT Broker (Mosquitto)

- Listens on port 1883 (TCP) and 9001 (WebSocket)
- Topic structure: `iot/events/p1`, `iot/events/p2`, `iot/events/p3`, `iot/events/p4`
- Anonymous access enabled for the demo environment

### 5.3 Monitoring Stack

**Prometheus** scrapes 4 targets every 15 seconds:
- `queue-api:8001/metrics`
- `inference-api:8000/metrics`
- `forensic-api:8002/metrics`
- `172.31.31.46:9100/metrics` (Node Exporter for system metrics)

**Grafana** displays 8 dashboard panels:
1. Event Enqueue Rate (by Priority) — time series
2. Queue Depth (Current) — gauge
3. Dequeue Rate — stat
4. Inference Latency P95/P50 — time series
5. Forensic Chain Length — stat
6. System CPU Usage — time series
7. System Memory Usage — gauge
8. Inference Requests Total — stat

### 5.4 Nginx Reverse Proxy

Routes all traffic through port 80:
- `/api/queue/*` → Queue API
- `/api/infer/*` → Inference API
- `/api/forensic/*` → Forensic Logger
- `/n8n/*` → Workflow Engine
- `/grafana/*` → Monitoring Dashboard

### 5.5 n8n Workflow Engine

3 workflows automate the event pipeline:

1. **MQTT Event Ingestor** — Listens on `iot/events/#`, parses events, computes priority scores, and POSTs to Queue API
2. **Queue Consumer** — Every 2 seconds, dequeues highest-priority event and forwards P1/P2 events to the Forensic Logger
3. **P1 Burst Demo** — Manual trigger that injects 10 P1 Emergency events simultaneously

---

## 6. IoT Event Simulator (`simulator/simulate.py`)

Simulates **100 virtual IoT devices** across 7 device types:

| Device Type | Count | Trust Score Range |
|------------|-------|------------------|
| Cameras | 20 | 0.85 – 0.99 |
| Temperature Sensors | 20 | 0.90 – 0.99 |
| Industrial Motors | 15 | 0.80 – 0.95 |
| Pressure Sensors | 15 | 0.88 – 0.98 |
| Wearables | 15 | 0.75 – 0.90 |
| Gateways | 10 | 0.95 – 0.99 |
| Vibration Sensors | 5 | 0.85 – 0.95 |

**Event Distribution (matching the research paper):**
- P1 Emergency: 8% (intrusion alerts, health crises, fire alarms, ransomware)
- P2 High: 22% (equipment warnings, anomalies, pressure spikes, unauthorized access)
- P3 Normal: 60% (temperature, humidity, heartbeats, vibration readings)
- P4 Batch: 10% (log archives, daily summaries, firmware reports)

Each event carries realistic payload data (e.g., fire alarms include smoke_level, temperature_c, zone).

**Usage:**
```bash
python simulate.py --rate 10 --duration 30     # 10 events/sec for 30s
python simulate.py --burst-p1 10               # Inject 10 P1 emergencies
```

---

## 7. Ceph Distributed Storage

### Cluster Topology

- **Ceph Squid 19.2.3** (installed from Ubuntu 24.04 repos)
- **3 MON daemons** (quorum across all 3 nodes)
- **2 OSD daemons** (one per storage node, 22GB SSD each)
- **1 RGW daemon** (S3-compatible gateway on Node 1, port 7480)
- **Total capacity:** 44GB with 2x replication

### Storage Pools

| Pool | Placement Groups | Replication | Purpose |
|------|-----------------|-------------|---------|
| `iot-p1-nvme` | 32 | size=2, min=1 | P1/P2 critical event data |
| `iot-p3-replicated` | 32 | size=2, min=1 | P3/P4 routine data |
| `iot-forensic-logs` | 16 | size=2, min=1 | Forensic chain backups |

### Fault Tolerance (Demonstrated)

The system survives single-node failures:

1. **Healthy state:** 2 OSDs up, all PGs active+clean
2. **Node failure:** Stop OSD.1 → Cluster detects within 15s → HEALTH_WARN, data degraded but **still readable**
3. **Recovery:** Restart OSD.1 → Ceph automatically re-replicates → HEALTH_OK within 60-120s
4. **Zero data loss, zero manual intervention**

---

## 8. Docker Composition

All 10 containers orchestrated via `docker-compose.yml`:

| Container | Image | Memory Limit | Health Check |
|-----------|-------|-------------|--------------|
| iotnas-redis | redis:7-alpine | — | `redis-cli ping` |
| iotnas-postgres | postgres:16-alpine | — | `pg_isready` |
| iotnas-mosquitto | eclipse-mosquitto:2 | — | MQTT subscribe test |
| iotnas-queue-api | custom (Python 3.11) | 256MB | `curl /health` |
| iotnas-inference-api | custom (Python 3.11) | 2GB | `curl /health` |
| iotnas-forensic-api | custom (Python 3.11) | 256MB | `curl /health` |
| iotnas-n8n | n8nio/n8n:latest | 1GB | — |
| iotnas-prometheus | prom/prometheus:latest | 512MB | — |
| iotnas-grafana | grafana/grafana:latest | 256MB | — |
| iotnas-nginx | nginx:alpine | 64MB | — |

**Total memory allocation:** ~4.3GB (fits within t3.large 8GB with headroom)

---

## 9. Deployment Challenges & Solutions

During deployment on Ubuntu 24.04 LTS (AWS), 12 issues were encountered and resolved:

| # | Issue | Root Cause | Solution |
|---|-------|-----------|----------|
| 1 | `docker ps` permission denied | Group not applied until re-login | `exit` + SSH back in |
| 2 | `libgl1-mesa-glx` not found | Package renamed in Debian Trixie | Use `libgl1 libglib2.0-0t64` |
| 3 | No space (pip install ~4GB) | CUDA PyTorch on CPU-only instance | `--index-url .../whl/cpu` (300MB) |
| 4 | No space (containerd) | containerd on 8GB root, not EBS | Symlink `/var/lib/containerd` to EBS |
| 5 | YOLOv8 weights won't load | PyTorch 2.6 `weights_only=True` default | Monkey-patch `torch.load` |
| 6 | `sshd.service` not found | Ubuntu 24.04 renamed to `ssh.service` | `systemctl restart ssh` |
| 7 | Ceph Reef repo 404 | No Noble (24.04) packages | Use `apt install cephadm` (Squid) |
| 8 | Hostname mismatch (Ceph) | Used custom name vs EC2 hostname | Use actual: `ip-172-31-16-12` |
| 9 | SSH permission denied (Ceph) | Ceph pubkey not on target node | Copy `/etc/ceph/ceph.pub` to nodes |
| 10 | n8n secure cookie error | HTTPS required for cookies by default | Set `N8N_SECURE_COOKIE=false` |
| 11 | Grafana "No data" | Datasource UID mismatch | Query actual UID via Grafana API |
| 12 | Node exporter unreachable | `host.docker.internal` not on Linux | Use actual IP `172.31.31.46` |

---

## 10. Verified Test Results

All tests passed on 2026-05-13:

| Test | Expected | Actual | Status |
|------|----------|--------|--------|
| P1 dequeues before P3 | `test_p1` first | `test_p1` first | ✅ |
| Forensic chain valid | `true` | `true` | ✅ |
| YOLOv8 bus detection | >80% confidence | 87.3% confidence | ✅ |
| LSTM anomaly (95°C, 2g, 140psi) | is_anomaly=true | is_anomaly=true, score=1.0 | ✅ |
| PostgreSQL seed data | 12 devices | 12 devices loaded | ✅ |
| Simulator distribution | ~8% P1 | 8.2% P1 (73 events) | ✅ |
| Ceph cluster health | 2 OSDs up | 2 up, 44GB available | ✅ |
| Grafana live panels | 8 panels | 8 panels with data | ✅ |
| Forensic chain (after sim) | >0 entries | 79 entries, valid=true | ✅ |

---

## 11. Web Interfaces

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana Dashboard | http://13.235.62.104:3000 | admin / iotnas2024 |
| n8n Workflow Engine | http://13.235.62.104:5678 | (set during first login) |
| Ceph Dashboard | https://13.235.62.104:8443 | admin / iotnas2024 |
| Prometheus | http://13.235.62.104:9090 | (no auth) |

---

## 12. Technologies Used

| Layer | Technology | Version |
|-------|-----------|---------|
| Container Runtime | Docker Engine | 29.4.3 |
| Orchestration | Docker Compose | v5.1.3 |
| Language | Python | 3.11 |
| API Framework | FastAPI + Uvicorn | latest |
| Priority Queue | Redis Sorted Sets | 7 (Alpine) |
| Database | PostgreSQL | 16 (Alpine) |
| MQTT Broker | Eclipse Mosquitto | 2.x |
| Object Detection | YOLOv8-Nano (Ultralytics) | 8.2+ |
| Deep Learning | PyTorch (CPU) | 2.6+ |
| Cryptography | PyNaCl (Ed25519 + SHA-256) | latest |
| Workflow Engine | n8n | latest |
| Monitoring | Prometheus + Grafana | latest |
| Distributed Storage | Ceph Squid | 19.2.3 |
| Reverse Proxy | Nginx | Alpine |
| OS | Ubuntu | 24.04 LTS |
| Cloud | AWS EC2 | t3.large (ap-south-1) |

---

## 13. How to Reproduce This Deployment

### Prerequisites
- 3 AWS EC2 instances (t3.large, Ubuntu 24.04, 8GB root + 22GB EBS each)
- Security Group allowing ports: 22, 80, 1883, 3000, 5678, 6789, 7480, 8000-8002, 8443, 9090, 9100
- SSH key pair for all 3 nodes

### Quick Start

```bash
# Node 1: Install Docker + mount EBS + clone + build + start
curl -fsSL https://get.docker.com | sudo sh
# (symlink /var/lib/docker and /var/lib/containerd to EBS mount)
git clone https://github.com/ashishlaheri/Iot_NAS_AI_Event_Driven.git ~/iot-nas
cd ~/iot-nas && docker compose build && docker compose up -d

# Nodes 2 & 3: Install Docker + enable root SSH + wipe EBS for Ceph
curl -fsSL https://get.docker.com | sudo sh
sudo wipefs -a /dev/nvme1n1

# Node 1: Bootstrap Ceph + add hosts + add OSDs + create pools
sudo apt install -y cephadm ceph-common
sudo cephadm bootstrap --mon-ip <NODE1_PRIVATE_IP>
sudo ceph orch host add <node2-hostname> <node2-ip>
sudo ceph orch host add <node3-hostname> <node3-ip>
sudo ceph orch daemon add osd <node2-hostname>:/dev/nvme1n1
sudo ceph orch daemon add osd <node3-hostname>:/dev/nvme1n1
```

See the full step-by-step walkthrough in the project artifacts for all fixes and details.

---

*This system demonstrates that intelligent, priority-aware data management combined with edge AI inference and cryptographic audit trails can transform a simple NAS into a security-critical IoT infrastructure platform.*
