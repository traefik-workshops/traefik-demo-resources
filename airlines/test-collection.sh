#!/bin/bash
# Test runner for the Hoppscotch collection against the transit cluster.
# Usage: ./test-collection.sh [domain]
# Example: ./test-collection.sh demo.traefik.ai
#
# Prerequisites:
#   - kubectl configured for the transit cluster
#   - npm/npx available
#   - @hoppscotch/cli installed (npm install -g @hoppscotch/cli)
#
# This script:
#   1. Extracts the rendered collection from the transit cluster configmap
#   2. Runs the hopp CLI against it
#   3. Reports results

set -euo pipefail

DOMAIN="${1:-demo.traefik.ai}"
NAMESPACE="${2:-default}"
CONFIGMAP_NAME="airlines-hoppscotch-collection"
COLLECTION_FILE="/tmp/airlines-collection.json"

echo "=== Airlines Hoppscotch Collection Test Runner ==="
echo "Domain: $DOMAIN"
echo "Namespace: $NAMESPACE"
echo ""

# Step 1: Extract collection from configmap
echo "[1/3] Extracting collection from ConfigMap '$CONFIGMAP_NAME'..."
if ! kubectl get configmap "$CONFIGMAP_NAME" -n "$NAMESPACE" -o jsonpath='{.data.collection\.json}' > "$COLLECTION_FILE" 2>/dev/null; then
    echo "ERROR: Could not extract configmap. Trying helm template render..."

    # Fallback: render via helm template
    CHART_DIR="$(dirname "$0")/helm"
    if [ -d "$CHART_DIR" ]; then
        echo "  Rendering via helm template..."
        helm template airlines "$CHART_DIR" --set global.domain="$DOMAIN" | \
            python3 -c "
import sys, yaml, json
docs = yaml.safe_load_all(sys.stdin)
for doc in docs:
    if doc and doc.get('kind') == 'ConfigMap' and doc['metadata']['name'] == '$CONFIGMAP_NAME':
        print(doc['data']['collection.json'])
        break
" > "$COLLECTION_FILE"
    else
        echo "ERROR: No chart directory found at $CHART_DIR and configmap not accessible."
        exit 1
    fi
fi

echo "  Collection saved to $COLLECTION_FILE"
echo "  Size: $(wc -c < "$COLLECTION_FILE") bytes"
echo ""

# Step 2: Validate JSON
echo "[2/3] Validating JSON structure..."
if python3 -c "import json; json.load(open('$COLLECTION_FILE'))" 2>/dev/null; then
    REQ_COUNT=$(python3 -c "
import json
def count(obj):
    c = len(obj.get('requests', []))
    for f in obj.get('folders', []): c += count(f)
    return c
data = json.load(open('$COLLECTION_FILE'))
print(count(data))
")
    echo "  Valid JSON with $REQ_COUNT requests"
else
    echo "  ERROR: Invalid JSON!"
    exit 1
fi
echo ""

# Step 3: Run tests
echo "[3/3] Running hopp CLI tests..."
echo "========================================"
npx @hoppscotch/cli test "$COLLECTION_FILE" 2>&1
EXIT_CODE=$?
echo "========================================"
echo ""

if [ $EXIT_CODE -eq 0 ]; then
    echo "ALL TESTS PASSED"
else
    echo "SOME TESTS FAILED (exit code: $EXIT_CODE)"
fi

exit $EXIT_CODE
