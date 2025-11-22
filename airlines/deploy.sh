#!/bin/bash
# Airlines Demo Deployment Script
# Usage: ./deploy.sh [domain]

DOMAIN=${1:-triple-gate.traefik.ai}
NAMESPACE="airlines"
RELEASE_NAME="airlines"

echo "✈️  Deploying Airlines Demo to $DOMAIN..."

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo "❌ Helm not found. Please install helm."
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "❌ Kubectl not found. Please install kubectl."
    exit 1
fi

# Update dependencies if any (none currently, but good practice)
# helm dependency update ./helm

# Deploy
echo "📦 Installing/Upgrading Helm Chart..."
helm upgrade --install $RELEASE_NAME ./helm \
    --namespace $NAMESPACE \
    --create-namespace \
    --set domain=$DOMAIN \
    --wait \
    --timeout 5m

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Deployment Successful!"
    echo "=================================================="
    echo "🌍 API Portal: https://portal.$DOMAIN"
    echo "✈️  Flights API: https://flights.$DOMAIN"
    echo "🎫 Ticketing Agent: (Internal MCP Service)"
    echo "=================================================="
    echo ""
    echo "🔍 Verify pods:"
    echo "kubectl get pods -n $NAMESPACE"
else
    echo "❌ Deployment Failed"
    exit 1
fi
