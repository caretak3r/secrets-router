#!/usr/bin/env python3
"""
Secrets Router Service - Dapr-based secrets broker
Fetches secrets from Dapr secret stores (AWS, Kubernetes) with priority fallback.
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
    # Enable httpx debug logging
    httpx_log = logging.getLogger('httpx')
    httpx_log.setLevel(logging.DEBUG)

# HTTP client for Dapr sidecar
dapr_client = httpx.AsyncClient(base_url=DAPR_HTTP_ENDPOINT, timeout=30.0)

logger.info(f"Dapr endpoint: {DAPR_HTTP_ENDPOINT}")
logger.info(f"AWS Secrets Enabled: {AWS_SECRETS_ENABLED}")
logger.info(f"Service version: {SERVICE_VERSION}")


class SecretsRouter:
    """Routes secret requests to Dapr secret stores with AWS → K8s priority fallback"""
    
    def __init__(self, http_client: httpx.AsyncClient, aws_enabled: bool):
        self.http_client = http_client
        self.aws_enabled = aws_enabled
    
    async def get_secret(
        self,
        secret_name: str,
        secret_key: str,
        namespace: Optional[str] = None
    ) -> Dict[str, str]:
        """
        Get secret from Dapr secret stores with AWS → K8s priority fallback.
        
        Args:
            secret_name: Name of the secret
            secret_key: Key within the secret
            namespace: Kubernetes namespace (optional, defaults to secret store's defaultNamespace)
        
        Returns:
            Dict with backend, secret_name, secret_key, and decoded value
        """
        errors = []
        
        # If no namespace provided, omit the metadata.namespace parameter
        # to use the defaultNamespace configured in the secret store
        namespace_param = f"?metadata.namespace={namespace}" if namespace else ""
        if self.aws_enabled:
            store_name = "aws-secrets-manager"
            try:
                logger.debug(f"Trying {store_name} for {secret_name}")
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
            logger.debug(f"Trying {store_name} for {secret_name} in namespace {namespace or 'default'}")
            namespace_param = f"?metadata.namespace={namespace}" if namespace else ""
            url = f"/v1.0/secrets/{store_name}/{secret_name}{namespace_param}"
            logger.debug(f"Full URL: {url}")
            
            response = await self.http_client.get(url)
            
            if response.status_code == 200:
                secret_data = response.json()
                
                if secret_key in secret_data:
                    # Kubernetes secrets are base64 encoded, decode them
                    value = secret_data[secret_key]
                    try:
                        # Try to decode as UTF-8 first (for text secrets)
                        raw_bytes = base64.b64decode(value)
                        decoded_value = raw_bytes.decode('utf-8')
                        content_type = "text"
                    except (TypeError, ValueError, UnicodeDecodeError):
                        # If UTF-8 decoding fails, this is binary data
                        # Use hex encoding for binary data to preserve exact bytes
                        raw_bytes = base64.b64decode(value)
                        decoded_value = raw_bytes.hex()
                        content_type = "binary"
                        
                    logger.info(f"Found secret '{secret_name}' in {store_name} ({content_type})")
                    return {
                        "backend": store_name,
                        "secret_name": secret_name,
                        "secret_key": secret_key,
                        "value": decoded_value,
                        "content_type": content_type
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
    """Liveness probe - returns HTTP 200 if service is running."""
    return {
        "status": "healthy",
        "service": "secrets-router",
        "version": SERVICE_VERSION
    }


@app.get("/readyz")
async def readiness_check():
    """Readiness probe - returns HTTP 200 when service and Dapr sidecar are ready."""
    try:
        # Check Dapr sidecar availability via metadata endpoint
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
    namespace: str = Query(None, description="Kubernetes namespace where secret exists (optional, defaults to secret store default)")
):
    """
    Get secret value from Dapr secret stores with AWS → K8s priority fallback.
    Returns decoded values ready for application use.
    
    Args:
        secret_name: Name of the secret
        secret_key: Key within the secret
        namespace: Kubernetes namespace where the secret exists (optional)
    
    Returns:
        JSON with backend, secret_name, secret_key, and decoded value
    
    Example:
        GET /secrets/database-credentials/password?namespace=production
        GET /secrets/database-credentials/password
    """
    try:
        result = await router.get_secret(secret_name, secret_key, namespace)
        
        logger.info(
            f"Secret access: {secret_name}/{secret_key} "
            f"namespace={namespace or 'default'} backend={result['backend']}"
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
