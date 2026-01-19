#!/bin/bash
#
# Deploy Ollama Trigger LLM to K3s
# Uses official Ollama image - no build needed
#
set -e

# Configuration
NAMESPACE="robert"
MODEL="${1:-qwen2:1.5b}"  # Default model, override with: ./deploy.sh phi3:mini

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=============================================="
echo "  Deploying Ollama Trigger LLM"
echo "=============================================="
echo "  Namespace:  ${NAMESPACE}"
echo "  Model:      ${MODEL}"
echo "=============================================="

# Step 1: Apply manifests
echo ""
echo "[1/5] Applying K8s manifests..."
kubectl apply -f "${SCRIPT_DIR}/pvc.yaml"
kubectl apply -f "${SCRIPT_DIR}/deployment.yaml"
kubectl apply -f "${SCRIPT_DIR}/service.yaml"

# Step 2: Wait for pod to be ready
echo ""
echo "[2/5] Waiting for Ollama pod to be ready..."
kubectl wait --for=condition=ready pod -l app=ollama -n "${NAMESPACE}" --timeout=180s

# Step 3: Pull the model
echo ""
echo "[3/5] Pulling model: ${MODEL}"
echo "      (This may take a few minutes on first run...)"

# Use kubectl exec to pull model
kubectl exec -it deploy/ollama -n "${NAMESPACE}" -- ollama pull "${MODEL}" || {
    echo "  Retrying model pull..."
    sleep 5
    kubectl exec -it deploy/ollama -n "${NAMESPACE}" -- ollama pull "${MODEL}"
}

# Step 4: Verify model is loaded
echo ""
echo "[4/5] Verifying model..."
kubectl exec deploy/ollama -n "${NAMESPACE}" -- ollama list

# Step 5: Test inference
echo ""
echo "[5/5] Testing inference (should respond in <2s on ARM64)..."
START=$(date +%s%N)
RESPONSE=$(kubectl exec deploy/ollama -n "${NAMESPACE}" -- \
    ollama run "${MODEL}" "Reply with just the word: working" 2>/dev/null | head -1)
END=$(date +%s%N)
LATENCY=$(( (END - START) / 1000000 ))

echo ""
echo "=============================================="
echo "  Deployment Complete"
echo "=============================================="
echo "  Model:    ${MODEL}"
echo "  Response: ${RESPONSE}"
echo "  Latency:  ${LATENCY}ms"
echo ""
echo "  Service URL (internal): http://ollama.${NAMESPACE}.svc.cluster.local:11434"
echo ""
echo "  Test from another pod:"
echo "    kubectl run -it --rm test --image=curlimages/curl -- \\"
echo "      curl -X POST http://ollama:11434/api/generate \\"
echo "      -d '{\"model\":\"${MODEL}\",\"prompt\":\"Hello\",\"stream\":false}'"
echo ""
echo "  To use in meeting-bot, set env:"
echo "    OLLAMA_URL=http://ollama:11434"
echo "    TRIGGER_MODEL=${MODEL}"
echo "=============================================="
