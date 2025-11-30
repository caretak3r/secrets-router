# Kubernetes Secrets Broker

A Dapr-based secrets broker service that provides a simple HTTP API for applications to fetch secrets from Kubernetes Secrets and AWS Secrets Manager.

## Overview

The Secrets Broker is deployed as an **umbrella Helm chart** that includes:
- **Dapr Control Plane**: Provides mTLS and component abstraction
- **Secrets Router Service**: HTTP API service for fetching secrets
- **Dapr Components**: Kubernetes Secrets and AWS Secrets Manager integrations

## Key Features

- ✅ **Namespace-Scoped**: All secrets are namespace-scoped (no cluster-wide secrets)
- ✅ **Auto-Decoding**: Kubernetes secrets automatically decoded (base64 → plain text)
- ✅ **Priority Resolution**: Tries Kubernetes Secrets first, then AWS Secrets Manager
- ✅ **Path-Based AWS**: Configurable path prefix for AWS Secrets Manager
- ✅ **Simple API**: Developer-friendly HTTP API
- ✅ **mTLS**: Automatic mTLS via Dapr Sentry
- ✅ **Umbrella Chart**: Single Helm chart installs everything

## Quick Start

### Control Plane Umbrella Chart

```bash
# Install the control-plane-umbrella chart (includes Dapr, secrets-router, sample-service)
helm upgrade --install control-plane ./charts/umbrella \
  --namespace production \
  --create-namespace \
  -f override.yaml
```

### Override Configuration

Create `override.yaml` to customize the installation:

```yaml
# override.yaml - Minimal overrides for your environment
secrets-router:
  secretStores:
    aws:
      enabled: false  # Disable AWS for K8s-only testing
    stores:
      kubernetes-secrets:
        namespaces:
          - production
          - shared-services
  image:
    pullPolicy: Never  # Use local images for testing

sample-service:
  enabled: true  # Enable sample clients for testing
  clients:
    python:
      enabled: true
      env:
        SECRETS_ROUTER_URL: "http://control-plane-secrets-router.production.svc.cluster.local:8080"
    node:
      enabled: false  # Disable if not needed
    bash:
      enabled: false  # Disable if not needed

# Note: Dapr control plane deploys to dapr-system namespace automatically
dapr:
  enabled: true
```

### Deploy Dapr Components (Generated Automatically)

The umbrella chart now generates Dapr Component resources automatically from Helm values via `secrets-components.yaml` template. No manual component deployment is required.

```bash
# Components are automatically created in the release namespace
kubectl get components -n production
```

### 3. Use in Your Application

```python
import requests

# Get secret value (always returns decoded value)
response = requests.get(
    "http://secrets-router:8080/secrets/database-credentials/password",
    params={"namespace": "production"}
)
secret_value = response.json()["value"]
```

## Architecture

```
Application → Secrets Router → Dapr Sidecar → Dapr Components → Backend Stores
```

- **Applications** make HTTP requests to Secrets Router service
- **Secrets Router** queries Dapr sidecar for secrets
- **Dapr Sidecar** routes to appropriate component (K8s or AWS)
- **Components** fetch from backend stores
- **Auto-decoding** happens transparently for K8s secrets

The project deploys as a **control-plane-umbrella Helm chart** that includes:
- **Dapr Control Plane**: Provides mTLS and component abstraction
- **Secrets Router Service**: HTTP API service for fetching secrets
- **Sample Services**: Optional client applications for testing
- **Dapr Components**: Kubernetes Secrets and AWS Secrets Manager integrations

## Key Deployment Configuration

### Helm Chart Structure
```
control-plane-umbrella (umbrella chart)
├── dapr (dependency)
│   └── Dapr control plane components
├── secrets-router (dependency)
│   ├── secrets-router service deployment
│   └── secrets-components.yaml (generates Dapr Component resources)
└── sample-service (dependency, optional for testing)
    ├── Python client
    ├── Node.js client
    └── Bash client
```

### Health Check Configuration
The Secrets Router includes enhanced health check configurations:
- **Liveness Probe**: `/healthz` endpoint with 30s initial delay
- **Readiness Probe**: `/readyz` endpoint with 30s initial delay  
- **Startup Probe**: `/healthz` with 10s initial delay and 30 failure threshold
  - Addresses Dapr timing issues during pod startup
  - Ensures service has adequate time to establish Dapr sidecar connection

### Image Pull Policies
- **secrets-router**: `Always` (production) or `Never` (local testing)
- **sample-services**: `Never` for local development/testing

### Restart Policy Configuration
- **secrets-router**: `Always` (standard for Deployment resources)
- **sample-services**: Configurable via Helm values (default: `Always`)

See [ARCHITECTURE.md](./ARCHITECTURE.md) for detailed diagrams and deployment patterns.

## Documentation

- **[Developer Guide](./DEVELOPER_GUIDE.md)**: How to consume secrets in your applications
- **[Architecture](./ARCHITECTURE.md)**: Architecture diagrams and design decisions
- **[ADR](./ADR.md)**: Architecture Decision Record
- **[Dapr Integration](./DAPR_INTEGRATION.md)**: Dapr component integration details
- **[Deployment Guide](./DEPLOYMENT.md)**: Step-by-step deployment instructions

## API Reference

### Get Secret

```
GET /secrets/{secret_name}/{secret_key}?namespace={namespace}
```

**Parameters:**
- `secret_name` (path, required): Name of the secret
- `secret_key` (path, required): Key within the secret
- `namespace` (query, required): Kubernetes namespace where secret is stored

