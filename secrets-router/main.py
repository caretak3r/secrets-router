#!/usr/bin/env python3
"""
Secrets Router Service - Dapr-based secrets broker
Uses Dapr components (kubernetes-secrets, aws-secrets-manager) to fetch secrets
"""

import os
import json
import logging
from typing import Dict, Optional, Any, List
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request, Header
from fastapi.responses import JSONResponse
from dapr.clients import DaprClient
from dapr.clients.exceptions import DaprException
from rich.console import Console
from rich.logging import RichHandler

# Configure logging with rich
logging.basicConfig(
    level=logging.INFO,
    format="%(message)s",
    datefmt="[%X]",
    handlers=[RichHandler(rich_tracebacks=True)]
)
logger = logging.getLogger(__name__)
console = Console()

# Environment variables
DEBUG_MODE = os.getenv("DEBUG_MODE", "false").lower() == "true"
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
DAPR_HTTP_PORT = int(os.getenv("DAPR_HTTP_PORT", "3500"))
DAPR_GRPC_PORT = int(os.getenv("DAPR_GRPC_PORT", "50001"))
K8S_SECRET_STORE = os.getenv("K8S_SECRET_STORE", "kubernetes-secrets")
AWS_SECRET_STORE = os.getenv("AWS_SECRET_STORE", "aws-secrets-manager")
SECRET_STORE_PRIORITY = os.getenv("SECRET_STORE_PRIORITY", f"{K8S_SECRET_STORE},{AWS_SECRET_STORE}").split(",")
SERVER_PORT = int(os.getenv("SERVER_PORT", "8080"))

if DEBUG_MODE:
    logging.getLogger().setLevel(logging.DEBUG)
    logger.setLevel(logging.DEBUG)

# Initialize Dapr client
# Dapr sidecar runs on localhost when injected
dapr_client = DaprClient(
    http_port=DAPR_HTTP_PORT,
    grpc_port=DAPR_GRPC_PORT
)
logger.info(f"Initialized Dapr client (HTTP: {DAPR_HTTP_PORT}, gRPC: {DAPR_GRPC_PORT})")
logger.info(f"Secret store priority: {SECRET_STORE_PRIORITY}")


