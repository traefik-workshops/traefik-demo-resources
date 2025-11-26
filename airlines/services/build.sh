#!/bin/bash
# Build and push airlines stateful services image

set -e

IMAGE_NAME="ghcr.io/traefik-workshops/airlines-stateful-api"
VERSION="v0.1.0"

echo "🏗️  Building Airlines Stateful Services..."
echo "Image: ${IMAGE_NAME}:${VERSION}"
echo ""

cd "$(dirname "$0")"

# Generate remaining services first
echo "📝 Generating all service entry points..."
bash generate_services.sh
echo ""

# Build Docker image
echo "🐳 Building Docker image..."
docker build -t "${IMAGE_NAME}:${VERSION}" .
docker tag "${IMAGE_NAME}:${VERSION}" "${IMAGE_NAME}:latest"
echo "✅ Build complete!"
echo ""

# Show image details
echo "📊 Image details:"
docker images | grep airlines-stateful-api
echo ""

# Ask to push
read -p "Push to registry? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🚀 Pushing to registry..."
    docker push "${IMAGE_NAME}:${VERSION}"
    docker push "${IMAGE_NAME}:latest"
    echo "✅ Pushed to registry!"
else
    echo "⏭️  Skipping push"
fi

echo ""
echo "✨ Done!"
echo ""
echo "Next steps:"
echo "1. Update helm/values.yaml:"
echo "   image:"
echo "     repository: ${IMAGE_NAME}"
echo "     tag: ${VERSION}"
echo ""
echo "2. Update each service deployment command:"
echo "   command: [\"python\", \"<service_name>_service.py\"]"
echo ""
echo "3. Deploy:"
echo "   terraform apply"
