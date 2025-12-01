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

### Health Check Configuration

The Secrets Router includes enhanced health check configurations optimized for Dapr sidecar timing:

```yaml
# Enhanced health checks addressing Dapr initialization
healthChecks:
  liveness:
    enabled: true
    path: /healthz
    initialDelaySeconds: 15
    periodSeconds: 15
  readiness:
    enabled: true
    path: /readyz
    initialDelaySeconds: 5
    periodSeconds: 5
    timeoutSeconds: 3
    failureThreshold: 6
  startupProbe:
    enabled: true
    path: /healthz
    initialDelaySeconds: 5
    periodSeconds: 5
    failureThreshold: 12  # Extended for Dapr timing issues
```

### Dynamic Service Discovery

Sample services now use dynamic endpoint configuration with the `sample-service.secretsRouterURL` helper template:

```yaml
# Automatically generates service URL: secrets-router.{namespace}.svc.cluster.local:8080
env:
  - name: SECRETS_ROUTER_URL
    value: {{ include "sample-service.secretsRouterURL" . | quote }}
  - name: TEST_NAMESPACE
    value: {{ .Release.Namespace | quote }}
```

#### Service Discovery Patterns

**Same-Namespace Access (Automatic):**
- Service name: `secrets-router` (always consistent, never includes release name)
- Short form: `secrets-router:8080` (same namespace only)
- Template helper: `{{ include "sample-service.secretsRouterURL" . }}`
- Generates FQDN: `http://secrets-router.{{ .Release.Namespace }}.svc.cluster.local:8080`

**Cross-Namespace Access (Manual):**
- Requires fully qualified domain name: `http://secrets-router.{target-namespace}.svc.cluster.local:8080`
- Current templates do not support automatic cross-namespace configuration
- See [Cross-Namespace Testing](#cross-namespace-testing) section for manual procedures

**Key Simplifications:**
- **Consistent Service Name**: Always `secrets-router` (not `{release-name}-secrets-router`)
- **Predictable URLs**: `http://secrets-router.{namespace}.svc.cluster.local:8080`
- **Template Logic Simplified**: Removed complex conditional logic for `.Values.targetNamespace`
- **Auto-Generated Environment Variables**: `SECRETS_ROUTER_URL` and `TEST_NAMESPACE` derived from `.Release.Namespace`

### Cross-Namespace Testing

The current template design prioritizes simplicity by using `.Release.Namespace` consistently. This means:

**What Works Automatically:**
- Same-namespace deployments where secrets-router and clients are deployed together
- Service discovery within a single namespace using the simplified `secrets-router` service name

**What Requires Manual Intervention:**
- Cross-namespace scenarios where secrets-router is in a different namespace than clients
- Multi-namespace testing setups

**Manual Cross-Namespace Procedure:**
1. Deploy secrets-router in namespace A: `helm install test-router ./charts/umbrella -n namespace-a`
2. Deploy sample-service separately in namespace B
3. Manually set environment variable: `SECRETS_ROUTER_URL=http://secrets-router.namespace-a.svc.cluster.local:8080`
4. Or use kubectl to patch the deployment with the correct URL

**Design Philosophy:**
The simplified template approach was chosen because:
- Most production use cases deploy services in the same namespace as secrets-router
- Cross-namespace access is an edge case that requires explicit configuration
- Removing `.Values.targetNamespace` eliminates template complexity and potential misconfiguration
- The predictable `secrets-router` service name makes manual cross-namespace configuration straightforward

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

### Common Issues and Solutions

#### Dapr Sidecar Timing Issues
**Symptoms**: Pods restart during startup, readiness probe failures
**Solutions**: Enhanced health checks now use startupProbe with 12 failure thresholds (60s startup window) and faster readiness delays (5s instead of 30s).

#### Curl Command Issues
**Symptoms**: Bash scripts failing with HTTP request errors
**Solutions**: Fixed quote escaping in bash scripts - changed from double quotes to single quotes around curl format strings: `curl -s -w '\n%{http_code}'`

#### Component Naming Conflicts
**Symptoms**: "kubernetes already exists" errors in Dapr logs
**Solutions**: Properly disable AWS components in test configurations and ensure unique component names.

#### Cross-Namespace Service Discovery
**Symptoms**: Sample services cannot connect to secrets router in a different namespace
**Solutions**: 
- **Same-namespace**: Works automatically using `secrets-router:8080` or the template helper
- **Cross-namespace**: Manual configuration required - use FQDN format: `http://secrets-router.{target-namespace}.svc.cluster.local:8080`
- **Service Name**: Always `secrets-router` (never includes release name like `{release-name}-secrets-router`)
- **Template Design**: Current templates use `.Release.Namespace` only; cross-namespace requires manual env var override

#### Sample Service Restart Policy
**Symptoms**: CrashLoopBackOff after successful completion
**Solutions**: Sample test runners now use `restartPolicy: Never` instead of "Always" for one-time test scenarios.

#### Image Pull Policy for Testing
**Best Practice**: Use `image.pullPolicy: Never` in override files for local development to ensure locally built images are used.

For comprehensive troubleshooting procedures, see [TESTING_WORKFLOW.md](./TESTING_WORKFLOW.md) and [DEVELOPER.md](./DEVELOPER.md#troubleshooting).

## License

See [LICENSE](./LICENSE) file.
