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
TEST_SECRET_NAME = os.getenv("TEST_SECRET_NAME", "database-credentials")
TEST_SECRET_KEY = os.getenv("TEST_SECRET_KEY", "password")
TEST_NAMESPACE = os.getenv("NAMESPACE")


async def test_secrets_router():
    """Test the Secrets Router service with various scenarios"""
    logger.info("🔍 Testing Secrets Router service...")
    logger.info(f"Service URL: {SECRETS_ROUTER_URL}")
    logger.info(f"Testing secret: {TEST_SECRET_NAME}/{TEST_SECRET_KEY}")
    
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
            
            # Test secret retrieval without namespace (uses default)
            logger.info("\n🔑 Testing secret retrieval without namespace...")
            secret_url1 = f"{SECRETS_ROUTER_URL}/secrets/{TEST_SECRET_NAME}/{TEST_SECRET_KEY}"
            logger.info(f"Requesting: GET {secret_url1}")
            
            try:
                response1 = await client.get(secret_url1)
                logger.info("✅ Secret without namespace: %s", json.dumps(response1.json(), indent=2))
            except httpx.HTTPStatusError as e:
                logger.error("❌ Request without namespace failed: %s", e.response.json())
            except Exception as e:
                logger.error("❌ Request without namespace failed: %s", str(e))
            
            # Test secret retrieval with namespace if provided
            if TEST_NAMESPACE:
                logger.info(f"\n🔑 Testing secret retrieval with namespace '{TEST_NAMESPACE}'...")
                secret_url2 = f"{SECRETS_ROUTER_URL}/secrets/{TEST_SECRET_NAME}/{TEST_SECRET_KEY}?namespace={TEST_NAMESPACE}"
                logger.info(f"Requesting: GET {secret_url2}")
                
                try:
                    response2 = await client.get(secret_url2)
                    logger.info("✅ Secret with namespace: %s", json.dumps(response2.json(), indent=2))
                except httpx.HTTPStatusError as e:
                    logger.error("❌ Request with namespace failed: %s", e.response.json())
                except Exception as e:
                    logger.error("❌ Request with namespace failed: %s", str(e))
            
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
