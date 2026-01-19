# Ollama Trigger LLM Deployment

Local LLM service for real-time trigger decisions in the meeting bot.

## Quick Start

```bash
# 1. Deploy Ollama
kubectl apply -k k8s/ollama/

# 2. Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=ollama -n robert --timeout=120s

# 3. Pull the model (run once)
kubectl apply -f k8s/ollama/model-pull-job.yaml

# 4. Watch model download progress
kubectl logs -f job/ollama-pull-model -n robert

# 5. Verify model is loaded
kubectl exec -it deploy/ollama -n robert -- ollama list
```

## Models

| Model | Size | Speed (ARM64) | Recommended For |
|-------|------|---------------|-----------------|
| `qwen2:1.5b` | ~1GB | ~300-500ms | **Default** - Fast trigger decisions |
| `phi3:mini` | ~2.3GB | ~500-800ms | Better reasoning, slower |
| `qwen2:0.5b` | ~400MB | ~150-300ms | Fastest, less accurate |

To change model:
```bash
# Pull different model
kubectl exec -it deploy/ollama -n robert -- ollama pull phi3:mini

# Update meeting bot env
kubectl set env deploy/meeting-scheduler -n robert TRIGGER_MODEL=phi3:mini
```

## Integration

### From Meeting Bot (Python)

```python
from trigger import should_respond, warm_up

# At startup - warm up model
latency = warm_up()
print(f"Trigger model ready: {latency:.0f}ms")

# During meeting - check if should respond
transcript = "Alice: What do you think, AI?"
decision = should_respond(transcript)

if decision.should_respond:
    print(f"Responding (confidence: {decision.confidence:.2f})")
    # Generate response...
else:
    print(f"Staying silent (confidence: {decision.confidence:.2f})")
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OLLAMA_URL` | `http://ollama:11434` | Ollama service URL |
| `TRIGGER_MODEL` | `qwen2:1.5b` | Model for trigger decisions |
| `TRIGGER_THRESHOLD` | `0.7` | Minimum confidence to respond |

## GPU Upgrade Path

When you add a GPU node to the cluster:

### 1. Label the GPU node
```bash
kubectl label node <gpu-node> nvidia.com/gpu.present=true
```

### 2. Update deployment
Edit `k8s/ollama/deployment.yaml`:

```yaml
# Change nodeSelector
nodeSelector:
  kubernetes.io/arch: amd64
  nvidia.com/gpu.present: "true"

# Add GPU resource limit
resources:
  limits:
    nvidia.com/gpu: 1
    memory: "8Gi"
  requests:
    memory: "4Gi"

# Increase parallelism
env:
- name: OLLAMA_NUM_PARALLEL
  value: "4"
```

### 3. Use larger model
```bash
kubectl exec -it deploy/ollama -n robert -- ollama pull phi3:medium
# or for best quality:
kubectl exec -it deploy/ollama -n robert -- ollama pull llama3:8b
```

### 4. Expected GPU performance
| Model | GPU (RTX 3060) | ARM64 CPU |
|-------|----------------|-----------|
| qwen2:1.5b | ~50ms | ~400ms |
| phi3:mini | ~80ms | ~600ms |
| llama3:8b | ~150ms | N/A (too slow) |

## Troubleshooting

### Model not loading
```bash
# Check pod logs
kubectl logs deploy/ollama -n robert

# Check available memory
kubectl top pod -n robert

# Manually pull model
kubectl exec -it deploy/ollama -n robert -- ollama pull qwen2:1.5b
```

### Slow responses
```bash
# Check if model is loaded (first request loads model)
kubectl exec -it deploy/ollama -n robert -- ollama list

# Increase keep-alive to prevent unloading
kubectl set env deploy/ollama -n robert OLLAMA_KEEP_ALIVE=24h
```

### Connection refused
```bash
# Check service
kubectl get svc ollama -n robert

# Test from another pod
kubectl run -it --rm debug --image=curlimages/curl -- \
  curl http://ollama.robert.svc.cluster.local:11434/api/tags
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Meeting Bot Pod                           │
│                                                              │
│  Audio Stream ──► ASR ──► Transcript Buffer                  │
│                              │                               │
│                              ▼                               │
│                    ┌─────────────────┐                       │
│                    │ trigger.py      │                       │
│                    │ should_respond()│                       │
│                    └────────┬────────┘                       │
│                             │ HTTP POST                      │
└─────────────────────────────┼───────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              Ollama Service (ClusterIP :11434)               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                   Ollama Pod                          │   │
│  │                                                       │   │
│  │   Model: qwen2:1.5b (or phi3:mini)                   │   │
│  │   Memory: 2-4GB                                       │   │
│  │   CPU: ARM64 (or GPU when available)                 │   │
│  │                                                       │   │
│  │   /api/generate ──► LLM inference ──► 0.0-1.0 score  │   │
│  │                                                       │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  PVC: ollama-models (10Gi)                                  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```
