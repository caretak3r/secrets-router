#!/usr/bin/env python3
"""
Python sample client for testing Secrets Router service
"""
import os
import json
import asyncio
import logging
from typing import Optional

import httpx

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

# Configuration
SECRETS_ROUTER_URL = os.getenv("SECRETS_ROUTER_URL", "http://secrets-router:8080")
NAMESPACE = os.getenv("NAMESPACE")

# Discover configured secrets from environment variables
def get_configured_secrets():
    """Extract secret references from environment variables that start with SECRET_"""
    secrets = {}
    for key, value in os.environ.items():
        if key.startswith("SECRET_"):
            # Remove SECRET_ prefix and convert to lowercase for the secret name
            secret_name = key[7:].lower().replace("_", "-")
            secrets[secret_name] = value
    return secrets


async def test_secrets_router():
    """Test the Secrets Router service with configured secrets"""
    logger.info("🔍 Testing Secrets Router service...")
    logger.info(f"Service URL: {SECRETS_ROUTER_URL}")
    
    configured_secrets = get_configured_secrets()
    
    if not configured_secrets:
        logger.warning("⚠️  No secrets configured. Set SECRET_* environment variables to test secret access.")
        return
    
    logger.info(f"Found {len(configured_secrets)} configured secrets: {list(configured_secrets.keys())}")
    
    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            # Test health endpoint
            logger.info("\n📋 Testing health check...")
            health_response = await client.get(f"{SECRETS_ROUTER_URL}/healthz")
            logger.info("✅ Health check: %s", health_response.json())
            
            # Test readiness endpoint
            logger.info("\n📋 Testing readiness check...")
            readiness_response = await client.get(f"{SECRETS_ROUTER_URL}/readyz")
            logger.info("✅ Readiness check: %s", readiness_response.json())
            
            # Test each configured secret
            for secret_name, secret_path in configured_secrets.items():
                logger.info(f"\n🔑 Testing secret: {secret_name} -> {secret_path}")
                
                # Test without namespace
                try:
                    secret_url = f"{SECRETS_ROUTER_URL}/secrets/{secret_path}/value"
                    logger.info(f"Requesting: GET {secret_url}")
                    response = await client.get(secret_url)
                    logger.info("✅ Secret retrieved: %s", json.dumps(response.json(), indent=2))
                except httpx.HTTPStatusError as e:
                    logger.error("❌ Secret retrieval failed: %s", e.response.json())
                except Exception as e:
                    logger.error("❌ Secret retrieval failed: %s", str(e))
                
                # Test with namespace if provided
                if NAMESPACE:
                    try:
                        secret_url_with_ns = f"{SECRETS_ROUTER_URL}/secrets/{secret_path}/value?namespace={NAMESPACE}"
                        logger.info(f"Requesting: GET {secret_url_with_ns}")
                        response = await client.get(secret_url_with_ns)
                        logger.info("✅ Secret with namespace: %s", json.dumps(response.json(), indent=2))
                    except httpx.HTTPStatusError as e:
                        logger.error("❌ Secret retrieval with namespace failed: %s", e.response.json())
                    except Exception as e:
                        logger.error("❌ Secret retrieval with namespace failed: %s", str(e))
            
            logger.info("\n🎉 Python client test completed successfully!")
            
        except httpx.HTTPStatusError as e:
            logger.error("❌ Test failed with HTTP %d: %s", e.response.status_code, e.response.text)
            raise
        except Exception as e:
            logger.error("❌ Test failed: %s", str(e))
            raise


async def main():
    """Main entry point"""
    try:
        await test_secrets_router()
    except Exception:
        logger.error("Test execution failed")
        return 1
    return 0


if __name__ == "__main__":
    exit_code = asyncio.run(main())
    exit(exit_code)
