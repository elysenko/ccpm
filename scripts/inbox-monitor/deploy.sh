#!/bin/bash
#
# Reliable K3s Deploy Script
# Handles the nerdctl -> k3s containerd image import properly
#
set -e

# Configuration
REGISTRY="ubuntu.desmana-truck.ts.net:30500"
NAMESPACE="robert"

# Determine what to build based on current directory or argument
if [[ "$1" == "meeting-bot" ]] || [[ "$(basename $(pwd))" == "meeting-bot" ]]; then
    APP="meeting-bot"
    DEPLOYMENT="meeting-scheduler"  # The scheduler spawns meeting-bot jobs
    CONTAINER="scheduler"
    BUILD_DIR="/home/ubuntu/ccpm/scripts/meeting-bot"
elif [[ "$1" == "scheduler" ]] || [[ "$(basename $(pwd))" == "inbox-monitor" ]]; then
    APP="meeting-scheduler"
    DEPLOYMENT="meeting-scheduler"
    CONTAINER="scheduler"
    BUILD_DIR="/home/ubuntu/ccpm/scripts/inbox-monitor"
else
    echo "Usage: $0 [meeting-bot|scheduler]"
    echo "  Or run from the inbox-monitor or meeting-bot directory"
    exit 1
fi

# Generate unique tag using timestamp
TAG="v$(date +%Y%m%d-%H%M%S)"
IMAGE="${REGISTRY}/${APP}:${TAG}"

echo "=============================================="
echo "  Deploying ${APP}"
echo "=============================================="
echo "  Image:      ${IMAGE}"
echo "  Deployment: ${DEPLOYMENT}"
echo "  Namespace:  ${NAMESPACE}"
echo "=============================================="

# Step 1: Build with no cache
echo ""
echo "[1/5] Building image..."
cd "${BUILD_DIR}"
sudo nerdctl build --no-cache -t "${IMAGE}" . 2>&1 | tail -10

# Step 2: Export from nerdctl and import to k3s containerd
echo ""
echo "[2/5] Importing to k3s containerd..."
sudo nerdctl save "${IMAGE}" | sudo k3s ctr images import -

# Step 3: Verify import
echo ""
echo "[3/5] Verifying import..."
if sudo k3s ctr images list | grep -q "${TAG}"; then
    echo "  ✅ Image found in k3s containerd"
else
    echo "  ❌ Image not found in k3s containerd!"
    exit 1
fi

# Step 4: Update deployment
echo ""
echo "[4/5] Updating deployment..."

# First ensure imagePullPolicy is IfNotPresent (since we're importing directly)
kubectl patch deployment "${DEPLOYMENT}" -n "${NAMESPACE}" \
    -p "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"${CONTAINER}\",\"imagePullPolicy\":\"IfNotPresent\"}]}}}}" \
    2>/dev/null || true

# Update the image
kubectl set image "deployment/${DEPLOYMENT}" "${CONTAINER}=${IMAGE}" -n "${NAMESPACE}"

# Step 5: Wait for rollout
echo ""
echo "[5/5] Waiting for rollout..."
kubectl rollout status "deployment/${DEPLOYMENT}" -n "${NAMESPACE}" --timeout=120s

# Verify
echo ""
echo "=============================================="
echo "  Deployment Complete"
echo "=============================================="
RUNNING_IMAGE=$(kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "  Running: ${RUNNING_IMAGE}"
echo ""
echo "  Logs:"
kubectl logs "deployment/${DEPLOYMENT}" -n "${NAMESPACE}" 2>&1 | head -20
echo "=============================================="
