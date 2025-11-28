# Secrets Broker Architecture with Performance Monitoring

```mermaid
graph TB
    %% Subgraphs for better organization
    subgraph "Load Balancer / Cluster Ingress"
        LB[Kubernetes Service / ClusterIP]
    end

    subgraph "Application Services (10x replica deployment)"
        subgraph "App Namespace 1"
            APP1[App Pod 1]
            APP2[App Pod 2] 
            APP3[App Pod 3]
        end
        
        subgraph "App Namespace 2" 
            APP4[App Pod 4]
            APP5[App Pod 5]
            APP6[App Pod 6]
        end
        
        subgraph "App Namespace 3"
            APP7[App Pod 7]
            APP8[App Pod 8]
            APP9[App Pod 9]
            APP10[App Pod 10]
        end
        
        SHARED_SECRET[Shared Secret<br/>test-namespace<br/>database-credentials]
    end

    subgraph "Secrets Router System"
        subgraph "Router Namespace: test-namespace"
            ROUTER[Secrets Router<br/>FastAPI Service<br/>Port: 8080]
            DAPR_SIDECAR[Dapr Sidecar<br/>HTTP: 3500<br/>gRPC: 50001]
            ROUTER <-->|localhost:3500| DAPR_SIDECAR
        end
        
        subgraph "Dapr Control Plane (dapr-system)"
            DAPR_OP[Dapr Operator]
            DAPR_SENTRY[Dapr Sentry<br/>mTLS Authority]
            DAPR_PLACEMENT[Dapr Placement<br/>Actor Placement]
            DAPR_SCHEDULER[Dapr Scheduler<br/>Job Scheduling]
        end
        
        subgraph "Dapr Components"
            K8S_COMP[Kubernetes Secrets<br/>Component<br/>Namespace Access Control]
            K8S_API[Kubernetes API Server<br/>Secret Store Backend]
        end
    end

    subgraph "Monitoring Stack"
        subgraph "monitoring namespace"
            PROMETHEUS[Prometheus<br/>Time Series Database]
            GRAFANA[Grafana<br/>Visualization Dashboard]
            ALERTMANAGER[AlertManager<br/>Alert Routing]
            
            PROMETHEUS -->|Query API| GRAFANA
            PROMETHEUS -->|Alert Rules| ALERTMANAGER
        end
        
        subgraph "Metrics Collection"
            PROM_POD[Node Exporter]
            DAPR_METRICS[Dapr Metrics<br/>Port: 9090]
            APP_METRICS[Application Metrics<br/>Performance Data]
        end
    end

    %% Secret Storage Areas
    subgraph "Secret Storage Backends"
        subgraph "test-namespace"
            SECRET1[database-credentials]
            SECRET2[api-keys]
        end
        subgraph "default namespace"
            SECRET3[shared-config]
            SECRET4[certificates]
        end
        subgraph "app namespaces"
            SECRET5[app-specific-secrets]
        end
    end

    %% Connection flows for secret access
    APP1 -->|HTTP GET /secrets/*| LB
    APP2 -->|HTTP GET /secrets/*| LB
    APP3 -->|HTTP GET /secrets/*| LB
    APP4 -->|HTTP GET /secrets/*| LB
    APP5 -->|HTTP GET /secrets/*| LB
    APP6 -->|HTTP GET /secrets/*| LB
    APP7 -->|HTTP GET /secrets/*| LB
    APP8 -->|HTTP GET /secrets/*| LB
    APP9 -->|HTTP GET /secrets/*| LB
    APP10 -->|HTTP GET /secrets/*| LB
    
    LB -->|Load Balancing| ROUTER
    
    %% Internal Dapr communication
    ROUTER -->|Secret Request| DAPR_SIDECAR
    DAPR_SIDECAR -->|Component API| K8S_COMP
    K8S_COMP -->|Read Secret| K8S_API
    K8S_API -->|Return Secret Data| K8S_COMP
    K8S_COMP -->|Decoded Value| DAPR_SIDECAR
    DAPR_SIDECAR -->|HTTP Response| ROUTER
    ROUTER -->|JSON Response| APP1
    ROUTER -->|JSON Response| APP2
    ROUTER -->|JSON Response| APP3
    ROUTER -->|JSON Response| APP4
    ROUTER -->|JSON Response| APP5
    ROUTER -->|JSON Response| APP6
    ROUTER -->|JSON Response| APP7
    ROUTER -->|JSON Response| APP8
    ROUTER -->|JSON Response| APP9
    ROUTER -->|JSON Response| APP10
    
    %% Dapr control plane connections
    DAPR_SIDECAR -.->|mTLS certs| DAPR_SENTRY
    DAPR_SIDECAR -.->|Actor placement| DAPR_PLACEMENT
    DAPR_SIDECAR -.->|Component registration| DAPR_OP
    DAPR_SIDECAR -.->|Scheduling| DAPR_SCHEDULER
    
    %% Metrics collection flows
    ROUTER -->|Performance Metrics| PROMETHEUS
    DAPR_SIDECAR -->|Dapr Metrics| DAPR_METRICS
    DAPR_METRICS -->|Scrape Metrics| PROMETHEUS
    APP1 -->|Request Metrics| PROMETHEUS
    APP2 -->|Request Metrics| PROMETHEUS
    APP3 -->|Request Metrics| PROMETHEUS
    APP4 -->|Request Metrics| PROMETHEUS
    APP5 -->|Request Metrics| PROMETHEUS
    APP6 -->|Request Metrics| PROMETHEUS
    APP7 -->|Request Metrics| PROMETHEUS
    APP8 -->|Request Metrics| PROMETHEUS
    APP9 -->|Request Metrics| PROMETHEUS
    APP10 -->|Request Metrics| PROMETHEUS
    PROM_POD -->|Node Metrics| PROMETHEUS
    
    %% Secret access patterns
    K8S_COMP -.->|Namespace: test-namespace| SECRET1
    K8S_COMP -.->|Namespace: test-namespace| SECRET2
    K8S_COMP -.->|Namespace: default| SECRET3
    K8S_COMP -.->|Namespace: default| SECRET4
    K8S_COMP -.->|Cross-namespace| SECRET5

    %% Styling
    classDef appService fill:#3498db,stroke:#2c3e50,color:white
    classDef routerService fill:#2ecc71,stroke:#2c3e50,color:white
    classDef daprService fill:#9b59b6,stroke:#2c3e50,color:white
    classDef monitoring fill:#e74c3c,stroke:#2c3e50,color:white
    classDef secret fill:#f39c12,stroke:#2c3e50,color:white
    
    class APP1,APP2,APP3,APP4,APP5,APP6,APP7,APP8,APP9,APP10 appService
    class ROUTER routerService
    class DAPR_SIDECAR,DAPR_OP,DAPR_SENTRY,DAPR_PLACEMENT,DAPR_SCHEDULER daprService
    class PROMETHEUS,GRAFANA,ALERTMANAGER,PROM_POD,DAPR_METRICS,APP_METRICS monitoring
    class SECRET1,SECRET2,SECRET3,SECRET4,SECRET5,SHARED_SECRET secret

    %% Annotations
    note right of ROUTER: **Centralized Secrets Router**<br/>• FastAPI HTTP API<br/>• Dapr Sidecar Integration<br/>• Multi-namespace Support<br/>• Auto-secret Decoding
    note right of K8S_COMP: **Dapr Kubernetes Component**<br/>• Namespace Scoping<br/>• Access Control<br/>• Base64 Decoding
    note right of GRAFANA: **Performance Dashboard**<br/>• Request Rates<br/>• Response Times<br/>• Error Rates<br/>• Resource Usage
```

