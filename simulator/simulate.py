"""
IoT-NAS — IoT Event Simulator
================================
Simulates 100 virtual IoT devices publishing events via MQTT
and directly to the Priority Queue API.

Usage:
    python simulate.py                          # Default: 5 events/sec
    python simulate.py --rate 20                # 20 events/sec
    python simulate.py --duration 60            # Run for 60 seconds
    python simulate.py --mqtt-host 10.0.1.5     # Custom MQTT host
    python simulate.py --api-host 10.0.1.5      # Custom API host
    python simulate.py --burst-p1 10            # Inject 10 P1 events then exit
"""

import argparse
import json
import random
import sys
import time
import uuid
from datetime import datetime

import paho.mqtt.client as mqtt
import requests

# ============================================
# Device Registry (100 virtual devices)
# ============================================
DEVICE_POOL = []

# Cameras (20 devices)
for i in range(1, 21):
    DEVICE_POOL.append({
        "device_id": f"camera_{i:02d}",
        "device_type": "camera",
        "trust_score": round(random.uniform(0.85, 0.99), 2),
    })

# Temperature sensors (20 devices)
for i in range(1, 21):
    DEVICE_POOL.append({
        "device_id": f"temp_{i:02d}",
        "device_type": "sensor",
        "trust_score": round(random.uniform(0.90, 0.99), 2),
    })

# Industrial motors/pumps (15 devices)
for i in range(1, 16):
    DEVICE_POOL.append({
        "device_id": f"motor_{i:02d}",
        "device_type": "industrial",
        "trust_score": round(random.uniform(0.80, 0.95), 2),
    })

# Pressure sensors (15 devices)
for i in range(1, 16):
    DEVICE_POOL.append({
        "device_id": f"pressure_{i:02d}",
        "device_type": "sensor",
        "trust_score": round(random.uniform(0.88, 0.98), 2),
    })

# Wearables (15 devices)
for i in range(1, 16):
    DEVICE_POOL.append({
        "device_id": f"wearable_{i:02d}",
        "device_type": "wearable",
        "trust_score": round(random.uniform(0.75, 0.90), 2),
    })

# Gateways (10 devices)
for i in range(1, 11):
    DEVICE_POOL.append({
        "device_id": f"gateway_{i:02d}",
        "device_type": "gateway",
        "trust_score": round(random.uniform(0.95, 0.99), 2),
    })

# Vibration sensors (5 devices)
for i in range(1, 6):
    DEVICE_POOL.append({
        "device_id": f"vibration_{i:02d}",
        "device_type": "sensor",
        "trust_score": round(random.uniform(0.85, 0.95), 2),
    })

# ============================================
# Event Templates (paper-accurate distribution)
# ============================================
EVENT_TEMPLATES = [
    # P1 Emergency (8%)
    {"type": "intrusion_alert",     "priority": 1, "weight": 0.03},
    {"type": "health_crisis",       "priority": 1, "weight": 0.02},
    {"type": "fire_alarm",          "priority": 1, "weight": 0.02},
    {"type": "ransomware_detected", "priority": 1, "weight": 0.01},
    # P2 High (22%)
    {"type": "equipment_warning",   "priority": 2, "weight": 0.08},
    {"type": "anomaly_detected",    "priority": 2, "weight": 0.07},
    {"type": "pressure_spike",      "priority": 2, "weight": 0.04},
    {"type": "unauthorized_access", "priority": 2, "weight": 0.03},
    # P3 Normal (60%)
    {"type": "temp_reading",        "priority": 3, "weight": 0.20},
    {"type": "humidity_reading",    "priority": 3, "weight": 0.15},
    {"type": "routine_heartbeat",   "priority": 3, "weight": 0.15},
    {"type": "vibration_reading",   "priority": 3, "weight": 0.10},
    # P4 Batch (10%)
    {"type": "batch_log_archive",   "priority": 4, "weight": 0.05},
    {"type": "daily_summary",       "priority": 4, "weight": 0.03},
    {"type": "firmware_report",     "priority": 4, "weight": 0.02},
]

TEMPLATES = [t for t in EVENT_TEMPLATES]
WEIGHTS = [t["weight"] for t in EVENT_TEMPLATES]

# ============================================
# Priority Colors for Terminal Output
# ============================================
COLORS = {
    1: "\033[91m",  # Red
    2: "\033[93m",  # Yellow
    3: "\033[92m",  # Green
    4: "\033[37m",  # White/Gray
}
RESET = "\033[0m"
PRIORITY_ICONS = {1: "🔴", 2: "🟠", 3: "🟢", 4: "⚪"}
PRIORITY_LABELS = {1: "P1-EMER", 2: "P2-HIGH", 3: "P3-NORM", 4: "P4-BATCH"}


