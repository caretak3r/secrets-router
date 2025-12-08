#!/usr/bin/env python3
import base64
import subprocess
import json

# Get the response using curl
result = subprocess.run(['curl', '-s', 'http://localhost:8080/secrets/identity-aes-key/aes-key?namespace=identity'], 
                       capture_output=True, text=True)
data = json.loads(result.stdout)
value = data['value']

print(f"Response value: {repr(value)}")
print(f"Length: {len(value)}")
print(f"UTF-8 encoded: {''.join(f'{ord(c):04x}' for c in value)}")

# Calculate what it should be
import base64
expected_base64 = "6XgTYv2cG3PERIYlMLLcGRNS+VnEdOzwAcKps3kMyI4="
decoded = base64.b64decode(expected_base64)
print(f"Original bytes: {len(decoded)}")
print(f"Original bytes: {decoded}")
print(f"Hex: {decoded.hex()}")
