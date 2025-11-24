# Secrets Router Service

Dapr-based secrets broker service that routes secret requests to Kubernetes Secrets and AWS Secrets Manager backends.

## Features

- Implements Dapr Secrets API (`/v1.0/secrets/{store}/{key}`)
- Backend priority: Kubernetes Secrets → AWS Secrets Manager
- Supports namespace-scoped and cluster-wide secrets
- mTLS via Dapr Sentry
- Audit logging
- Health and readiness endpoints

## Environment Variables

- `DEBUG_MODE`: Enable debug logging (default: `false`)
- `LOG_LEVEL`: Logging level (default: `INFO`)
- `K8S_CLUSTER_WIDE_NAMESPACE`: Namespace for cluster-wide secrets (default: `kube-system`)
- `AWS_REGION`: AWS region for Secrets Manager (default: `us-east-1`)
- `AWS_SECRETS_MANAGER_PREFIX`: Prefix for AWS secrets (default: `/app/secrets`)
- `AWS_CLUSTER_SECRETS_PREFIX`: Prefix for cluster-wide AWS secrets (default: `/app/secrets/cluster`)
- `SERVER_PORT`: Server port (default: `8080`)

## Building

```bash
docker build -t secrets-router:latest .
```

## Running Locally

```bash
pip install -r requirements.txt
python main.py
```

## API Endpoints

- `GET /healthz` - Health check
- `GET /readyz` - Readiness check
- `GET /v1.0/secrets/{store}/{secret_name}` - Dapr Secrets API
- `GET /v1/secrets/{secret_name}?namespace={ns}&key={key}` - Direct API

