#!/usr/bin/env python3
"""
Test script to reproduce the raw bytes vs encoded issue in secrets-router
"""

import base64
import json
import os

def test_raw_bytes_issue():
    """Test the 32-byte raw bytes turning into 42 bytes issue"""
    
    # Create 32 bytes of raw data (simulating an AES crypto key)
    raw_bytes = os.urandom(32)
    print(f"Original raw bytes length: {len(raw_bytes)}")
    print(f"Original raw bytes: {raw_bytes}")
    
    # In Kubernetes, secrets are stored as base64 encoded
    # This is what gets stored in the K8s secret
    k8s_stored_value = base64.b64encode(raw_bytes).decode('ascii')
    print(f"K8s stored (base64) length: {len(k8s_stored_value)}")
    print(f"K8s stored (base64): {k8s_stored_value}")
    
    # Now simulate what secrets-router currently does
    try:
        # Step 1: Decode base64 (this is what line 114 does)
        decoded_bytes = base64.b64decode(k8s_stored_value)
        print(f"After base64 decode length: {len(decoded_bytes)}")
        
        # Step 2: Try to decode as UTF-8 (this is what line 115 does)
        decoded_utf8 = decoded_bytes.decode('utf-8')
        print(f"After UTF-8 decode length: {len(decoded_utf8)}")
        print("UTF-8 decode: SUCCESS")
        
    except UnicodeDecodeError as e:
        print(f"UTF-8 decode failed: {e}")
        # Step 3: Fall back to original base64 value (this is the problem!)
        print(f"Fallback value length: {len(k8s_stored_value)}")
        print(f"Fallback value: {k8s_stored_value}")
        
        print(f"\nPROBLEM: {len(raw_bytes)} bytes became {len(k8s_stored_value)} bytes!")
        return False
    
    return True

def test_json_serialization():
    """Test how raw bytes behave in JSON serialization"""
    
    # Create 32 bytes of raw data
    raw_bytes = os.urandom(32)
    
    # Try to put raw bytes directly in JSON (this will fail)
    try:
        json_data = {"value": raw_bytes}
        json_str = json.dumps(json_data)
        print("Direct raw bytes in JSON: SUCCESS")
    except (TypeError, UnicodeDecodeError) as e:
        print(f"Direct raw bytes in JSON: FAILED - {e}")
    
    # Base64 encoded version (current workaround)
    base64_value = base64.b64encode(raw_bytes).decode('ascii')
    json_data = {"value": base64_value}
    json_str = json.dumps(json_data)
    print(f"Base64 value in JSON: SUCCESS - length: {len(base64_value)}")
    
    # What we want: hex encoded for binary data
    hex_value = raw_bytes.hex()
    json_data = {"value": hex_value}
    json_str = json.dumps(json_data)
    print(f"Hex value in JSON: SUCCESS - length: {len(hex_value)}")

if __name__ == "__main__":
    print("=== Testing Raw Bytes Issue ===")
    test_raw_bytes_issue()
    
    print("\n=== Testing JSON Serialization ===")
    test_json_serialization()