**Response:**
```json
{
  "backend": "kubernetes-secrets",
  "secret_name": "database-credentials",
  "secret_key": "password",
  "value": "mypassword123"
}
```

**Note**: All secret values are automatically decoded and returned as plain text. Kubernetes secrets (base64 encoded) are decoded automatically.

### Health Checks

```
GET /healthz  # Liveness probe - returns HTTP 200 if service is running
GET /readyz   # Readiness probe - returns HTTP 200 if ready to receive traffic
```

**Health Check Responses:**

`/healthz` (HTTP 200):
```json
{
  "status": "healthy",
  "service": "secrets-router",
  "version": "1.0.0"
}
```

`/readyz` (HTTP 200 when ready, HTTP 503 when not ready):

When ready (HTTP 200):
```json
{
  "status": "ready",
  "service": "secrets-router",
  "dapr_sidecar": "connected",
  "version": "1.0.0"
}
```

When not ready (HTTP 503):
```json
{
  "status": "not_ready",
  "service": "secrets-router",
  "dapr_sidecar": "disconnected",
  "error": "Cannot connect to Dapr sidecar"
}
```

The `/readyz` endpoint checks connectivity to the Dapr sidecar and returns HTTP 503 if the sidecar is not reachable or not healthy. This ensures the service only receives traffic when it can actually process requests.

## Configuration

### Umbrella Chart Values

```yaml
global:
  namespace: production  # Your application namespace

secrets-router:
  env:
    SECRET_STORE_PRIORITY: "kubernetes-secrets,aws-secrets-manager"
  # Optional: Configure AWS secret paths
  # awsSecretPaths:
  #   database-credentials: "/app/secrets/production/database-credentials"
```

### AWS IRSA Configuration

If using AWS Secrets Manager:

```yaml
secrets-router:
  serviceAccount:
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/secrets-router-role
```

## Secret Storage

### Kubernetes Secrets

- **Location**: Same namespace as your application
- **Format**: `{namespace}/{secret-name}`
- **Auto-decoding**: Yes (base64 → plain text)

### AWS Secrets Manager

- **Location**: AWS Secrets Manager
- **Format**: Full paths configured in Helm chart values, or simple names
- **Configuration**: Secret paths configured in `values.yaml` (e.g., `database-credentials: "/app/secrets/production/database-credentials"`)
- **Auto-decoding**: No (already decoded)

## Examples

See [DEVELOPER_GUIDE.md](./DEVELOPER_GUIDE.md) for code examples in:
- Python
- Go
- Node.js/TypeScript

## Project Structure

```
k8s-secrets-broker/
├── charts/
│   ├── umbrella/          # Umbrella chart (Dapr + Secrets Router + Sample Service)
│   ├── secrets-router/    # Secrets Router service chart
│   └── sample-service/    # Sample client applications chart
├── secrets-router/        # Python service implementation
├── containers/            # Sample client Dockerfiles
│   ├── sample-python/     # Python client
│   ├── sample-node/       # Node.js client
│   └── sample-bash/       # Bash client
├── testing/               # Test scenarios and override files
│   ├── 1/                 # Test 1: Basic functionality
│   ├── 2/                 # Test 2: Multi-namespace access
│   └── 3/                 # Test 3: AWS integration
├── scripts/                # Build and deployment scripts
└── docs/                   # Documentation (ADR.md, ARCHITECTURE.md, etc.)
```

## Building and Testing

### Container Builds

The project includes both the secrets-router service and sample client containers:

```bash
# Build secrets-router service
docker build -t secrets-router:latest -f secrets-router/Dockerfile secrets-router/

# Build sample client containers (for testing)
docker build -t sample-python:latest -f containers/sample-python/Dockerfile containers/sample-python/
docker build -t sample-node:latest -f containers/sample-node/Dockerfile containers/sample-node/
docker build -t sample-bash:latest -f containers/sample-bash/Dockerfile containers/sample-bash/

# Or use the Makefile
make build IMAGE_TAG=latest
```

### Helm Chart Structure

The project uses an umbrella chart with dependencies:

```
charts/
├── umbrella/          # Main deployment chart with dependencies
│   ├── Chart.yaml     # Dependencies on dapr, secrets-router, sample-service
│   ├── values.yaml    # High-level enable/disable flags
│   └── Chart.lock     # Pinned dependency versions
├── secrets-router/    # Secrets router service chart
│   ├── values.yaml    # Default configurations
│   └── templates/     # Kubernetes manifests
└── sample-service/    # Sample client applications chart
    ├── values.yaml    # Client configurations
    └── templates/     # Pod templates for Python/Node/Bash clients
```

### Test Infrastructure

The project includes comprehensive testing workflows with automated test orchestration:

1. **Test Scenarios**: Located in `testing/N/` directories with minimal `override.yaml` files
2. **Container Builds**: Automated builds for secrets-router and sample services
3. **Helm Dependencies**: Automatically managed via `helm dependency build`
4. **Namespace Isolation**: Each test runs in isolated namespaces
5. **Health Validation**: Comprehensive health check validation with startupProbe support

```bash
# Run tests using the test orchestrator approach
# See TESTING_WORKFLOW.md for complete procedures
```

## Troubleshooting

See [DEVELOPER_GUIDE.md](./DEVELOPER_GUIDE.md#troubleshooting) for troubleshooting tips.

## License

See [LICENSE](./LICENSE) file.
