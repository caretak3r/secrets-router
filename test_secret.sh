#!/bin/sh
echo "=== Testing Secrets Router ==="

# Test health endpoint
echo "1. Testing health endpoint:"
curl -s secrets-router:8080/healthz
echo ""
echo ""

# Test secret retrieval
echo "2. Testing secret retrieval:"
curl -s secrets-router:8080/secrets/test-secret/test.pem
echo ""
echo ""

# Test if secret contains PEM format
echo "3. Validating PEM format:"
SECRET_CONTENT=$(curl -s secrets-router:8080/secrets/test-secret/test.pem | grep -o '"value":"[^"]*"' | sed 's/"value":"//g' | sed 's/"//g')
if echo "$SECRET_CONTENT" | grep -q "-----BEGIN PRIVATE KEY-----"; then
    echo "✓ PEM format detected"
else
    echo "✗ Invalid PEM format"
fi

echo "4. Showing first few lines of secret:"
echo "$SECRET_CONTENT" | head -5
echo ""

echo "=== Test Complete ==="
