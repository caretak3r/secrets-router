# Secrets Broker Umbrella Chart

This umbrella chart installs the complete Secrets Broker solution, including Dapr control plane and Secrets Router service.

## Quick Start

```bash
# Install in your namespace
helm install secrets-broker ./charts/umbrella \
  --namespace production \
  --create-namespace \
  --set global.namespace=production
```

## Chart Dependencies

- **dapr**: Dapr control plane (installed in `dapr-system` namespace)
- **secrets-router**: Secrets Router service (installed in your namespace)

## Configuration

### Basic Configuration

```yaml
global:
  namespace: production  # Your application namespace

dapr:
  enabled: true

secrets-router:
  enabled: true
```

### AWS Secrets Manager Configuration

If using AWS Secrets Manager:

```yaml
secrets-router:
  env:
    SECRET_STORE_PRIORITY: "kubernetes-secrets,aws-secrets-manager"
    AWS_SECRETS_PATH_PREFIX: "/app/secrets"  # Path prefix for AWS secrets
  
  serviceAccount:
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/secrets-router-role
```

### Custom Image Registry

```yaml
secrets-router:
  image:
    repository: your-registry.io/secrets-router
    tag: v1.0.0
```

## Values Reference

See `values.yaml` for all configurable options.

## Post-Installation

After installing the umbrella chart:

1. **Deploy Dapr Components**:
   ```bash
   kubectl apply -f dapr-components/kubernetes-secrets-component.yaml -n <namespace>
   kubectl apply -f dapr-components/aws-secrets-manager-component.yaml -n <namespace>
   ```

2. **Verify Installation**:
   ```bash
   kubectl get pods -n <namespace> -l app.kubernetes.io/name=secrets-router
   kubectl get components -n <namespace>
   ```

3. **Test Secret Retrieval**:
   ```bash
   kubectl port-forward -n <namespace> svc/secrets-router 8080:8080
   curl http://localhost:8080/secrets/my-secret/password?namespace=<namespace>
   ```

## Uninstallation

```bash
helm uninstall secrets-broker -n <namespace>
```

Note: Dapr control plane in `dapr-system` namespace will remain if other applications use it.

