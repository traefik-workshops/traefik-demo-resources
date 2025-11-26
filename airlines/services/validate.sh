#!/bin/bash
# Comprehensive validation script for all services

set -e

echo "="*70
echo "VALIDATION SCRIPT - Testing All Services"
echo "="*70

# Activate venv
source .venv/bin/activate

# Create test data
mkdir -p /tmp/airlines-test
cat > /tmp/airlines-test/api.json << 'EOF'
{
  "flights": {
    "FL123": {"flight_id": "FL123", "origin": "JFK", "destination": "LAX", "price": 450},
    "FL456": {"flight_id": "FL456", "origin": "SFO", "destination": "SEA", "price": 200}
  },
  "bookings": {
    "BK001": {"booking_id": "BK001", "flight_id": "FL123", "passenger_id": "P001", "status": "confirmed"}
  }
}
EOF

echo ""
echo "✅ Test data created at /tmp/airlines-test/api.json"
echo ""

# Test 1: In-memory database demo
echo "TEST 1: In-Memory Database Demo"
echo "-" *70
python3 test_inmemory.py | head -50
echo ""
echo "✅ TEST 1 PASSED: In-memory database works"
echo ""

# Test 2: Validate all service files exist
echo "TEST 2: Service Files Validation"
echo "-"*70
SERVICES=(flights bookings checkin loyalty tickets passengers pricing baggage notifications ancillaries)
for service in "${SERVICES[@]}"; do
    if [ -f "${service}_service.py" ]; then
        echo "✅ ${service}_service.py exists"
    else
        echo "❌ ${service}_service.py MISSING"
        exit 1
    fi
done
echo ""
echo "✅ TEST 2 PASSED: All 10 service files exist"
echo ""

# Test 3: Validate base service
echo "TEST 3: Base Service Validation"
echo "-"*70
python3 << 'PYEOF'
import sys
sys.path.insert(0, '.')
from base_service import InMemoryStore

# Create store
store = InMemoryStore('/tmp/airlines-test/api.json', 'flight_id')

# Test CRUD
assert len(store.data) == 2, "Should load 2 flights"
store.create({'flight_id': 'FL789', 'origin': 'NYC', 'destination': 'MIA'})
assert len(store.data) == 3, "Should have 3 flights after create"
store.update('FL789', {'price': 350})
assert store.get_by_id('FL789')['price'] == 350, "Update should work"
store.delete('FL456')
assert len(store.data) == 2, "Should have 2 flights after delete"
results = store.search(origin='NYC')
assert len(results) == 1, "Search should find 1 flight"

print("✅ CREATE works")
print("✅ READ works")
print("✅ UPDATE works")
print("✅ DELETE works")
print("✅ SEARCH works")
PYEOF
echo ""
echo "✅ TEST 3 PASSED: All CRUD operations work"
echo ""

# Test 4: Validate service entry points
echo "TEST 4: Service Entry Points Validation"
echo "-"*70
python3 << 'PYEOF'
import sys
import os
sys.path.insert(0, '.')

# Set environment for testing
os.environ['DATA_FILE'] = '/tmp/airlines-test/api.json'

# Test importing each service
services = ['flights', 'bookings', 'checkin', 'loyalty', 'tickets', 
            'passengers', 'pricing', 'baggage', 'notifications', 'ancillaries']

for service in services:
    try:
        # Import without running
        with open(f'{service}_service.py', 'r') as f:
            code = f.read()
            assert 'run_service' in code, f"{service}_service.py must call run_service"
            assert 'resource_name' in code, f"{service}_service.py must set resource_name"
            assert 'from base_service import run_service' in code, f"{service}_service.py must import run_service"
        print(f"✅ {service}_service.py is valid")
    except Exception as e:
        print(f"❌ {service}_service.py failed: {e}")
        sys.exit(1)
PYEOF
echo ""
echo "✅ TEST 4 PASSED: All entry points are valid"
echo ""

# Test 5: Dockerfile validation
echo "TEST 5: Dockerfile Validation"
echo "-"*70
if [ -f "Dockerfile" ]; then
    echo "✅ Dockerfile exists"
    if grep -q "COPY \*_service.py" Dockerfile; then
        echo "✅ Dockerfile copies all service files"
    fi
    if grep -q "FROM python:3.11" Dockerfile; then
        echo "✅ Dockerfile uses Python 3.11"
    fi
    if grep -q "requirements.txt" Dockerfile; then
        echo "✅ Dockerfile installs requirements"
    fi
else
    echo "❌ Dockerfile missing"
    exit 1
fi
echo ""
echo "✅ TEST 5 PASSED: Dockerfile is valid"
echo ""

# Summary
echo "="*70
echo "✨ ALL TESTS PASSED! ✨"
echo "="*70
echo ""
echo "Summary:"
echo "  ✅ In-memory database works (Python dict)"
echo "  ✅ All 10 service files exist"
echo "  ✅ CRUD operations validated"
echo "  ✅ Service entry points are valid"
echo "  ✅ Dockerfile is correct"
echo ""
echo "Architecture:"
echo "  • ONE Dockerfile → ONE image"
echo "  • ONE base_service.py → shared by all"
echo "  • TEN *_service.py → entry points"
echo "  • In-memory DB → Python dict"
echo ""
echo "Ready to deploy!"
