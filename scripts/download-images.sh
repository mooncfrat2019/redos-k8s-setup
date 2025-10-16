#!/bin/bash
set -e

# Configuration
DOWNLOAD_DIR="./files/images"
IMAGE_LIST_FILE="./scripts/image-list.txt"
mkdir -p $DOWNLOAD_DIR
mkdir -p "$(dirname "$IMAGE_LIST_FILE")"

# Default registry (can be overridden by command line argument)
REGISTRY="${1:-localhost:5000}"

echo "=== Downloading Kubernetes and Calico Docker Images ==="
echo "📦 Target registry: $REGISTRY"

K8S_VERSION="1.33.4"
PAUSE_VERSION="3.10"
CALICO_VERSION="3.27.2"
ETCD_VERSION="3.6.5-0"
COREDNS_VERSION="1.12.0"
FLANNEL_VERSION="0.27.4"
FLANNEL_CNI_VERSION="1.8.0-flannel1"
CILIUM_VERSION="1.18.2"

# Kubernetes images
K8S_IMAGES=(
    "registry.k8s.io/kube-apiserver:v${K8S_VERSION}"
    "registry.k8s.io/kube-controller-manager:v${K8S_VERSION}"
    "registry.k8s.io/kube-scheduler:v${K8S_VERSION}"
    "registry.k8s.io/kube-proxy:v${K8S_VERSION}"
    "registry.k8s.io/pause:${PAUSE_VERSION}"
    "registry.k8s.io/etcd:${ETCD_VERSION}"
    "registry.k8s.io/coredns/coredns:v${COREDNS_VERSION}"
)

FLANNEL_IMAGES=(
    "ghcr.io/flannel-io/flannel-cni-plugin:v${FLANNEL_CNI_VERSION}"
    "flannel/flannel:v${FLANNEL_VERSION}"
)

CILIUM_IMAGES=(
    "quay.io/cilium/cilium:v${CILIUM_VERSION}"
    "quay.io/cilium/cilium:v1.17.8"
    "quay.io/cilium/cilium:v1.16.15"
)

# Calico images
CALICO_IMAGES=(
    "docker.io/calico/node:v${CALICO_VERSION}"
    "docker.io/calico/cni:v${CALICO_VERSION}"
    "docker.io/calico/kube-controllers:v${CALICO_VERSION}"
    "docker.io/calico/pod2daemon-flexvol:v${CALICO_VERSION}"
    "docker.io/calico/typha:v${CALICO_VERSION}"
)

# Registry image
REGISTRY_IMAGES=(
    "registry:2"
)

# Функция для нормализации имени образа для registry
normalize_image_name() {
    local image=$1
    local registry=$2

    # Убираем префиксы репозиториев и оставляем только имя образа и тег
    local image_name=$(echo "$image" | sed 's|.*/||')

    # Если registry содержит порт, убираем протокол если есть
    local clean_registry=$(echo "$registry" | sed 's|^https?://||')

    echo "$clean_registry/$image_name"
}

# Функция для загрузки и сохранения образа
download_and_save_image() {
    local image=$1
    local filename=$(echo $image | tr '/' '_' | tr ':' '_').tar
    local registry_image=$(normalize_image_name "$image" "$REGISTRY")

    echo "🐳 Downloading image: $image"

    # Пуллим образ
    if ! docker pull $image; then
        echo "❌ Failed to pull: $image"
        return 1
    fi

    # Сохраняем образ в файл
    if docker save $image -o "$DOWNLOAD_DIR/$filename"; then
        echo "💾 Saved: $filename"
        echo "$image -> $filename -> $registry_image" >> $IMAGE_LIST_FILE
        return 0
    else
        echo "❌ Failed to save: $image"
        return 1
    fi
}

# Функция для проверки доступности Docker
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "❌ Docker is not installed"
        echo "Please install Docker first:"
        echo "  sudo apt-get update && sudo apt-get install -y docker.io"
        return 1
    fi

    if ! docker info &> /dev/null; then
        echo "❌ Docker daemon is not running"
        echo "Please start Docker: sudo systemctl start docker"
        echo "And add your user to docker group: sudo usermod -aG docker $USER"
        return 1
    fi

    return 0
}