def generate_payload(event_type: str) -> dict:
    """Generate realistic payload data for each event type."""
    payloads = {
        "intrusion_alert": {
            "zone": random.choice(["entrance", "warehouse", "server_room", "parking"]),
            "confidence": round(random.uniform(0.85, 0.99), 2),
            "persons_detected": random.randint(1, 3),
        },
        "health_crisis": {
            "heart_rate": random.randint(140, 200),
            "spo2": random.randint(60, 85),
            "worker_id": f"W{random.randint(100, 999)}",
        },
        "fire_alarm": {
            "zone": random.choice(["floor_1", "floor_2", "basement", "rooftop"]),
            "smoke_level": round(random.uniform(0.7, 1.0), 2),
            "temperature_c": round(random.uniform(80, 200), 1),
        },
        "ransomware_detected": {
            "family": random.choice(["WannaCry", "Ryuk", "Conti", "LockBit"]),
            "confidence": round(random.uniform(0.90, 0.99), 2),
            "affected_shares": random.randint(1, 5),
        },
        "equipment_warning": {
            "component": random.choice(["bearing", "motor", "pump", "valve"]),
            "vibration_g": round(random.uniform(1.0, 3.0), 2),
            "remaining_life_hours": random.randint(10, 200),
        },
        "anomaly_detected": {
            "metric": random.choice(["temperature", "pressure", "vibration", "current"]),
            "value": round(random.uniform(80, 150), 1),
            "threshold": round(random.uniform(70, 90), 1),
            "deviation_pct": round(random.uniform(10, 80), 1),
        },
        "pressure_spike": {
            "pressure_psi": round(random.uniform(130, 200), 1),
            "max_safe_psi": 130,
            "duration_ms": random.randint(100, 5000),
        },
        "unauthorized_access": {
            "door": random.choice(["main_entrance", "server_room", "lab_3"]),
            "badge_id": f"B{random.randint(1000, 9999)}",
            "authorized": False,
        },
        "temp_reading": {
            "temp_c": round(random.uniform(18, 45), 1),
            "humidity": round(random.uniform(30, 80), 1),
        },
        "humidity_reading": {
            "humidity_pct": round(random.uniform(20, 90), 1),
            "dew_point_c": round(random.uniform(5, 25), 1),
        },
        "routine_heartbeat": {
            "uptime_hours": random.randint(1, 8760),
            "cpu_pct": round(random.uniform(5, 60), 1),
            "memory_pct": round(random.uniform(20, 80), 1),
        },
        "vibration_reading": {
            "vibration_g": round(random.uniform(0.01, 0.8), 3),
            "frequency_hz": round(random.uniform(10, 500), 1),
        },
        "batch_log_archive": {
            "log_lines": random.randint(1000, 50000),
            "compressed_size_kb": random.randint(100, 5000),
        },
        "daily_summary": {
            "events_today": random.randint(500, 5000),
            "alerts_today": random.randint(0, 20),
            "uptime_pct": round(random.uniform(99.0, 99.99), 2),
        },
        "firmware_report": {
            "version": f"{random.randint(1,5)}.{random.randint(0,9)}.{random.randint(0,99)}",
            "update_available": random.choice([True, False]),
        },
    }
    return payloads.get(event_type, {"raw": "generic_event_data"})


def generate_event(counter: int) -> dict:
    """Generate a single IoT event."""
    template = random.choices(TEMPLATES, weights=WEIGHTS, k=1)[0]
    device = random.choice(DEVICE_POOL)
    ts = time.time_ns()

    return {
        "event_id": f"evt_{uuid.uuid4().hex[:12]}",
        "event_type": template["type"],
        "priority": template["priority"],
        "device_id": device["device_id"],
        "payload": generate_payload(template["type"]),
        "timestamp_ns": ts,
        "device_trust_score": device["trust_score"],
    }


def print_event(event: dict, counter: int):
    """Pretty-print an event to the terminal."""
    p = event["priority"]
    icon = PRIORITY_ICONS.get(p, "?")
    label = PRIORITY_LABELS.get(p, "????")
    color = COLORS.get(p, "")
    ts = datetime.now().strftime("%H:%M:%S.%f")[:-3]

    print(
        f"{color}[{ts}] {icon} {label} | "
        f"{event['event_type']:<22} | "
        f"{event['device_id']:<15} | "
        f"trust={event['device_trust_score']:.2f}"
        f"{RESET}"
    )


