# ADR-001: Kubernetes Secrets Broker Service Architecture

## Status
**Proposed** | Date: 2024-12-19 | Authors: Platform Engineering Team

## Context

In air-gapped Kubernetes deployments, applications require secure **read-only** access to secrets stored across multiple backends:
- Kubernetes Secrets (native K8s resources)
- AWS Secrets Manager (external cloud service)

**Note**: Applications will only fetch/read secrets through this service. Secret creation and updates are managed separately by cluster administrators or CI/CD pipelines.

Current challenges:
1. **Direct Secret Access Limitations**: Some applications cannot directly read Kubernetes Secrets due to RBAC constraints, security policies, or architectural patterns
2. **Multi-Backend Complexity**: Secrets exist in both Kubernetes Secrets and AWS Secrets Manager, requiring different access mechanisms
3. **Dynamic Secret Lifecycle**: Secrets are created at various times (before, during, or after application deployment), requiring just-in-time fetching capabilities
4. **Namespace-Scoped Secrets**: All secrets are namespace-scoped - applications access secrets from their deployment namespace
5. **Security Requirements**: Need for mTLS, auditability, and secure communication patterns
6. **Operational Overhead**: Mounting secrets as volumes/files creates coupling and reduces flexibility
7. **Developer Experience**: Need simple, consistent API for developers to consume secrets

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
    participant App as Application Pod<br/>(Namespace: production)
    participant SB as Secrets Broker
    participant Auth as K8s Auth Passthrough
    participant K8S as K8s API Server
    participant AWS as AWS Secrets Manager
    
    App->>SB: GET /v1/secrets/app-db-credentials (mTLS)
    SB->>SB: Extract ServiceAccount + Namespace from mTLS cert
    Note over SB: Namespace: production<br/>ServiceAccount: frontend-sa
    SB->>Auth: Get ServiceAccount token
    Auth->>K8S: Authenticate with SA token
    K8S->>K8S: RBAC Check
    
    alt Secret in caller namespace (production)
        K8S->>SB: Return namespace-scoped secret
        SB->>App: Return secret
    else Secret not in caller namespace
        alt Cluster-wide secret exists
            K8S->>SB: Return cluster-wide secret (kube-system)
            SB->>App: Return secret
        else Secret not in K8s
            SB->>AWS: Fetch from Secrets Manager<br/>Path: /app/secrets/production/app-db-credentials
            AWS->>SB: Return secret
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
- ✅ Read-only access model simplifies security and operations

#### Cons
- ❌ Requires ServiceAccount token management
- ❌ Additional network hop for secret access
- ❌ ServiceAccount token rotation handling needed
- ❌ No caching in MVP (deferred to long-term)

#### Secret Scoping Model

The service supports two types of secret scoping:

**1. Namespace-Scoped Secrets**: Secrets specific to a namespace, accessible only by applications in that namespace
**2. Cluster-Wide Secrets**: Centrally managed secrets accessible by all services across the cluster

```mermaid
graph TB
    subgraph "Cluster-Wide Secrets"
        CW_SECRET1[shared-db-credentials<br/>Namespace: kube-system]
        CW_SECRET2[cluster-certificate<br/>Namespace: kube-system]
    end
    
    subgraph "Namespace: production"
        NS_PROD_SECRET1[app-db-credentials]
        NS_PROD_SECRET2[api-keys]
        PROD_POD1[Frontend Pod]
        PROD_POD2[Backend Pod]
    end
    
    subgraph "Namespace: staging"
        NS_STAGING_SECRET1[app-db-credentials]
        NS_STAGING_SECRET2[api-keys]
        STAGING_POD1[Frontend Pod]
        STAGING_POD2[Backend Pod]
    end
    
    subgraph "Secrets Broker Service"
        SB[Secrets Broker]
        NS_RESOLVER[Namespace Resolver]
    end
    
    PROD_POD1 -->|GET /v1/secrets/app-db-credentials| SB
    PROD_POD2 -->|GET /v1/secrets/shared-db-credentials| SB
    STAGING_POD1 -->|GET /v1/secrets/app-db-credentials| SB
    STAGING_POD2 -->|GET /v1/secrets/shared-db-credentials| SB
    
    SB --> NS_RESOLVER
    NS_RESOLVER -->|Check caller namespace| NS_PROD_SECRET1
    NS_RESOLVER -->|Check caller namespace| NS_STAGING_SECRET1
    NS_RESOLVER -->|Check cluster-wide| CW_SECRET1
    
    style CW_SECRET1 fill:#ffd700
    style CW_SECRET2 fill:#ffd700
    style NS_PROD_SECRET1 fill:#50c878
    style NS_STAGING_SECRET1 fill:#50c878
    style SB fill:#4a90e2
    style NS_RESOLVER fill:#7b68ee
```

**Secret Resolution Logic**:

1. **Extract Caller Context**: Service extracts caller's namespace from ServiceAccount (via mTLS certificate)
2. **Namespace-Scoped Lookup**: First checks for secret in caller's namespace
3. **Cluster-Wide Lookup**: If not found, checks cluster-wide secrets (typically in `kube-system` or `platform` namespace)
4. **AWS Fallback**: If not found in K8s, queries AWS Secrets Manager with namespace-aware path

**API Behavior**:
- `GET /v1/secrets/{name}` - Automatically resolves namespace from caller context
- `GET /v1/secrets/{name}?namespace={ns}` - Optional explicit namespace override (subject to RBAC)
- Cluster-wide secrets are typically prefixed or stored in a designated namespace (e.g., `kube-system`, `platform`)

**RBAC Enforcement**:
- Namespace-scoped secrets: Only accessible by ServiceAccounts with RBAC permissions in that namespace
- Cluster-wide secrets: Accessible by ServiceAccounts with ClusterRole permissions
- ServiceAccount passthrough ensures native K8s RBAC is enforced

