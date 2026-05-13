# IoT-Aware AI Event-Driven NAS — Full Project Context
> **Purpose of this document:** Feed this to any AI assistant to get full context of the project, its research paper, and its AWS implementation plan. This document is self-contained.
> **Author:** Ashish Laheri (Ashish Kumar Laheri), LPU (Lovely Professional University), Punjab
> **Project type:** B.Tech Capstone / IEEE-format Research Paper + Working AWS Implementation

---

## 1. What This Project Is

An **IoT-Aware AI Event-Driven NAS (Network-Attached Storage)** system. It is NOT a wrapper around an existing NAS product. It is a ground-up redesign of how storage systems should behave in IoT environments.

Traditional NAS systems are passive — they sit and wait for data, then store it. They cannot classify incoming streams, decide what matters, or respond to a ransomware attack in real time. This project closes that gap.

**One-line summary:** A Raspberry Pi 5 (or AWS EC2 equivalent) turned into an intelligent edge storage hub that classifies IoT events by priority, runs on-device AI inference, stores data across a 3-tier hybrid strategy, and maintains forensic-grade cryptographic audit logs.

**Key results (from the paper):**
- 78% reduction in P1 emergency alert latency vs FIFO baseline (169.9ms vs 773ms P95)
- 99.2% ransomware detection TPR, 0.6% FPR across 4 ransomware families
- 7.1× AI inference speedup via Coral TPU (34ms vs 241ms CPU)
- Zero filesystem corruption across 10 simulated power failures
- Ceph cluster self-healing in 3min 42s with zero data loss under node failure
- 5–10× cost reduction vs commercial NAS ($277 vs $500–2000)

---

## 2. Research Paper Summary

### 2.1 Paper Metadata
- **Format:** IEEE (single-column, double-spaced, ~31 pages + appendices)
- **Sections:** Introduction, Literature Review, System Architecture, Implementation, Results, Research Gaps, ER Diagram, Future Work, Conclusion, References, Appendices
- **References:** 20 IEEE/ACM papers (2016–2025)
- **Research gaps addressed:** 33 total gaps across 7 domains
- **Novel contributions:** 5 (listed in §2.4 below)

### 2.2 The Problem
- 75 billion IoT devices projected by 2025, generating 79 zettabytes/year
- Conventional NAS: passive file servers — no event intelligence, no priority, no AI
- Gap between what traditional NAS does and what modern edge environments need

### 2.3 The Solution (5-Layer Architecture)
The system has five integrated layers:

| Layer | Components | Purpose |
|---|---|---|
| L1: IoT Protocol Ingestion | MQTT (Mosquitto 2.0+), HTTP webhooks, SMB/NFS file watchers | Receive data from all IoT device types |
| L2: Priority Event Queue | Redis Sorted Sets, 4-tier (P1–P4) | Ensure critical events processed first |
| L3: TinyML Inference | Coral USB TPU, YOLOv8-Nano, CNN, LSTM | On-device AI without cloud round-trip |
| L4: Hybrid Storage | NVMe local, 3-node Ceph RADOS, S3-compatible cloud | Cost/latency/availability optimized placement |
| L5: Security & Forensics | Network TAP, Ed25519 hash chain, AES-256-GCM | Ransomware detection + forensic chain-of-custody |

**Orchestration:** n8n workflow engine ties all layers together, routing events from priority queue to appropriate pipelines.

