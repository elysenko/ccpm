#!/bin/bash
#
# Meeting Bot Deploy Script
# Builds meeting-bot image and optionally tests with a real meeting
#
set -e

# Configuration
REGISTRY="ubuntu.desmana-truck.ts.net:30500"
NAMESPACE="robert"
BUILD_DIR="/home/ubuntu/ccpm/scripts/meeting-bot"
APP="meeting-bot"

# Parse arguments
TEST_URL=""
BOT_MODE="listen-only"  # Default to listen-only for testing

while [[ $# -gt 0 ]]; do
    case $1 in
        --test)
            TEST_URL="$2"
            shift 2
            ;;
        --mode)
            BOT_MODE="$2"
            shift 2
            ;;
        meeting-bot|scheduler)
            # Legacy support - just build meeting-bot
            shift
            ;;
        *)
            echo "Usage: $0 [--test <meeting-url>] [--mode <listen-only|full>]"
            echo ""
            echo "Options:"
            echo "  --test URL    After building, spawn a job to join this meeting"
            echo "  --mode MODE   Bot mode: listen-only (default) or full"
            echo ""
            echo "Examples:"
            echo "  $0                                    # Just build"
            echo "  $0 --test https://meet.google.com/xxx # Build and test"
            exit 1
            ;;
    esac
done

# Generate unique tag using timestamp
TAG="v$(date +%Y%m%d-%H%M%S)"
IMAGE="${REGISTRY}/${APP}:${TAG}"

echo "=============================================="
echo "  Building ${APP}"
echo "=============================================="
echo "  Image:      ${IMAGE}"
echo "  Namespace:  ${NAMESPACE}"
if [ -n "${TEST_URL}" ]; then
    echo "  Test URL:   ${TEST_URL}"
    echo "  Mode:       ${BOT_MODE}"
fi
echo "=============================================="

# Step 1: Build with no cache
echo ""
echo "[1/4] Building image..."
cd "${BUILD_DIR}"
sudo nerdctl build --no-cache -t "${IMAGE}" . 2>&1 | tail -10

# Step 2: Export from nerdctl and import to k3s containerd
echo ""
echo "[2/4] Importing to k3s containerd..."
sudo nerdctl save "${IMAGE}" | sudo k3s ctr images import -

# Step 3: Verify import
echo ""
echo "[3/4] Verifying import..."
if sudo k3s ctr images list | grep -q "${TAG}"; then
    echo "  ✅ Image found in k3s containerd"
else
    echo "  ❌ Image not found in k3s containerd!"
    exit 1
fi

# Step 4: Tag as latest
echo ""
echo "[4/4] Tagging as latest..."
sudo nerdctl tag "${IMAGE}" "${REGISTRY}/${APP}:latest"
sudo nerdctl save "${REGISTRY}/${APP}:latest" | sudo k3s ctr images import -

echo ""
echo "=============================================="
echo "  Build Complete"
echo "=============================================="
echo "  Image: ${IMAGE}"
echo "  Also:  ${REGISTRY}/${APP}:latest"
echo "=============================================="

# Optionally run test job
if [ -n "${TEST_URL}" ]; then
    echo ""
    echo "Spawning test job..."

    # Generate job name from timestamp
    JOB_NAME="meeting-bot-test-$(date +%H%M%S)"

    # Create job YAML
    cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${NAMESPACE}
spec:
  ttlSecondsAfterFinished: 3600
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: bot
        image: ${IMAGE}
        imagePullPolicy: IfNotPresent
        env:
        - name: MEETING_URL
          value: "${TEST_URL}"
        - name: BOT_MODE
          value: "${BOT_MODE}"
        - name: OLLAMA_URL
          value: "http://ollama:11434"
        - name: TRIGGER_MODEL
          value: "phi3:mini"
        - name: VOSK_MODEL_PATH
          value: "/app/models/vosk-model-small-en-us-0.15"
        resources:
          requests:
            memory: "2Gi"
            cpu: "1"
          limits:
            memory: "4Gi"
            cpu: "2"
        securityContext:
          capabilities:
            add: ["SYS_ADMIN"]
        volumeMounts:
        - name: dshm
          mountPath: /dev/shm
      volumes:
      - name: dshm
        emptyDir:
          medium: Memory
          sizeLimit: "2Gi"
      nodeSelector:
        kubernetes.io/arch: arm64
EOF

    echo ""
    echo "  Job: ${JOB_NAME}"
    echo "  URL: ${TEST_URL}"
    echo "  Mode: ${BOT_MODE}"
    echo ""
    echo "  Watch logs with:"
    echo "    kubectl logs -f job/${JOB_NAME} -n ${NAMESPACE}"
    echo ""
    echo "  Delete job with:"
    echo "    kubectl delete job ${JOB_NAME} -n ${NAMESPACE}"
fi
