#!/bin/bash
#
# Setup Listen-Only Mode for Meeting Bot
# Downloads Vosk model and configures environment
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="${SCRIPT_DIR}/models"
VOSK_MODEL="vosk-model-small-en-us-0.15"
VOSK_URL="https://alphacephei.com/vosk/models/${VOSK_MODEL}.zip"

echo "=============================================="
echo "  Setup Listen-Only Meeting Bot"
echo "=============================================="

# Step 1: Create virtual environment
echo ""
echo "[1/4] Setting up Python environment..."
cd "${SCRIPT_DIR}"

if [ ! -d ".venv" ]; then
    python3 -m venv .venv
fi
source .venv/bin/activate

pip install --upgrade pip -q
pip install -r requirements.txt -q

echo "  ✅ Python dependencies installed"

# Step 2: Download Vosk model
echo ""
echo "[2/4] Checking Vosk model..."

mkdir -p "${MODEL_DIR}"

if [ -d "${MODEL_DIR}/${VOSK_MODEL}" ]; then
    echo "  ✅ Vosk model already exists"
else
    echo "  Downloading ${VOSK_MODEL} (~40MB)..."
    cd "${MODEL_DIR}"
    curl -L -o model.zip "${VOSK_URL}"
    unzip -q model.zip
    rm model.zip
    echo "  ✅ Vosk model downloaded"
fi

# Step 3: Install Playwright browsers (if needed for meeting join)
echo ""
echo "[3/4] Checking Playwright..."
if python -c "from playwright.sync_api import sync_playwright" 2>/dev/null; then
    echo "  ✅ Playwright available"
else
    echo "  Installing Playwright browsers..."
    playwright install chromium
fi

# Step 4: Check Ollama connection
echo ""
echo "[4/4] Checking Ollama trigger service..."

# Get Ollama service IP
OLLAMA_IP=$(kubectl get svc ollama -n robert -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")

if [ -n "${OLLAMA_IP}" ]; then
    export OLLAMA_URL="http://${OLLAMA_IP}:11434"
    echo "  Ollama URL: ${OLLAMA_URL}"

    if curl -s "${OLLAMA_URL}/api/tags" > /dev/null 2>&1; then
        echo "  ✅ Ollama is reachable"
        MODELS=$(curl -s "${OLLAMA_URL}/api/tags" | python3 -c "import sys,json; print([m['name'] for m in json.load(sys.stdin).get('models',[])])" 2>/dev/null || echo "[]")
        echo "  Models: ${MODELS}"
    else
        echo "  ⚠️  Ollama not responding (trigger will fail)"
    fi
else
    echo "  ⚠️  Ollama service not found in K8s"
    echo "     Deploy with: kubectl apply -k k8s/ollama/"
fi

# Done
echo ""
echo "=============================================="
echo "  Setup Complete!"
echo "=============================================="
echo ""
echo "  Environment:"
echo "    VOSK_MODEL_PATH=${MODEL_DIR}/${VOSK_MODEL}"
echo "    OLLAMA_URL=${OLLAMA_URL:-http://ollama:11434}"
echo ""
echo "  Test microphone (no meeting):"
echo "    source .venv/bin/activate"
echo "    export VOSK_MODEL_PATH=${MODEL_DIR}/${VOSK_MODEL}"
echo "    export OLLAMA_URL=${OLLAMA_URL:-http://ollama:11434}"
echo "    python listen_only.py --test"
echo ""
echo "  Join a meeting:"
echo "    python listen_only.py --url 'https://meet.google.com/xxx-yyyy-zzz'"
echo ""
echo "=============================================="

# Create env file for convenience
cat > "${SCRIPT_DIR}/.env.listen" << EOF
export VOSK_MODEL_PATH="${MODEL_DIR}/${VOSK_MODEL}"
export OLLAMA_URL="${OLLAMA_URL:-http://ollama:11434}"
export TRIGGER_MODEL="qwen2:1.5b"
export TRIGGER_THRESHOLD="0.7"
EOF

echo "  Env file created: source .env.listen"
