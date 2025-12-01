# Kubernetes Secrets Broker

A Dapr-based secrets broker service that provides a simple HTTP API for applications to fetch secrets from Kubernetes Secrets and AWS Secrets Manager.

## Architecture Overview

The Kubernetes Secrets Broker acts as a centralized secret management layer that integrates with Dapr to provide seamless secret access for applications running in Kubernetes clusters.

```mermaid
graph TB
    subgraph "Kubernetes Cluster"
        subgraph "Application Namespace"
            App1[Application 1<br/>Python Service]
            App2[Application 2<br/>Node.js Service]
            App3[Application 3<br/>Bash Service]
        end
        
        subgraph "Control Plane Namespace"
            SR[Secrets Router<br/>HTTP API Service]
            DS[Dapr Sidecar<br/>mTLS + Service Discovery]
            DC[Dapr Control Plane<br/>Sentry + Components]
        end
        
        subgraph "Secret Storage"
            K8S[Kubernetes Secrets<br/>Namespace-scoped]
            AWS[AWS Secrets Manager<br/>Cloud Storage]
        end
    end
    
    classDef app fill:#e1f5fe
    classDef router fill:#f3e5f5
    classDef dapr fill:#e8f5e8
    classDef storage fill:#fff3e0
    
    class App1,App2,App3 app
    class SR router
    class DS,DC dapr
    class K8S,AWS storage
    
    App1 -.->|"1. HTTP Request<br/>GET /secrets/{name}/{key}"| SR
    App2 -.->|"1. HTTP Request<br/>GET /secrets/{name}/{key}"| SR  
    App3 -.->|"1. HTTP Request<br/>GET /secrets/{name}/{key}"| SR
    
    SR -->|"2. Dapr Invoke<br/>GET /secret/{store}/{name}"| DS
    DS -->|"3. Component Lookup<br/>kubernetes-secrets<br/>aws-secrets-manager"| DC
    
    DC -->|"4a. Fetch<br/>Namespace-scoped"| K8S
    DC -->|"4b. Fetch<br/>Cloud storage"| AWS
    
    K8S -->|"5a. Return<br/>Auto-decoded"| DS
    AWS -->|"5b. Return<br/>JSON payload"| DS
    
    DS -->|"6. Response<br/>Plain text"| SR
    SR -->|"7. HTTP Response<br/>JSON with secret value"| App1
    SR -->|"7. HTTP Response<br/>JSON with secret value"| App2
    SR -->|"7. HTTP Response<br/>JSON with secret value"| App3
```

## Service Flow

The Secrets Broker follows a simple 7-step flow for secret retrieval:

1. **Application Request** - Applications make HTTP requests to the Secrets Router service
2. **Dapr Invoke** - Secrets Router uses Dapr's secret management API via the sidecar
3. **Component Resolution** - Dapr resolves which secret store component to use (Kubernetes or AWS)
4. **Backend Access** - Dapr fetches the secret from the configured backend store
5. **Data Return** - Backend returns secret data (auto-decoded for K8s, JSON for AWS)
6. **Sidecar Response** - Dapr sidecar returns the secret to Secrets Router
7. **HTTP Response** - Secrets Router returns a clean JSON response to the application

## Key Benefits

### 🔒 **Secure by Design**
- **Namespace Isolation**: All secrets are scoped to specific namespaces
- **mTLS Security**: Automatic mutual TLS via Dapr Sentry
- **No Secret Exposure**: Secrets never appear as environment variables

### 🚀 **Developer-Friendly**
- **Simple HTTP API**: Standard REST endpoints for secret access  
- **Auto-Decoding**: Kubernetes secrets automatically decoded from base64
- **Multi-Language**: Works with any HTTP-capable programming language

### ⚡ **Production-Ready**
- **High Availability**: Dapr provides resilience and failover
- **Multi-Backend**: Support for both Kubernetes Secrets and AWS Secrets Manager
- **Umbrella Chart**: Single Helm deployment with all dependencies

### 🔧 **Operationally Simple**
- **Zero Configuration**: Same-namespace deployments work out of the box
- **Cross-Namespace**: Manual configuration supported for complex scenarios
- **Health Monitoring**: Built-in health checks and readiness probes

## Quick Start

```bash
# Deploy the complete secrets broker (includes Dapr control plane)
helm upgrade secrets-broker ./charts/umbrella \
  --namespace production \
  --create-namespace

# Access secrets from any application
curl "http://secrets-router.production.svc.cluster.local:8080/secrets/database-credentials/password?namespace=production"
```

## Deployment

The Secrets Broker is deployed as an **umbrella Helm chart** that bundles:
- **Dapr Control Plane**: mTLS security, service discovery, and component management
- **Secrets Router Service**: HTTP API layer for secret access
- **Sample Services**: Optional client applications for testing and validation

```bash
# Install with default configuration
helm upgrade secrets-broker ./charts/umbrella \
  --namespace production \
  --create-namespace

# Install with custom configuration
helm upgrade secrets-broker ./charts/umbrella \
  --namespace production \
  --create-namespace \
  -f override.yaml
```

