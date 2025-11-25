# Changes Summary

This document summarizes all changes made to reflect the updated architecture requirements.

## Architecture Changes

### 1. Umbrella Chart Deployment ✅

- **Created**: `charts/umbrella/Chart.yaml` - Umbrella chart with Dapr and Secrets Router dependencies
- **Created**: `charts/umbrella/values.yaml` - Configuration values for umbrella chart
- **Created**: `charts/umbrella/README.md` - Umbrella chart documentation
- **Created**: `charts/umbrella/templates/_helpers.tpl` - Helm template helpers

**Impact**: Customers install a single umbrella chart that includes both Dapr control plane and Secrets Router service.

### 2. Namespace-Scoped Architecture ✅

- **Updated**: `secrets-router/main.py` - Removed cluster-wide secret logic
- **Updated**: `ADR.md` - Removed references to cluster-wide secrets
- **Updated**: API endpoint - `namespace` parameter is now **required**

**Changes**:
- All secrets are namespace-scoped
- No cluster-wide secrets concept
- Namespace must be provided in API requests
- Secrets stored in customer's deployment namespace

### 3. Auto-Decoding of Kubernetes Secrets ✅

- **Updated**: `secrets-router/main.py` - Added automatic base64 decoding for K8s secrets
- **Behavior**: Kubernetes secrets are automatically decoded before returning to caller
- **Transparent**: Developers receive decoded values without needing to decode themselves

**Code Change**:
```python
# Auto-decode K8s secrets (they come base64 encoded from K8s API)
if "kubernetes" in store_lower:
    decoded_value = base64.b64decode(value).decode('utf-8')
    value = decoded_value
```

### 4. Path-Based AWS Secrets Manager ✅

- **Added**: `AWS_SECRETS_PATH_PREFIX` environment variable
- **Updated**: `charts/secrets-router/values.yaml` - Added AWS path prefix configuration
- **Updated**: `charts/umbrella/values.yaml` - Added AWS path prefix configuration
- **Format**: `{AWS_SECRETS_PATH_PREFIX}/{namespace}/{secret-name}`

**Example**: `/app/secrets/production/database-credentials`

### 5. Developer Documentation ✅

- **Created**: `DEVELOPER_GUIDE.md` - Comprehensive developer-focused guide
- **Created**: `QUICKSTART.md` - Quick start guide
- **Updated**: `README.md` - Updated main README with new architecture

**Contents**:
- API usage examples (Python, Go, Node.js)
- Code snippets and patterns
- Best practices
- Troubleshooting guide

### 6. Removed Secrets Router Component ✅

- **Deleted**: `dapr-components/secrets-router-component.yaml`
- **Reason**: Secrets Router service doesn't need its own Dapr component - it queries other components directly

### 7. Updated Diagrams ✅

- **Updated**: `ARCHITECTURE.md` - New architecture diagrams
- **Updated**: `DAPR_INTEGRATION.md` - Updated sequence diagrams
- **Updated**: `ADR.md` - Updated flow diagrams

**Key Changes**:
- Removed cluster-wide secret references
- Added namespace-scoped flow
- Added auto-decoding step
- Updated AWS path format

### 8. Updated ADR ✅

- **Updated**: Decision outcome section - Changed to Option 3 (Dapr-based)
- **Updated**: Secret scoping section - Removed cluster-wide secrets
- **Updated**: API endpoints section - Simplified to single endpoint
- **Updated**: Environment variables section - Removed cluster-wide config
- **Updated**: RBAC section - Changed to namespace-scoped Role/RoleBinding

## Code Changes

### secrets-router/main.py

1. **Auto-decoding**: Added automatic base64 decoding for K8s secrets
2. **Namespace required**: Made namespace parameter required
3. **Path-based AWS**: Added AWS_SECRETS_PATH_PREFIX support
4. **Error handling**: Improved error messages for missing namespace

### Helm Charts

1. **Umbrella chart**: New chart with dependencies
2. **Environment variables**: Added AWS_SECRETS_PATH_PREFIX
3. **Namespace injection**: Added NAMESPACE environment variable from pod metadata

## Documentation Changes

### New Files

- `DEVELOPER_GUIDE.md` - Developer-focused usage guide
- `QUICKSTART.md` - Quick start guide
- `ARCHITECTURE.md` - Architecture diagrams and details
- `CHANGES_SUMMARY.md` - This file

### Updated Files

- `README.md` - Updated with new architecture
- `ADR.md` - Updated to reflect namespace-scoped architecture
- `DAPR_INTEGRATION.md` - Updated diagrams and flow
- `charts/umbrella/README.md` - Umbrella chart documentation

## Migration Notes

### For Existing Deployments

If you have an existing deployment:

1. **Update API calls**: Add `namespace` parameter (now required)
2. **Remove cluster-wide secrets**: Move to namespace-scoped
3. **Update AWS paths**: Use new path format: `{prefix}/{namespace}/{secret-name}`
4. **Redeploy**: Use new umbrella chart

### API Changes

**Before**:
```
GET /v1/secrets/{name}?namespace={ns}  # namespace optional
```

**After**:
```
GET /secrets/{name}/{key}?namespace={ns}  # namespace required
```

## Testing Checklist

- [ ] Umbrella chart installs successfully
- [ ] Dapr control plane deployed
- [ ] Secrets Router service deployed
- [ ] Dapr components deployed
- [ ] Kubernetes secrets can be fetched
- [ ] AWS secrets can be fetched (if configured)
- [ ] Auto-decoding works for K8s secrets
- [ ] Namespace parameter validation works
- [ ] Priority resolution works (K8s → AWS)
- [ ] Health checks work
- [ ] Developer examples work

## Breaking Changes

1. **API Endpoint Changed**: `/v1/secrets/{name}` → `/secrets/{name}/{key}`
2. **Namespace Required**: No longer optional
3. **No Cluster-Wide Secrets**: All secrets must be namespace-scoped
4. **Component Removed**: secrets-router-component.yaml no longer needed

## Next Steps

1. Test umbrella chart installation
2. Verify Dapr component integration
3. Test secret retrieval from both stores
4. Validate auto-decoding behavior
5. Update application code to use new API

