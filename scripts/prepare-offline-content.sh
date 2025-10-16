#!/bin/bash
set -e

echo "=== Preparing Complete Offline Content for Kubernetes ==="

# Configuration
DOWNLOAD_DIR="./files"
PACKAGES_DIR="$DOWNLOAD_DIR/packages"
IMAGES_DIR="$DOWNLOAD_DIR/images"
REGISTRY="${1:-localhost:5000}"
# Создаем директории
mkdir -p $PACKAGES_DIR
mkdir -p $IMAGES_DIR

# Загружаем образы
echo ""
echo "=== DOWNLOADING DOCKER IMAGES ==="
./scripts/download-images.sh ${REGISTRY}
IMAGE_COUNT=$(find $IMAGES_DIR -name "*.tar" 2>/dev/null | wc -l || echo 0)
echo "🐳 Images downloaded: $IMAGE_COUNT"

# Создаем архив
echo ""
echo "=== CREATING OFFLINE BUNDLE ==="
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BUNDLE_NAME="k8s-offline-bundle-${TIMESTAMP}.tar.gz"

tar -czf $BUNDLE_NAME \
    ./files/ \
    ./scripts/ \
    ./inventory/ \
    ./group_vars/ \
    ./roles/ \
    ./site.yml \
    ./ansible.cfg 2>/dev/null || true

# Копируем как основной бандл
cp "$BUNDLE_NAME" "./files/k8s-offline-bundle.tar.gz" 2>/dev/null || true

echo ""
echo "🎉 Offline preparation completed!"
echo "📦 Bundle: $BUNDLE_NAME"
echo "📊 Summary: $PACKAGE_COUNT packages, $IMAGE_COUNT images"

if [ $IMAGE_COUNT -gt 0 ]; then
    echo "🚀 Ready for deployment!"
else
    echo "⚠️  Some components may be missing, but we can proceed"
fi