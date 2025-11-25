#!/usr/bin/env python3
"""
Secrets Router Service - Dapr-based secrets broker
Fetches secrets from Dapr components via HTTP requests to sidecar
"""

import os
import base64
import logging
from typing import Dict, Optional, List
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, HTTPException, Query
from rich.logging import RichHandler

# Configure logging
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
SECRET_STORE_PRIORITY = os.getenv(
    "SECRET_STORE_PRIORITY",
    "kubernetes-secrets,aws-secrets-manager"
).split(",")
AWS_SECRETS_PATH_PREFIX = os.getenv("AWS_SECRETS_PATH_PREFIX", "/app/secrets")
SERVER_PORT = int(os.getenv("SERVER_PORT", "8080"))

if DEBUG_MODE:
    logging.getLogger().setLevel(logging.DEBUG)

# HTTP client for Dapr sidecar
dapr_client = httpx.AsyncClient(base_url=DAPR_HTTP_ENDPOINT, timeout=30.0)

logger.info(f"Dapr endpoint: {DAPR_HTTP_ENDPOINT}")
logger.info(f"Secret store priority: {SECRET_STORE_PRIORITY}")


class SecretsRouter:
    """Routes secret requests to Dapr secret store components with priority fallback"""
    
    def __init__(self, http_client: httpx.AsyncClient, store_priority: List[str]):
        self.http_client = http_client
        self.store_priority = [s.strip() for s in store_priority]
    
    async def get_secret(
        self,
        secret_name: str,
        secret_key: str,
        namespace: str
    ) -> Dict[str, str]:
        """
        Get secret from Dapr secret stores in priority order.
        
        Args:
            secret_name: Name of the secret
            secret_key: Key within the secret
            namespace: Kubernetes namespace (required)
        
        Returns:
            Dict with backend, secret_name, secret_key, and decoded value
        """
        errors = []
        
        for store_name in self.store_priority:
            try:
                logger.debug(f"Trying {store_name} for {secret_name}/{secret_key}")
                
                # Construct secret key for Dapr component
                dapr_key = self._build_secret_key(store_name, namespace, secret_name)
                
                # Fetch from Dapr component
                url = f"/v1.0/secrets/{store_name}/{dapr_key}"
                response = await self.http_client.get(url)
                
                if response.status_code == 404:
                    logger.debug(f"Secret not found in {store_name}")
                    continue
                
                response.raise_for_status()
                secret_data = response.json()
                
                # Extract requested key
                if secret_key not in secret_data:
                    logger.warning(f"Key '{secret_key}' not in secret '{secret_name}'")
                    continue
                
                value = secret_data[secret_key]
                
                # Decode K8s secrets (base64 encoded by K8s API)
                if "kubernetes" in store_name.lower():
                    try:
                        value = base64.b64decode(value).decode('utf-8')
                        logger.debug(f"Decoded base64 from K8s secret")
                    except Exception:
                        # Value might not be base64 encoded, use as-is
                        pass
                
                logger.info(f"Found secret '{secret_name}' in {store_name}")
                
                return {
                    "backend": store_name,
                    "secret_name": secret_name,
                    "secret_key": secret_key,
                    "value": value
                }
                
            except httpx.HTTPStatusError as e:
                if e.response.status_code != 404:
                    logger.error(f"HTTP error from {store_name}: {e}")
                    errors.append(f"{store_name}: {e}")
            except Exception as e:
                logger.warning(f"Error from {store_name}: {e}")
                errors.append(f"{store_name}: {e}")
        
        # Secret not found in any store
        error_msg = f"Secret '{secret_name}/{secret_key}' not found in any store"
        if errors:
            error_msg += f" (errors: {'; '.join(errors)})"
        raise HTTPException(status_code=404, detail=error_msg)
    
    def _build_secret_key(self, store_name: str, namespace: str, secret_name: str) -> str:
        """
        Build the secret key for Dapr component API.
        
        Kubernetes: namespace/secret-name
        AWS: {prefix}/{namespace}/{secret-name}
        """
        store_lower = store_name.lower()
        
        if "kubernetes" in store_lower:
            return f"{namespace}/{secret_name}"
        
        if "aws" in store_lower or "secretsmanager" in store_lower:
            return f"{AWS_SECRETS_PATH_PREFIX}/{namespace}/{secret_name}"
        
        # Default format
        return f"{namespace}/{secret_name}"


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
    version="1.0.0",
    lifespan=lifespan
)

router = SecretsRouter(dapr_client, SECRET_STORE_PRIORITY)


@app.get("/healthz", status_code=200)
async def health_check():
    """
    Liveness probe endpoint.
    Returns HTTP 200 if the service process is running.
    """
    return {
        "status": "healthy",
        "service": "secrets-router",
        "version": "1.0.0"
    }


@app.get("/readyz")
async def readiness_check():
    """
    Readiness probe endpoint.
    Returns HTTP 200 only if the service is ready to receive traffic.
    Checks Dapr sidecar connectivity.
    """
    try:
        # Check if Dapr sidecar is reachable
        # Try to connect to Dapr sidecar health endpoint
        health_url = f"{DAPR_HTTP_ENDPOINT}/v1.0/healthz"
        async with httpx.AsyncClient(timeout=2.0) as client:
            response = await client.get(health_url)
            if response.status_code == 200:
                return {
                    "status": "ready",
                    "service": "secrets-router",
                    "dapr_sidecar": "connected",
                    "version": "1.0.0"
                }
            else:
                # Dapr sidecar not healthy
                logger.warning(f"Dapr sidecar health check returned {response.status_code}")
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
    namespace: str = Query(..., description="Kubernetes namespace (required)")
):
    """
    Get secret value from Dapr secret stores.
    
    Tries stores in priority order (K8s → AWS by default).
    Returns decoded values ready for application use.
    
    Args:
        secret_name: Name of the secret
        secret_key: Key within the secret
        namespace: Kubernetes namespace (required)
    
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
