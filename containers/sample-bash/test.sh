#!/bin/bash

set -euo pipefail

# Configuration
SECRETS_ROUTER_URL="${SECRETS_ROUTER_URL:-http://secrets-router:8080}"
NAMESPACE="${NAMESPACE:-}"

echo "🔍 Testing Secrets Router service with Bash client..."
echo "Service URL: $SECRETS_ROUTER_URL"

# Discover configured secrets from environment variables
function get_configured_secrets() {
    local secrets=()
    for env_var in $(env | grep '^SECRET_'); do
        local secret_name=$(echo "$env_var" | cut -d'=' -f1)
        local secret_path=$(echo "$env_var" | cut -d'=' -f2)
        # Remove SECRET_ prefix and convert to lowercase for the secret name
        secret_name="${secret_name#SECRET_}"
        secret_name="${secret_name,,}"
        secret_name="${secret_name//_/-}"
        secrets+=("$secret_name:$secret_path")
    done
    echo "${secrets[@]}"
}

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
            echo "✅ Success (HTTP $http_code):"
            echo "$body" | jq . 2>/dev/null || echo "$body"
        else
            echo "❌ Failed (HTTP $http_code): $body"
            return 1
        fi
    else
        echo "❌ Failed to make request"
        return 1
    fi
    echo
}

# Get configured secrets
configured_secrets=($(get_configured_secrets))

if [[ ${#configured_secrets[@]} -eq 0 ]]; then
    echo "⚠️  No secrets configured. Set SECRET_* environment variables to test secret access."
    exit 0
fi

echo "Found ${#configured_secrets[@]} configured secrets:"
for secret in "${configured_secrets[@]}"; do
    secret_name="${secret%%:*}"
    secret_path="${secret##*:}"
    echo "  - $secret_name -> $secret_path"
done
echo

# Test health endpoint
test_endpoint "$SECRETS_ROUTER_URL/healthz" "Health check" || true

# Test readiness endpoint
test_endpoint "$SECRETS_ROUTER_URL/readyz" "Readiness check" || true

# Test each configured secret
for secret in "${configured_secrets[@]}"; do
    secret_name="${secret%%:*}"
    secret_path="${secret##*:}"
    
    echo "🔑 Testing secret: $secret_name -> $secret_path"
    
    # Test without namespace
    test_endpoint "$SECRETS_ROUTER_URL/secrets/$secret_path/value" "Secret without namespace" || true
    
    # Test with namespace if provided
    if [[ -n "$NAMESPACE" ]]; then
        test_endpoint "$SECRETS_ROUTER_URL/secrets/$secret_path/value?namespace=$NAMESPACE" "Secret with namespace" || true
    fi
done

echo "🎉 Bash client test completed!"
