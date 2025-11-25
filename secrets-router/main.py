#!/usr/bin/env python3
"""
Secrets Router Service - Dapr-based secrets broker
Uses HTTP requests to Dapr sidecar to fetch secrets from Dapr components
"""

import os
import base64
import logging
from typing import Dict, Optional, Any, List
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, HTTPException, Query
from rich.logging import RichHandler

# Configure logging with rich
logging.basicConfig(
    level=logging.INFO,
    format="%(message)s",
    datefmt="[%X]",
    handlers=[RichHandler(rich_tracebacks=True)]
)
logger = logging.getLogger(__name__)

# Environment variables
DEBUG_MODE = os.getenv("DEBUG_MODE", "false").lower() == "true"
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
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
    logger.setLevel(logging.DEBUG)

# HTTP client for Dapr sidecar
dapr_client = httpx.AsyncClient(
    base_url=DAPR_HTTP_ENDPOINT,
    timeout=30.0
)

logger.info(f"Dapr sidecar endpoint: {DAPR_HTTP_ENDPOINT}")
logger.info(f"Secret store priority: {SECRET_STORE_PRIORITY}")
logger.info(f"AWS Secrets Manager path prefix: {AWS_SECRETS_PATH_PREFIX}")


class SecretsRouter:
    """Routes secret requests to Dapr secret store components via HTTP with priority"""
    
    def __init__(self, http_client: httpx.AsyncClient, store_priority: List[str]):
        self.http_client = http_client
        self.store_priority = [store.strip() for store in store_priority]
        
    async def get_secret(
        self,
        secret_name: str,
        secret_key: str,
        namespace: Optional[str] = None,
        decode: bool = False
    ) -> Dict[str, Any]:
        """
        Get secret from Dapr secret stores in priority order.
        Tries each store in SECRET_STORE_PRIORITY until found.
        
        Args:
            secret_name: Name of the secret
            secret_key: Key within the secret
            namespace: Kubernetes namespace (used for K8s secrets component)
            decode: If True, return decoded value; if False, return base64 encoded
        
        Returns:
            Dict with backend, secret_name, secret_key, and value (encoded or decoded)
        """
        last_error = None
        
        for store_name in self.store_priority:
            try:
                logger.debug(f"Trying secret store '{store_name}' for secret '{secret_name}' key '{secret_key}'")
                
                # Construct secret key for Dapr component based on store type
                dapr_secret_key = self._construct_secret_key(secret_name, namespace, store_name)
                
                # Fetch secret from Dapr component via HTTP
                secret_data = await self._get_secret_from_dapr(store_name, dapr_secret_key)
                
                if secret_data:
                    logger.info(f"Found secret '{secret_name}' in Dapr store '{store_name}'")
                    
                    # Extract the requested key
                    if secret_key not in secret_data:
                        logger.warning(f"Key '{secret_key}' not found in secret '{secret_name}' from store '{store_name}'")
                        continue
                    
                    value = secret_data[secret_key]
                    
                    # Auto-decode K8s secrets (they come base64 encoded from K8s API)
                    # AWS Secrets Manager values are already decoded
                    store_lower = store_name.lower()
                    if "kubernetes" in store_lower:
                        # K8s secrets are base64 encoded, decode them automatically
                        try:
                            if isinstance(value, str):
                                # Try to decode base64
                                decoded_value = base64.b64decode(value).decode('utf-8')
                                value = decoded_value
                                logger.debug(f"Auto-decoded base64 value from K8s secret '{secret_name}'")
                        except Exception as e:
                            logger.debug(f"Value from K8s secret '{secret_name}' is not base64 encoded: {e}")
                            # Value might already be decoded or not base64, use as-is
                    
                    # Encode/decode based on request
                    if decode:
                        # Return decoded value
                        final_value = value
                    else:
                        # Return base64 encoded value
                        if isinstance(value, str):
                            final_value = base64.b64encode(value.encode('utf-8')).decode('utf-8')
                        else:
                            # If already bytes or other type, encode to string first
                            final_value = base64.b64encode(str(value).encode('utf-8')).decode('utf-8')
                    
                    return {
                        "backend": store_name,
                        "secret_name": secret_name,
                        "secret_key": secret_key,
                        "value": final_value,
                        "encoded": not decode
                    }
                    
            except httpx.HTTPStatusError as e:
                if e.response.status_code == 404:
                    logger.debug(f"Secret '{secret_name}' not found in store '{store_name}'")
                    last_error = e
                    continue
                else:
                    logger.error(f"HTTP error from Dapr store '{store_name}': {e}")
                    last_error = e
                    continue
            except Exception as e:
                logger.warning(f"Error fetching from store '{store_name}': {e}")
                last_error = e
                continue
        
        # Secret not found in any store
        error_msg = f"Secret '{secret_name}' key '{secret_key}' not found in any configured secret store"
        if last_error:
            error_msg += f" (last error: {str(last_error)})"
        raise HTTPException(status_code=404, detail=error_msg)
    
    def _construct_secret_key(
        self,
        secret_name: str,
        namespace: Optional[str],
        store_name: str
    ) -> str:
        """
        Construct the secret key for Dapr component API.
        Different stores may have different key formats.
        """
        store_lower = store_name.lower()
        
        # For Kubernetes secrets component, format: namespace/secret-name
        # Namespace is required - secrets are namespace-scoped
        if "kubernetes" in store_lower:
            if not namespace:
                raise HTTPException(
                    status_code=400,
                    detail="namespace query parameter is required for Kubernetes secrets"
                )
            return f"{namespace}/{secret_name}"
        
        # For AWS Secrets Manager, use path-based format
        # Format: {AWS_SECRETS_PATH_PREFIX}/{namespace}/{secret_name}
        if "aws" in store_lower or "secretsmanager" in store_lower:
            if not namespace:
                raise HTTPException(
                    status_code=400,
                    detail="namespace query parameter is required for AWS Secrets Manager"
                )
            return f"{AWS_SECRETS_PATH_PREFIX}/{namespace}/{secret_name}"
        
        # Default: use namespace/secret-name format
        if not namespace:
            raise HTTPException(
                status_code=400,
                detail="namespace query parameter is required"
            )
        return f"{namespace}/{secret_name}"
    
    async def _get_secret_from_dapr(
        self,
        store_name: str,
        secret_key: str
    ) -> Optional[Dict[str, str]]:
        """
        Fetch secret from Dapr secret store component via HTTP.
        Uses Dapr Secrets API: GET /v1.0/secrets/{store_name}/{secret_key}
        """
        try:
            # Dapr Secrets API endpoint
            url = f"/v1.0/secrets/{store_name}/{secret_key}"
            
            logger.debug(f"Calling Dapr API: {url}")
            
            response = await self.http_client.get(url)
            response.raise_for_status()
            
            # Dapr returns secret data as JSON
            secret_data = response.json()
            
            return secret_data
            
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 404:
                logger.debug(f"Secret '{secret_key}' not found in store '{store_name}'")
                return None
            logger.error(f"HTTP error from Dapr API for store '{store_name}', key '{secret_key}': {e}")
            raise
        except httpx.RequestError as e:
            logger.error(f"Request error calling Dapr API: {e}")
            raise
        except Exception as e:
            logger.error(f"Error fetching secret from store '{store_name}', key '{secret_key}': {e}")
            raise


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan context manager for startup/shutdown"""
    logger.info("Starting Secrets Router service...")
    logger.info(f"Dapr sidecar endpoint: {DAPR_HTTP_ENDPOINT}")
    logger.info(f"Secret store priority: {SECRET_STORE_PRIORITY}")
    
    yield
    
    # Cleanup
    await dapr_client.aclose()
    logger.info("Shutting down Secrets Router service...")


app = FastAPI(
    title="Secrets Router",
    description="Dapr-based secrets broker using HTTP requests to Dapr sidecar",
    version="1.0.0",
    lifespan=lifespan
)

router = SecretsRouter(dapr_client, SECRET_STORE_PRIORITY)


@app.get("/healthz", status_code=200)
async def health_check():
    """
    Liveness probe endpoint.
    Returns healthy status if the service is running.
    """
    return {"status": "healthy"}


@app.get("/readyz", status_code=200)
async def readiness_check():
    """
    Readiness probe endpoint.
    Returns ready status if the service is ready to accept traffic.
    """
    return {"status": "healthy"}


@app.get("/secrets/{secret_name}/{secret_key}")
async def get_secret(
    secret_name: str,
    secret_key: str,
    namespace: str = Query(..., description="Kubernetes namespace where the secret is stored (required)"),
    decode: bool = Query(False, description="If true, return decoded value; if false, return base64 encoded")
):
    """
    Get secret value from Dapr secret stores.
    
    **Namespace-Scoped**: All secrets are namespace-scoped. The namespace parameter is required.
    
    **Auto-Decoding**: Kubernetes secrets are automatically decoded (base64 → plain text) before returning.
    AWS Secrets Manager values are already decoded.
    
    **Priority**: Tries Kubernetes Secrets first, then AWS Secrets Manager.
    
    Args:
        secret_name: Name of the Kubernetes Secret or AWS Secrets Manager secret
        secret_key: Key within the secret to retrieve
        namespace: Kubernetes namespace where the secret is stored (required)
        decode: If true, return decoded value; if false, return base64 encoded (default)
    
    Returns:
        JSON response with secret value (encoded or decoded based on decode parameter)
    
    Example:
        GET /secrets/database-credentials/password?namespace=production&decode=true
        Returns decoded value (recommended)
    """
    try:
        result = await router.get_secret(
            secret_name=secret_name,
            secret_key=secret_key,
            namespace=namespace,
            decode=decode
        )
        
        # Log audit trail
        logger.info(
            f"Secret access: secret={secret_name}, key={secret_key}, "
            f"namespace={namespace}, backend={result['backend']}, "
            f"encoded={result['encoded']}"
        )
        
        return result
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(
            f"Error fetching secret '{secret_name}' key '{secret_key}': {e}",
            exc_info=True
        )
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=SERVER_PORT,
        log_level=LOG_LEVEL.lower()
    )

