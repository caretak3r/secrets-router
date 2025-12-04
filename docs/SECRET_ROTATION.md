# Secrets Rotation Guide

This document outlines the supported patterns and best practices for rotating secrets in the K8s Secrets Broker service.

## Overview

The Secrets Broker supports multiple rotation strategies across both Kubernetes Secrets and AWS Secrets Manager backends. The service is designed to handle secret rotation with zero downtime and maintain backward compatibility during transitions.

## Supported Rotation Strategies

### 1. Create New Secret (Recommended)

**Best Practice**: Create new secrets with versioned names rather than updating existing secrets in-place.

#### Kubernetes Secrets Rotation

```bash
# Step 1: Create new secret with versioned name
kubectl create secret generic database-credentials-v2 \
  --from-literal=password=newSecurePassword123 \
  --from-literal=username=admin \
  --from-literal=host=production-db.example.com \
  --namespace=production

# Step 2: Update umbrella chart configuration
# override.yaml
sample-service-python:
  secrets:
    rds-credentials: "database-credentials-v2"  # Updated to new version
    api-keys: "api-keys-v2"                    # Updated to new version

# Step 3: Deploy updated configuration
helm upgrade secrets-broker ./charts/umbrella \
  --namespace production \
  -f override.yaml

# Step 4: Verify applications are using new secret
kubectl exec -n production deployment/sample-service-python -- \
  curl "http://secrets-router:8080/secrets/database-credentials-v2/password?namespace=production"

# Step 5: Remove old secret after verification (optional)
kubectl delete secret database-credentials-v1 --namespace=production
```

#### AWS Secrets Manager Rotation

```bash
# Step 1: Create new secret with versioned path/name
aws secretsmanager create-secret \
  --name "production/database-credentials-v2" \
  --secret-string '{
    "password": "newSecurePassword123",
    "username": "admin",
    "host": "production-db.example.com"
  }' \
  --region us-east-1

# Step 2: Configure service mapping
# override.yaml
secrets-router:
  secretStores:
    aws:
      enabled: true
      region: us-east-1
      multipleKeyValuesPerSecret: false

sample-service-python:
  secrets:
    rds-credentials: "production/database-credentials-v2"  # AWS secret name/path

# Step 3: Deploy and verify (same as Kubernetes flow)
```

**Benefits:**
- Zero downtime during rotation
- Immediate rollback capability
- Clear audit trail of version changes
- Applications switch atomically during deployment

### 2. AWS Secrets Manager In-Place Rotation

AWS Secrets Manager supports automatic rotation within the same secret name using multiple versions.

#### IAM Permissions for Rotation

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SecretsManagerReadWrite",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:PutSecretValue",
        "secretsmanager:UpdateSecret",
        "secretsmanager:DescribeSecret",
        "secretsmanager:CreateSecret",
        "secretsmanager:DeleteSecret"
      ],
      "Resource": "arn:aws:secretsmanager:region:account:secret:*"
    },
    {
      "Sid": "SecretsManagerRotation",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:RotateSecret",
        "secretsmanager:CancelRotateSecret",
        "secretsmanager:GetSecretRotationStatus"
      ],
      "Resource": "arn:aws:secretsmanager:region:account:secret:*"
    },
    {
      "Sid": "LambdaRotationPermissions",
      "Effect": "Allow",
      "Action": [
        "lambda:InvokeFunction"
      ],
      "Resource": "arn:aws:lambda:region:account:function:*RotationFunction*"
    }
  ]
}
```

#### AWS Automatic Rotation Setup

```bash
# Enable automatic rotation (requires Lambda function)
aws secretsmanager rotate-secret \
  --secret-id "production/database-credentials" \
  --rotation-lambda-arn "arn:aws:lambda:region:account:function:MyRotationFunction" \
  --rotation-rules AutomaticallyAfterDays=30

# Check rotation status
aws secretsmanager DescribeSecret --secret-id "production/database-credentials"
```

#### Version Management

Applications can specify which version to use:

```bash
# Get current version (latest)
curl "http://secrets-router:8080/secrets/database-credentials/password?namespace=production"

# AWS automatically manages versions - applications always get the latest
# Previous versions remain available for rollback if needed
```

**Benefits:**
- Automated rotation without manual intervention
- Built-in version history and rollback
- Integrates with AWS rotation Lambda functions

**Considerations:**
- Requires additional Lambda function for complex rotation logic
- Applications automatically receive new values (may need refresh logic)
- More complex setup and troubleshooting

## Configuration Examples

### Multi-Backend Rotation Strategy

```yaml
# override.yaml - Production setup with rotation workflow
secrets-router:
  secretStores:
    aws:
      enabled: true
      region: us-east-1
      multipleKeyValuesPerSecret: false
    kubernetes:
      enabled: true

