#!/usr/bin/env python3
import time
import requests
import json
import sys

def make_secret_request(secret_key, namespace="test-namespace", sleep_time=2):
    url = f"http://secrets-broker-test-secrets-router.test-namespace.svc.cluster.local:8080/secrets/shared-database-secret/{secret_key}?namespace={namespace}"
    
    while True:
        try:
            response = requests.get(url, timeout=5)
            if response.status_code == 200:
                data = response.json()
                print(f"SUCCESS: {data}")
            else:
                print(f"ERROR: {response.status_code} - {response.text}")
        except Exception as e:
            print(f"REQUEST FAILED: {e}")
        
        time.sleep(sleep_time)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        secret_key = sys.argv[1]
        sleep_time = float(sys.argv[2]) if len(sys.argv) > 2 else 2
        make_secret_request(secret_key, "test-namespace", sleep_time)
    else:
        print("Usage: python secret_client.py <secret_key> [sleep_time]")
