"""
IoT-NAS — Priority Queue API
=============================
FastAPI microservice implementing the paper's priority event queue.

Port: 8001
Backend: Redis Sorted Sets (ZADD / ZPOPMAX)

Scoring formula (corrected):
  score = (4 - priority_level) × 10^18 + unix_timestamp_ns
  
  This ensures P1 events ALWAYS have higher scores than P2/P3/P4,
  and within the same tier, newer events have higher scores.
  ZPOPMAX returns the highest score first = P1 processed first.
"""

import json
import time
import os
import logging
from contextlib import asynccontextmanager
from typing import Optional

import redis
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from prometheus_client import (
    Counter, Gauge, Histogram, generate_latest, CONTENT_TYPE_LATEST
)
from fastapi.responses import Response

# ---- Logging ----
logging.basicConfig(level=logging.INFO, format="%(asctime)s [QUEUE] %(message)s")
logger = logging.getLogger("queue-api")

# ---- Redis Connection ----
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", 6379))
QUEUE_KEY = "iot:priority_queue"

r: Optional[redis.Redis] = None

# ---- Prometheus Metrics ----
ENQUEUE_TOTAL = Counter(
    "queue_enqueue_total", "Total events enqueued", ["priority"]
)
DEQUEUE_TOTAL = Counter(
    "queue_dequeue_total", "Total events dequeued"
)
QUEUE_DEPTH = Gauge(
    "queue_depth", "Current queue depth"
)
ENQUEUE_LATENCY = Histogram(
    "queue_enqueue_latency_seconds", "Enqueue latency",
    buckets=[0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25]
)

# ---- Priority Labels ----
PRIORITY_LABELS = {
    1: "P1-Emergency",
    2: "P2-High",
    3: "P3-Normal",
    4: "P4-Batch"
}


# ---- Pydantic Models ----
class IoTEvent(BaseModel):
    """Incoming IoT event to enqueue."""
    event_id: str = Field(..., description="Unique event identifier")
    type: str = Field(..., alias="event_type", description="Event type name")
    priority: int = Field(..., ge=1, le=4, description="Priority 1-4 (1=Emergency)")
    device: str = Field(default="unknown", alias="device_id", description="Source device ID")
    payload: dict = Field(default_factory=dict, description="Event payload data")
    timestamp_ns: Optional[int] = Field(default=None, description="Nanosecond timestamp")
    device_trust_score: Optional[float] = Field(default=None, ge=0.0, le=1.0)

    class Config:
        populate_by_name = True  # Allow both field name and alias


class EnqueueResponse(BaseModel):
    status: str
    event_id: str
    priority: int
    priority_label: str
    score: float
    queue_depth: int


class DequeueResponse(BaseModel):
    status: str
    event: Optional[dict]
    score: Optional[float]
    priority_label: Optional[str]
    queue_depth: int


# ---- Lifespan ----
@asynccontextmanager
async def lifespan(app: FastAPI):
    global r
    logger.info(f"Connecting to Redis at {REDIS_HOST}:{REDIS_PORT}")
    r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)
    r.ping()
    logger.info("Redis connected successfully")
    yield
    logger.info("Shutting down Queue API")
    if r:
        r.close()