#### Implementation Notes
- Service extracts ServiceAccount identity and namespace from mTLS client certificate
- Uses Kubernetes client library with ServiceAccount token
- Read-only operations: GET requests only, no write/update/delete endpoints
- Secret scoping: Supports both namespace-scoped and cluster-wide secrets
- Namespace resolution: Automatically resolves caller namespace, with optional override
- Audit logs include: caller identity, namespace, secret name, backend source, timestamp

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
    
    alt Secret in K8s
        SB->>K8S: Fetch secret (ClusterRole)
        K8S->>SB: Return secret
        SB->>App: Return secret
    else Secret not in K8s
        SB->>AWS: Fetch from Secrets Manager (IRSA)
        AWS->>SB: Return secret
        SB->>App: Return secret
    end
    
    SB->>SB: Audit log (caller, secret, backend, timestamp)
```

#### Pros
- ✅ Simplified access model (no token passthrough)
- ✅ Centralized authorization logic
- ✅ Supports both backends seamlessly
- ✅ Lightweight Python service
- ✅ Full control over authorization policies
- ✅ Read-only access model simplifies security

#### Cons
- ❌ Requires ClusterRole permissions (security concern)
- ❌ Authorization logic must be maintained separately from K8s RBAC
- ❌ Potential for privilege escalation if misconfigured
- ❌ No caching in MVP (deferred to long-term)

#### Implementation Notes
- Service runs with ClusterRole allowing secret read access only
- Custom authorization engine validates caller identity against secret access policies
- Policies can be defined via ConfigMap or CRD
- Read-only operations: GET requests only, no write/update/delete endpoints
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

**Chosen Solution: Option 3 - Dapr-Based Secrets Broker**

We have chosen Option 3 (Dapr-based architecture) as the implementation approach:

- **Control Plane Umbrella Chart**: Single Helm chart (`control-plane-umbrella`) installs Dapr control plane and Secrets Router
- **Chart Dependencies**: Secrets Router chart has dependency on Dapr chart
- **Multi-Namespace Support**: Secrets can be accessed from multiple namespaces (configured via Helm values)
- **Configurable Components**: Dapr Components generated from Helm values via `secrets-components.yaml` template
- **Two Stores**: Kubernetes Secrets and AWS Secrets Manager
- **Auto-Decoding**: Kubernetes secrets automatically decoded for developers
- **Path-Based AWS**: AWS secrets use configurable path prefix
- **Namespace from Release**: All resources use `{{ .Release.Namespace }}` (no hardcoded namespaces)

### Implementation: Dapr-Based Secrets Broker (Option 3)

**Chosen Solution**: Dapr-based secrets broker with umbrella chart deployment

#### Rationale

1. **Control Plane Umbrella Chart**: Single Helm chart (`control-plane-umbrella`) installs Dapr control plane and Secrets Router, simplifying customer deployment
2. **Chart Dependencies**: Secrets Router chart declares dependency on Dapr, ensuring proper installation order
3. **Configurable Secret Stores**: Developers configure secret locations via `override.yaml` - no code changes needed
4. **Multi-Namespace Support**: Secrets can be accessed from multiple namespaces, configured via Helm values
5. **Template-Based Components**: Dapr Components generated from `secrets-components.yaml` template based on Helm values
6. **Developer Experience**: Simple HTTP API with automatic base64 decoding for Kubernetes secrets
7. **Two Store Support**: Kubernetes Secrets (primary) and AWS Secrets Manager (fallback)
8. **Path-Based AWS Configuration**: Configurable path prefix for AWS secrets organization
9. **mTLS**: Automatic mTLS via Dapr Sentry without custom implementation
10. **Observability**: Built-in metrics and logging via Dapr
11. **Standardized Components**: Uses Dapr's standard secret store components
12. **Namespace Flexibility**: All resources use `{{ .Release.Namespace }}` - no hardcoded namespaces

#### Architecture Benefits

**Simplicity**:
- Single umbrella chart (`control-plane-umbrella`) for deployment
- Configurable secret stores via `override.yaml`
- Auto-decoding hides complexity from developers
- Update `override.yaml` to add new secret locations - no code changes

**Security**:
- mTLS via Dapr Sentry
- RBAC enforcement for Kubernetes secrets
- IRSA support for AWS Secrets Manager
- Namespace isolation

**Flexibility**:
- Supports both Kubernetes Secrets and AWS Secrets Manager
- Secrets can be accessed from multiple namespaces (configured in `override.yaml`)
- Configurable path prefix for AWS secrets
- Priority-based resolution (K8s first, then AWS)
- Easy to add new namespaces or secret stores via Helm values

**Developer Experience**:
- Simple HTTP API: `GET /secrets/{name}/{key}?namespace={ns}`
- Auto-decoding of Kubernetes secrets
- Clear error messages
- Comprehensive documentation

### Requirements Support

**MVP1 (Option 1) Support**:
- ✅ All core requirements fully supported (REQ-001 through REQ-021)
- ✅ Just-in-time API, read-only access, no mounting, RBAC enforcement
- ✅ mTLS, multi-backend support, auditability, air-gapped compatibility
- ✅ Lightweight, scalable, and deployable via Helm

**MVP2 (Option 3) Enhancements**:
- ✅ All MVP1 requirements maintained
- ✅ Additional: Standardized Dapr Secrets API, built-in observability
- ✅ Additional: Service mesh capabilities, multi-language SDK support
- ✅ Additional: Advanced resilience patterns (circuit breakers, retries)

### Decision Summary

**MVP1** provides a production-ready solution that meets all current requirements with minimal complexity. **MVP2** enhances the solution with Dapr's advanced capabilities once we have validated the approach and built operational maturity. This phased strategy balances immediate needs with long-term architectural improvements while minimizing risk and maximizing value delivery.

### Requirements Comparison Matrix

This matrix evaluates each option against the core requirements and design criteria. Each requirement includes a description explaining its importance and evaluation criteria.

| Requirement | Description | Option 1 | Option 2 | Option 3 | Option 4 |
|-------------|-------------|----------|----------|----------|----------|
| **REQ-001: Just-in-Time API** | Applications must fetch secrets dynamically via API requests at runtime, without pre-mounting or pre-loading secrets. Secrets may be created at any time (before, during, or after application deployment) and must be immediately available. | ✅ **Full Support**<br/>REST API with on-demand fetching | ✅ **Full Support**<br/>REST API with on-demand fetching | ✅ **Full Support**<br/>Dapr Secrets API with on-demand fetching | ❌ **Not Supported**<br/>CRD-based sync model; secrets must be synced before use |
| **REQ-002: Read-Only Access** | Service provides read-only access to secrets. Applications can only fetch/read secrets, not create, update, or delete them. Secret management (creation/updates) is handled separately by cluster administrators or CI/CD pipelines. | ✅ **Full Support**<br/>GET endpoints only; no write operations | ✅ **Full Support**<br/>GET endpoints only; no write operations | ✅ **Full Support**<br/>Read-only Dapr API | ✅ **Full Support**<br/>Read-only sync from external sources |
| **REQ-003: No Secret Mounting** | Applications must not mount secrets as volumes or files. All secret access must be programmatic via API calls to maintain flexibility and reduce coupling. | ✅ **Full Support**<br/>No mounting required; API-only access | ✅ **Full Support**<br/>No mounting required; API-only access | ✅ **Full Support**<br/>No mounting required; SDK/API access | ❌ **Not Supported**<br/>Requires applications to read K8s Secrets (may require mounting) |
| **REQ-004: Kubernetes RBAC Enforcement** | Must maintain Kubernetes RBAC policies. Applications should only access secrets they are authorized to access based on their ServiceAccount and RBAC rules. | ✅ **Full Support**<br/>ServiceAccount passthrough maintains native RBAC | ⚠️ **Partial Support**<br/>Custom authorization logic required; not using native RBAC | ✅ **Full Support**<br/>Can leverage K8s RBAC through Dapr components | ✅ **Full Support**<br/>Applications use native K8s RBAC to read synced secrets |
| **REQ-005: mTLS Support** | All communication between applications and the secrets broker must use mutual TLS (mTLS) for authentication and encryption. Both client and server must authenticate each other. | ✅ **Full Support**<br/>Built-in mTLS implementation | ✅ **Full Support**<br/>Built-in mTLS implementation | ✅ **Full Support**<br/>Dapr Sentry provides mTLS automatically | ❌ **Not Supported**<br/>No API interface; direct K8s API access |
| **REQ-006: Multi-Backend Support** | Must support fetching secrets from multiple backends: Kubernetes Secrets (primary) and AWS Secrets Manager (secondary). Should check K8s Secrets first, then fallback to configured backends. | ✅ **Full Support**<br/>Native support for both backends with priority logic | ✅ **Full Support**<br/>Native support for both backends with priority logic | ✅ **Full Support**<br/>Dapr components for both backends | ⚠️ **Partial Support**<br/>Syncs AWS → K8s; doesn't provide unified API |
| **REQ-007: Backend Priority Logic** | Must check Kubernetes Secrets first before querying other backends. This ensures K8s Secrets take precedence and reduces unnecessary external API calls. | ✅ **Full Support**<br/>Configurable priority: K8s → AWS | ✅ **Full Support**<br/>Configurable priority: K8s → AWS | ✅ **Full Support**<br/>Can implement priority in component logic | ⚠️ **Partial Support**<br/>AWS secrets synced to K8s; no runtime priority |
| **REQ-008: Caching Mechanism** | Should implement caching to reduce load on backends and improve response times. Cache should support TTL-based expiration and invalidation. Cache hits should not compromise security or RBAC enforcement. **Note**: Deferred to long-term implementation. | ⚠️ **Deferred**<br/>Not in MVP; planned for long-term with in-memory TTL cache | ⚠️ **Deferred**<br/>Not in MVP; planned for long-term with in-memory TTL cache | ⚠️ **Deferred**<br/>Dapr supports caching but not implemented in MVP | ⚠️ **Partial Support**<br/>K8s API server caching; no application-level cache |
| **REQ-009: Cache Invalidation** | Cache must support invalidation when secrets are updated. Should support both TTL-based expiration and manual invalidation. Cache consistency must be maintained across replicas. **Note**: Deferred to long-term implementation. | ⚠️ **Deferred**<br/>Not in MVP; planned for long-term | ⚠️ **Deferred**<br/>Not in MVP; planned for long-term | ⚠️ **Deferred**<br/>Not in MVP; planned for long-term | ⚠️ **Partial Support**<br/>Relies on K8s watch/refresh; no explicit cache control |
| **REQ-010: Cache Security** | Cached secrets must maintain the same security posture as direct backend access. Cache must respect RBAC - different callers should not access each other's cached secrets. **Note**: Deferred to long-term implementation. | ⚠️ **Deferred**<br/>Not in MVP; planned for long-term | ⚠️ **Deferred**<br/>Not in MVP; planned for long-term | ⚠️ **Deferred**<br/>Not in MVP; planned for long-term | ✅ **Full Support**<br/>K8s API cache respects RBAC natively |
| **REQ-011: Lightweight Service** | Service should be lightweight with minimal resource footprint. Written in Python3 (latest) and suitable for distroless container images. Should have minimal dependencies. | ✅ **Full Support**<br/>Python3 FastAPI; minimal deps; ~50MB distroless image | ✅ **Full Support**<br/>Python3 FastAPI; minimal deps; ~50MB distroless image | ❌ **Not Supported**<br/>Requires Dapr control plane + sidecars; higher resource overhead | ✅ **Full Support**<br/>Go-based operator; efficient but requires CRD management |
| **REQ-012: Dynamic Secret Fetching** | Must support fetching secrets that are created dynamically at runtime. Secrets may not exist at application startup but must be available when requested. | ✅ **Full Support**<br/>On-demand API calls; no pre-sync required | ✅ **Full Support**<br/>On-demand API calls; no pre-sync required | ✅ **Full Support**<br/>On-demand Dapr API calls | ⚠️ **Partial Support**<br/>Requires ExternalSecret CRD creation; sync delay possible |
| **REQ-013: Auditability** | Must log all secret access requests with metadata: caller identity (ServiceAccount, namespace, pod), secret name, backend source, timestamp, and access decision. Logs must be searchable and retainable. | ✅ **Full Support**<br/>Centralized audit logging with comprehensive metadata | ✅ **Full Support**<br/>Centralized audit logging with comprehensive metadata | ✅ **Full Support**<br/>Dapr observability + custom audit logs | ⚠️ **Partial Support**<br/>K8s audit logs + ESO logs; less centralized |
| **REQ-014: Debug Logging** | Must support comprehensive debug logging controlled via environment variable. Should log request/response details, backend calls, and error details for troubleshooting. | ✅ **Full Support**<br/>Environment-controlled debug mode; comprehensive logging | ✅ **Full Support**<br/>Environment-controlled debug mode; comprehensive logging | ✅ **Full Support**<br/>Dapr debug logging + custom logs | ⚠️ **Partial Support**<br/>ESO controller logs; less granular application-level logging |
| **REQ-015: Request Metadata Extraction** | Must extract and log caller metadata from requests: ServiceAccount name, namespace, pod name, IP address. This enables audit trails and security monitoring. | ✅ **Full Support**<br/>Extracts metadata from mTLS cert + request headers | ✅ **Full Support**<br/>Extracts metadata from mTLS cert + request headers | ✅ **Full Support**<br/>Dapr provides caller identity; can extract additional metadata | ⚠️ **Partial Support**<br/>K8s audit logs provide some metadata; less comprehensive |
| **REQ-016: Air-Gapped Compatibility** | Must work in air-gapped/isolated environments with no external internet dependencies beyond required APIs (K8s API, AWS APIs). Should not require external package repositories or services. | ✅ **Full Support**<br/>No external deps; uses K8s API + AWS APIs only | ✅ **Full Support**<br/>No external deps; uses K8s API + AWS APIs only | ⚠️ **Partial Support**<br/>Requires Dapr control plane; more complex in air-gapped | ✅ **Full Support**<br/>No external deps; uses K8s API + AWS APIs only |
| **REQ-017: Operational Complexity** | Should minimize operational overhead. Deployment, configuration, and maintenance should be straightforward. Fewer moving parts are preferred. | ⚠️ **Medium Complexity**<br/>Custom service to deploy/maintain; moderate complexity | ✅ **Low Complexity**<br/>Simpler auth model; easier to operate | ❌ **High Complexity**<br/>Dapr control plane + sidecars; higher operational overhead | ⚠️ **Medium Complexity**<br/>CRD management; operator lifecycle; moderate complexity |
| **REQ-018: Deployment Mechanism** | Should support standard Kubernetes deployment mechanisms. Helm charts are preferred for declarative, version-controlled deployments that integrate with GitOps workflows. | ✅ **Full Support**<br/>Helm chart deployment; standard K8s manifests | ✅ **Full Support**<br/>Helm chart deployment; standard K8s manifests | ✅ **Full Support**<br/>Helm chart or Dapr CLI; official Helm charts available | ✅ **Full Support**<br/>Helm chart deployment; official ESO Helm chart |
| **REQ-019: High Availability** | Service should support multi-replica deployments for high availability. Stateless design enables easy horizontal scaling. | ✅ **Full Support**<br/>Stateless design; supports multiple replicas | ✅ **Full Support**<br/>Stateless design; supports multiple replicas | ✅ **Full Support**<br/>Dapr supports HA; sidecar per pod provides redundancy | ✅ **Full Support**<br/>Operator supports multiple replicas; HA controller |
| **REQ-020: Performance** | Should minimize latency for secret fetching. Should handle concurrent requests efficiently with async support and connection pooling. **Note**: Caching deferred to long-term. | ✅ **Full Support**<br/>Async support; connection pooling; no caching in MVP | ✅ **Full Support**<br/>Async support; connection pooling; no caching in MVP | ⚠️ **Partial Support**<br/>Sidecar adds latency; async support available | ⚠️ **Partial Support**<br/>Sync model adds delay; K8s API caching helps |
| **REQ-021: Scalability** | Should scale horizontally to handle increasing load. Stateless design enables linear scaling. | ✅ **Full Support**<br/>Horizontal scaling; stateless design | ✅ **Full Support**<br/>Horizontal scaling; stateless design | ✅ **Full Support**<br/>Dapr scales with application pods; sidecar per pod | ⚠️ **Partial Support**<br/>Operator scaling limited; K8s API server may bottleneck |

### Requirement Summary

**Legend:**
- ✅ **Full Support**: Requirement is fully met with native support
- ⚠️ **Partial Support**: Requirement is partially met or requires additional work
- ❌ **Not Supported**: Requirement is not met or contradicts the approach

**Key Findings:**
- **Option 1** meets all core requirements with full support for RBAC and multi-backend access. Caching deferred to long-term.
- **Option 2** similar to Option 1 but requires custom authorization (not native RBAC). Caching deferred to long-term.
- **Option 3** meets requirements but adds significant operational complexity. Caching deferred to long-term.
- **Option 4** fails to meet core requirements (no just-in-time API, requires secret mounting)

## Consequences

### Positive

1. **Security**: RBAC enforcement maintained through ServiceAccount passthrough
2. **Flexibility**: Applications can fetch secrets dynamically via API calls (read-only)
3. **Centralized Control**: Single point for secret access policies and audit logging
4. **Backend Agnostic**: Easy to add additional secret backends in the future
5. **Simplicity**: Read-only model simplifies security model and reduces attack surface
6. **Stateless Design**: No caching in MVP makes service fully stateless and easier to scale

### Negative

1. **Additional Service**: Requires deployment and maintenance of the secrets broker service
2. **Network Latency**: Additional network hop for secret access (no caching in MVP)
3. **Token Management**: Need to handle ServiceAccount token rotation and refresh
4. **Single Point of Failure**: Service availability critical for application startup (mitigated by high availability deployment)
5. **Read-Only Limitation**: Applications cannot create or update secrets through this service (by design)

### Mitigation Strategies

1. **High Availability**: Deploy multiple replicas with pod disruption budgets
2. **Caching**: Implement TTL-based caching with configurable expiration
3. **Health Checks**: Comprehensive health endpoints for Kubernetes liveness/readiness probes
4. **Circuit Breakers**: Implement circuit breakers for backend failures
5. **Monitoring**: Comprehensive metrics and alerting for service health
6. **Token Refresh**: Automatic ServiceAccount token refresh with retry logic

## Implementation Plan

### Development Workflow: Sidecar to Dapr Integration

The following diagram illustrates the complete development workflow from transforming the existing secrets-broker sidecar into a fully-fledged Kubernetes service, through deployment and testing, to eventual Dapr integration.

```mermaid
flowchart TD
    START([Existing Secrets-Broker<br/>Sidecar]) --> MVP1_DEV[MVP1: Transform Sidecar<br/>to K8s Service]
    
    MVP1_DEV --> PHASE1[Phase 1: Core Service<br/>Weeks 1-2<br/>- FastAPI with mTLS<br/>- K8s Secrets backend<br/>- ServiceAccount passthrough<br/>- Health endpoints]
    
    PHASE1 --> PHASE2[Phase 2: AWS Integration<br/>Week 3<br/>- AWS Secrets Manager<br/>- IRSA configuration<br/>- Backend priority logic]
    
    PHASE2 --> PHASE3[Phase 3: Security & Observability<br/>Week 4<br/>- Audit logging<br/>- Request metadata<br/>- Prometheus metrics]
    
    PHASE3 --> PHASE4[Phase 4: Production Hardening<br/>Week 5<br/>- Distroless image<br/>- Resource limits<br/>- Security policies]
    
    PHASE4 --> HELM_DEV[Helm Chart Development<br/>- Service deployment<br/>- ServiceAccount & RBAC<br/>- ConfigMaps & Secrets<br/>- Service & Ingress<br/>- Values.yaml]
    
    HELM_DEV --> DEPLOY[Deployment<br/>- Deploy to dev cluster<br/>- Configure IRSA<br/>- Set up mTLS certs<br/>- Validate RBAC]
    
    DEPLOY --> TESTING[Testing & Validation<br/>Week 6<br/>- Unit tests<br/>- Integration tests<br/>- Load testing<br/>- Security testing<br/>- Air-gapped validation]
    
    TESTING --> MVP1_PROD{MVP1 Production<br/>Ready?}
    
    MVP1_PROD -->|Yes| MVP1_DEPLOY[MVP1 Production Deployment<br/>- Deploy to production<br/>- Monitor & observe<br/>- Gather usage metrics]
    
    MVP1_PROD -->|No| PHASE4
    
    MVP1_DEPLOY --> MVP1_OPERATIONS[MVP1 Operations<br/>- Monitor performance<br/>- Collect usage patterns<br/>- Identify improvements<br/>- Build operational expertise]
    
    MVP1_OPERATIONS --> MVP2_DECISION{MVP2 Decision Point<br/>Evaluate Dapr Need}
    
    MVP2_DECISION -->|Skip MVP2| END1([Continue with MVP1])
    
    MVP2_DECISION -->|Proceed to MVP2| MVP2_PHASE1[MVP2 Phase 1: Dapr Control Plane<br/>- Deploy Dapr Operator<br/>- Deploy Dapr Sentry<br/>- Deploy Dapr Placement<br/>- Configure certificates]
    
    MVP2_PHASE1 --> MVP2_PHASE2[MVP2 Phase 2: Component Development<br/>- Wrap MVP1 service as Dapr component<br/>- Implement Dapr Secrets API<br/>- Create K8s Secrets component<br/>- Create AWS Secrets component]
    
    MVP2_PHASE2 --> MVP2_PHASE3[MVP2 Phase 3: Application Migration<br/>- Update app SDKs<br/>- Migrate to Dapr sidecar<br/>- Gradual rollout<br/>- Maintain backward compatibility]
    
    MVP2_PHASE3 --> MVP2_PHASE4[MVP2 Phase 4: Advanced Features<br/>- Dapr observability<br/>- Resilience patterns<br/>- Rate limiting<br/>- Multi-language SDKs]
    
    MVP2_PHASE4 --> MVP2_TESTING[MVP2 Testing<br/>- Component testing<br/>- Integration testing<br/>- Performance validation<br/>- Migration validation]
    
    MVP2_TESTING --> MVP2_PROD{MVP2 Production<br/>Ready?}
    
    MVP2_PROD -->|Yes| MVP2_DEPLOY[MVP2 Production Deployment<br/>- Deploy Dapr components<br/>- Migrate applications<br/>- Monitor migration]
    
    MVP2_PROD -->|No| MVP2_PHASE2
    
    MVP2_DEPLOY --> MVP2_OPTIMIZE[MVP2 Optimization<br/>- Optimize components<br/>- Remove MVP1 service<br/>- Update documentation]
    
    MVP2_OPTIMIZE --> END2([Dapr Integration Complete])
    
    style START fill:#e1f5ff
    style MVP1_DEV fill:#4a90e2
    style PHASE1 fill:#7b68ee
    style PHASE2 fill:#7b68ee
    style PHASE3 fill:#7b68ee
    style PHASE4 fill:#7b68ee
    style HELM_DEV fill:#50c878
    style DEPLOY fill:#ffd700
    style TESTING fill:#ff6b6b
    style MVP1_DEPLOY fill:#50c878
    style MVP1_OPERATIONS fill:#87ceeb
    style MVP2_PHASE1 fill:#9370db
    style MVP2_PHASE2 fill:#9370db
    style MVP2_PHASE3 fill:#9370db
    style MVP2_PHASE4 fill:#9370db
    style MVP2_TESTING fill:#ff6b6b
    style MVP2_DEPLOY fill:#50c878
    style END1 fill:#e1f5ff
    style END2 fill:#e1f5ff
