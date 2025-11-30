#!/bin/bash

set -euo pipefail

# Configuration
SECRETS_ROUTER_URL="${SECRETS_ROUTER_URL:-http://secrets-router:8080}"
TEST_SECRET_NAME="${TEST_SECRET_NAME:-database-credentials}"
TEST_SECRET_KEY="${TEST_SECRET_KEY:-password}"
TEST_NAMESPACE="${TEST_NAMESPACE:-}"

echo "🔍 Testing Secrets Router service with Bash client..."
echo "Service URL: $SECRETS_ROUTER_URL"
echo "Testing secret: $TEST_SECRET_NAME/$TEST_SECRET_KEY"

# Function to make HTTP request and handle response
test_endpoint() {
    local url="$1"
    local description="$2"
    
    echo "📋 Testing: $description"
    echo "Requesting: GET $url"
    
    if response=$(curl -s -w '\n%{http_code}' "$url"); then
        http_code=$(echo "$response" | tail -n1)
        body=$(echo "$response" | sed '$d')
        
        if [[ "$http_code" -eq 200 ]]; then
            echo "✅ ✅ Success (HTTP $http_code):"
            echo "$body" | jq . 2>/dev/null || echo "$body"
        else
            echo "❌ Failed (HTTP $http_code): $body"
            return 1
        fi
    else
        echo "❌ ❌ Failed to make request"
        return 1
    fi
    echo
}

# Test health endpoint
test_endpoint "$SECRETS_ROUTER_URL/healthz" "Health check" || true

# Test readiness endpoint
test_endpoint "$SECRETS_ROUTER_URL/readyz" "Readiness check" || true

# Test secret retrieval without namespace (uses default)
test_endpoint "$SECRETS_ROUTER_URL/secrets/$TEST_SECRET_NAME/$TEST_SECRET_KEY" "Secret without namespace" || true

# Test secret retrieval with namespace if provided
if [[ -n "$TEST_NAMESPACE" ]]; then
    test_endpoint "$SECRETS_ROUTER_URL/secrets/$TEST_SECRET_NAME/$TEST_SECRET_KEY?namespace=$TEST_NAMESPACE" "Secret with namespace" || true
fi

echo "🎉 Bash client test completed!"