# Функция для загрузки группы образов
download_image_group() {
    local group_name=$1
    shift
    local images=("$@")

    echo ""
    echo "📥 Downloading $group_name images..."

    local success_count=0
    local total_count=${#images[@]}

    for image in "${images[@]}"; do
        if download_and_save_image "$image"; then
            success_count=$((success_count + 1))
        else
            echo "⚠️  Skipping $image due to error"
        fi
    done

    echo "✅ $group_name: $success_count/$total_count images downloaded"
}

# Функция для создания скрипта пуша в registry
create_push_script() {
    local registry=$1

    echo ""
    echo "📝 Creating registry push script for: $registry..."

    cat > "$DOWNLOAD_DIR/push-to-registry.sh" << EOF
#!/bin/bash
set -e

TARGET_REGISTRY="\${1:-$registry}"
IMAGES_DIR="\$(cd "\$(dirname "\$0")" && pwd)"

echo "🚀 Pushing images to registry: \$TARGET_REGISTRY"

# Функция для нормализации имени образа
normalize_for_registry() {
    local image=\$1
    local registry=\$2
    local image_name=\$(echo "\$image" | sed 's|.*/||')
    local clean_registry=\$(echo "\$registry" | sed 's|^https?://||')
    echo "\$clean_registry/\$image_name"
}

push_image() {
    local image_file=\$1
    local original_image=\$(basename "\$image_file" .tar | sed 's/_/:/' | sed 's/_/\//g')
    local registry_image=\$(normalize_for_registry "\$original_image" "\$TARGET_REGISTRY")

    echo "📤 Loading: \$original_image"
    docker load -i "\$image_file"

    echo "🏷️  Tagging: \$original_image -> \$registry_image"
    docker tag "\$original_image" "\$registry_image"

    echo "📤 Pushing: \$registry_image"
    if docker push "\$registry_image"; then
        echo "✅ Successfully pushed: \$registry_image"
    else
        echo "❌ Failed to push: \$registry_image"
        return 1
    fi

    # Очищаем
    docker rmi "\$original_image" "\$registry_image" 2>/dev/null || true
}

# Проверяем доступность Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "❌ Docker daemon is not running"
    exit 1
fi

# Проверяем доступность registry
echo "🔍 Checking registry availability: \$TARGET_REGISTRY"
if ! docker pull "\$TARGET_REGISTRY/alpine:latest" 2>/dev/null; then
    echo "⚠️  Cannot access registry \$TARGET_REGISTRY"
    echo "💡 Make sure the registry is running and accessible"
fi

# Пушим все образы
echo ""
echo "📦 Starting to push images..."
FAILED_IMAGES=()
SUCCESS_COUNT=0
TOTAL_COUNT=\$(ls -1 "\$IMAGES_DIR"/*.tar 2>/dev/null | wc -l || echo 0)

for image_file in "\$IMAGES_DIR"/*.tar; do
    if [[ -f "\$image_file" ]]; then
        if push_image "\$image_file"; then
            SUCCESS_COUNT=\$((SUCCESS_COUNT + 1))
        else
            FAILED_IMAGES+=("\$(basename "\$image_file")")
        fi
        echo "---"
    fi
done

echo ""
echo "📊 Push summary:"
echo "✅ Successfully pushed: \$SUCCESS_COUNT/\$TOTAL_COUNT"

if [ \${#FAILED_IMAGES[@]} -ne 0 ]; then
    echo "❌ Failed images:"
    printf '  - %s\n' "\${FAILED_IMAGES[@]}"
    exit 1
else
    echo "🎉 All images pushed successfully to registry: \$TARGET_REGISTRY"
fi

echo ""
echo "📋 Image mapping:"
for image_file in "\$IMAGES_DIR"/*.tar; do
    if [[ -f "\$image_file" ]]; then
        local original_image=\$(basename "\$image_file" .tar | sed 's/_/:/' | sed 's/_/\//g')
        local registry_image=\$(normalize_for_registry "\$original_image" "\$TARGET_REGISTRY")
        echo "  \$original_image -> \$registry_image"
    fi
done

EOF

    chmod +x "$DOWNLOAD_DIR/push-to-registry.sh"
    echo "✅ Created push script: $DOWNLOAD_DIR/push-to-registry.sh"
}

# Основной процесс
echo "🔍 Checking Docker availability..."
if ! check_docker; then
    exit 1
fi

# Очищаем файл списка
> $IMAGE_LIST_FILE

# Загружаем образы по группам
download_image_group "Kubernetes" "${K8S_IMAGES[@]}"
download_image_group "Calico" "${CALICO_IMAGES[@]}"
download_image_group "Flannel" "${FLANNEL_IMAGES[@]}"
download_image_group "Cilium" "${CILIUM_IMAGES[@]}"
download_image_group "Registry" "${REGISTRY_IMAGES[@]}"

# Создаем скрипт для загрузки образов в указанный registry
create_push_script "$REGISTRY"

# Создаем файл с информацией об образах
echo ""
echo "📝 Creating image information file..."
cat > "$DOWNLOAD_DIR/images-info.txt" << EOF
Kubernetes Images for Version: $K8S_VERSION
Calico Version: $CALICO_VERSION
Target Registry: $REGISTRY
Download Date: $(date)

Images downloaded:
$(ls -1 "$DOWNLOAD_DIR"/*.tar 2>/dev/null | xargs -n1 basename 2>/dev/null || echo "No images")

Total images: $(ls -1 "$DOWNLOAD_DIR"/*.tar 2>/dev/null | wc -l || echo 0)

Usage:
1. Load images to Docker: docker load -i <image_file.tar>
2. Push to registry: cd $DOWNLOAD_DIR && ./push-to-registry.sh
   Or specify different registry: ./push-to-registry.sh your-registry:5000
3. Use in Kubernetes with image: $REGISTRY/image-name:tag

Image mapping:
$(cat $IMAGE_LIST_FILE 2>/dev/null || echo "No image mapping available")

Registry push examples:
  ./push-to-registry.sh                    # Use default: $REGISTRY
  ./push-to-registry.sh 192.168.1.100:5000 # Use custom registry
  ./push-to-registry.sh my-registry.local:5000
EOF

# Финальный отчет
echo ""
echo "🎉 Image download completed!"
echo "📁 Images saved to: $DOWNLOAD_DIR"

IMAGE_COUNT=$(ls -1 $DOWNLOAD_DIR/*.tar 2>/dev/null | wc -l || echo 0)
echo "📊 Total images downloaded: $IMAGE_COUNT"

echo ""
echo "📋 Image list:"
ls -la $DOWNLOAD_DIR/*.tar 2>/dev/null | awk '{print $9}' | xargs -n1 basename 2>/dev/null || echo "No images found"

echo ""
echo "🚀 Next steps:"
echo "1. Copy the images directory to your offline environment"
echo "2. Load images: docker load -i <image_file.tar>"
echo "3. Push to registry: ./push-to-registry.sh"
echo "4. Or specify different registry: ./push-to-registry.sh your-registry:5000"
echo ""
echo "📄 For more info see: $DOWNLOAD_DIR/images-info.txt"

echo ""
echo "✅ Image download process finished successfully!"
exit 0