```

**Key Workflow Stages**:

1. **MVP1 Development (Weeks 1-5)**: Transform sidecar into standalone Kubernetes service
   - Phase 1-4: Core service development
   - Incremental feature development

2. **Helm Chart Development**: Create deployment artifacts
   - Service manifests
   - RBAC resources
   - Configuration management
   - Values customization

3. **Deployment**: Deploy to development/test environment
   - Infrastructure setup
   - Configuration validation
   - Initial testing

4. **Testing & Validation (Week 6)**: Comprehensive testing
   - Functional testing
   - Performance testing
   - Security validation

5. **MVP1 Production**: Production deployment and operations
   - Production rollout
   - Monitoring and metrics collection
   - Operational learning

6. **MVP2 Decision Point**: Evaluate need for Dapr
   - Based on MVP1 learnings
   - Business case validation
   - Option to skip if MVP1 sufficient

7. **MVP2 Development**: Dapr integration (if proceeding)
   - Control plane deployment
   - Component development
   - Application migration
   - Advanced features

### Implementation Plan

**Goal**: Deploy Dapr-based secrets broker with umbrella chart

#### Phase 1: Control Plane Umbrella Chart Development
- Create `control-plane-umbrella` chart with Dapr and Secrets Router dependencies
- Secrets Router chart declares dependency on Dapr
- Configure deployment using `{{ .Release.Namespace }}` (no hardcoded namespaces)
- Set up environment variable configuration
- Create `secrets-components.yaml` template for generating Dapr Components
- Test chart installation

#### Phase 2: Secrets Router Service
- Python3 FastAPI service with HTTP requests to Dapr sidecar
- Auto-decoding of Kubernetes secrets (all values returned decoded)
- Priority-based secret store resolution
- Health check endpoints (`/healthz`, `/readyz`)
- API endpoint: `GET /secrets/{name}/{key}?namespace={ns}`

#### Phase 3: Dapr Components
- Create `secrets-components.yaml` template in Secrets Router chart
- Generate Kubernetes Secrets component from Helm values
- Generate AWS Secrets Manager component (if configured)
- Support multiple namespaces in Kubernetes Secrets component
- Configure path-based AWS secrets
- Test component integration
- Ensure components use `{{ .Release.Namespace }}` for namespace

#### Phase 4: Production Hardening
- Distroless container image optimization
- Resource limits and requests
- Security policies (Pod Security Standards)
- RBAC configuration
- Documentation and runbooks

#### Phase 5: Testing & Validation
- Unit tests for core functionality
- Integration tests with K8s and AWS backends
- Load testing
- Security testing
- Air-gapped environment validation

**Deliverables**:
- Production-ready `control-plane-umbrella` Helm chart
- Secrets Router chart with Dapr dependency
- `secrets-components.yaml` template for generating Dapr Components
- Secrets Router service with auto-decoding
- Configurable secret store definitions (via Helm values)
- Comprehensive documentation
- Developer guide with examples and `override.yaml` configuration

## Technical Specifications

### Service Architecture

```mermaid
graph LR
    subgraph "Secrets Broker Pod"
        API[FastAPI Server<br/>Port 8443]
        AUTH[Auth Module<br/>mTLS + SA Token]
        K8S_BACKEND[K8s Backend]
        AWS_BACKEND[AWS Backend]
        AUDIT[Audit Logger]
    end
    
    API --> AUTH
    AUTH --> K8S_BACKEND
    AUTH --> AWS_BACKEND
    API --> AUDIT
    K8S_BACKEND --> AUDIT
    AWS_BACKEND --> AUDIT
