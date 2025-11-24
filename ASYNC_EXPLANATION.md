# Why Async Calls Are Used in secrets-router

## Current Async Usage

The `main.py` file uses async/await in several places:

1. **FastAPI endpoint handlers** (`async def health_check()`, `async def get_secret()`, etc.)
2. **HTTP client calls** (`await self.http_client.get(url)`)
3. **Lifespan manager** (`async def lifespan()`)
4. **SecretsRouter methods** (`async def get_secret()`, `async def _get_secret_from_dapr()`)

## Why Async Is Needed

### 1. **FastAPI is an Async Framework**

FastAPI is built on **Starlette** and **Uvicorn**, which are async web frameworks. While FastAPI supports both sync and async handlers, async is the recommended approach for I/O-bound operations.

```python
# Async (current approach - recommended)
@app.get("/secrets/{secret_name}/{secret_key}")
async def get_secret(...):
    result = await router.get_secret(...)  # Non-blocking
    return result

# Sync (alternative - less efficient)
@app.get("/secrets/{secret_name}/{secret_key}")
def get_secret(...):
    result = router.get_secret(...)  # Blocks thread
    return result
```

### 2. **HTTP Requests Are I/O-Bound Operations**

When making HTTP requests to the Dapr sidecar, the CPU is idle waiting for network I/O. Async allows the server to:

- **Handle multiple requests concurrently** without blocking
- **Use fewer resources** (no need for thread pools)
- **Scale better** under load

**Example Scenario:**
```
Request 1: Waiting for Dapr response (100ms)
Request 2: Waiting for Dapr response (100ms)  
Request 3: Waiting for Dapr response (100ms)

With async: All 3 requests handled concurrently (total time: ~100ms)
With sync:  Requests handled sequentially (total time: ~300ms)
```

### 3. **httpx.AsyncClient Requires Async**

The `httpx.AsyncClient` is specifically designed for async operations:

```python
# httpx.AsyncClient - async only
dapr_client = httpx.AsyncClient(...)
response = await dapr_client.get(url)  # Must use await

# Alternative: httpx.Client (sync) - but blocks the event loop
dapr_client = httpx.Client(...)
response = dapr_client.get(url)  # Blocks thread
```

### 4. **Performance Benefits**

For a secrets broker service that:
- Receives multiple concurrent requests
- Makes HTTP calls to Dapr sidecar (network I/O)
- Needs to handle high throughput

Async provides significant performance improvements:

| Metric | Sync | Async |
|--------|------|-------|
| Concurrent requests | Limited by thread pool | Limited by memory |
| Resource usage | Higher (thread overhead) | Lower (event loop) |
| Latency under load | Higher (thread contention) | Lower (non-blocking) |

## Could We Use Sync Instead?

**Yes, but with trade-offs:**

### Option 1: Sync Endpoints with Sync HTTP Client

```python
import httpx  # Sync client

dapr_client = httpx.Client(base_url=DAPR_HTTP_ENDPOINT)

@app.get("/secrets/{secret_name}/{secret_key}")
def get_secret(...):  # Sync handler
    response = dapr_client.get(url)  # Blocks thread
    return result
```

**Problems:**
- Each request blocks a thread
- Limited concurrency (thread pool size)
- Higher resource usage
- Worse performance under load

### Option 2: Sync Endpoints with Async HTTP Client (Not Recommended)

```python
dapr_client = httpx.AsyncClient(...)

@app.get("/secrets/{secret_name}/{secret_key}")
def get_secret(...):  # Sync handler
    # Can't use await in sync function!
    response = await dapr_client.get(url)  # ERROR!
```

**This won't work** - you can't use `await` in a sync function.

## Real-World Impact

### Scenario: 100 concurrent requests

**Async approach:**
- All 100 requests handled concurrently
- Each waits ~50ms for Dapr response
- Total time: ~50ms
- CPU usage: Low (event loop efficient)

**Sync approach:**
- Limited by thread pool (e.g., 10 threads)
- First 10 requests handled, then next 10, etc.
- Total time: ~500ms (10 batches × 50ms)
- CPU usage: Higher (thread overhead)

## Conclusion

**Async is necessary because:**

1. ✅ **FastAPI is designed for async** - it's the framework's strength
2. ✅ **HTTP requests are I/O-bound** - async is perfect for this
3. ✅ **httpx.AsyncClient requires async** - it's async-only
4. ✅ **Better performance** - handles concurrent requests efficiently
5. ✅ **Lower resource usage** - no thread pool overhead

**For a production secrets broker service**, async is the right choice. It allows the service to handle many concurrent requests efficiently while waiting for Dapr sidecar responses.

## When Sync Would Be Acceptable

Sync would be acceptable if:
- Very low traffic (< 10 requests/second)
- Single-threaded application
- No external I/O operations
- Simple CPU-bound operations

But for a Kubernetes service that needs to scale and handle concurrent requests, **async is the better choice**.

