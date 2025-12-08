#!/usr/bin/env python3
import base64
import subprocess
import json

# Expected original data
expected_base64 = "6XgTYv2cG3PERIYlMLLcGRNS+VnEdOzwAcKps3kMyI4="
expected_bytes = base64.b64decode(expected_base64)
print(f"Expected bytes: {len(expected_bytes)}")
print(f"Expected hex:  {expected_bytes.hex()}")

# Get response from secrets-router
result = subprocess.run(['curl', '-s', 'http://localhost:8080/secrets/test-aes-key/aes-key'], 
                       capture_output=True, text=True)
data = json.loads(result.stdout)
value = data['value']

print(f"Response value: {value}")
print(f"Response type: {data['content_type']}")

# Convert hex back to bytes
response_bytes = bytes.fromhex(value)
print(f"Response bytes: {len(response_bytes)}")

# Verify they match
if response_bytes == expected_bytes:
    print("✅ SUCCESS: Bytes match perfectly!")
else:
    print("❌ FAILURE: Bytes don't match!")
    print(f"Expected: {expected_bytes}")
    print(f"Received: {response_bytes}")
