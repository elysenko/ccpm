#!/bin/bash
#
# schedule_setup.sh - Deploy meeting scheduler to Kubernetes
#
# This script:
# 1. Scales up PostgreSQL in the robert namespace
# 2. Builds the Docker image for the scheduler
# 3. Deploys the scheduler to Kubernetes
# 4. Verifies everything is running
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(dirname "$SCRIPT_DIR")/../k8s/scheduler"
NAMESPACE="robert"

echo "=============================================="
echo "  CCPM Meeting Scheduler Setup"
echo "=============================================="
echo ""

# Step 1: Scale up PostgreSQL
echo "📦 Step 1: Ensuring PostgreSQL is running..."
POSTGRES_REPLICAS=$(kubectl get statefulset robert-postgresql -n $NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")

if [ "$POSTGRES_REPLICAS" == "0" ]; then
    echo "   Scaling up PostgreSQL..."
    kubectl scale statefulset robert-postgresql -n $NAMESPACE --replicas=1

    echo "   Waiting for PostgreSQL to be ready..."
    kubectl rollout status statefulset/robert-postgresql -n $NAMESPACE --timeout=120s
else
    echo "   PostgreSQL already running ($POSTGRES_REPLICAS replicas)"
fi

# Wait for PostgreSQL to be accepting connections
echo "   Waiting for PostgreSQL to accept connections..."
for i in {1..30}; do
    if kubectl exec -n $NAMESPACE robert-postgresql-0 -- pg_isready -U robert -d robert &>/dev/null; then
        echo "   ✅ PostgreSQL is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "   ⚠️  PostgreSQL not ready after 30s, continuing anyway..."
    fi
    sleep 1
done

# Step 2: Build Docker image
echo ""
echo "🐳 Step 2: Building Docker image..."
cd "$SCRIPT_DIR"

# Use local registry or build for k3s
docker build -t ccpm/meeting-scheduler:latest .

# For k3s, import the image directly
echo "   Importing image to k3s..."
docker save ccpm/meeting-scheduler:latest | sudo k3s ctr images import -

echo "   ✅ Image built and imported"

# Step 3: Apply Kubernetes manifests
echo ""
echo "☸️  Step 3: Deploying to Kubernetes..."

# Apply secret
echo "   Applying secrets..."
kubectl apply -f "$K8S_DIR/secret.yaml"

# Apply deployment
echo "   Applying deployment..."
kubectl apply -f "$K8S_DIR/deployment.yaml"

# Wait for deployment
echo "   Waiting for deployment to be ready..."
kubectl rollout status deployment/meeting-scheduler -n $NAMESPACE --timeout=60s

# Step 4: Verify
echo ""
echo "✅ Step 4: Verifying deployment..."
echo ""
echo "Pods:"
kubectl get pods -n $NAMESPACE -l app=meeting-scheduler

echo ""
echo "Logs (last 20 lines):"
sleep 3  # Give it a moment to start
kubectl logs -n $NAMESPACE -l app=meeting-scheduler --tail=20 || echo "   (waiting for logs...)"

echo ""
echo "=============================================="
echo "  Setup Complete!"
echo "=============================================="
echo ""
echo "Useful commands:"
echo "  View logs:     kubectl logs -n $NAMESPACE -l app=meeting-scheduler -f"
echo "  Check status:  kubectl get pods -n $NAMESPACE -l app=meeting-scheduler"
echo "  Restart:       kubectl rollout restart deployment/meeting-scheduler -n $NAMESPACE"
echo "  Stop:          kubectl scale deployment/meeting-scheduler -n $NAMESPACE --replicas=0"
echo ""
