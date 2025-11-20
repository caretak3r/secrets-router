# ADR-001: Kubernetes Secrets Broker Service Architecture

## Status
**Proposed** | Date: 2024-12-19 | Authors: Platform Engineering Team

## Context

In air-gapped Kubernetes deployments, applications require secure access to secrets stored across multiple backends:
- Kubernetes Secrets (native K8s resources)
- AWS Secrets Manager (external cloud service)

Current challenges:
1. **Direct Secret Access Limitations**: Some applications cannot directly read Kubernetes Secrets due to RBAC constraints, security policies, or architectural patterns
2. **Multi-Backend Complexity**: Secrets exist in both Kubernetes Secrets and AWS Secrets Manager, requiring different access mechanisms
3. **Dynamic Secret Lifecycle**: Secrets are created at various times (before, during, or after application deployment), requiring just-in-time fetching capabilities
4. **Security Requirements**: Need for mTLS, auditability, and secure communication patterns
5. **Operational Overhead**: Mounting secrets as volumes/files creates coupling and reduces flexibility

## Decision Drivers

1. **Security**: mTLS support, auditability, least-privilege access
2. **Flexibility**: Support multiple secret backends (K8s Secrets, AWS Secrets Manager)
3. **Performance**: Lightweight service with minimal resource footprint
4. **Dynamic Access**: Just-in-time secret fetching without pre-mounting
5. **Air-Gapped Compatibility**: Must work in isolated environments
6. **Maintainability**: Python3-based service with comprehensive logging
7. **Backend Priority**: Check Kubernetes Secrets first, then fallback to configured backends

## Considered Options

### Option 1: Secrets Broker Service with AWS Secrets Manager + Kubernetes Secrets Support (Centralized Proxy with K8s Auth Passthrough)

#### Architecture

```mermaid
graph TB
    subgraph "Application Pods"
        A1[Frontend Pod]
        A2[Backend Pod]
        A3[Worker Pod]
    end
    
    subgraph "Secrets Broker Service"
        SB[Secrets Broker<br/>Python Service]
        AUTH[K8s Auth Passthrough<br/>ServiceAccount Token]
        CACHE[In-Memory Cache<br/>TTL-based]
    end
    
    subgraph "Kubernetes API"
        K8S_API[Kubernetes API Server]
        K8S_SECRETS[Kubernetes Secrets]
    end
    
    subgraph "AWS Services"
        AWS_SM[AWS Secrets Manager]
        IRSA[IAM Role for ServiceAccount]
    end
    
    A1 -->|HTTPS + mTLS| SB
    A2 -->|HTTPS + mTLS| SB
    A3 -->|HTTPS + mTLS| SB
    
    SB -->|ServiceAccount Token| AUTH
    AUTH -->|RBAC Check| K8S_API
    K8S_API -->|Read Secrets| K8S_SECRETS
    
    SB -->|IAM Credentials<br/>via IRSA| AWS_SM
    
    SB -->|Cache Hit| CACHE
    
    style SB fill:#4a90e2
    style AUTH fill:#7b68ee
    style K8S_SECRETS fill:#50c878
    style AWS_SM fill:#ff6b6b
```

#### Description

A centralized Python service that acts as a proxy, leveraging Kubernetes ServiceAccount tokens for authentication passthrough. Applications authenticate to the broker using mTLS, and the broker uses the caller's ServiceAccount context to access Kubernetes Secrets, maintaining RBAC enforcement.

#### Flow Diagram

```mermaid
sequenceDiagram
    participant App as Application Pod
    participant SB as Secrets Broker
    participant Auth as K8s Auth Passthrough
    participant K8S as K8s API Server
    participant AWS as AWS Secrets Manager
    
    App->>SB: GET /secrets/{name} (mTLS)
    SB->>SB: Extract ServiceAccount from mTLS cert
    SB->>SB: Check cache (TTL)
    
    alt Cache Hit
        SB->>App: Return cached secret
    else Cache Miss
        SB->>Auth: Get ServiceAccount token
        Auth->>K8S: Authenticate with SA token
        K8S->>K8S: RBAC Check
        alt Secret in K8s
            K8S->>SB: Return K8s Secret
            SB->>SB: Cache secret
            SB->>App: Return secret
        else Secret not in K8s
            SB->>AWS: Fetch from Secrets Manager (IRSA)
            AWS->>SB: Return secret
            SB->>SB: Cache secret
            SB->>App: Return secret
        end
    end
```