```

### API Endpoints

```
GET  /healthz                              # Health check
GET  /readyz                               # Readiness check
GET  /metrics                              # Prometheus metrics
GET  /v1/secrets/{name}                    # Fetch secret by name (auto-resolves namespace)
GET  /v1/secrets/{name}?namespace={ns}     # Fetch secret with explicit namespace override
GET  /v1/secrets/{name}/{key}?namespace={ns} # Fetch specific key from secret (always decoded)
POST /v1/secrets/batch                     # Batch fetch multiple secrets
```

**Secret Scoping Behavior**:

1. **Default Behavior** (`GET /v1/secrets/{name}`):
   - Automatically extracts caller's namespace from ServiceAccount (via mTLS certificate)
   - First checks for secret in caller's namespace
   - Falls back to cluster-wide secrets (if RBAC allows)
   - Finally checks AWS Secrets Manager with namespace-aware path

2. **Explicit Namespace Override** (`GET /v1/secrets/{name}?namespace={ns}`):
   - Allows explicit namespace specification
   - Subject to RBAC: caller must have permissions in specified namespace
   - Useful for cross-namespace access (if authorized) or cluster-wide secrets

3. **Cluster-Wide Secrets**:
   - Typically stored in `kube-system` or `platform` namespace
   - Accessible by ServiceAccounts with ClusterRole permissions
   - Examples: shared database credentials, cluster certificates, license keys

4. **AWS Secrets Manager Path Structure**:
   - Full paths configured in Helm chart values
   - Secret names can be simple names (mapped via Helm config) or full paths
   - Example: `database-credentials: "/app/secrets/production/database-credentials"` in Helm values

### Environment Variables

```bash
# Backend Configuration
SECRET_STORE_PRIORITY=kubernetes-secrets,aws-secrets-manager

