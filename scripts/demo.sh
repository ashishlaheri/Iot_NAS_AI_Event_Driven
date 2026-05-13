#!/bin/bash
# ============================================
# IoT-NAS — Pre-Demo Health Check
# ============================================
# Run before every demo to verify all systems are operational
# Usage: chmod +x demo.sh && ./demo.sh

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'
PASS="${GREEN}✓ PASS${NC}"
FAIL="${RED}✗ FAIL${NC}"
WARN="${YELLOW}⚠ WARN${NC}"

CHECKS=0
PASSED=0
FAILED=0

check() {
    CHECKS=$((CHECKS + 1))
    local desc="$1"
    local cmd="$2"
    
    if eval "$cmd" > /dev/null 2>&1; then
        echo -e "  $PASS  $desc"
        PASSED=$((PASSED + 1))
    else
        echo -e "  $FAIL  $desc"
        FAILED=$((FAILED + 1))
    fi
}

echo ""
echo "============================================"
echo "  IoT-NAS — Pre-Demo Health Check"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"
echo ""

# ---- Docker Containers ----
echo "📦 Docker Containers:"
check "All containers running" "docker compose ps --status running | grep -c 'running' | grep -q '[7-9]\|1[0-9]'"
check "Redis container up" "docker compose ps redis | grep -q 'Up\|running'"
check "PostgreSQL container up" "docker compose ps postgres | grep -q 'Up\|running'"
check "Mosquitto container up" "docker compose ps mosquitto | grep -q 'Up\|running'"
check "n8n container up" "docker compose ps n8n | grep -q 'Up\|running'"
check "Queue API container up" "docker compose ps queue-api | grep -q 'Up\|running'"
check "Inference API container up" "docker compose ps inference-api | grep -q 'Up\|running'"
check "Forensic API container up" "docker compose ps forensic-api | grep -q 'Up\|running'"
echo ""

# ---- API Health Checks ----
echo "🔌 API Health:"
check "Queue API (8001)" "curl -sf http://localhost:8001/health | jq -e '.status == \"ok\"'"
check "Inference API (8000)" "curl -sf http://localhost:8000/health | jq -e '.status == \"ok\"'"
check "Forensic API (8002)" "curl -sf http://localhost:8002/health | jq -e '.status == \"ok\"'"
check "Redis connected" "curl -sf http://localhost:8001/health | jq -e '.redis == \"connected\"'"
check "YOLOv8 model loaded" "curl -sf http://localhost:8000/health | jq -e '.yolov8_loaded == true'"
echo ""

# ---- Database ----
echo "🗄️  Database:"
check "PostgreSQL accepting connections" "docker compose exec -T postgres pg_isready -U iotnas"
check "iot_events table exists" "docker compose exec -T postgres psql -U iotnas -d iotnas -c 'SELECT 1 FROM iot_events LIMIT 1'"
check "priority_summary view works" "docker compose exec -T postgres psql -U iotnas -d iotnas -c 'SELECT * FROM priority_summary'"
check "device_registry has seed data" "docker compose exec -T postgres psql -U iotnas -d iotnas -c 'SELECT count(*) FROM device_registry' | grep -q '[1-9]'"
echo ""

# ---- MQTT ----
echo "📡 MQTT Broker:"
check "Mosquitto port 1883 open" "timeout 3 bash -c 'echo > /dev/tcp/localhost/1883' 2>/dev/null"
echo ""

# ---- Monitoring ----
echo "📊 Monitoring:"
check "Prometheus (9090)" "curl -sf http://localhost:9090/-/ready"
check "Grafana (3000)" "curl -sf http://localhost:3000/api/health | jq -e '.database == \"ok\"'"
check "Node Exporter (9100)" "curl -sf http://localhost:9100/metrics | head -1"
echo ""

# ---- Ceph (if installed) ----
echo "💾 Ceph Cluster:"
if command -v ceph &> /dev/null; then
    check "Ceph HEALTH_OK" "ceph health | grep -q 'HEALTH_OK'"
    check "3 OSDs up" "ceph osd stat | grep -q '3 up'"
    check "Pools exist" "ceph osd pool ls | grep -q 'iot-p1-nvme'"
    check "RGW running (7480)" "curl -sf http://localhost:7480 > /dev/null"
else
    echo -e "  $WARN  Ceph not installed yet (run setup-ceph-cluster.sh)"
fi
echo ""

# ---- Functional Test ----
echo "🧪 Quick Functional Test:"
# Enqueue a test event
TEST_RESULT=$(curl -sf -X POST http://localhost:8001/enqueue \
    -H "Content-Type: application/json" \
    -d '{"event_id":"test_demo_check","event_type":"health_check","priority":3,"device_id":"demo_device","payload":{"test":true}}' 2>/dev/null)
check "Enqueue test event" "echo '$TEST_RESULT' | jq -e '.status == \"enqueued\"'"

# Dequeue the test event
DEQUEUE_RESULT=$(curl -sf http://localhost:8001/dequeue 2>/dev/null)
check "Dequeue test event" "echo '$DEQUEUE_RESULT' | jq -e '.status == \"dequeued\"'"

# Log to forensic chain
FORENSIC_RESULT=$(curl -sf -X POST http://localhost:8002/log \
    -H "Content-Type: application/json" \
    -d '{"event_id":"test_forensic","event_type":"health_check","priority":3,"device":"demo","payload":{"test":true}}' 2>/dev/null)
check "Forensic log entry" "echo '$FORENSIC_RESULT' | jq -e '.hash'"

# Verify chain
check "Forensic chain valid" "curl -sf http://localhost:8002/verify | jq -e '.valid == true'"
echo ""

# ---- Summary ----
echo "============================================"
if [ $FAILED -eq 0 ]; then
    echo -e "  ${GREEN}ALL $CHECKS CHECKS PASSED ✓${NC}"
    echo "  System is DEMO READY!"
else
    echo -e "  ${PASSED}/${CHECKS} passed, ${RED}${FAILED} failed${NC}"
    echo "  Fix failed checks before demo."
fi
echo "============================================"
echo ""

# ---- Quick Reference ----
echo "📋 Demo Quick Reference:"
echo "  Simulator:  cd ~/iot-nas/simulator && source venv/bin/activate && python simulate.py --rate 10"
echo "  P1 Burst:   python simulate.py --burst-p1 10"
echo "  Queue:      curl localhost:8001/queue/status | jq"
echo "  Inference:  curl -X POST localhost:8000/infer/sensor -H 'Content-Type: application/json' -d '{\"temp_c\":95,\"vibration\":2.0,\"pressure_psi\":140}'"
echo "  Chain:      curl localhost:8002/chain | jq"
echo "  n8n:        http://<PUBLIC_IP>:5678"
echo "  Grafana:    http://<PUBLIC_IP>:3000 (admin/iotnas2024)"
echo "  Ceph:       sudo ceph status"
echo ""

exit $FAILED