### Override Configuration

Customize your deployment by creating an `override.yaml` file:

```yaml
# Production configuration example
secrets-router:
  secretStores:
    aws:
      enabled: true  # Enable AWS Secrets Manager
  image:
    pullPolicy: Always  # Production setting

# Configure sample services with their required secrets
sample-service-python:
  secrets:
    rds-credentials: "production-db-credentials"    # Kubernetes secret name
    api-keys: "/aws/production/api-keys"              # AWS Secrets Manager path

sample-service-node:
  secrets:
    rds-credentials: "production-db-credentials"
    redis-password: "redis-cluster-prod"

sample-service-bash:
  secrets:
    rds-credentials: "production-db-credentials"
    shell-password: "/ops/shell/secrets"
```

## Application Integration

Applications access secrets through simple HTTP requests to the Secrets Router service. Each service receives only essential environment variables:

```python
import requests
import os

def get_secret(secret_name: str, secret_key: str = "value") -> str:
    """Retrieve secret value via Secrets Router HTTP API."""
    secrets_router_url = os.getenv("SECRETS_ROUTER_URL")
    namespace = os.getenv("TEST_NAMESPACE")
    
    url = f"{secrets_router_url}/secrets/{secret_name}/{secret_key}"
    response = requests.get(url, params={"namespace": namespace})
    return response.json()["value"]

# Usage examples using secret names from umbrella chart configuration
database_password = get_secret("rds-credentials", "password")
api_key_secret = get_secret("/aws/production/api-keys")  # AWS Secrets Manager path
```

### Environment Variables

Each service automatically receives these core environment variables:
- `SECRETS_ROUTER_URL`: URL of the secrets router service  
- `TEST_NAMESPACE`: Kubernetes namespace where secrets are stored

The secret names themselves are configured in the umbrella chart values, allowing services to reference them by logical names while the secrets-router handles the backend resolution.
```

## API Reference

### Get Secret

Retrieve a specific secret value from any configured backend.

```
GET /secrets/{secret_name}/{secret_key}?namespace={namespace}
```

**Parameters:**
- `secret_name` (path, required): Name or path of the secret
- `secret_key` (path, required): Key within the secret 
- `namespace` (query, required): Kubernetes namespace where the secret is stored

**Response:**
```json
{
  "backend": "kubernetes-secrets",
  "secret_name": "database-credentials", 
  "secret_key": "password",
  "value": "mypassword123"
}
```

### Health Checks

Monitor service health and readiness.

```
GET /healthz  # Liveness probe
GET /readyz   # Readiness probe
```

**Health Check Responses:**

**Liveness** (HTTP 200 when service is running):
```json
{
  "status": "healthy",
  "service": "secrets-router",
  "version": "1.0.0"
}
```

**Readiness** (HTTP 200 when Dapr is connected, HTTP 503 otherwise):
```json
{
  "status": "ready",
  "service": "secrets-router",
  "dapr_sidecar": "connected",
  "version": "1.0.0"
}
```

## Cross-Namespace Access

The Secrets Router prioritizes same-namespace deployments (works automatically). For cross-namespace scenarios, manual configuration is required:

```bash
# Same-namespace (automatic)
curl "http://secrets-router:8080/secrets/db-secret/password?namespace=production"

# Cross-namespace (manual URL configuration)
curl "http://secrets-router.shared-secrets.svc.cluster.local:8080/secrets/db-secret/password?namespace=shared-secrets"
```

For cross-namespace deployments, manually set the `SECRETS_ROUTER_URL` environment variable in your application configuration.

## Configuration

### Umbrella Chart Structure

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

### Secret Storage Backends

**Kubernetes Secrets**
- **Location**: Same namespace as your application
- **Format**: Standard Kubernetes secret objects
- **Auto-Decoding**: Yes (base64 → plain text)

**AWS Secrets Manager**
- **Location**: AWS Secrets Manager
- **Format**: Configurable paths (e.g., `/app/secrets/production/database`)
- **Auto-Decoding**: No (already plain text)

## Documentation

- **[Developer Guide](./DEVELOPER.md)**: How to consume secrets in your applications
- **[Architecture](./ARCHITECTURE.md)**: Architecture diagrams and design decisions  
- **[ADR](./ADR.md)**: Architecture Decision Record
- **[Testing Workflow](./TESTING_WORKFLOW.md)**: Comprehensive testing procedures

## Project Structure

```
k8s-secrets-broker/
├── charts/
│   ├── umbrella/          # Umbrella chart (Dapr + Secrets Router + Sample Service)
│   ├── secrets-router/    # Secrets Router service chart
│   └── sample-service/    # Sample client applications chart
├── secrets-router/        # Python service implementation
├── containers/            # Sample client Dockerfiles
├── testing/               # Test scenarios and override files
├── scripts/                # Build and deployment scripts
└── docs/                   # Documentation
```

## License

See [LICENSE](./LICENSE) file.