# Request Flow Sequence

```mermaid
sequenceDiagram
    participant App as Application Service
    participant LB as Load Balancer  
    participant Router as Secrets Router
    participant Dapr as Dapr Sidecar
    participant K8sComp as K8s Component
    participant K8sAPI as K8s API
    participant Grafana as GrafanaDashboard
    participant Prometheus as Prometheus

    %% Concurrent requests from multiple services
    par Concurrent Access (10x)
        App->>+LB: GET /secrets/database-creds/password?namespace=test-namespace
    and    
        App->>+LB: GET /secrets/shared-config/api-key?namespace=default
    and
        App->>+LB: GET /secrets/app-secret/token?namespace=app-namespace
    end

    LB->>+Router: HTTP Request
    Router->>+Prometheus: Record Request Metrics
    Router->>+Dapr: GET /v1.0/secrets/kubernetes-secrets/secret?metadata.namespace=xxx
    
    Dapr->>+K8sComp: Component API Call
    K8sComp->>+K8sAPI: Read Secret from Namespace
    K8sAPI-->>-K8sComp: Secret Data (base64)
    K8sComp->>K8sComp: Decode base64
    K8sComp-->>-Dapr: Secret Value (plaintext)
    
    Dapr-->>-Router: HTTP Response with Secret
    Router-->>-Prometheus: Record Response Metrics
    Router-->>-LB: JSON Response
    
    LB-->>-App: Secret Value
    App->>+Prometheus: Application Metrics
    Prometheus->>+Grafana: Update Dashboard
    
    Note over Prometheus,Grafana: Live Performance Monitoring<br/>• Request Rate/sec<br/>• Response Time(ms)<br/>• Success/Error Rate<br/>• Resource Utilization
```

# Performance Metrics Dashboard Overview

The Grafana dashboard provides real-time monitoring of:

## **Key Metrics Tracked**

### **Application Performance**
- **Request Rate**: Requests per second to secrets router
- **Response Time**: Average and P99 latency
- **Error Rate**: Failed requests vs successful requests
- **Throughput**: Total secrets fetched per minute

### **Resource Utilization**
- **CPU Usage**: Secrets router pod CPU consumption
- **Memory Usage**: Pod memory (request/response size impact)
- **Network I/O**: Internal Dapr communication overhead
- **Dapr Metrics**: Sidecar resource utilization

### **Dapr Component Performance**
- **Secret Store Latency**: Time to fetch from Kubernetes API
- **Component Error Rate**: Authentication/access failures
- **Cache Hit Rate**: Component caching effectiveness
- **Connection Pool**: Dapr connection usage

### **Kubernetes Infrastructure**
- **Pod Health**: Secrets router availability
- **Node Resources**: Cluster resource impact
- **Network Traffic**: Cross-namespace communication
- **API Server Load**: Kubernetes secret access patterns