# Security
MTLS_ENABLED=true
MTLS_CA_CERT_PATH=/etc/tls/ca.crt
MTLS_SERVER_CERT_PATH=/etc/tls/server.crt
MTLS_SERVER_KEY_PATH=/etc/tls/server.key

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
- `secrets_broker_backend_errors_total` - Backend error count
- `secrets_broker_secrets_fetched_total` - Secrets fetched by backend
- `secrets_broker_backend_requests_total` - Backend requests by type (k8s/aws)

### Audit Log Format

```json
{
  "timestamp": "2024-12-19T10:30:00Z",
  "request": {
    "method": "GET",
    "path": "/secrets/database-credentials/password",
    "secret_name": "database-credentials",
    "secret_key": "password",
    "namespace": "production"
  },
  "response": {
    "status_code": 200,
    "backend": "kubernetes-secrets",
    "encoded": false
  },
  "duration_ms": 15
}
```

**Audit Log Fields**:
- `secret_name`: Name of the secret requested
- `secret_key`: Key within the secret requested
- `namespace`: Namespace where secret was stored (required parameter)
- `backend`: Secret store that provided the secret (`kubernetes-secrets` or `aws-secrets-manager`)

## Secret Scoping and Access Control

### Namespace-Scoped Secrets

**Use Case**: Secrets specific to a namespace that should only be accessible by applications in that namespace.

