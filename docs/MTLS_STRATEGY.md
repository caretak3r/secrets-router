# Unified mTLS Strategy: cert-manager + Dapr

## 1. The Objective
To establish a Zero Trust environment where:
1.  **mTLS** is enforced between all services (specifically `secrets-router`).
2.  **cert-manager** acts as the "Root of Trust" (God CA), managing the signing certificates.
3.  **Dapr Sentry** uses these certificates to issue ephemeral, short-lived workload certs to sidecars.

## 2. Architecture Overview

| Component | Role | Responsibility |
|-----------|------|----------------|
| **cert-manager** | Root CA Manager | Manages the long-lived Root CA and issues the intermediate signing certs. |
| **Dapr Sentry** | Workload CA | Uses cert-manager's signing certs to issue short-lived (24h) certs to pods. |
| **Dapr Sidecar** | mTLS Proxy | Handles encryption/decryption on the wire; app talks plaintext on localhost. |

---

## 3. Implementation Steps

### Phase 1: Establish the Root Trust (cert-manager)

Ensure your ClusterIssuer (e.g., `factory-self-ca`) is ready. Then, create a Certificate resource that generates the keys Dapr needs.

**Manifest: `dapr-root-certificate.yaml`**
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: dapr-root-cert
  namespace: dapr-system
spec:
  secretName: dapr-trust-bundle
  duration: 2160h # 90 days
  renewBefore: 360h # 15 days
  commonName: dapr-root-ca
  isCA: true
  issuerRef:
    name: factory-self-ca # Your existing ClusterIssuer
    kind: ClusterIssuer
  usages:
    - digital signature
    - key encipherment
    - cert sign
    - crl sign
```

### Phase 2: The Brain Transplant (Configure Dapr)

Update the Dapr Helm chart values to stop generating its own certs and use the ones from `cert-manager`.

**Update `k8s-secrets-broker/charts/dapr/values.yaml`:**

```yaml
dapr_sentry:
  tls:
    enabled: true
    # Point Sentry to the secret created by cert-manager
    secretName: dapr-trust-bundle
    # Map cert-manager's output keys to what Dapr expects
    # Note: If your cert-manager outputs tls.crt/tls.key, map them here:
    rootCertFileName: "ca.crt"    # CA cert from the bundle
    issuerCertFileName: "tls.crt" # The signed cert
    issuerKeyFileName: "tls.key"  # The private key
```

*Note: If Dapr's chart version doesn't support filename remapping directly, you may need a small `CronJob` to copy `tls.crt` -> `issuer.crt` inside the secret.*

### Phase 3: Service Mesh Configuration

#### For `secrets-router` (The Target)
Ensure Dapr is enabled. This is already set in your values, but confirm:
```yaml
# k8s-secrets-broker/charts/secrets-router/values.yaml
dapr:
  enabled: true
  appId: secrets-router
  appPort: 8080
```

#### For Client Services (e.g., Frontend)
To talk to `secrets-router` securely, client services **must** be part of the mesh.

**Option A: The Assimilation (Recommended)**
Add Dapr annotations to `helm-factory/services/frontend/configuration.yml`:
```yaml
service:
  annotations:
    dapr.io/enabled: "true"
    dapr.io/app-id: "frontend"
    dapr.io/app-port: "80" # The port your app listens on
```
**Usage:** Frontend calls `http://localhost:3500/v1.0/invoke/secrets-router/method/...`

**Option B: Istio Integration**
If using Istio (via `platform-library`):
1.  Disable Dapr mTLS (`spec.mtls.enabled: false`) to avoid double-encryption overhead.
2.  Let Istio handle mTLS transparently.
3.  Dapr handles application logic (state, pub/sub, secrets).

---

## 4. Verification

Run these checks to confirm the exploit is active:

1.  **Check the Secret:**
    ```bash
    kubectl get secret dapr-trust-bundle -n dapr-system -o yaml
    # Verify it has ca.crt, tls.crt, tls.key
    ```

2.  **Verify Sentry Logs:**
    ```bash
    kubectl logs -l app=dapr-sentry -n dapr-system
    # Look for "Signing certificate loaded from file"
    ```

3.  **Test Connectivity:**
    Exec into a client pod and curl the `secrets-router` via Dapr sidecar:
    ```bash
    curl http://localhost:3500/v1.0/invoke/secrets-router/method/healthz
    ```

## 5. Troubleshooting "The Other Services"

If a service cannot talk to `secrets-router`:
*   **Symptom:** Connection refused or 500 error on Dapr invoke.
*   **Cause:** Client service is not sidecar-injected.
*   **Fix:** Add `dapr.io/enabled: "true"` annotation to the client Deployment and redeploy. Dapr mTLS is **exclusive**; you cannot easily talk to a mTLS-enabled Dapr service from outside the mesh without an Ingress Gateway.