def main():
    parser = argparse.ArgumentParser(description="IoT-NAS Event Simulator")
    parser.add_argument("--rate", type=float, default=5.0, help="Events per second")
    parser.add_argument("--duration", type=int, default=0, help="Duration in seconds (0=infinite)")
    parser.add_argument("--mqtt-host", type=str, default="localhost", help="MQTT broker host")
    parser.add_argument("--mqtt-port", type=int, default=1883, help="MQTT broker port")
    parser.add_argument("--api-host", type=str, default="localhost", help="Queue API host")
    parser.add_argument("--api-port", type=int, default=8001, help="Queue API port")
    parser.add_argument("--burst-p1", type=int, default=0, help="Inject N P1 events and exit")
    parser.add_argument("--no-mqtt", action="store_true", help="Skip MQTT publishing")
    parser.add_argument("--no-api", action="store_true", help="Skip API posting")
    args = parser.parse_args()

    # ---- MQTT Connection ----
    mqtt_client = None
    if not args.no_mqtt:
        try:
            mqtt_client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
            mqtt_client.connect(args.mqtt_host, args.mqtt_port)
            mqtt_client.loop_start()
            print(f"✅ MQTT connected to {args.mqtt_host}:{args.mqtt_port}")
        except Exception as e:
            print(f"⚠️  MQTT connection failed: {e} — continuing without MQTT")
            mqtt_client = None

    api_url = f"http://{args.api_host}:{args.api_port}/enqueue"

    # ---- P1 Burst Mode ----
    if args.burst_p1 > 0:
        print(f"\n🔴 BURST MODE: Injecting {args.burst_p1} P1 Emergency events...")
        for i in range(args.burst_p1):
            event = {
                "event_id": f"burst_{uuid.uuid4().hex[:8]}",
                "event_type": random.choice(["intrusion_alert", "fire_alarm", "health_crisis"]),
                "priority": 1,
                "device_id": f"camera_{random.randint(1,20):02d}",
                "payload": generate_payload("intrusion_alert"),
                "timestamp_ns": time.time_ns(),
                "device_trust_score": 0.95,
            }
            print_event(event, i)
            if mqtt_client:
                mqtt_client.publish("iot/events/p1", json.dumps(event))
            if not args.no_api:
                try:
                    requests.post(api_url, json=event, timeout=1)
                except requests.exceptions.RequestException:
                    pass
            time.sleep(0.05)
        print(f"\n✅ Burst complete: {args.burst_p1} P1 events injected")
        return

    # ---- Continuous Mode ----
    delay = 1.0 / args.rate
    start_time = time.time()
    counter = 0
    stats = {1: 0, 2: 0, 3: 0, 4: 0}

    print(f"\n{'='*70}")
    print(f"  IoT-NAS Event Simulator")
    print(f"  Rate: {args.rate} events/sec | Devices: {len(DEVICE_POOL)}")
    print(f"  MQTT: {args.mqtt_host}:{args.mqtt_port} | API: {api_url}")
    print(f"  Distribution: 8% P1 | 22% P2 | 60% P3 | 10% P4")
    if args.duration > 0:
        print(f"  Duration: {args.duration}s")
    print(f"{'='*70}\n")

    try:
        while True:
            if args.duration > 0 and (time.time() - start_time) > args.duration:
                break

            event = generate_event(counter)
            counter += 1
            stats[event["priority"]] += 1
            print_event(event, counter)

            # Publish via MQTT
            if mqtt_client:
                topic = f"iot/events/p{event['priority']}"
                mqtt_client.publish(topic, json.dumps(event))

            # POST to Queue API
            if not args.no_api:
                try:
                    requests.post(api_url, json=event, timeout=0.5)
                except requests.exceptions.RequestException:
                    pass  # MQTT is primary; API is secondary

            time.sleep(delay + random.uniform(-delay * 0.2, delay * 0.2))

    except KeyboardInterrupt:
        pass

    elapsed = time.time() - start_time
    print(f"\n{'='*70}")
    print(f"  Simulation Complete")
    print(f"  Total events: {counter} | Duration: {elapsed:.1f}s")
    print(f"  Rate: {counter/max(elapsed,1):.1f} events/sec")
    print(f"  P1: {stats[1]} ({stats[1]/max(counter,1)*100:.1f}%)")
    print(f"  P2: {stats[2]} ({stats[2]/max(counter,1)*100:.1f}%)")
    print(f"  P3: {stats[3]} ({stats[3]/max(counter,1)*100:.1f}%)")
    print(f"  P4: {stats[4]} ({stats[4]/max(counter,1)*100:.1f}%)")
    print(f"{'='*70}")

    if mqtt_client:
        mqtt_client.loop_stop()
        mqtt_client.disconnect()


if __name__ == "__main__":
    main()
