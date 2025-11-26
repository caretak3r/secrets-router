# Changes Summary: Secrets Router Helm Chart Architecture Update

## Overview

Updated the Secrets Router architecture to support:
1. Umbrella chart structure (`control-plane-umbrella`)
2. Secrets Router chart dependency on Dapr
3. Configurable Dapr Components generated from Helm values
4. Multi-namespace secret access support
5. Namespace determined from `{{ .Release.Namespace }}` (no hardcoded namespaces)

## Key Changes

### 1. Chart Structure Updates

#### Umbrella Chart (`charts/umbrella/Chart.yaml`)
- **Renamed**: `secrets-broker` → `control-plane-umbrella`
- **Dependencies**: Dapr and Secrets Router remain as dependencies

#### Secrets Router Chart (`charts/secrets-router/Chart.yaml`)
- **Added**: Dependency on Dapr chart
- Ensures Dapr is installed before Secrets Router

### 2. New Template: `secrets-components.yaml`

**Location**: `charts/secrets-router/templates/secrets-components.yaml`

**Purpose**: Generates Dapr Component resources based on Helm values

**Features**:
- Supports multiple secret store types (Kubernetes, AWS Secrets Manager)
- Configurable namespaces for Kubernetes secrets
- Generates components in `{{ .Release.Namespace }}`
- Configurable via `secretStores.stores` in values.yaml

**Example Generated Component**:
```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: kubernetes-secrets
  namespace: <Release.Namespace>
spec:
  type: secretstores.kubernetes
  version: v1
  metadata:
  - name: allowedNamespaces
    value: "production,staging,shared-services"
  - name: defaultSecretStore
    value: "true"
```

### 3. Values Configuration Updates

#### `charts/secrets-router/values.yaml`
**Added**: `secretStores` section:
```yaml
secretStores:
  enabled: true
  stores:
    kubernetes-secrets:
      type: secretstores.kubernetes
      defaultSecretStore: true
      namespaces:
        - production
        - staging
    aws-secrets-manager:
      type: secretstores.aws.secretsmanager
      defaultSecretStore: false
      region: us-east-1
      pathPrefix: "/app/secrets"
      auth:
        secretStore: kubernetes
```

#### `charts/umbrella/values.yaml`
**Updated**: Added `secretStores` configuration under `secrets-router` section

### 4. Template Updates: Namespace Usage

All templates now use `{{ .Release.Namespace }}` instead of hardcoded namespaces:

- ✅ `deployment.yaml` - Added `namespace: {{ .Release.Namespace }}`
- ✅ `service.yaml` - Added `namespace: {{ .Release.Namespace }}`
- ✅ `serviceaccount.yaml` - Added `namespace: {{ .Release.Namespace }}`
- ✅ `rbac.yaml` - Added `namespace: {{ .Release.Namespace }}` to Role and RoleBinding
- ✅ `secrets-components.yaml` - Uses `{{ $.Release.Namespace }}` for Component namespace

### 5. Dapr Annotations Updates

#### `charts/secrets-router/templates/deployment.yaml`
**Added**: Dapr component scoping annotation:
```yaml
annotations:
  dapr.io/component-scope: "{{ .Release.Namespace }}"
```

This ensures Dapr components are scoped to the release namespace.

### 6. Documentation Updates

#### `ARCHITECTURE.md`
- Updated to reflect `control-plane-umbrella` chart name
- Added explanation of chart dependencies
- Added developer workflow section
- Updated configuration examples

#### `ADR.md`
- Updated rationale section with new architecture details
- Updated implementation plan phases
- Added notes about configurable components and multi-namespace support

#### `DEVELOPER_GUIDE.md`
- Added "Configuring Secret Stores" section
- Updated secret storage locations explanation
- Added troubleshooting for namespace configuration
- Added integration examples for service helm charts

#### `secrets-router/main.py`
- Updated docstrings to explain namespace parameter
- Added architecture context comments
- Clarified how namespace validation works with Dapr components

### 7. New Documentation Files

#### `SECRETS_ROUTER_INTEGRATION.md`
**Purpose**: Comprehensive guide for integrating Secrets Router with service helm charts

