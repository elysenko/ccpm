#!/bin/bash
set -e

echo "=============================================="
echo "  Meeting Bot Starting (non-root user)"
echo "=============================================="
echo "  User: $(whoami)"
echo "  Home: $HOME"

# Create XDG_RUNTIME_DIR (required for PulseAudio)
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Start Xvfb virtual display FIRST
echo "[1/3] Starting Xvfb on display :99..."
Xvfb :99 -screen 0 1920x1080x24 -ac &
XVFB_PID=$!
sleep 2

# Verify Xvfb is running
if kill -0 $XVFB_PID 2>/dev/null; then
    echo "      OK: Xvfb running (PID: $XVFB_PID)"
else
    echo "      ERROR: Xvfb failed to start!"
    exit 1
fi
export DISPLAY=:99

# Start PulseAudio daemon (non-root, normal mode)
echo "[2/3] Starting PulseAudio..."
pulseaudio -D \
    --exit-idle-time=-1 \
    --log-target=stderr \
    --log-level=warning

sleep 1

# Verify PulseAudio is running
if pulseaudio --check 2>/dev/null; then
    echo "      OK: PulseAudio daemon running"
else
    echo "      ERROR: PulseAudio failed to start!"
    echo "      Trying verbose start for debugging..."
    pulseaudio -D --exit-idle-time=-1 --log-level=debug 2>&1 | head -20
    sleep 2
fi

# Create virtual audio sink
echo "[3/3] Configuring virtual audio sink..."

# Load null-sink module for capturing browser audio
pactl load-module module-null-sink \
    sink_name=VirtualSpeaker \
    sink_properties=device.description="Virtual_Speaker" 2>/dev/null || echo "      (sink may already exist)"

# Set as default sink (where browser audio goes)
pactl set-default-sink VirtualSpeaker 2>/dev/null || true

# Set monitor as default source (for ffmpeg recording)
pactl set-default-source VirtualSpeaker.monitor 2>/dev/null || true

sleep 1

# Verify setup
echo ""
echo "=============================================="
echo "  Audio Stack Ready"
echo "=============================================="
echo "  DISPLAY=$DISPLAY"
echo "  XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
echo ""
echo "  Sinks:"
pactl list short sinks 2>/dev/null | sed 's/^/    /' || echo "    (unavailable)"
echo ""
echo "  Sources (for recording):"
pactl list short sources 2>/dev/null | sed 's/^/    /' || echo "    (unavailable)"
echo ""
echo "  Default sink: $(pactl get-default-sink 2>/dev/null || echo 'unknown')"
echo "  Default source: $(pactl get-default-source 2>/dev/null || echo 'unknown')"
echo "=============================================="
echo ""

# Export audio source for bot.py
export AUDIO_SOURCE="VirtualSpeaker.monitor"

# Determine which mode to run
if [ "$BOT_MODE" = "listen-only" ]; then
    echo ""
    echo "Running in LISTEN-ONLY mode (trigger testing)"
    echo "  OLLAMA_URL: ${OLLAMA_URL:-not set}"
    echo "  TRIGGER_MODEL: ${TRIGGER_MODEL:-not set}"
    echo "  VOSK_MODEL_PATH: ${VOSK_MODEL_PATH:-not set}"
    echo ""
    exec python /app/listen_only.py --url "${MEETING_URL}" "$@"
else
    echo ""
    echo "Running in FULL RECORDING mode"
    echo ""
    exec python /app/__main__.py "$@"
fi