**Examples**:
- Application-specific database credentials per environment (production, staging, dev)
- API keys unique to each namespace
- Service-to-service authentication tokens scoped to namespace

**Access Pattern**:
1. Application in `production` namespace requests secret with `namespace=production`
2. Service checks `production` namespace in Kubernetes Secrets
3. If not found, checks AWS Secrets Manager with path `/app/secrets/production/{secret-name}`
4. Returns secret if found and RBAC allows
5. Returns 404 if not found in any store

**RBAC Requirements**:
- ServiceAccount must have `get` permission on secrets in its namespace
- Typically granted via Role and RoleBinding
- No ClusterRole needed (namespace-scoped only)

### Secret Resolution Flow

```mermaid
flowchart TD
    A[Application Request<br/>namespace=production] --> B[Try Kubernetes Secrets<br/>production/{secret-name}]
    B -->|Found| C[Auto-decode base64]
    C --> D[Return Secret]
    B -->|Not Found| E[Try AWS Secrets Manager<br/>/app/secrets/production/{secret-name}]
    E -->|Found| D
    E -->|Not Found| F[Return 404 Not Found]
    
    style C fill:#50c878
    style D fill:#50c878
    style F fill:#ff6b6b
```

### Best Practices

1. **Naming Conventions**:
   - Namespace-scoped: Use descriptive names (e.g., `app-db-credentials`, `api-keys`)
   - Cluster-wide: Prefix with `shared-` or `cluster-` (e.g., `shared-db-credentials`, `cluster-certificate`)

