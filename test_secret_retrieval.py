#!/usr/bin/env python3
import requests
import sys
import json

try:
    # Test health endpoint
    health_response = requests.get('http://secrets-router:8080/healthz')
    print('=== Secrets Router Health ===')
    print(json.dumps(health_response.json(), indent=2))
    print()
    
    # Get secret value
    secret_response = requests.get('http://secrets-router:8080/secrets/test-secret/test.pem')
    secret_data = secret_response.json()
    
    print('=== Secret Retrieved ===')
    print(f'Secret Name: {secret_data["secret_name"]}')
    print(f'Secret Key: {secret_data["secret_key"]}')
    print(f'Backend: {secret_data["backend"]}')
    print()
    
    # Display the PEM content
    pem_content = secret_data['value']
    print('=== PEM Content ===')
    print(pem_content)
    print()
    
    print('=== Validation ===')
    if '-----BEGIN PRIVATE KEY-----' in pem_content and '-----END PRIVATE KEY-----' in pem_content:
        print('✓ Valid PEM private key format detected')
    else:
        print('✗ Invalid PEM format')
    
    print(f'✓ Secret retrieval successful via secrets-router')
    
except Exception as e:
    print(f'Error retrieving secret: {e}')
    sys.exit(1)
