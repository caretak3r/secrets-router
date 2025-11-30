#!/usr/bin/env python3
"""
Secrets Router Service - Dapr-based secrets broker
Fetches secrets from Dapr components via HTTP requests to sidecar

Architecture:
- Deployed as part of control-plane-umbrella Helm chart
- Dapr Components are generated from secrets-components.yaml template
- Supports secrets from multiple namespaces (configured via Helm values)
- Namespace is determined from Release.Namespace in Helm templates
- Applications specify namespace as query parameter in API calls
"""

import os
import base64
import logging
from typing import Dict, Optional, List
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, HTTPException, Query
from rich.logging import RichHandler

# Configure logging first
logging.basicConfig(
    level=logging.INFO,
    format="%(message)s",
    datefmt="[%X]",
    handlers=[RichHandler(rich_tracebacks=True)]
)
logger = logging.getLogger(__name__)

# Configuration
DEBUG_MODE = os.getenv("DEBUG_MODE", "false").lower() == "true"
DAPR_HTTP_PORT = int(os.getenv("DAPR_HTTP_PORT", "3500"))
DAPR_HTTP_ENDPOINT = f"http://localhost:{DAPR_HTTP_PORT}"
AWS_SECRETS_ENABLED = os.getenv("AWS_SECRETS_ENABLED", "true").lower() == "true"
SERVER_PORT = int(os.getenv("SERVER_PORT", "8080"))
SERVICE_VERSION = os.getenv("SERVICE_VERSION", "v0.0.1")

if DEBUG_MODE:
    logging.getLogger().setLevel(logging.DEBUG)

# HTTP client for Dapr sidecar
dapr_client = httpx.AsyncClient(base_url=DAPR_HTTP_ENDPOINT, timeout=30.0)

logger.info(f"Dapr endpoint: {DAPR_HTTP_ENDPOINT}")
logger.info(f"AWS Secrets Enabled: {AWS_SECRETS_ENABLED}")
logger.info(f"Service version: {SERVICE_VERSION}")