2. **RBAC Design**:
   - Grant namespace-scoped access by default (least privilege)
   - Use ClusterRoles sparingly for truly shared secrets
   - Document which secrets are cluster-wide and why

3. **Secret Organization**:
   - Keep namespace-scoped secrets in their respective namespaces
   - Centralize cluster-wide secrets in designated namespace (`kube-system` or `platform`)
   - Use consistent naming patterns for easy identification

4. **AWS Secrets Manager Structure**:
   ```
   /app/secrets/
   ├── production/
   │   ├── app-db-credentials
   │   └── api-keys
   ├── staging/
   │   ├── app-db-credentials
   │   └── api-keys
   └── cluster/
       ├── shared-db-credentials
       └── cluster-certificate
   ```

## Security Considerations

1. **mTLS**: All client connections require valid mTLS certificates
2. **RBAC**: ServiceAccount passthrough maintains Kubernetes RBAC enforcement
3. **Namespace Isolation**: Namespace-scoped secrets are automatically isolated by RBAC
4. **Cluster-Wide Access Control**: Cluster-wide secrets require explicit ClusterRole permissions
5. **Secret Encryption**: Secrets in transit encrypted via TLS, secrets at rest encrypted by backend
6. **Audit Logging**: All secret access logged with caller identity, namespace, and secret scope
7. **Least Privilege**: ServiceAccount has minimal required permissions (namespace-scoped by default)
8. **Network Policies**: Restrict network access to secrets broker service
9. **Pod Security**: Run with non-root user, read-only root filesystem

## References