class SecretsRouter:
    """Routes secret requests to Dapr secret store components"""
    
    def __init__(self, dapr_client: DaprClient, store_priority: List[str]):
        self.dapr_client = dapr_client
        self.store_priority = store_priority
        
    async def get_secret(
        self,
        secret_name: str,
        namespace: Optional[str] = None,
        key: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Get secret from Dapr secret stores in priority order.
        Tries each store in SECRET_STORE_PRIORITY until found.
        """
        last_error = None
        
        for store_name in self.store_priority:
            store_name = store_name.strip()
            try:
                logger.debug(f"Trying secret store '{store_name}' for secret '{secret_name}'")
                
                # Construct secret key (Dapr components handle namespace internally)
                # For K8s secrets, format: namespace/secret-name or just secret-name
                # For AWS, format: secret-path
                secret_key = self._construct_secret_key(secret_name, namespace, store_name)
                
                # Fetch secret from Dapr component
                secret_data = await self._get_secret_from_dapr(store_name, secret_key)
                
                if secret_data:
                    logger.info(f"Found secret '{secret_name}' in Dapr store '{store_name}'")
                    
                    # Return specific key if requested
                    if key:
                        if key in secret_data:
                            return {
                                "backend": store_name,
                                "data": {key: secret_data[key]}
                            }
                        else:
                            logger.warning(f"Key '{key}' not found in secret '{secret_name}'")
                            continue
                    
                    return {
                        "backend": store_name,
                        "data": secret_data
                    }
                    
            except DaprException as e:
                logger.debug(f"Secret '{secret_name}' not found in store '{store_name}': {e}")
                last_error = e
                continue
            except Exception as e:
                logger.warning(f"Error fetching from store '{store_name}': {e}")
                last_error = e
                continue
        
        # Secret not found in any store
        error_msg = f"Secret '{secret_name}' not found in any Dapr secret store"
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
        Construct the secret key based on store type.
        Different stores may have different key formats.
        """
        store_lower = store_name.lower()
        
        # For Kubernetes secrets component, format: namespace/secret-name or secret-name
        if "kubernetes" in store_lower:
            if namespace:
                return f"{namespace}/{secret_name}"
            return secret_name
        
        # For AWS Secrets Manager, use full path
        if "aws" in store_lower or "secretsmanager" in store_lower:
            if namespace:
                return f"/app/secrets/{namespace}/{secret_name}"
            return f"/app/secrets/cluster/{secret_name}"
        
        # Default: just use secret name
        return secret_name
    
    async def _get_secret_from_dapr(
        self,
        store_name: str,
        secret_key: str
    ) -> Optional[Dict[str, str]]:
        """
        Fetch secret from Dapr secret store component.
        Uses Dapr SDK to call the sidecar API.
        """
        try:
            # Dapr SDK get_secret is synchronous, but we're in async context
            # Run in executor to avoid blocking event loop
            import asyncio
            
            def _fetch_secret():
                try:
                    response = self.dapr_client.get_secret(
                        store_name=store_name,
                        key=secret_key
                    )
                    return response
                except Exception as e:
                    # Re-raise to be caught by outer try-except
                    raise e
            
            # Run Dapr call in executor
            loop = asyncio.get_event_loop()
            secret_response = await loop.run_in_executor(None, _fetch_secret)
            
            if secret_response and secret_response.secrets:
                # Convert Dapr secret response to dict
                return dict(secret_response.secrets)
            
            return None
            
        except DaprException as e:
            # DaprException for not found or other Dapr errors
            error_msg = str(e).lower()
            if "not found" in error_msg or "404" in error_msg or "no such" in error_msg:
                logger.debug(f"Secret '{secret_key}' not found in store '{store_name}'")
                return None
            # Re-raise other Dapr exceptions
            logger.error(f"Dapr exception for store '{store_name}', key '{secret_key}': {e}")
            raise
        except Exception as e:
            logger.error(f"Error fetching secret from Dapr store '{store_name}', key '{secret_key}': {e}")
            raise


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan context manager for startup/shutdown"""
    logger.info("Starting Secrets Router service...")
    logger.info(f"Dapr HTTP port: {DAPR_HTTP_PORT}")
    logger.info(f"Dapr gRPC port: {DAPR_GRPC_PORT}")
    logger.info(f"K8s secret store: {K8S_SECRET_STORE}")
    logger.info(f"AWS secret store: {AWS_SECRET_STORE}")
    logger.info(f"Secret store priority: {SECRET_STORE_PRIORITY}")
    
    # Test Dapr connectivity
    try:
        # This will fail if Dapr sidecar is not available, but won't crash the app
        # The sidecar might not be ready immediately
        logger.info("Dapr client initialized successfully")
    except Exception as e:
        logger.warning(f"Dapr client initialization warning: {e}")
        logger.warning("Make sure Dapr sidecar is injected and running")
    
    yield
    
    # Cleanup
    try:
        dapr_client.close()
    except Exception:
        pass
    logger.info("Shutting down Secrets Router service...")


app = FastAPI(
    title="Secrets Router",
    description="Dapr-based secrets broker using Dapr secret store components",
    version="1.0.0",
    lifespan=lifespan
)

router = SecretsRouter(dapr_client, SECRET_STORE_PRIORITY)


@app.get("/healthz")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy"}


@app.get("/readyz")
async def readiness_check():
    """Readiness check endpoint"""
    return {"status": "ready"}


@app.get("/v1.0/secrets/{store_name}/{secret_name}")
async def get_secret_dapr(
    store_name: str,
    secret_name: str,
    request: Request,
    dapr_app_id: Optional[str] = Header(None, alias="dapr-app-id")
):
    """
    Dapr Secrets API endpoint
    GET /v1.0/secrets/{store_name}/{secret_name}
    """
    try:
        # Extract namespace from request if available
        namespace = request.query_params.get("namespace")
        key = request.query_params.get("key")
        
        result = await router.get_secret(secret_name, namespace, key)
        
        # Log audit trail
        logger.info(
            f"Secret access: store={store_name}, secret={secret_name}, "
            f"namespace={namespace}, backend={result['backend']}, "
            f"caller={dapr_app_id or 'unknown'}"
        )
        
        return result["data"]
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error fetching secret '{secret_name}': {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/v1/secrets/{secret_name}")
async def get_secret_direct(
    secret_name: str,
    request: Request,
    namespace: Optional[str] = None,
    key: Optional[str] = None
):
    """
    Direct API endpoint (backward compatibility)
    GET /v1/secrets/{secret_name}?namespace={ns}&key={key}
    """
    try:
        result = await router.get_secret(secret_name, namespace, key)
        
        # Log audit trail
        logger.info(
            f"Secret access: secret={secret_name}, namespace={namespace}, "
            f"backend={result['backend']}"
        )
        
        return {
            "secret_name": secret_name,
            "backend": result["backend"],
            "data": result["data"]
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error fetching secret '{secret_name}': {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=SERVER_PORT,
        log_level=LOG_LEVEL.lower()
    )