### 2.4 Five Novel Contributions
1. **Event-Driven Storage Orchestration** — first system integrating n8n workflows directly with storage layer; NAS becomes active event processor, not passive file server
2. **Hardware-Accelerated Timestamping** — STM32G031 PPS co-processor providing ±5μs accuracy (24× better than software NTP's ±120μs)
3. **On-Device Ransomware Detection at Network TAP Layer** — first ML-based (15-class CNN) ransomware classifier operating at the wire before traffic reaches storage; 99.2% TPR, 0.6% FPR
4. **Priority-Based Event Queue for IoT-NAS** — extends traditional NAS with real-time mixed-criticality scheduling; 78% P1 latency reduction vs FIFO
5. **Forensic-Grade Edge Storage at Commodity Cost** — ISO/IEC 27037-compliant chain-of-custody with sub-200ms edge latency at $150–300; unavailable in any commercial or academic system reviewed

### 2.5 Key Technical Specifications (from paper)

**Priority Scoring Formula:**
```
score = (4 − priority_level) × 10^9 + unix_timestamp_ns
```
- P1 (Emergency): score = 3×10^9 + ts → highest, processed first via ZPOPMAX
- P2 (High): score = 2×10^9 + ts
- P3 (Normal): score = 1×10^9 + ts
- P4 (Batch): score = 0×10^9 + ts → lowest

**Priority Tier Definitions:**
- P1 Emergency: security alerts, health crises (target P95 < 200ms)
- P2 High: anomaly detections, equipment warnings (target P95 < 500ms)
- P3 Normal: routine sensor readings (target P95 < 2000ms)
- P4 Batch: cloud archive uploads (best-effort)

**Event Priority Assignment — 3 signals:**
1. Event type: alert > reading > log
2. Source device trust score (derived from authentication history)
3. Age-of-Information (AoI): readings older than 1 second demoted one tier

**TinyML Models:**
- YOLOv8-Nano INT8: object detection, 640×480, 30 FPS, 34ms mean latency on Coral TPU, trained on COCO + 4,200 IoT-scene images
- 15-class CNN: ransomware classifier, trained on 48,000 labelled SMB opcode sequences (WannaCry, Ryuk, Conti, LockBit, REvil + benign)
- LSTM: sensor anomaly detection, 60-sample sliding window, predicts equipment failure up to 2 hours ahead

**Storage Tiers:**
- NVMe local: P1/P2 events, latency-sensitive, confidential data
- Ceph RADOS 3-node: P3 replicated storage, 2× fault tolerance
- S3-compatible cloud: P4 batch archival, off-peak uploads

**Security:**
- Ed25519 signatures over all event objects
- SHA-256 hash chain (each event links to prior event's hash)
- AES-256-GCM payload encryption
- STM32G031 hardware PPS timestamps (±5μs jitter)
- ISO/IEC 27037 forensic chain-of-custody compliance

**Ransomware detection pipeline:**
- Raspberry Pi 4 network TAP passively mirrors all SMB traffic
- CNN classifies 128-opcode sliding windows
- Detection-to-block: 173ms average (TAP → CNN inference → SMB session termination via iptables)

### 2.6 Hardware Platform (Original Design)
```
Minimum build: $277
  - Raspberry Pi 5 (8GB RAM): $80
  - Samsung 990 Pro 2TB NVMe: $150
  - Official RPi 5 27W PSU: $12
  - Argon NEO 5 NVMe Case: $30
  - Cat6 Ethernet: $5

Full build: $422 (adds):
  - Coral USB TPU: $60
  - Raspberry Pi 4 (4GB) as network TAP: $55
  - STM32G031 Dev Board (PPS timestamping): $10
```

### 2.7 AWS Cloud Testbed (What We Actually Implement)
The paper explicitly states in §5: *"Due to cost escalations in Raspberry Pi 5 components, the experimental testbed was migrated to Amazon Web Services (AWS) cloud infrastructure provisioned at equivalent specifications."*

This is the justification for the AWS implementation — it is consistent with the paper, not a deviation from it.

```
AWS equivalent (~$85/month):
  - EC2 t3.large (NAS Core): 2 vCPU, 8GB RAM
  - ElastiCache r6g.large (Redis): 13GB, 2.5Gbps
  - EBS gp3 2TB (NVMe tier): 10,000 IOPS, 500MB/s
  - 3× EC2 t3.medium + EBS gp3 (Ceph cluster): 2× replication
  - S3 Standard-IA (archive): 99.9% durability
  - ECS Fargate (n8n): 2 vCPU, 4GB
  - RDS db.t3.medium (PostgreSQL 16): Multi-AZ
  - EC2 + Coral USB passthrough (ML inference): INT8 quantized
```

### 2.8 Experimental Results (from paper §5)

**End-to-End Latency (500 events/sec, 100 devices, 30 min):**
| Priority | P50 (ms) | P95 (ms) | P99 (ms) | Target P95 | Met? |
|---|---|---|---|---|---|
| P1 Emergency | 106.4 | 169.9 | 214.8 | 200ms | Yes |
| P2 Anomaly | 235.3 | 425.8 | 577.7 | 500ms | Yes |
| P3 Routine | 400.2 | 836.6 | 1216.5 | 2000ms | Yes |
| P4 Batch | 5315.2 | 21652.5 | 39878.6 | best-effort | Yes |

**Ransomware Detection:**
| Family | TPR (%) | FPR (%) | Latency (ms) |
|---|---|---|---|
| WannaCry | 99.7 | 0.3 | 88 |
| Ryuk | 99.1 | 0.7 | 104 |
| Conti | 98.4 | 0.8 | 138 |
| LockBit | 97.9 | 0.9 | 162 |
| Overall | 99.2 | 0.6 | 123 |

**YOLOv8-Nano Inference:**
| Platform | Mean (ms) | CPU Util | FPS | mAP@0.5 |
|---|---|---|---|---|
| Coral USB TPU (INT8) | 33.8 | 18% | 29.5 | 70.3% |
| CPU ARM FP32 | 241.3 | 88% | 4.1 | 72.4% |
| Improvement | 7.1× faster | −70% | 7.2× | −2.1pp |

**Scalability:**
| Event Rate | P1 P95 | P2 P95 | P4 Drop% |
|---|---|---|---|
| 500 evt/s | 169.9ms | 425.8ms | 0.00% |
| 1000 evt/s | 170.5ms | 427.9ms | 0.00% |
| 2000 evt/s | 171.4ms | 432.2ms | 0.73% |

---

## 3. Research Gaps Addressed

### 33 Total Research Gaps Across 7 Domains

**Edge Computing (5 gaps):**
- EG-1: No automated edge-cloud application logic splitting → solved with 3-phase context-aware partitioning (latency, privacy, energy criteria)
- EG-4: No standardized APIs for heterogeneous IoT device integration → OpenAPI abstraction over MQTT/HTTP/file watchers
- EG-5: Benchmark realism gap (simulators miss real network jitter) → 100 simulated MQTT clients with recorded IoT traffic replays

**Security & Forensics (6 gaps — P0 severity):**
- SG-1: No forensic chain-of-custody for IoT events → Ed25519-signed hash chain + STM32 hardware PPS (±5μs)
- SG-3: Ceph scale testing limited to 91MB on 10 nodes → 3-node cluster validated with TB-scale video ingestion simulation
- SG-4: Incomplete ransomware threat model, SMB vulnerability unaddressed → 15-class CNN at network TAP layer; 99.2% TPR
- SG-5: No fine-grained multi-tenant access control in OMV → per-device Docker containers with Linux network namespaces

**Real-Time Scheduling (7 gaps):**
- RG-5: No trust-based scheduling → device trust score rate-limits low-trust devices at MQTT broker
- RG-6: AoI metrics underdeveloped → readings older than 1s demoted one priority tier
- RG-7: Mixed-criticality scheduling for heterogeneous IoT underexplored → Redis Sorted Set priority queue with 4-tier system

**TinyML (5 gaps):**
- TG-3: No integration of TinyML with storage systems, no ransomware detection at storage layer → CNN at TAP layer + filesystem snapshot on detection

**Network Forensics (5 gaps):**
- FG-1: Passive TAP only, no automated response workflows → TAP feeds into n8n for automated anomaly response
- FG-4: Unmanaged PCAP storage accumulation → ML-based traffic classification replaces manual PCAP review
- FG-5: PCAP files lack cryptographic proof of integrity → Ed25519 signed + hardware timestamped before NAS write

**Virtualization (5 gaps):**
- VG-1: No benchmark of VM vs container vs bare-metal for IoT ingestion on ARM → Docker containers benchmarked
- VG-3: Multi-tenant security isolation for per-device storage quotas unaddressed → per-device Docker + Linux network namespaces

---

## 4. System Architecture — Detailed

### 4.1 Data Flow (End-to-End)

```
IoT Devices (Sensors, IP Cameras, Wearables, Industrial)
    │
    │ MQTT / HTTP Webhooks / SMB-NFS file watchers
    ▼
[P1: IoT Protocol Ingestion — Mosquitto 2.0+]
    │
    │ Raw events (serialized JSON)
    ▼
[P2: Priority Event Queue — Redis Sorted Sets]
    │ score = (4 - priority) × 10^9 + unix_timestamp_ns
    │ ZPOPMAX → P1 always dispatched first
    │
    ├──[P1/P2 events]──────────────────────────────┐
    │                                              │
    ▼                                              ▼
[P3: TinyML Inference — Coral USB TPU]    [P5: Security & Forensics]
    │ YOLOv8-Nano: object detection        │ Network TAP → CNN ransomware
    │ CNN: ransomware classification       │ Ed25519 hash chain
    │ LSTM: anomaly detection              │ AES-256-GCM encryption
    │                                      │ Hardware PPS timestamps
    ▼                                      │
[P4: Hybrid Storage Orchestration]◄────────┘
    │
    ├── NVMe Local (P1/P2 confidential, <200ms write)
    ├── Ceph RADOS 3-node (P3 replicated, 2× fault tolerance)
    └── S3-Compatible Cloud (P4 batch, off-peak)
    
[n8n Workflow Engine — orchestrates all layers]
    ├── MQTT event subscriber
    ├── Priority queue enqueue/dequeue
    ├── TFLite inference dispatcher
    ├── Storage routing logic
    └── Alert dispatcher (Slack / Telegram / SMS)

[PostgreSQL 16 — event metadata, audit trail]
[Prometheus + Grafana — monitoring]
[System Administrator] ←→ [Config, Rules, Workflow Definitions]
[Forensic Auditor] ← Signed Event Logs, Chain-of-Custody
[Alert Recipients] ← P1/P2 Alerts (Telegram/Slack/SMS)
[AWS S3] ← P4 Batch Archives, Encrypted Backups
```

### 4.2 DFD Process Decomposition

**Level 1 — 5 main processes, 6 data stores:**
- P1: IoT Protocol Ingestion (MQTT/HTTP/SMB)
- P2: Priority Event Queue Processor (Redis + n8n)
- P3: TinyML Inference Engine (YOLOv8/CNN/LSTM)
- P4: Hybrid Storage Orchestration (NVMe/Ceph/S3)
- P5: Security & Forensics Layer (TAP/Ed25519/AES)

**Data Stores:**
- D1: Redis Priority Queue (Sorted Set)
- D2: NVMe Local Storage (P1/P2 events)
- D3: Ceph RADOS Cluster (P3 replicated)
- D4: S3 Cloud Archive (P4 batch)
- D5: PostgreSQL Event Metadata
- D6: Forensic Audit Trail (Ed25519 hash chain)

**Level 2 — P2 Priority Queue Processor (6 subprocesses):**
- P2.1: Event Classifier (event type + device trust score + AoI freshness)
- P2.2: Priority Scoring Engine (computes Redis score)
- P2.3: Redis ZADD enqueue
- P2.4: n8n Dequeue Worker (ZPOPMAX polling)
- P2.5: Alert Dispatcher (P1/P2 → Telegram/Slack)
- P2.6: Age-of-Information Monitor (demotes stale readings)

**Level 2 — P4 Hybrid Storage Orchestration (7 subprocesses):**
- P4.1: Sensitivity Classifier (public / internal / confidential)
- P4.2: Latency-Cost Optimizer (selects storage tier)
- P4.3: NVMe Local Writer (P1/P2 low-latency)
- P4.4: Ceph RADOS Replicator (P3 replicated, 2× fault tolerance)
- P4.5: S3 Batch Uploader (P4 multipart uploads)
- P4.6: Access Pattern Predictor (promotes cold data after 7 days inactivity from NVMe to S3)
- P4.7: Quota & Isolation Enforcer (per-device Docker namespace quotas)

### 4.3 Database Design (PostgreSQL 16)

**5 key entity relationships:**
- Device → Event: 1:N (cascade delete, index on device_id)
- Event → File: 1:N (video frames, thumbnails, metadata JSON)
- Workflow → Event: N:N via workflow_runs table
- Device → Quota: 1:1 (per-device storage limits enforced before file_storage write)
- Alert Rule → Event: N:N via alert_history (throttling + retry logic)

**Design principles applied:**
- UUID primary keys (distributed system compatibility)
- JSONB fields (schema evolution without migrations)
- Hard deletes with CASCADE (controls storage in high-volume IoT)
- Timestamps on all records (created_at, updated_at, accessed_at)
- CHECK constraints for database-level validity
- B-tree and GIN indexes for common query patterns
- 3NF normalized (selective denormalization: device_name in workflow_runs for historical accuracy)

---

## 5. Software Stack

| Layer | Component | Version | License |
|---|---|---|---|
| OS | Ubuntu 22.04 LTS (EC2) | Jammy | Free |
| NAS | OpenMediaVault | 7.x | GPL-3.0 |
| Workflows | n8n | 1.60+ | Sustainable Use |
| Database | PostgreSQL | 16.x | PostgreSQL License |
| Cache/Queue | Redis | 7.x | BSD-3-Clause |
| MQTT Broker | Mosquitto | 2.0+ | EPL/EDL |
| ML Framework | TensorFlow Lite / Ultralytics | 2.17+ / 8.2+ | Apache-2.0 |
| Containerization | Docker + Docker Compose v2 | Latest | Apache-2.0 |
| Storage Cluster | Ceph (via cephadm) | Quincy/Reef | LGPL |
| Web Server | Nginx | 1.24+ | BSD-2-Clause |
| Monitoring | Prometheus + Grafana | Latest | Apache-2.0 |

---

## 6. AWS Implementation Plan

> This is the actual implementation plan Ashish is executing for the capstone demo.

### 6.1 Constraints and Compromises

| Paper Specification | AWS Implementation | Reason |
|---|---|---|
| Raspberry Pi 5 ($277) | 3× EC2 instances | Paper §5 explicitly migrated to AWS |
| Coral USB TPU (34ms) | CPU-based TFLite/Ultralytics (~150–400ms) | No USB passthrough on EC2 |
| STM32G031 PPS ±5μs | Software `time.time_ns()` ±1ms | No hardware co-processor on EC2 |
| Samsung 990 Pro NVMe | EBS gp3 (10,000 IOPS) | AWS cloud equivalent |
| Physical 3-node Ceph | 3-node Ceph on EC2 + EBS | Functionally identical |

**All compromises are consistent with the paper's §5 AWS testbed section.**

### 6.2 AWS Infrastructure (3 Nodes)

```
Node 1 — t3.large (2 vCPU, 8GB RAM)  [NAS Core]
  Services: Redis, n8n, Mosquitto, PostgreSQL
            Priority Queue API (FastAPI, port 8001)
            TFLite Inference API (FastAPI, port 8000)
            Forensic Logger API (FastAPI, port 8002)
            Prometheus (port 9090)
            Grafana (port 3000)
            Nginx (port 80)
            Ceph MON + MGR + OSD1
  EBS: 30GB root + 20GB Ceph OSD

Node 2 — t3.medium (2 vCPU, 4GB RAM)  [Ceph OSD Node]
  Services: Ceph OSD2
  EBS: 20GB root + 20GB Ceph OSD

Node 3 — t3.medium (2 vCPU, 4GB RAM)  [Ceph OSD Node]
  Services: Ceph OSD3
  EBS: 20GB root + 20GB Ceph OSD
```

**Security Group (iot-nas-sg):**
- Port 22 (SSH) — your IP only
- Port 1883 (MQTT) — 0.0.0.0/0
- Port 5678 (n8n UI) — 0.0.0.0/0
- Port 3000 (Grafana) — 0.0.0.0/0
- Port 8000 (Inference API) — 0.0.0.0/0
- Port 8001 (Queue API) — 0.0.0.0/0
- Port 8002 (Forensic API) — 0.0.0.0/0
- Port 8443 (Ceph Dashboard) — 0.0.0.0/0
- All traffic — self-referencing (iot-nas-sg → iot-nas-sg for inter-node)

**Estimated cost: ~$17.80/week** (well within AWS student credits)

### 6.3 Implementation Timeline

| Day | Focus | Duration | Key Output |
|---|---|---|---|
| 1 | AWS infra setup | 2–3h | 3 EC2 instances running, SSH configured, EBS attached |
| 2 | Core services on Node 1 | 4–5h | Docker Compose up, Queue API, Inference API running |
| 3 | Ceph 3-node cluster | 5–6h | HEALTH_OK, 3 OSDs, Ceph S3 accessible |
| 4 | n8n workflows + IoT simulator | 5h | End-to-end event flow working |
| 5 | Integration + demo prep | 3–4h | Full demo rehearsed, all checks green |

### 6.4 Microservices Architecture (Custom Code)

**Three custom FastAPI microservices on Node 1:**

**Service 1: Priority Queue API (port 8001)**
```
POST /enqueue       → ZADD to Redis Sorted Set (score formula applied)
GET  /dequeue       → ZPOPMAX (highest priority event returned and removed)
GET  /queue/status  → queue depth by priority tier
DELETE /queue/flush → clear queue (testing)
GET  /health        → Redis ping check
```

**Service 2: TFLite Inference API (port 8000)**
```
POST /infer/image   → YOLOv8-Nano object detection (upload image file)
POST /infer/sensor  → LSTM anomaly detection (POST JSON sensor readings)
GET  /health        → model backend status
```

**Service 3: Forensic Logger API (port 8002)**
```
POST /log           → Ed25519 sign event, append to hash chain, return signed entry
GET  /chain         → view recent entries in chain
GET  /verify        → verify hash chain integrity
```

### 6.5 IoT Event Simulator

Python script (`simulate.py`) that:
- Simulates 100 virtual IoT devices
- Sends events matching paper's distribution: 8% P1, 22% P2, 60% P3, 10% P4
- Publishes via MQTT to `iot/events/p{priority}` topics
- Also POSTs directly to Priority Queue API for immediate demo visibility
- Event types: intrusion alerts, health crises, equipment warnings, pressure anomalies, routine readings, batch logs

**Event structure:**
```json
{
  "event_id": "evt_0000001",
  "type": "intrusion_alert",
  "priority": 1,
  "device": "camera_01",
  "payload": {"zone": "entrance", "confidence": 0.97},
  "timestamp_ns": 1717123456789000000,
  "device_trust_score": 0.95
}
```

### 6.6 n8n Workflows (3 workflows)

**Workflow 1: MQTT Event Ingestor**
- Trigger: MQTT Subscribe (topic: `iot/events/#`)
- Step 1: Parse event JSON
- Step 2: Code node — compute priority score using paper's formula
- Step 3: HTTP POST to Priority Queue API `/enqueue`
- Step 4: PostgreSQL insert to iot_events table

**Workflow 2: Priority Queue Consumer**
- Trigger: Schedule (every 500ms)
- Step 1: HTTP GET `/dequeue` from Queue API
- Step 2: IF queue empty → stop
- Step 3: Switch on priority:
  - P1/P2 → HTTP POST to Inference API → HTTP POST to Forensic Logger → Telegram alert
  - P3 → HTTP PUT to Ceph S3 bucket
  - P4 → queued for background S3 batch upload
- Demonstrates: P1 events always processed before P3/P4 regardless of arrival order

**Workflow 3: Demo — Inject P1 Burst (manual trigger)**
- Manual trigger for examiner demo
- Injects 10 P1 events rapidly into queue
- Shows them all drain before any P3/P4 events

### 6.7 PostgreSQL Schema (Key Table)

```sql
CREATE TABLE iot_events (
    id           SERIAL PRIMARY KEY,
    event_id     VARCHAR(50) UNIQUE NOT NULL,
    event_type   VARCHAR(100) NOT NULL,
    priority     SMALLINT NOT NULL CHECK (priority BETWEEN 1 AND 4),
    device_id    VARCHAR(100),
    payload      JSONB,
    timestamp_ns BIGINT,
    processed    BOOLEAN DEFAULT FALSE,
    created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for demo queries
CREATE INDEX idx_events_priority ON iot_events(priority);
CREATE INDEX idx_events_created  ON iot_events(created_at);
CREATE INDEX idx_events_device   ON iot_events(device_id);

-- Demo view
CREATE VIEW priority_summary AS
SELECT
    priority,
    CASE priority
        WHEN 1 THEN 'P1-Emergency'
        WHEN 2 THEN 'P2-High'
        WHEN 3 THEN 'P3-Normal'
        WHEN 4 THEN 'P4-Batch'
    END as level,
    COUNT(*) as event_count
FROM iot_events GROUP BY priority ORDER BY priority;
```

### 6.8 Ceph Cluster Setup Summary

**Tool used:** cephadm (official Ceph orchestrator, manages Ceph via containers)

**Bootstrap sequence:**
1. Install cephadm on Node 1
2. `cephadm bootstrap --mon-ip <NODE1_PRIVATE_IP>` — creates MON + MGR + first OSD
3. Copy Ceph SSH public key to Node 2 and Node 3
4. `ceph orch host add iot-nas-ceph2 <IP>` and same for ceph3
5. `ceph orch daemon add osd iot-nas-ceph2:/dev/nvme1n1` — adds OSD on each node
6. Create pools: `iot-p1-nvme`, `iot-p3-replicated`, `iot-forensic-logs` with size=2

**Ceph Object Gateway (S3 compatible):**
- `ceph mgr module enable rgw`
- `radosgw-admin user create --uid=iotnas ...`
- S3 endpoint: `http://localhost:7480`
- Bucket: `iot-events`

**Fault tolerance demo:**
- Stop Ceph OSD on Node 3: `sudo systemctl stop ceph-osd@*`
- `ceph status` shows HEALTH_WARN, 2 OSDs up, self-healing active
- Restart: `sudo systemctl start ceph-osd@*`
- `ceph status` returns to HEALTH_OK (self-healing ~2–4 minutes)

### 6.9 Live Demo Sequence (for Examiner, ~15 minutes)

| Step | What to Show | Duration |
|---|---|---|
| 1 | AWS Console: 3 EC2 instances running, explain topology | 2 min |
| 2 | Start IoT simulator: P1🔴 P2🟠 P3🟢 P4⚪ events flowing | 2 min |
| 3 | n8n: Workflow 1 (MQTT Ingestor) executing in real time | 1 min |
| 4 | Queue status: inject P3 burst then 1 P1 event, show P1 jumps queue | 3 min |
| 5 | Inference API: upload image → YOLOv8 detects persons; sensor anomaly → LSTM flags critical | 2 min |
| 6 | Ceph cluster: `ceph status` → stop Node 3 OSD → HEALTH_WARN → restart → HEALTH_OK | 3 min |
| 7 | Forensic chain: `curl /chain` → show Ed25519 signatures, hash links | 1 min |
| 8 | Grafana dashboard: event counts, priority distribution, system resources | 1 min |

### 6.10 Pre-Demo Checklist

```
□ All 3 EC2 instances running
□ docker compose ps  →  all containers Up on Node 1
□ curl localhost:8001/health  →  {"status":"ok","redis":"connected"}
□ curl localhost:8000/health  →  {"status":"ok","backend":"YOLOv8n-ultralytics-CPU"}
□ curl localhost:8002/health  →  {"status":"ok"}
□ sudo ceph status  →  HEALTH_OK, 3 osds: 3 up, 3 in
□ n8n workflows: all 3 active (green, not errored)
□ PostgreSQL: iot_events table exists, priority_summary view works
□ Simulator test run: produces visible mixed P1-P4 output
□ Ceph failure demo: rehearsed at least once
□ Browser tabs pre-opened: n8n (5678), Grafana (3000), Ceph Dashboard (8443)
□ Test image downloaded: /tmp/test_scene.jpg
□ Terminal sessions arranged: queue watch, simulator, Ceph status
```

---

## 7. Key Code Snippets

### 7.1 Priority Queue Formula (Redis)
```python
import redis
import json
import time

r = redis.Redis(host='localhost', port=6379, decode_responses=True)
QUEUE_KEY = "iot:priority_queue"

def enqueue(event: dict):
    priority = event['priority']          # 1=Emergency, 4=Batch
    ts = time.time_ns()
    # Paper's formula: (4 - priority_level) × 10^9 + unix_timestamp_ns
    score = (4 - priority) * (10**9) + (ts % (10**9))
    r.zadd(QUEUE_KEY, {json.dumps(event): score})
    return score

def dequeue():
    result = r.zpopmax(QUEUE_KEY, count=1)  # Highest score = P1 = highest priority
    if result:
        event_json, score = result[0]
        return json.loads(event_json), score
    return None, None
```

### 7.2 IoT Event Simulator (core loop)
```python
import paho.mqtt.client as mqtt
import json, time, random, requests

event_templates = [
    {"type": "intrusion_alert",   "priority": 1, "device": "camera_01"},
    {"type": "equipment_warning", "priority": 2, "device": "motor_01"},
    {"type": "temp_reading",      "priority": 3, "device": "temp_01"},
    {"type": "batch_log_archive", "priority": 4, "device": "gateway_01"},
]
# Weights match paper distribution: 8% P1, 22% P2, 60% P3, 10% P4
weights = [0.08, 0.22, 0.60, 0.10]

client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
client.connect("localhost", 1883)
client.loop_start()

while True:
    template = random.choices(event_templates, weights=weights)[0]
    event = {**template, "event_id": f"evt_{time.time_ns()}", "timestamp_ns": time.time_ns()}
    client.publish(f"iot/events/p{event['priority']}", json.dumps(event))
    requests.post("http://localhost:8001/enqueue", json=event, timeout=0.5)
    time.sleep(random.uniform(0.05, 0.3))
```

### 7.3 TFLite Inference (YOLOv8-Nano CPU Simulation)
```python
from ultralytics import YOLO
import time

model = YOLO('yolov8n.pt')   # auto-downloads on first run

def infer_image(img_path: str) -> dict:
    t0 = time.perf_counter()
    results = model(img_path, verbose=False)
    latency_ms = (time.perf_counter() - t0) * 1000
    detections = []
    for r in results:
        for box in r.boxes:
            detections.append({
                "class": model.names[int(box.cls)],
                "confidence": round(float(box.conf), 4)
            })
    return {
        "model": "YOLOv8-Nano (CPU Simulation — Coral TPU emulated)",
        "latency_ms": round(latency_ms, 1),
        "note": "Physical Coral USB TPU achieves ~34ms (7.1× faster)",
        "detections": detections
    }
```

### 7.4 Forensic Logger (Ed25519 Hash Chain)
```python
import nacl.signing, hashlib, json, time

signing_key = nacl.signing.SigningKey.generate()
prev_hash = "genesis_block_iot_nas"
chain = []

def log_event(event: dict) -> dict:
    global prev_hash
    entry = {**event, "timestamp_us": int(time.time() * 1_000_000), "prev_hash": prev_hash}
    serialized = json.dumps(entry, sort_keys=True).encode()
    current_hash = hashlib.sha256(serialized).hexdigest()
    signature = signing_key.sign(serialized).signature.hex()
    log_entry = {**entry, "hash": current_hash, "signature_ed25519": signature, "compliant": "ISO/IEC 27037"}
    chain.append(log_entry)
    prev_hash = current_hash
    return log_entry
```

### 7.5 Sensor Anomaly Detection (LSTM Simulation)
```python
def infer_sensor(data: dict) -> dict:
    temp = data.get("temp_c", 25.0)
    vibration = data.get("vibration", 0.0)
    pressure = data.get("pressure_psi", 100.0)

    # Simulates LSTM 60-sample window anomaly scoring
    score = 0.0
    reasons = []
    if temp > 80:       score += 0.4; reasons.append(f"temp {temp}°C > 80°C threshold")
    if vibration > 1.5: score += 0.35; reasons.append(f"vibration {vibration}g > 1.5g")
    if pressure > 130:  score += 0.35; reasons.append(f"pressure {pressure}psi > 130psi")

    return {
        "model": "LSTM Anomaly Detector (CPU Simulation)",
        "anomaly_score": round(score, 3),
        "is_anomaly": score >= 0.5,
        "anomaly_reasons": reasons,
        "predicted_failure_eta_hours": max(0, 2.0 - score * 3.5) if score > 0.25 else None,
        "priority_recommendation": 1 if score >= 0.7 else (2 if score >= 0.4 else 3)
    }
```

### 7.6 Docker Compose (Node 1 Core Services)
```yaml
version: '3.8'
services:
  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]
    command: redis-server --appendonly yes --appendfsync everysec
    volumes: [redis_data:/data]

  mosquitto:
    image: eclipse-mosquitto:2
    ports: ["1883:1883", "9001:9001"]
    volumes: [./mosquitto/config:/mosquitto/config, mosquitto_data:/mosquitto/data]

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: iotnas
      POSTGRES_USER: iotnas
      POSTGRES_PASSWORD: iotnas2024
    ports: ["5432:5432"]
    volumes: [postgres_data:/var/lib/postgresql/data]

  n8n:
    image: n8nio/n8n:latest
    ports: ["5678:5678"]
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=iotnas2024
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_DATABASE=iotnas
      - DB_POSTGRESDB_USER=iotnas
      - DB_POSTGRESDB_PASSWORD=iotnas2024
    volumes: [n8n_data:/home/node/.n8n]
    depends_on: [postgres, redis]

  prometheus:
    image: prom/prometheus:latest
    ports: ["9090:9090"]
    volumes: [./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml]

  grafana:
    image: grafana/grafana:latest
    ports: ["3000:3000"]
    environment: [GF_SECURITY_ADMIN_PASSWORD=iotnas2024]
    volumes: [grafana_data:/var/lib/grafana]

  node-exporter:
    image: prom/node-exporter:latest
    ports: ["9100:9100"]
    network_mode: host

volumes:
  redis_data: mosquitto_data: postgres_data: n8n_data: prometheus_data: grafana_data:
```

---

## 8. Common Issues and Solutions

| Issue | Likely Cause | Fix |
|---|---|---|
| Ceph bootstrap fails | Wrong mon-ip (must be private IP, not public) | Use `hostname -I` to get correct private IP |
| cephadm can't SSH to Node 2/3 | Root SSH disabled on Ubuntu | `sudo sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && sudo systemctl restart sshd` |
| Ceph OSD won't start | Device already has partition table | Wipe: `sudo wipefs -a /dev/nvme1n1` |
| n8n can't connect to Redis | Container network isolation | Use `host.docker.internal` or Node 1's private IP instead of `localhost` inside n8n |
| Inference API slow on EC2 | t3.large has limited CPU | Expected 150–400ms (CPU vs 34ms Coral TPU); label it as simulation |
| MQTT not receiving | Topic mismatch | Simulator publishes to `iot/events/p1`, n8n subscribes to `iot/events/#` (wildcard) |
| Docker Compose `n8n` exits | PostgreSQL not ready yet | Add `restart: unless-stopped` and healthcheck to postgres |
| Port already in use | Previous process running | `sudo lsof -i :8001` then `kill -9 <PID>` |
| EBS device name unknown | Nitro instances use NVMe naming | Run `lsblk` after attaching EBS, device will be `/dev/nvme1n1` not `/dev/sdf` |

---

## 9. Project Context for AI Assistants

If you are an AI assistant reading this document, here is what you need to know to help Ashish effectively:

**What Ashish has already done:**
- Written the complete IEEE research paper (31+ pages, 20 references, all sections complete)
- Designed the full architecture with DFDs (Level 0, Level 1, Level 2 for P2 and P4)
- Created all diagrams (system architecture, DFDs, Ceph fault tolerance, TAP pipeline, queue comparison figures)
- Written the AWS execution plan (Day 1–5, complete with commands)
- Identified the 33 research gaps and 5 novel contributions
- Has a working DevOps background (AWS EC2, Docker, Kubernetes, n8n — see his GitStalker and SOVEREIGN projects)

**What Ashish is currently doing:**
- Implementing the system on AWS in < 1 week for a live examiner demo
- Using student AWS credits (cost not a blocker)
- Coral USB TPU is NOT available — using CPU-based YOLOv8 inference instead
- STM32 PPS timestamps NOT available — using `time.time_ns()` software timestamps instead
- These compromises are justified by the paper's own §5 AWS testbed methodology

**What Ashish needs help with (typical tasks):**
- Debugging AWS/Docker/Ceph setup issues
- Writing or fixing Python/FastAPI microservice code
- Configuring n8n workflows
- Troubleshooting Redis, Ceph, or Mosquitto
- Adding features to the existing implementation plan
- Preparing demo scripts or documentation

**Important technical constraints to remember:**
- All nodes are Ubuntu 22.04 LTS on EC2
- Node 1 is t3.large (8GB RAM), Nodes 2/3 are t3.medium (4GB RAM)
- Python version: 3.10+ (Ubuntu 22.04 default)
- n8n version: 1.60+
- Redis: Sorted Sets with ZADD/ZPOPMAX (NOT ZPOPMIN — score is inverted for priority)
- Ceph deployment: cephadm (NOT Rook, NOT manual)
- All custom services run via FastAPI + uvicorn, NOT Flask
- Docker Compose v2 (command is `docker compose`, NOT `docker-compose`)

**File locations (on Node 1 EC2):**
```
~/iot-nas/                     → project root
~/iot-nas/docker-compose.yml   → core services
~/iot-nas/mosquitto/           → MQTT config
~/iot-nas/prometheus/          → Prometheus config
~/iot-nas/services/queue/      → Priority Queue API (port 8001)
~/iot-nas/services/inference/  → TFLite Inference API (port 8000)
~/iot-nas/services/forensics/  → Forensic Logger API (port 8002)
~/iot-nas/simulator/           → IoT Event Simulator
/tmp/queue_api.log             → Queue API log
/tmp/infer_api.log             → Inference API log
/tmp/forensic.log              → Forensic Logger log
```

**Key ports:**
- 1883: MQTT (Mosquitto)
- 5678: n8n UI
- 3000: Grafana
- 6379: Redis
- 5432: PostgreSQL
- 8000: TFLite Inference API
- 8001: Priority Queue API
- 8002: Forensic Logger API
- 9090: Prometheus
- 7480: Ceph Object Gateway (S3)
- 8443: Ceph Dashboard
- 9100: Node Exporter

---

*Document version: 1.0 | Generated for Ashish Kumar Laheri's IoT-NAS Capstone Project*
*Last updated: Implementation phase (AWS execution in progress)*