# Services with versioned secret references
sample-service-python:
  secrets:
    # Primary database credentials (currently v2)
    rds-credentials: "database-credentials-v2"
    # API keys (currently v3)
    api-keys: "api-keys-v3"
    # Shared service credentials (unversioned, external rotation)
    shared-redis: "production/shared-redis-credentials"

sample-service-node:
  secrets:
    # Different version for isolation
    rds-credentials: "database-credentials-v2"
    # Service-specific secrets
    node-api-keys: "node-api-keys-v1"
```

### Rotation Workflow Configuration

```yaml
# override.yaml - with rotation metadata
secrets-router:
  env:
    ROTATION_ENABLED: "true"
    ROTATION_GRACE_PERIOD: "3600"  # 1 hour grace period
    ROTATION_NOTIFICATION_WEBHOOK: "https://hooks.slack.com/..."

sample-service-python:
  secrets:
    database-credentials:
      name: "database-credentials-v2"
      metadata:
        rotation_policy: "manual"
        last_rotation: "2024-12-01T10:00:00Z"
        rotation_grace_period: "2h"
        notification_channels: ["slack", "email"]
```

## Environment-Specific Considerations

### Development Environments

```yaml
# Development - rapid rotation for testing
secrets-router:
  env:
    DEBUG_MODE: "true"
    ROTATION_ENABLED: "true"
    SECRET_CACHE_TTL: "300"  # 5 minutes for rapid updates

sample-service-dev:
  secrets:
    dev-db: "dev-db-$(date +%s)"  # Timestamp-based names
```

### Production Environments

```yaml
# Production - conservative rotation approach
secrets-router:
  env:
    DEBUG_MODE: "false"
    SECRET_CACHE_TTL: "3600"  # 1 hour cache for stability
    ROTATION_GRACE_PERIOD: "7200"  # 2 hours rollback window

sample-service-prod:
  secrets:
    prod-db: "production-database-credentials-v4"
    prod-api: "production-api-keys-v2"
```

## Monitoring and Auditing

### Rotation Events Logging

The service logs all rotation-related events with detailed metadata:

```json
{
  "timestamp": "2024-12-01T15:30:00Z",
  "event_type": "secret_rotation",
  "secret_name": "database-credentials",
  "old_version": "v1",
  "new_version": "v2",
  "namespace": "production",
  "backend": "kubernetes-secrets",
  "initiated_by": "helm-upgrade",
  "affected_services": [
    "sample-service-python",
    "sample-service-node"
  ]
}
```

### Health Checks During Rotation

The health check endpoints continue to work during rotation:

```bash
# Service health (independent of secret changes)
curl "http://secrets-router:8080/healthz"

# Readiness check (validates Dapr and secret backends)
curl "http://secrets-router:8080/readyz"

# Test access to rotated secret
curl "http://secrets-router:8080/secrets/database-credentials-v2/password?namespace=production"
```

## Troubleshooting

### Common Rotation Issues

#### 1. Secret Not Found After Rotation

```bash
# Check secret exists
kubectl get secret database-credentials-v2 -n production

# Check service configuration
kubectl get configmap -n production -l app.kubernetes.io/name=secrets-router

# Test access directly
kubectl exec -n production deployment/secrets-router -- \
  curl "http://localhost:8080/secrets/database-credentials-v2/password?namespace=production"
```

#### 2. Applications Still Using Old Secret

```bash
# Check application environment
kubectl exec -n production deployment/sample-service-python -- \
  env | grep SECRETS_ROUTER_URL

# Verify service endpoints
kubectl get endpoints -n production secrets-router

# Restart application to pick up new configuration
kubectl rollout restart deployment/sample-service-python -n production
```

#### 3. AWS Secret Access Issues

```bash
# Check IAM permissions
aws sts get-caller-identity

# Verify secret exists and is accessible
aws secretsmanager GetSecretValue \
  --secret-id "production/database-credentials-v2" \
  --region us-east-1

