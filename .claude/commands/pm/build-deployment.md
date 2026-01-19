# Build Deployment

Build container images and push to registry using nerdctl/containerd.

## Usage
```
/pm:build-deployment <scope-name>
```

## Quick Check

```bash
test -f .claude/scopes/$ARGUMENTS.md || echo "❌ Scope not found: $ARGUMENTS"
```

## Instructions

### 1. Load Configuration

Read from `.claude/scopes/$ARGUMENTS.md`:

```yaml
deploy:
  enabled: true
  work_dir: /path/to/project
  registry: ubuntu.desmana-truck.ts.net:30500
  images:
    - name: app-frontend
      dockerfile: frontend/Dockerfile
      context: ./frontend
    - name: app-backend
      dockerfile: backend/Dockerfile
      context: ./backend
```

**Required fields:**
- `deploy.registry` - Where to push images
- `deploy.images` - List of images to build

**If images not specified**, auto-detect from project structure:
```bash
# Check for common Dockerfile locations
ls {work_dir}/Dockerfile           # Single image, use project name
ls {work_dir}/frontend/Dockerfile  # Frontend image
ls {work_dir}/backend/Dockerfile   # Backend image
```

### 2. Build Each Image

For each image in the config:

```bash
cd {work_dir}

# Build with nerdctl
sudo nerdctl build \
  -t {registry}/{name}:latest \
  -f {dockerfile} \
  {context}

# Check exit code
if [ $? -ne 0 ]; then
  echo "❌ Build failed: {name}"
  exit 1
fi

echo "✅ Built: {registry}/{name}:latest"
```

### 3. Push Each Image

```bash
# Push with insecure-registry flag (HTTP registry)
sudo nerdctl push --insecure-registry {registry}/{name}:latest

if [ $? -ne 0 ]; then
  echo "❌ Push failed: {name}"
  exit 1
fi

echo "✅ Pushed: {registry}/{name}:latest"
```

### 4. Verify Images in Registry

```bash
# Check registry catalog
curl -s http://{registry}/v2/_catalog | grep {name}
```

## Output

### Success
```
✅ Build complete for {scope}

Images pushed to {registry}:
  - {name-1}:latest
  - {name-2}:latest

Registry catalog: {count} images
```

### Failure
```
❌ Build failed: {scope}

Failed image: {name}
Exit code: {code}

Last 20 lines:
{build output}

To retry: /pm:build-deployment {scope}
```

## Auto-Detection Rules

When `deploy.images` is not specified:

| Files Found | Images Created |
|-------------|----------------|
| `Dockerfile` | `{project-name}:latest` |
| `frontend/Dockerfile` | `{project-name}-frontend:latest` |
| `backend/Dockerfile` | `{project-name}-backend:latest` |
| `services/*/Dockerfile` | `{project-name}-{service}:latest` |

## Environment Variables

The command sets these before building:

```bash
export REGISTRY="{registry}"
export TAG="latest"
export BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

## Notes

- Uses nerdctl (not docker) for builds
- Uses buildkit via systemd service
- Always uses `--insecure-registry` for push (HTTP registry)
- Images are tagged `:latest` (configurable via TAG env var)
- This command only builds/pushes - use `/pm:deploy` for K8s deployment
- Can be called standalone or by `/pm:deploy`