**Contents**:
- Architecture overview
- Developer workflow (4 steps)
- Integration options for service charts
- Example service chart integration
- Troubleshooting guide

## Developer Workflow

### Before (Old Way)
1. Create secrets in namespace
2. Hardcode namespace in component files
3. Manually create/update Dapr Component resources
4. Redeploy components

### After (New Way)
1. Create secrets in any namespace
2. Update `override.yaml` to add namespace to `secretStores.stores.kubernetes-secrets.namespaces`
3. Run `helm upgrade control-plane ./charts/umbrella -f override.yaml`
4. Components are automatically generated/updated

## Benefits

1. **Streamlined Configuration**: Update `override.yaml` instead of editing component files
2. **No Code Changes**: Adding new namespaces doesn't require code changes
3. **Multi-Namespace Support**: Access secrets from multiple namespaces
4. **Namespace Flexibility**: All resources use `{{ .Release.Namespace }}`
5. **Template-Based**: Components generated from Helm values
6. **Developer Friendly**: Simple workflow for adding new secret locations

## Migration Guide

### For Existing Deployments

1. **Update Chart Name**:
   ```bash
   # Old
   helm install secrets-broker ./charts/umbrella
   
   # New
   helm install control-plane ./charts/umbrella
   ```

2. **Create override.yaml**:
   ```yaml
   secrets-router:
     secretStores:
       enabled: true
       stores:
         kubernetes-secrets:
           namespaces:
             - <your-namespace>
   ```

3. **Upgrade Release**:
   ```bash
   helm upgrade control-plane ./charts/umbrella -f override.yaml
   ```

### For New Deployments

1. **Install Umbrella Chart**:
   ```bash
   helm install control-plane ./charts/umbrella -f override.yaml
   ```

2. **Configure Secret Stores** in `override.yaml`:
   ```yaml
   secrets-router:
     secretStores:
       stores:
         kubernetes-secrets:
           namespaces:
             - production
             - staging
   ```

3. **Create Secrets** in configured namespaces

4. **Use Secrets** in applications via HTTP API

## Files Changed

### Charts
- `charts/umbrella/Chart.yaml` - Renamed to control-plane-umbrella
- `charts/umbrella/values.yaml` - Added secretStores configuration
- `charts/secrets-router/Chart.yaml` - Added Dapr dependency
- `charts/secrets-router/values.yaml` - Added secretStores section
- `charts/secrets-router/templates/deployment.yaml` - Added namespace, Dapr annotations
- `charts/secrets-router/templates/service.yaml` - Added namespace
- `charts/secrets-router/templates/serviceaccount.yaml` - Added namespace
- `charts/secrets-router/templates/rbac.yaml` - Added namespaces to Role/RoleBinding
- `charts/secrets-router/templates/secrets-components.yaml` - **NEW** - Generates Dapr Components

### Documentation
- `ARCHITECTURE.md` - Updated architecture details
- `ADR.md` - Updated decision rationale and implementation plan
- `DEVELOPER_GUIDE.md` - Added configuration and integration guides
- `secrets-router/main.py` - Updated docstrings and comments
- `SECRETS_ROUTER_INTEGRATION.md` - **NEW** - Integration guide
- `CHANGES_SUMMARY.md` - **NEW** - This file

## Testing

To test the new architecture:

1. **Template Test**:
   ```bash
   helm template test ./charts/secrets-router -f test-values.yaml
   ```

2. **Verify Components Generated**:
   ```bash
   helm template test ./charts/secrets-router -f test-values.yaml | grep -A 20 "kind: Component"
   ```

3. **Check Namespace Usage**:
   ```bash
   helm template test ./charts/secrets-router -f test-values.yaml | grep "namespace:"
   ```

## Next Steps

1. Test helm chart installation with new structure
2. Verify Dapr Components are created correctly
3. Test multi-namespace secret access
4. Update CI/CD pipelines if needed
5. Update any existing deployment scripts

## Questions?

See:
- `SECRETS_ROUTER_INTEGRATION.md` for integration examples
- `DEVELOPER_GUIDE.md` for usage examples
- `ARCHITECTURE.md` for architecture details
