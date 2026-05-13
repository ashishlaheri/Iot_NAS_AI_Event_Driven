"""
IoT-NAS — Forensic Logger API
===============================
FastAPI microservice implementing Ed25519 hash chain with persistence.

Port: 8002
Features:
  - Ed25519 digital signatures on every event
  - SHA-256 hash chain (each entry links to previous)
  - Persistent signing key (survives restarts)
  - Persistent chain (JSON file on Docker volume)
  - ISO/IEC 27037 forensic chain-of-custody compliance
"""

import json
import time
import os
import hashlib
import logging
from contextlib import asynccontextmanager
from typing import Optional, List
from pathlib import Path

import nacl.signing
import nacl.encoding
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from prometheus_client import (
    Counter, Gauge, generate_latest, CONTENT_TYPE_LATEST
)
from fastapi.responses import Response

# ---- Logging ----
logging.basicConfig(level=logging.INFO, format="%(asctime)s [FORENSIC] %(message)s")
logger = logging.getLogger("forensic-api")

# ---- Persistence Paths ----
DATA_DIR = Path(os.getenv("DATA_DIR", "/app/data"))
KEY_FILE = DATA_DIR / "ed25519_signing_key.bin"
CHAIN_FILE = DATA_DIR / "forensic_chain.json"
DATA_DIR.mkdir(parents=True, exist_ok=True)

# ---- Prometheus Metrics ----
LOG_TOTAL = Counter("forensic_log_total", "Total events logged")
VERIFY_TOTAL = Counter("forensic_verify_total", "Total verifications")
CHAIN_LENGTH = Gauge("forensic_chain_length", "Current chain length")

# ---- Global State ----
signing_key: Optional[nacl.signing.SigningKey] = None
verify_key_hex: str = ""
chain: List[dict] = []
prev_hash: str = "genesis_block_iot_nas"


# ---- Key Management ----
def load_or_create_key() -> nacl.signing.SigningKey:
    """Load Ed25519 signing key from disk, or create and persist a new one."""
    if KEY_FILE.exists():
        logger.info("Loading existing Ed25519 signing key")
        with open(KEY_FILE, "rb") as f:
            return nacl.signing.SigningKey(f.read())
    else:
        logger.info("Generating new Ed25519 signing key")
        key = nacl.signing.SigningKey.generate()
        with open(KEY_FILE, "wb") as f:
            f.write(key.encode())
        return key


# ---- Chain Persistence ----
def load_chain():
    """Load the hash chain from disk."""
    global chain, prev_hash
    if CHAIN_FILE.exists():
        try:
            with open(CHAIN_FILE, "r") as f:
                data = json.load(f)
            chain = data.get("chain", [])
            prev_hash = data.get("prev_hash", "genesis_block_iot_nas")
            logger.info(f"Loaded chain with {len(chain)} entries")
        except (json.JSONDecodeError, KeyError) as e:
            logger.error(f"Corrupted chain file, starting fresh: {e}")
            chain = []
            prev_hash = "genesis_block_iot_nas"
    else:
        chain = []
        prev_hash = "genesis_block_iot_nas"
        logger.info("No existing chain found, starting from genesis")


def save_chain():
    """Persist the hash chain to disk."""
    with open(CHAIN_FILE, "w") as f:
        json.dump({"chain": chain, "prev_hash": prev_hash}, f)


# ---- Pydantic Models ----
class ForensicEvent(BaseModel):
    event_id: str = Field(..., description="Event identifier")
    event_type: str = Field(default="generic", description="Event type")
    priority: int = Field(default=3, ge=1, le=4)
    device: str = Field(default="unknown")
    payload: dict = Field(default_factory=dict)


class LogEntry(BaseModel):
    event_id: str
    event_type: str
    priority: int
    device: str
    payload: dict
    timestamp_us: int
    prev_hash: str
    hash: str
    signature_ed25519: str
    verify_key: str
    compliant: str
    chain_index: int


class VerifyResult(BaseModel):
    valid: bool
    chain_length: int
    errors: List[str]
    checked_at: float


# ---- Lifespan ----
@asynccontextmanager
async def lifespan(app: FastAPI):
    global signing_key, verify_key_hex
    signing_key = load_or_create_key()
    verify_key_hex = signing_key.verify_key.encode(
        encoder=nacl.encoding.HexEncoder
    ).decode()
    load_chain()
    CHAIN_LENGTH.set(len(chain))
    logger.info(f"Forensic Logger ready | verify_key={verify_key_hex[:16]}...")
    yield
    save_chain()
    logger.info("Forensic Logger shut down, chain saved")