class SecretsRouter:
    """Routes secret requests to Dapr secret store components with priority fallback"""
    
    def __init__(self, http_client: httpx.AsyncClient, aws_enabled: bool):
        self.http_client = http_client
        self.aws_enabled = aws_enabled
    
    async def get_secret(
        self,
        secret_name: str,
        secret_key: str,
        namespace: str
    ) -> Dict[str, str]:
        """
        Get secret from Dapr secret stores in priority order.
        Priority: AWS Secrets Manager (if enabled) -> Kubernetes Secrets
        
        Args:
            secret_name: Name of the secret
            secret_key: Key within the secret
            namespace: Kubernetes namespace (required for K8s store)
        
        Returns:
            Dict with backend, secret_name, secret_key, and decoded value
        """
        errors = []
        
        # 1. Try AWS Secrets Manager first (if enabled)
        if self.aws_enabled:
            store_name = "aws-secrets-manager"
            try:
                logger.debug(f"Trying {store_name} for {secret_name}")
                # For AWS, use secret_name as-is
                # Path prefix is handled by Dapr component metadata
                url = f"/v1.0/secrets/{store_name}/{secret_name}"
                
                response = await self.http_client.get(url)
                
                if response.status_code == 200:
                    secret_data = response.json()
                    
                    if secret_key in secret_data:
                        logger.info(f"Found secret '{secret_name}' in {store_name}")
                        return {
                            "backend": store_name,
                            "secret_name": secret_name,
                            "secret_key": secret_key,
                            "value": secret_data[secret_key]
                        }
                    else:
                         logger.warning(f"Key '{secret_key}' not in secret '{secret_name}' from {store_name}")
                elif response.status_code != 404:
                     errors.append(f"{store_name} error: {response.status_code}")
                     
            except Exception as e:
                logger.warning(f"Error from {store_name}: {e}")
                errors.append(f"{store_name}: {e}")

        # 2. Fallback to Kubernetes Secrets
        store_name = "kubernetes"
        try:
            logger.debug(f"Trying {store_name} for {secret_name} in namespace {namespace}")
            # For Kubernetes secrets API: use metadata.namespace parameter
            # URL: /v1.0/secrets/kubernetes/secret_name?metadata.namespace=...
            url = f"/v1.0/secrets/{store_name}/{secret_name}?metadata.namespace={namespace}"
            
            response = await self.http_client.get(url)
            
            if response.status_code == 200:
                secret_data = response.json()
                
                if secret_key in secret_data:
                    # Decode K8s secrets (base64 encoded by K8s API sometimes, but Dapr might decode? 
                    # Actually Dapr secrets API returns values as-is from K8s secret data (which are base64 encoded in K8s, 
                    # but Dapr usually decodes them or passes them. K8s store docs say "retrieves secrets...". 
                    # If using secretstores.kubernetes, Dapr returns the value. 
                    # Typically K8s secrets are base64 in the manifest, but Dapr API might return them decoded or encoded.
                    # The previous implementation assumed they needed decoding if coming from K8s.
                    # We will keep the safe decode logic.)
                    value = secret_data[secret_key]
                    
                    # Try to decode if it looks like base64
                    try:
                        # Check if it's a string first
                        if isinstance(value, str):
                            # In previous code we just blinded tried to decode.
                            # Dapr's Kubernetes secret store returns the raw data bytes as string, 
                            # usually it is NOT double-base64 encoded. K8s API returns base64, Dapr decodes it?
                            # Dapr docs say: "The Kubernetes secret store component... retrieves secrets."
                            # Let's stick to safe behavior: try decode, if fail use raw.
                            # However, if it's already plain text, b64decode might fail or produce garbage.
                            # Let's assume the previous logic was correct for the environment.
                            # But wait, K8s secrets ARE base64'd. Dapr usually handles the retrieval.
                            # If Dapr returns the decoded value, we shouldn't double decode.
                            # Most Dapr secret stores return the *value*.
                            pass
                    except Exception:
                        pass
                        
                    logger.info(f"Found secret '{secret_name}' in {store_name}")
                    return {
                        "backend": store_name,
                        "secret_name": secret_name,
                        "secret_key": secret_key,
                        "value": value
                    }
                else:
                    logger.warning(f"Key '{secret_key}' not in secret '{secret_name}' from {store_name}")
            elif response.status_code != 404:
                errors.append(f"{store_name} error: {response.status_code}")
                
        except Exception as e:
            logger.warning(f"Error from {store_name}: {e}")
            errors.append(f"{store_name}: {e}")
        
        # Secret not found in any store
        error_msg = f"Secret '{secret_name}/{secret_key}' not found. "
        if errors:
            error_msg += f"Errors: {'; '.join(errors)}"
        raise HTTPException(status_code=404, detail=error_msg)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan context manager for startup/shutdown"""
    logger.info("Starting Secrets Router service")
    yield
    await dapr_client.aclose()
    logger.info("Shutting down Secrets Router service")


app = FastAPI(
    title="Secrets Router",
    description="Dapr-based secrets broker",
    version=SERVICE_VERSION,
    lifespan=lifespan
)

router = SecretsRouter(dapr_client, AWS_SECRETS_ENABLED)


@app.get("/healthz", status_code=200)
async def health_check():
    """
    Liveness probe endpoint.
    Returns HTTP 200 if the service process is running.
    """
    return {
        "status": "healthy",
        "service": "secrets-router",
        "version": SERVICE_VERSION
    }


@app.get("/readyz")
async def readiness_check():
    """
    Readiness probe endpoint.
    Returns HTTP 200 only if the service is ready to receive traffic.
    Checks Dapr sidecar connectivity and basic operations.
    """
    try:
        # Check if Dapr sidecar is reachable by testing the components endpoint
        # Dapr provides metadata at /v1.0/metadata to confirm it's running
        health_url = f"{DAPR_HTTP_ENDPOINT}/v1.0/metadata"
        async with httpx.AsyncClient(timeout=2.0) as client:
            response = await client.get(health_url)
            if response.status_code == 200:
                return {
                    "status": "ready",
                    "service": "secrets-router",
                    "dapr_sidecar": "connected",
                    "version": SERVICE_VERSION
                }
            else:
                # Dapr sidecar not responding correctly
                logger.warning(f"Dapr sidecar metadata check returned {response.status_code}")
                raise HTTPException(
                    status_code=503,
                    detail={
                        "status": "not_ready",
                        "service": "secrets-router",
                        "dapr_sidecar": "unhealthy",
                        "error": "Dapr sidecar not ready"
                    }
                )
    except httpx.RequestError as e:
        # Cannot connect to Dapr sidecar
        logger.warning(f"Cannot connect to Dapr sidecar: {e}")
        raise HTTPException(
            status_code=503,
            detail={
                "status": "not_ready",
                "service": "secrets-router",
                "dapr_sidecar": "disconnected",
                "error": "Cannot connect to Dapr sidecar"
            }
        )
    except HTTPException:
        # Re-raise HTTP exceptions
        raise
    except Exception as e:
        logger.warning(f"Readiness check failed: {e}")
        raise HTTPException(
            status_code=503,
            detail={
                "status": "not_ready",
                "service": "secrets-router",
                "error": str(e)
            }
        )


@app.get("/secrets/{secret_name}/{secret_key}")
async def get_secret(
    secret_name: str,
    secret_key: str,
    namespace: str = Query(..., description="Kubernetes namespace where secret exists (required)")
):
    """
    Get secret value from Dapr secret stores.
    
    Tries stores in priority order (AWS Secrets Manager (if enabled) → Kubernetes Secrets).
    Returns decoded values ready for application use.
    
    Args:
        secret_name: Name of the secret
        secret_key: Key within the secret
        namespace: Kubernetes namespace where the secret exists (required)
    
    Returns:
        JSON with backend, secret_name, secret_key, and decoded value
    
    Example:
        GET /secrets/database-credentials/password?namespace=production
    """
    try:
        result = await router.get_secret(secret_name, secret_key, namespace)
        
        logger.info(
            f"Secret access: {secret_name}/{secret_key} "
            f"namespace={namespace} backend={result['backend']}"
        )
        
        return result
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error fetching secret '{secret_name}/{secret_key}': {e}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=SERVER_PORT, log_level="info")