#### Pros
- ✅ Maintains Kubernetes RBAC enforcement through ServiceAccount passthrough
- ✅ Single point of access control and auditability
- ✅ Supports both K8s Secrets and AWS Secrets Manager
- ✅ Lightweight Python service
- ✅ mTLS support for secure communication
- ✅ Caching reduces API calls

#### Cons
- ❌ Requires ServiceAccount token management
- ❌ Additional network hop for secret access
- ❌ Cache invalidation complexity
- ❌ ServiceAccount token rotation handling needed

#### Implementation Notes
- Service extracts ServiceAccount identity from mTLS client certificate
- Uses Kubernetes client-go library with ServiceAccount token
- Implements TTL-based caching with configurable expiration
- Audit logs include: caller identity, secret name, backend source, timestamp

---

### Option 2: Secrets Broker Service with AWS Secrets Manager + Kubernetes Secrets Support (Direct Access)

#### Architecture

```mermaid
graph TB
    subgraph "Application Pods"
        A1[Frontend Pod]
        A2[Backend Pod]
        A3[Worker Pod]
    end
    
    subgraph "Secrets Broker Service"
        SB[Secrets Broker<br/>Python Service]
        K8S_CLIENT[K8s Client<br/>Cluster Admin RBAC]
        AWS_CLIENT[AWS Client<br/>IRSA]
        CACHE[In-Memory Cache<br/>TTL-based]
    end
    
    subgraph "Kubernetes API"
        K8S_API[Kubernetes API Server]
        K8S_SECRETS[Kubernetes Secrets]
    end
    
    subgraph "AWS Services"
        AWS_SM[AWS Secrets Manager]
        IRSA[IAM Role for ServiceAccount]
    end
    
    A1 -->|HTTPS + mTLS| SB
    A2 -->|HTTPS + mTLS| SB
    A3 -->|HTTPS + mTLS| SB
    
    SB -->|Cluster Admin<br/>ServiceAccount| K8S_CLIENT
    K8S_CLIENT -->|Direct Access| K8S_API
    K8S_API -->|Read Secrets| K8S_SECRETS
    
    SB -->|IAM Credentials<br/>via IRSA| AWS_CLIENT
    AWS_CLIENT -->|Direct Access| AWS_SM
    
    SB -->|Cache Hit| CACHE
    
    style SB fill:#4a90e2
    style K8S_CLIENT fill:#7b68ee
    style AWS_CLIENT fill:#ff6b6b
    style K8S_SECRETS fill:#50c878
    style AWS_SM fill:#ff6b6b
```

#### Description

A centralized Python service with elevated Kubernetes permissions (ClusterRole) that directly accesses both Kubernetes Secrets and AWS Secrets Manager. Applications authenticate via mTLS, and the broker performs authorization checks based on request metadata before fetching secrets.

#### Flow Diagram

```mermaid
sequenceDiagram
    participant App as Application Pod
    participant SB as Secrets Broker
    participant Auth as Authorization Engine
    participant K8S as K8s API Server
    participant AWS as AWS Secrets Manager
    
    App->>SB: GET /secrets/{name} (mTLS)
    SB->>SB: Extract caller identity from mTLS cert
    SB->>Auth: Authorize request (namespace, secret name)
    SB->>SB: Check cache (TTL)
    
    alt Cache Hit
        SB->>App: Return cached secret
    else Cache Miss
        alt Secret in K8s
            SB->>K8S: Fetch secret (ClusterRole)
            K8S->>SB: Return secret
            SB->>SB: Cache secret
            SB->>App: Return secret
        else Secret not in K8s
            SB->>AWS: Fetch from Secrets Manager (IRSA)
            AWS->>SB: Return secret
            SB->>SB: Cache secret
            SB->>App: Return secret
        end
    end
    
    SB->>SB: Audit log (caller, secret, backend, timestamp)
```

#### Pros
- ✅ Simplified access model (no token passthrough)
- ✅ Centralized authorization logic
- ✅ Supports both backends seamlessly
- ✅ Lightweight Python service
- ✅ Full control over authorization policies