# Check Dapr component configuration
kubectl get daprcomponent -n production
```

## Best Practices

### 1. Rotation Planning

1. **Pre-rotation Testing**: Test new secrets in staging environment first
2. **Rollback Plan**: Always maintain ability to revert to previous versions
3. **Gradual Rollout**: Use canary deployments for critical secrets
4. **Documentation**: Track rotation history and decisions

### 2. Configuration Management

1. **Version Naming**: Use consistent naming (v1, v2, or timestamps)
2. **Environment Separation**: Different rotation strategies per environment
3. **Automated Validation**: Scripts to verify post-rotation functionality
4. **Change Management**: Formal process for production rotations

### 3. Monitoring and Alerting

1. **Rotation Metrics**: Track rotation frequency and success rates
2. **Application Health**: Monitor application behavior during/after rotation
3. **Access Patterns**: Alert on unusual secret access patterns
4. **Audit Trails**: Maintain comprehensive rotation logs

## Integration Examples

### CI/CD Pipeline Integration

```yaml
# .github/workflows/secret-rotation.yml
name: Secret Rotation
on:
  schedule:
    - cron: '0 2 * * 1'  # Weekly on Monday 2 AM

jobs:
  rotate-secrets:
    runs-on: ubuntu-latest
    steps:
      - name: Create new secret
        run: |
          # Generate new password
          NEW_PASSWORD=$(openssl rand -base64 32)
          
          # Create new versioned secret
          kubectl create secret generic db-credentials-$(date +%s) \
            --from-literal=password=$NEW_PASSWORD \
            --namespace=production
            
      - name: Update configuration
        run: |
          # Update override.yaml with new secret name
          sed -i 's/db-credentials: ".*"/db-credentials: "db-credentials-$(date +%s)"/' override.yaml
          
      - name: Deploy update
        run: |
          helm upgrade secrets-broker ./charts/umbrella \
            --namespace production \
            -f override.yaml
            
      - name: Verify deployment
        run: |
          # Test secret access
          kubectl exec -n production deployment/secrets-router -- \
            curl "http://localhost:8080/secrets/..." \
            --max-time 30
```

### Application Integration Examples

```python
# Python application with refresh capability
import requests
import os
import time

class SecretManager:
    def __init__(self):
        self.secrets_url = os.getenv('SECRETS_ROUTER_URL')
        self.namespace = os.getenv('NAMESPACE')
        self.cache = {}
        self.last_refresh = {}
        
    def get_secret(self, secret_name: str, secret_key: str, force_refresh: bool = False):
        cache_key = f"{secret_name}/{secret_key}"
        
        # Check cache and age
        if not force_refresh and cache_key in self.cache:
            if time.time() - self.last_refresh.get(cache_key, 0) < 3600:  # 1 hour
                return self.cache[cache_key]
        
        # Fetch fresh secret
        try:
            response = requests.get(
                f"{self.secrets_url}/secrets/{secret_name}/{secret_key}",
                params={"namespace": self.namespace},
                timeout=10
            )
            response.raise_for_status()
            
            secret_value = response.json()['value']
            self.cache[cache_key] = secret_value
            self.last_refresh[cache_key] = time.time()
            
            return secret_value
            
        except requests.RequestException as e:
            # If fetch fails, return cached value if available
            if cache_key in self.cache:
                print(f"Warning: Using cached secret for {cache_key}: {e}")
                return self.cache[cache_key]
            raise

# Usage
secrets = SecretManager()
db_password = secrets.get_secret("database-credentials-v2", "password")

# Force refresh after known rotation
db_password = secrets.get_secret("database-credentials-v2", "password", force_refresh=True)
```

## Security Considerations

### 1. Minimal Exposure During Rotation

- New secrets should be created with appropriate permissions
- Old secrets should be revoked/deleted after verification
- Audit all access during rotation periods

### 2. Access Control

```yaml
# ServiceAccount with restricted access during rotation
apiVersion: v1
kind: ServiceAccount
metadata:
  name: secrets-rotation-operator
  namespace: production
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::account:role/secrets-rotation-role
```

### 3. Compliance and Audit

- Maintain rotation logs for compliance periods
- Document rotation procedures and approvals
- Regular access reviews for secret management

## Future Enhancements

Planned features for enhanced rotation support:

1. **Automated Rotation API**: Built-in endpoints for rotation workflows
2. **Secret Rotation Policies**: Declarative rotation configuration
3. **Multi-Region Coordination**: Cross-region secret rotations
4. **Advanced Monitoring**: Rotation-specific metrics and alerting
5. **Rollback Automation**: Automated rollback on detection of issues

## Support and Troubleshooting

For rotation-related issues:

1. Check service logs for rotation events
2. Verify secret existence and permissions
3. Test endpoint connectivity
4. Review configuration consistency
5. Validate application integration

Detailed troubleshooting steps and common error patterns are documented in the Troubleshooting section above.
