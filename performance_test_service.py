import requests
import time
import os
import sys
import threading
import json

def make_request(service_id, secret_key, sleep_time):
    url = "http://secrets-broker-test-secrets-router.test-namespace.svc.cluster.local:8080/secrets/shared-database-secret/{}/?namespace=test-namespace".format(secret_key)
    
    count = 0
    while True:
        try:
            start_time = time.time()
            response = requests.get(url, timeout=5)
            end_time = time.time()
            
            if response.status_code == 200:
                data = response.json()
                print(f"[{service_id}] SUCCESS: {data.get('backend', 'unknown')} | key={secret_key} | time={(end_time - start_time):.3f}s | count={count}")
            else:
                print(f"[{service_id}] ERROR: {response.status_code} - {response.text}")
            
            count += 1
            if count % 5 == 0:
                print(f"[{service_id}] Completed {count} requests to {secret_key}")
                
        except Exception as e:
            print(f"[{service_id}] Request failed: {e}")
        
        time.sleep(sleep_time)

def main():
    service_id = os.environ.get("SERVICE_ID", "unknown")
    secret_keys = os.environ.get("SECRET_KEYS", "password").split(",")
    sleep_time = float(os.environ.get("SLEEP_TIME", "2"))
    
    print(f"[{service_id}] Starting performance testing service")
    print(f"[{service_id}] Secret keys: {secret_keys}")
    print(f"[{service_id}] Sleep interval: {sleep_time}s")
    
    # Create threads for multiple concurrent requests
    threads = []
    for i, key in enumerate(secret_keys):
        thread = threading.Thread(target=make_request, args=(f"{service_id}-{i}", key.strip(), sleep_time))
        thread.daemon = True
        threads.append(thread)
    
    for thread in threads:
        thread.start()
    
    # Keep main thread alive
    try:
        while True:
            time.sleep(10)
    except KeyboardInterrupt:
        print(f"[{service_id}] Shutting down...")

if __name__ == "__main__":
    main()