- [Kubernetes Secrets Documentation](https://kubernetes.io/docs/concepts/configuration/secret/)
- [AWS Secrets Manager Documentation](https://docs.aws.amazon.com/secretsmanager/)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Distroless Images](https://github.com/GoogleContainerTools/distroless)
- [External Secrets Operator](https://external-secrets.io/)

---

## Implementation Roadmap: Short-Term vs Long-Term

This section outlines the phased approach for implementing the Secrets Broker Service, balancing immediate needs with long-term enhancements.

### Component Implementation Timeline

| Component/Feature | Short-Term (MVP - Weeks 1-3) | Long-Term (Full Implementation - Weeks 4+) | Rationale |
|-------------------|------------------------------|--------------------------------------------|-----------|
| **Core API Endpoints** | | | |
| Single secret fetch (`GET /v1/secrets/{name}`) | ✅ Implement | ✅ Maintain | Core functionality required for MVP |
| Specific key fetch (`GET /v1/secrets/{name}/{key}`) | ✅ Implement | ✅ Maintain | Essential for structured secrets |
| Batch secret fetch (`POST /v1/secrets/batch`) | ❌ Defer | ✅ Implement | Optimization for multiple secrets; can use multiple single requests initially |
| Health/readiness endpoints | ✅ Implement | ✅ Enhance with detailed checks | Required for K8s probes |
| Metrics endpoint (`/metrics`) | ⚠️ Basic metrics | ✅ Full Prometheus integration | Basic metrics for MVP, comprehensive metrics later |
| | | | |
| **Backend Providers** | | | |
| Kubernetes Secrets backend | ✅ Implement | ✅ Optimize with connection pooling | Primary backend, required for MVP |
| AWS Secrets Manager backend | ✅ Implement | ✅ Add retry logic, rate limiting | Secondary backend, required for MVP |
| Backend priority logic (K8s → AWS) | ✅ Implement | ✅ Configurable priority order | Core requirement |
| Additional backends (Azure Key Vault, HashiCorp Vault, etc.) | ❌ Defer | ✅ Implement as plugins | Not required for initial deployment |
| Backend health checks | ⚠️ Basic | ✅ Comprehensive health monitoring | Basic checks for MVP, detailed monitoring later |
| | | | |
| **Caching** | | | |
| In-memory caching | ❌ Defer | ✅ Implement TTL-based cache | Can start without cache; add for performance optimization |
| Cache invalidation | ❌ Defer | ✅ Implement (TTL + manual invalidation) | Required when caching is implemented |
| Cache size limits | ❌ Defer | ✅ Implement LRU eviction | Required when caching is implemented |
| Distributed caching (Redis) | ❌ Defer | ✅ Consider for multi-replica deployments | Not needed for single-replica MVP |
| Cache metrics | ❌ Defer | ✅ Implement hit/miss ratios | Required when caching is implemented |
| | | | |
| **Authentication & Security** | | | |
| mTLS support | ✅ Implement | ✅ Enhance with certificate rotation | Core security requirement |
| ServiceAccount token passthrough | ✅ Implement | ✅ Add token refresh/rotation logic | Core requirement for RBAC enforcement |
| Basic RBAC enforcement | ✅ Implement | ✅ Fine-grained authorization policies | Core requirement |
| Certificate management | ⚠️ Manual | ✅ Automated rotation via cert-manager | Manual for MVP, automation for production |
| Network policies | ⚠️ Basic | ✅ Comprehensive policies | Basic policies for MVP, detailed policies later |
| Pod security standards | ✅ Implement | ✅ Enhance with PSA policies | Required for security compliance |
| | | | |
| **Observability** | | | |
| Basic audit logging | ✅ Implement | ✅ Enhance with structured logging | Core requirement for compliance |
| Request metadata extraction | ✅ Implement (basic) | ✅ Comprehensive metadata | Basic caller identity for MVP |
| Debug logging (env var controlled) | ✅ Implement | ✅ Enhance with log levels | Required for troubleshooting |
| Application logs (stdout/stderr) | ✅ Implement | ✅ Structured JSON logging | Basic logging for MVP |
| Prometheus metrics | ⚠️ Basic counters | ✅ Comprehensive metrics (histograms, gauges) | Basic metrics for MVP |
| Distributed tracing | ❌ Defer | ✅ Implement (OpenTelemetry) | Not required for MVP |
| Log aggregation | ⚠️ Basic | ✅ Integration with logging stack | Basic for MVP, full integration later |
| | | | |
| **Error Handling & Resilience** | | | |
| Basic error handling | ✅ Implement | ✅ Comprehensive error types | Required for MVP |
| Retry logic | ⚠️ Basic retries | ✅ Exponential backoff, circuit breakers | Basic retries for MVP |
| Circuit breakers | ❌ Defer | ✅ Implement for backend failures | Not critical for MVP |
| Rate limiting | ❌ Defer | ✅ Implement per-client limits | Not required for initial deployment |
| Timeout handling | ✅ Implement | ✅ Configurable per-backend | Required for MVP |
| Graceful shutdown | ⚠️ Basic | ✅ Comprehensive cleanup | Basic for MVP, full cleanup later |
| | | | |
| **Deployment & Operations** | | | |
| Single replica deployment | ✅ Implement | ✅ Multi-replica with HA | Start with single replica |
| Basic resource limits | ✅ Implement | ✅ Optimized based on metrics | Required for resource management |
| Distroless container image | ⚠️ Standard Python image | ✅ Distroless optimization | Standard image for MVP, distroless for production |
| Helm chart | ⚠️ Basic | ✅ Comprehensive with values | Basic chart for MVP |
| CI/CD pipeline | ⚠️ Basic | ✅ Full pipeline with tests | Basic pipeline for MVP |
| Documentation | ⚠️ Basic README | ✅ Comprehensive docs + runbooks | Basic docs for MVP |
| | | | |
| **Testing** | | | |
| Unit tests | ⚠️ Basic coverage | ✅ Comprehensive coverage (>80%) | Basic tests for MVP |
| Integration tests | ⚠️ Basic | ✅ Full integration test suite | Basic tests for MVP |
| Load testing | ❌ Defer | ✅ Comprehensive load testing | Not required for MVP |
| Security testing | ⚠️ Basic | ✅ Penetration testing | Basic security checks for MVP |
| Chaos engineering | ❌ Defer | ✅ Implement chaos tests | Not required for MVP |
| | | | |
| **Advanced Features** | | | |
| Secret versioning support | ❌ Defer | ✅ Implement version selection | Not required for MVP |
| Secret rotation webhooks | ❌ Defer | ✅ Implement webhook notifications | Not required for MVP |
| Secret metadata API | ❌ Defer | ✅ Implement metadata endpoints | Not required for MVP |
| Secret validation | ❌ Defer | ✅ Implement schema validation | Not required for MVP |
| Secret encryption at rest (additional layer) | ❌ Defer | ✅ Consider for sensitive deployments | Backends handle encryption |
| Multi-region support | ❌ Defer | ✅ Implement for AWS multi-region | Not required for MVP |
| Namespace-scoped deployments | ❌ Defer | ✅ Support namespace-scoped instances | Cluster-wide for MVP |

### Short-Term MVP Scope (Weeks 1-3)

**Must Have:**
- Core API endpoints (single secret fetch, key fetch)
- Kubernetes Secrets backend
- AWS Secrets Manager backend
- Backend priority logic
- mTLS support
- ServiceAccount token passthrough
- Basic audit logging
- Health/readiness endpoints
- Basic error handling
- Single replica deployment

**Should Have:**
- Basic metrics endpoint
- Debug logging via environment variable
- Basic resource limits
- Basic unit tests
- Basic documentation

**Nice to Have:**
- Basic retry logic
- Basic integration tests

### Long-Term Enhancements (Weeks 4+)

**Performance Optimizations:**
- TTL-based caching with invalidation
- Connection pooling for backends
- Distributed caching for multi-replica deployments
- Comprehensive metrics and monitoring

**Reliability Enhancements:**
- Circuit breakers
- Rate limiting
- Comprehensive retry logic with exponential backoff
- Multi-replica high availability deployment

**Security Hardening:**
- Automated certificate rotation
- Comprehensive network policies
- Pod security admission policies
- Security penetration testing

**Operational Excellence:**
- Distroless container optimization
- Comprehensive Helm charts
- Full CI/CD pipeline
- Comprehensive documentation and runbooks
- Chaos engineering tests

**Feature Extensions:**
- Batch secret fetching
- Additional backend providers
- Secret versioning
- Secret rotation webhooks
- Multi-region support

### Decision Criteria for Short-Term vs Long-Term

1. **Core Functionality First**: Features required for basic secret fetching are prioritized for MVP
2. **Security Essentials**: mTLS and RBAC enforcement are non-negotiable for MVP
3. **Performance Can Wait**: Caching and optimizations can be added after validating core functionality
4. **Operational Simplicity**: Start with single replica, basic monitoring; scale complexity as needed
5. **Incremental Value**: Each long-term feature should provide measurable value over the MVP

### Risk Mitigation

**Short-Term Risks:**
- **No caching**: May cause higher load on backends → Mitigate with rate limiting and monitoring
- **Single replica**: Single point of failure → Mitigate with quick failover procedures
- **Basic error handling**: May not cover all edge cases → Mitigate with comprehensive logging

**Long-Term Considerations:**
- **Caching complexity**: Cache invalidation and consistency → Plan for distributed cache if needed
- **Multi-replica coordination**: Cache synchronization → Consider Redis or similar
- **Certificate rotation**: Operational overhead → Automate via cert-manager or similar