#### Cons
- ❌ Requires ClusterRole permissions (security concern)
- ❌ Authorization logic must be maintained separately from K8s RBAC
- ❌ Potential for privilege escalation if misconfigured
- ❌ Cache invalidation complexity

#### Implementation Notes
- Service runs with ClusterRole allowing secret read access
- Custom authorization engine validates caller identity against secret access policies
- Policies can be defined via ConfigMap or CRD
- Audit logs include: caller identity, secret name, backend source, authorization decision, timestamp

---

### Option 3: Secrets Broker Service using Dapr

#### Architecture

```mermaid
graph TB
    subgraph "Application Pods"
        A1[Frontend Pod<br/>+ Dapr Sidecar]
        A2[Backend Pod<br/>+ Dapr Sidecar]
        A3[Worker Pod<br/>+ Dapr Sidecar]
    end
    
    subgraph "Dapr Control Plane"
        DAPR_OP[Dapr Operator]
        DAPR_SENTRY[Dapr Sentry<br/>mTLS]
        DAPR_PLACEMENT[Dapr Placement]
    end
    
    subgraph "Secrets Broker Service"
        SB[Secrets Broker<br/>Dapr Component]
        K8S_COMP[K8s Secrets<br/>Component]
        AWS_COMP[AWS Secrets<br/>Component]
    end
    
    subgraph "Kubernetes API"
        K8S_API[Kubernetes API Server]
        K8S_SECRETS[Kubernetes Secrets]
    end
    
    subgraph "AWS Services"
        AWS_SM[AWS Secrets Manager]
        IRSA[IAM Role for ServiceAccount]
    end
    
    A1 -->|Dapr API| A1
    A2 -->|Dapr API| A2
    A3 -->|Dapr API| A3
    
    A1 -.->|mTLS| DAPR_SENTRY
    A2 -.->|mTLS| DAPR_SENTRY
    A3 -.->|mTLS| DAPR_SENTRY
    
    A1 -->|HTTP/gRPC| SB
    A2 -->|HTTP/gRPC| SB
    A3 -->|HTTP/gRPC| SB
    
    SB -->|Dapr Component| K8S_COMP
    SB -->|Dapr Component| AWS_COMP
    
    K8S_COMP -->|Direct Access| K8S_API
    K8S_API -->|Read Secrets| K8S_SECRETS
    
    AWS_COMP -->|IRSA| AWS_SM
    
    style SB fill:#4a90e2
    style DAPR_SENTRY fill:#7b68ee
    style K8S_COMP fill:#50c878
    style AWS_COMP fill:#ff6b6b
```

#### Description

Leverages Dapr (Distributed Application Runtime) as the secrets broker infrastructure. Applications use Dapr SDK/API to fetch secrets, and Dapr handles mTLS, service discovery, and component abstraction. Custom Dapr components are created for Kubernetes Secrets and AWS Secrets Manager integration.

#### Flow Diagram

```mermaid
sequenceDiagram
    participant App as Application Pod
    participant Sidecar as Dapr Sidecar
    participant Sentry as Dapr Sentry
    participant SB as Secrets Broker Component
    participant K8S as K8s API Server
    participant AWS as AWS Secrets Manager
    
    App->>Sidecar: GET /v1.0/secrets/{store}/{key}
    Sidecar->>Sentry: mTLS Certificate Validation
    Sentry->>Sidecar: Validated Identity
    Sidecar->>SB: Forward Request
    
    SB->>SB: Determine backend (K8s or AWS)
    
    alt Secret in K8s
        SB->>K8S: Fetch secret
        K8S->>SB: Return secret
        SB->>Sidecar: Return secret
    else Secret in AWS
        SB->>AWS: Fetch from Secrets Manager
        AWS->>SB: Return secret
        SB->>Sidecar: Return secret
    end
    
    Sidecar->>App: Return secret
    SB->>SB: Audit log via Dapr observability
```

#### Pros
- ✅ Built-in mTLS and service mesh capabilities
- ✅ Standardized API (Dapr Secrets API)
- ✅ Component abstraction for multiple backends
- ✅ Observability and tracing built-in
- ✅ No custom mTLS implementation needed