# ---- FastAPI App ----
app = FastAPI(
    title="IoT-NAS Forensic Logger API",
    description="Ed25519 signed hash chain for forensic audit trail",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---- Endpoints ----
@app.post("/log", response_model=LogEntry)
async def log_event(event: ForensicEvent):
    """Sign an event with Ed25519 and append to the hash chain."""
    global prev_hash

    # Build entry with chain linkage
    entry = {
        "event_id": event.event_id,
        "event_type": event.event_type,
        "priority": event.priority,
        "device": event.device,
        "payload": event.payload,
        "timestamp_us": int(time.time() * 1_000_000),
        "prev_hash": prev_hash,
    }

    # Compute SHA-256 hash of the entry
    serialized = json.dumps(entry, sort_keys=True).encode()
    current_hash = hashlib.sha256(serialized).hexdigest()

    # Sign with Ed25519
    signature = signing_key.sign(serialized).signature.hex()

    # Complete log entry
    log_entry = {
        **entry,
        "hash": current_hash,
        "signature_ed25519": signature,
        "verify_key": verify_key_hex,
        "compliant": "ISO/IEC 27037",
        "chain_index": len(chain),
    }

    chain.append(log_entry)
    prev_hash = current_hash
    save_chain()

    LOG_TOTAL.inc()
    CHAIN_LENGTH.set(len(chain))

    logger.info(
        f"LOG #{len(chain)-1} | {event.event_type} | {event.event_id} | "
        f"hash={current_hash[:16]}..."
    )

    return LogEntry(**log_entry)


@app.get("/chain")
async def get_chain(limit: int = 20, offset: int = 0):
    """View recent entries in the hash chain (paginated)."""
    total = len(chain)
    # Return most recent entries first
    start = max(0, total - offset - limit)
    end = total - offset
    entries = chain[start:end]
    entries.reverse()

    return {
        "status": "ok",
        "total_entries": total,
        "showing": len(entries),
        "offset": offset,
        "limit": limit,
        "genesis_hash": "genesis_block_iot_nas",
        "verify_key": verify_key_hex,
        "entries": entries,
    }


@app.get("/verify", response_model=VerifyResult)
async def verify_chain():
    """Verify the integrity of the entire hash chain."""
    errors = []
    expected_prev = "genesis_block_iot_nas"

    for i, entry in enumerate(chain):
        # Check prev_hash linkage
        if entry.get("prev_hash") != expected_prev:
            errors.append(
                f"Entry {i}: prev_hash mismatch "
                f"(expected={expected_prev[:16]}, got={entry.get('prev_hash', 'MISSING')[:16]})"
            )

        # Recompute hash from entry data
        verify_entry = {
            "event_id": entry["event_id"],
            "event_type": entry["event_type"],
            "priority": entry["priority"],
            "device": entry["device"],
            "payload": entry["payload"],
            "timestamp_us": entry["timestamp_us"],
            "prev_hash": entry["prev_hash"],
        }
        serialized = json.dumps(verify_entry, sort_keys=True).encode()
        recomputed = hashlib.sha256(serialized).hexdigest()

        if recomputed != entry.get("hash"):
            errors.append(
                f"Entry {i}: hash mismatch "
                f"(expected={recomputed[:16]}, got={entry.get('hash', 'MISSING')[:16]})"
            )

        expected_prev = entry.get("hash", "")

    VERIFY_TOTAL.inc()
    valid = len(errors) == 0

    logger.info(
        f"VERIFY | {'PASS' if valid else 'FAIL'} | "
        f"{len(chain)} entries | {len(errors)} errors"
    )

    return VerifyResult(
        valid=valid,
        chain_length=len(chain),
        errors=errors,
        checked_at=time.time(),
    )


@app.get("/health")
async def health_check():
    """Health check."""
    return {
        "status": "ok",
        "chain_length": len(chain),
        "signing_key_loaded": signing_key is not None,
        "verify_key": verify_key_hex[:16] + "..." if verify_key_hex else None,
        "compliant": "ISO/IEC 27037",
    }


@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint."""
    CHAIN_LENGTH.set(len(chain))
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8002)