# ---- FastAPI App ----
app = FastAPI(
    title="IoT-NAS Priority Queue API",
    description="Event-driven priority queue using Redis Sorted Sets",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---- Scoring Function ----
def compute_score(priority: int, timestamp_ns: int) -> float:
    """
    Paper's priority scoring formula (corrected implementation):
    
    score = (4 - priority) × 10^18 + timestamp_ns
    
    P1 Emergency: (4-1) × 10^18 + ts = 3×10^18 + ts  → highest
    P2 High:      (4-2) × 10^18 + ts = 2×10^18 + ts
    P3 Normal:    (4-3) × 10^18 + ts = 1×10^18 + ts
    P4 Batch:     (4-4) × 10^18 + ts = 0×10^18 + ts  → lowest
    
    ZPOPMAX returns highest score first → P1 always processed before P2.
    Within same tier, newer events (higher ts) are processed first.
    """
    return (4 - priority) * (10**18) + timestamp_ns


# ---- Endpoints ----
@app.post("/enqueue", response_model=EnqueueResponse)
async def enqueue_event(event: IoTEvent):
    """Enqueue an IoT event into the priority queue."""
    ts = event.timestamp_ns or time.time_ns()
    score = compute_score(event.priority, ts)

    # Build the stored event
    stored_event = {
        "event_id": event.event_id,
        "type": event.type,
        "priority": event.priority,
        "device": event.device,
        "payload": event.payload,
        "timestamp_ns": ts,
        "device_trust_score": event.device_trust_score,
        "enqueued_at": time.time(),
    }

    with ENQUEUE_LATENCY.time():
        r.zadd(QUEUE_KEY, {json.dumps(stored_event): score})

    depth = r.zcard(QUEUE_KEY)
    ENQUEUE_TOTAL.labels(priority=str(event.priority)).inc()
    QUEUE_DEPTH.set(depth)

    logger.info(
        f"ENQUEUE {PRIORITY_LABELS.get(event.priority, '??')} "
        f"| {event.type} | {event.event_id} | score={score:.0f} | depth={depth}"
    )

    return EnqueueResponse(
        status="enqueued",
        event_id=event.event_id,
        priority=event.priority,
        priority_label=PRIORITY_LABELS.get(event.priority, "Unknown"),
        score=score,
        queue_depth=depth,
    )


@app.get("/dequeue", response_model=DequeueResponse)
async def dequeue_event():
    """Dequeue the highest-priority event (ZPOPMAX)."""
    result = r.zpopmax(QUEUE_KEY, count=1)
    depth = r.zcard(QUEUE_KEY)
    QUEUE_DEPTH.set(depth)

    if not result:
        return DequeueResponse(
            status="empty",
            event=None,
            score=None,
            priority_label=None,
            queue_depth=depth,
        )

    event_json, score = result[0]
    event = json.loads(event_json)
    DEQUEUE_TOTAL.inc()

    priority = event.get("priority", 0)
    logger.info(
        f"DEQUEUE {PRIORITY_LABELS.get(priority, '??')} "
        f"| {event.get('type')} | {event.get('event_id')} | score={score:.0f}"
    )

    return DequeueResponse(
        status="dequeued",
        event=event,
        score=score,
        priority_label=PRIORITY_LABELS.get(priority, "Unknown"),
        queue_depth=depth,
    )


@app.get("/queue/status")
async def queue_status():
    """Get queue depth broken down by priority tier."""
    total = r.zcard(QUEUE_KEY)

    # Count events by priority tier using score ranges
    # P1: score >= 3×10^18, P2: 2×10^18 <= score < 3×10^18, etc.
    tiers = {}
    for p in range(1, 5):
        min_score = (4 - p) * (10**18)
        max_score = (4 - p + 1) * (10**18) - 1 if p > 1 else "+inf"
        count = r.zcount(QUEUE_KEY, min_score, max_score)
        tiers[PRIORITY_LABELS[p]] = count

    QUEUE_DEPTH.set(total)

    return {
        "status": "ok",
        "total_depth": total,
        "by_priority": tiers,
        "timestamp": time.time(),
    }


@app.delete("/queue/flush")
async def flush_queue():
    """Clear the entire queue (testing/demo only)."""
    count = r.zcard(QUEUE_KEY)
    r.delete(QUEUE_KEY)
    QUEUE_DEPTH.set(0)
    logger.warning(f"FLUSH: Cleared {count} events from queue")
    return {"status": "flushed", "cleared": count}


@app.get("/health")
async def health_check():
    """Health check — verifies Redis connectivity."""
    try:
        r.ping()
        return {
            "status": "ok",
            "redis": "connected",
            "host": REDIS_HOST,
            "queue_depth": r.zcard(QUEUE_KEY),
        }
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Redis error: {str(e)}")


@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint."""
    # Update queue depth gauge before scrape
    try:
        QUEUE_DEPTH.set(r.zcard(QUEUE_KEY))
    except Exception:
        pass
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)


# ---- Run ----
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