#### Cons
- ❌ Requires Dapr control plane (additional infrastructure)
- ❌ Sidecar pattern adds resource overhead per pod
- ❌ Learning curve for Dapr
- ❌ More complex deployment and operational overhead
- ❌ May be overkill for simple secret fetching

#### Implementation Notes
- Deploy Dapr control plane components (Operator, Sentry, Placement)
- Create custom Dapr secret store components for K8s and AWS
- Applications use Dapr SDK or HTTP API
- Audit logs via Dapr observability pipeline
- Backend priority logic implemented in custom components

---

### Option 4: External Secrets Operator (OSS Project)

#### Architecture

```mermaid
graph TB
    subgraph "Application Pods"
        A1[Frontend Pod]
        A2[Backend Pod]
        A3[Worker Pod]
    end
    
    subgraph "External Secrets Operator"
        ESO[External Secrets<br/>Operator Controller]
        ES_API[ESO API Server]
        SECRET_STORE[SecretStore CRD]
        EXTERNAL_SECRET[ExternalSecret CRD]
    end
    
    subgraph "Kubernetes API"
        K8S_API[Kubernetes API Server]
        K8S_SECRETS[Kubernetes Secrets<br/>Synced by ESO]
    end
    
    subgraph "AWS Services"
        AWS_SM[AWS Secrets Manager]
        IRSA[IAM Role for ServiceAccount]
    end
    
    A1 -->|Read K8s Secret| K8S_SECRETS
    A2 -->|Read K8s Secret| K8S_SECRETS
    A3 -->|Read K8s Secret| K8S_SECRETS
    
    ESO -->|Watch CRDs| EXTERNAL_SECRET
    ESO -->|Read SecretStore| SECRET_STORE
    
    ESO -->|Sync Secrets| K8S_API
    K8S_API -->|Create/Update| K8S_SECRETS
    
    ESO -->|Fetch Secrets| AWS_SM
    AWS_SM -->|IRSA| IRSA
    
    style ESO fill:#4a90e2
    style EXTERNAL_SECRET fill:#7b68ee
    style SECRET_STORE fill:#50c878
    style K8S_SECRETS fill:#50c878
    style AWS_SM fill:#ff6b6b
```

#### Description

Uses the open-source External Secrets Operator (ESO) to sync secrets from AWS Secrets Manager into Kubernetes Secrets. Applications read secrets from Kubernetes Secrets as usual. ESO watches ExternalSecret CRDs and continuously syncs secrets from external backends.

#### Flow Diagram

```mermaid
sequenceDiagram
    participant Admin as Cluster Admin
    participant ESO as External Secrets Operator
    participant K8S as K8s API Server
    participant AWS as AWS Secrets Manager
    participant App as Application Pod
    
    Admin->>K8S: Create ExternalSecret CRD
    Admin->>K8S: Create SecretStore CRD
    
    ESO->>K8S: Watch ExternalSecret CRDs
    ESO->>K8S: Watch SecretStore CRDs
    
    ESO->>AWS: Fetch secret (IRSA)
    AWS->>ESO: Return secret
    
    ESO->>K8S: Create/Update K8s Secret
    K8S->>K8S: Store secret in etcd
    
    App->>K8S: Read K8s Secret (RBAC)
    K8S->>App: Return secret
    
    Note over ESO,AWS: Periodic sync (configurable interval)
```

#### Pros
- ✅ Mature, production-ready OSS project
- ✅ Declarative secret management via CRDs
- ✅ Supports multiple backends (AWS, Azure, GCP, HashiCorp Vault, etc.)
- ✅ Automatic secret synchronization
- ✅ No custom code required
- ✅ Well-documented and community-supported

#### Cons
- ❌ Still requires applications to mount/read K8s Secrets (doesn't solve the core requirement)
- ❌ Not a just-in-time API service (secrets are synced, not fetched on-demand)
- ❌ CRD-based approach adds complexity
- ❌ Secrets are stored in etcd (potential security concern)
- ❌ Doesn't provide mTLS API interface
- ❌ Less flexible for dynamic secret fetching scenarios

#### Implementation Notes
- Deploy External Secrets Operator via Helm or manifests
- Create SecretStore CRDs for AWS Secrets Manager
- Create ExternalSecret CRDs for each secret to sync
- Applications read synced Kubernetes Secrets
- Audit logs via ESO controller logs and Kubernetes audit logs

---

## Decision Outcome

**Chosen Option: Option 1 - Secrets Broker Service with AWS Secrets Manager + Kubernetes Secrets Support (Centralized Proxy with K8s Auth Passthrough)**

### Rationale

1. **Meets Core Requirements**: Provides just-in-time API-based secret fetching without mounting secrets
2. **Security**: Maintains Kubernetes RBAC enforcement through ServiceAccount passthrough, ensuring least-privilege access
3. **Flexibility**: Supports dynamic secret fetching from multiple backends with configurable priority
4. **Lightweight**: Python3 service with minimal dependencies, suitable for distroless containers
5. **Auditability**: Centralized logging of all secret access requests with caller identity
6. **mTLS Support**: Built-in mTLS for secure pod-to-service communication
7. **Air-Gapped Compatible**: No external dependencies beyond Kubernetes API and AWS APIs

### Comparison Matrix

| Criteria | Option 1 | Option 2 | Option 3 | Option 4 |
|----------|----------|----------|----------|----------|
| Just-in-Time API | ✅ | ✅ | ✅ | ❌ |
| No Secret Mounting | ✅ | ✅ | ✅ | ❌ |
| K8s RBAC Enforcement | ✅ | ⚠️ | ✅ | ✅ |
| mTLS Support | ✅ | ✅ | ✅ | ❌ |
| Lightweight | ✅ | ✅ | ❌ | ✅ |
| Dynamic Secret Fetching | ✅ | ✅ | ✅ | ⚠️ |
| Auditability | ✅ | ✅ | ✅ | ⚠️ |
| Operational Complexity | Medium | Low | High | Medium |

## Consequences

### Positive

1. **Security**: RBAC enforcement maintained through ServiceAccount passthrough
2. **Flexibility**: Applications can fetch secrets dynamically via API calls
3. **Centralized Control**: Single point for secret access policies and audit logging
4. **Backend Agnostic**: Easy to add additional secret backends in the future
5. **Performance**: Caching reduces load on Kubernetes API and AWS Secrets Manager

### Negative

1. **Additional Service**: Requires deployment and maintenance of the secrets broker service
2. **Network Latency**: Additional network hop for secret access (mitigated by caching)
3. **Token Management**: Need to handle ServiceAccount token rotation and refresh
4. **Cache Invalidation**: Requires logic to invalidate cache when secrets are updated
5. **Single Point of Failure**: Service availability critical for application startup (mitigated by high availability deployment)

### Mitigation Strategies

1. **High Availability**: Deploy multiple replicas with pod disruption budgets
2. **Caching**: Implement TTL-based caching with configurable expiration
3. **Health Checks**: Comprehensive health endpoints for Kubernetes liveness/readiness probes
4. **Circuit Breakers**: Implement circuit breakers for backend failures
5. **Monitoring**: Comprehensive metrics and alerting for service health
6. **Token Refresh**: Automatic ServiceAccount token refresh with retry logic

## Implementation Plan

### Phase 1: Core Service (Weeks 1-2)
- Python3 FastAPI service with mTLS support
- Kubernetes Secrets backend integration
- ServiceAccount token passthrough mechanism
- Basic caching implementation
- Health check endpoints

### Phase 2: AWS Integration (Week 3)
- AWS Secrets Manager integration
- IRSA (IAM Role for ServiceAccount) configuration
- Backend priority logic (K8s first, then AWS)
- Error handling and fallback mechanisms

### Phase 3: Security & Observability (Week 4)
- Comprehensive audit logging
- Request metadata extraction (caller identity, namespace, etc.)
- Debug logging via environment variable
- Metrics and Prometheus integration

### Phase 4: Production Hardening (Week 5)
- Distroless container image optimization
- Resource limits and requests
- Security policies (PodSecurityPolicy/PSA)
- Documentation and runbooks

### Phase 5: Testing & Validation (Week 6)
- Integration tests
- Load testing
- Security testing (penetration testing)
- Air-gapped environment validation

## Technical Specifications

### Service Architecture

```mermaid
graph LR
    subgraph "Secrets Broker Pod"
        API[FastAPI Server<br/>Port 8443]
        AUTH[Auth Module<br/>mTLS + SA Token]
        K8S_BACKEND[K8s Backend]
        AWS_BACKEND[AWS Backend]
        CACHE[Cache Manager]
        AUDIT[Audit Logger]
    end
    
    API --> AUTH
    AUTH --> CACHE
    CACHE --> K8S_BACKEND
    CACHE --> AWS_BACKEND
    API --> AUDIT
    K8S_BACKEND --> AUDIT
    AWS_BACKEND --> AUDIT
```

### API Endpoints

```
GET  /healthz                    # Health check
GET  /readyz                     # Readiness check
GET  /metrics                    # Prometheus metrics
GET  /v1/secrets/{name}          # Fetch secret by name
GET  /v1/secrets/{name}/{key}    # Fetch specific key from secret
POST /v1/secrets/batch           # Batch fetch multiple secrets
```

### Environment Variables

```bash
# Backend Configuration
SECRETS_BACKEND=k8s,aws-secrets-manager
K8S_NAMESPACE=default
AWS_REGION=us-east-1
AWS_SECRETS_MANAGER_PREFIX=/app/secrets

# Security
MTLS_ENABLED=true
MTLS_CA_CERT_PATH=/etc/tls/ca.crt
MTLS_SERVER_CERT_PATH=/etc/tls/server.crt
MTLS_SERVER_KEY_PATH=/etc/tls/server.key

# Caching
CACHE_ENABLED=true
CACHE_TTL_SECONDS=300
CACHE_MAX_SIZE=1000

# Logging
LOG_LEVEL=INFO
DEBUG_MODE=false
AUDIT_LOG_ENABLED=true
AUDIT_LOG_PATH=/var/log/secrets-broker/audit.log

# Service Configuration
SERVER_PORT=8443
WORKERS=4
```

### Kubernetes Resources

```yaml
# ServiceAccount with IRSA annotation
apiVersion: v1
kind: ServiceAccount
metadata:
  name: secrets-broker
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/secrets-broker-role
---
# ClusterRole for reading secrets
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: secrets-broker-reader
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list"]
---
# ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: secrets-broker-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: secrets-broker-reader
subjects:
- kind: ServiceAccount
  name: secrets-broker
  namespace: platform
```

### Container Image

- **Base**: `gcr.io/distroless/python3-debian12:latest`
- **Size**: ~50MB (estimated)
- **Python Version**: 3.11+
- **Dependencies**: FastAPI, kubernetes, boto3, cryptography

## Monitoring & Observability

### Metrics

- `secrets_broker_requests_total` - Total API requests
- `secrets_broker_requests_duration_seconds` - Request latency
- `secrets_broker_cache_hits_total` - Cache hit count
- `secrets_broker_cache_misses_total` - Cache miss count
- `secrets_broker_backend_errors_total` - Backend error count
- `secrets_broker_secrets_fetched_total` - Secrets fetched by backend

### Audit Log Format

```json
{
  "timestamp": "2024-12-19T10:30:00Z",
  "caller": {
    "service_account": "frontend-service",
    "namespace": "production",
    "pod": "frontend-abc123"
  },
  "request": {
    "method": "GET",
    "path": "/v1/secrets/database-credentials",
    "secret_name": "database-credentials"
  },
  "response": {
    "status_code": 200,
    "backend": "kubernetes",
    "cache_hit": true
  },
  "duration_ms": 15
}
```

## Security Considerations

1. **mTLS**: All client connections require valid mTLS certificates
2. **RBAC**: ServiceAccount passthrough maintains Kubernetes RBAC enforcement
3. **Secret Encryption**: Secrets in transit encrypted via TLS, secrets at rest encrypted by backend
4. **Audit Logging**: All secret access logged with caller identity
5. **Least Privilege**: ServiceAccount has minimal required permissions
6. **Network Policies**: Restrict network access to secrets broker service
7. **Pod Security**: Run with non-root user, read-only root filesystem

## References

- [Kubernetes Secrets Documentation](https://kubernetes.io/docs/concepts/configuration/secret/)
- [AWS Secrets Manager Documentation](https://docs.aws.amazon.com/secretsmanager/)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Distroless Images](https://github.com/GoogleContainerTools/distroless)
- [External Secrets Operator](https://external-secrets.io/)

