#!/bin/bash
# Deploy 10 services using Python for HTTP requests instead of curl

# Create a ConfigMap with our Python client script
kubectl create configmap secret-client-script --from-file=secret_client.py=/dev/stdin --dry-run=client -o yaml <<EOF | kubectl apply -f -
#!/usr/bin/env python3
import time
import requests
import json
import sys
import os

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
    secret_key = os.environ.get("SECRET_KEY", "password")
    sleep_time = float(os.environ.get("SLEEP_TIME", "2"))
    namespace = os.environ.get("NAMESPACE", "test-namespace")
    make_secret_request(secret_key, namespace, sleep_time)
EOF

cat <<EOF > multi-service-python-deployment.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: perf-service-1
  namespace: perf-test-ns-1
  labels:
    app: perf-service-1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: perf-service-1
  template:
    metadata:
      labels:
        app: perf-service-1
    spec:
      containers:
      - name: perf-service-1
        image: python:3.11-slim
        command:
        - /bin/bash
        - -c
        - |
          pip install requests && python /app/secret_client.py
        env:
        - name: SECRET_KEY
          value: "password"
        - name: SLEEP_TIME
          value: "2"
        - name: NAMESPACE
          value: "test-namespace"
        volumeMounts:
        - name: script-volume
          mountPath: /app/secret_client.py
          subPath: secret_client.py
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
      volumes:
      - name: script-volume
        configMap:
          name: secret-client-script

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: perf-service-2
  namespace: perf-test-ns-1
  labels:
    app: perf-service-2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: perf-service-2
  template:
    metadata:
      labels:
        app: perf-service-2
    spec:
      containers:
      - name: perf-service-2
        image: python:3.11-slim
        command:
        - /bin/bash
        - -c
        - |
          pip install requests && python /app/secret_client.py
        env:
        - name: SECRET_KEY
          value: "username"
        - name: SLEEP_TIME
          value: "3"
        - name: NAMESPACE
          value: "test-namespace"
        volumeMounts:
        - name: script-volume
          mountPath: /app/secret_client.py
          subPath: secret_client.py
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
      volumes:
      - name: script-volume
        configMap:
          name: secret-client-script

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: perf-service-3
  namespace: perf-test-ns-1
  labels:
    app: perf-service-3
spec:
  replicas: 1
  selector:
    matchLabels:
      app: perf-service-3
  template:
    metadata:
      labels:
        app: perf-service-3
    spec:
      containers:
      - name: perf-service-3
        image: python:3.11-slim
        command:
        - /bin/bash
        - -c
        - |
          pip install requests && python /app/secret_client.py
        env:
        - name: SECRET_KEY
          value: "connection-string"
        - name: SLEEP_TIME
          value: "2.5"
        - name: NAMESPACE
          value: "test-namespace"
        volumeMounts:
        - name: script-volume
          mountPath: /app/secret_client.py
          subPath: secret_client.py
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
      volumes:
      - name: script-volume
        configMap:
          name: secret-client-script

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: perf-service-4
  namespace: perf-test-ns-2
  labels:
    app: perf-service-4
spec:
  replicas: 1
  selector:
    matchLabels:
      app: perf-service-4
  template:
    metadata:
      labels:
        app: perf-service-4
    spec:
      containers:
      - name: perf-service-4
        image: python:3.11-slim
        command:
        - /bin/bash
        - -c
        - |
          pip install requests && python /app/secret_client.py
        env:
        - name: SECRET_KEY
          value: "password"
        - name: SLEEP_TIME
          value: "1.5"
        - name: NAMESPACE
          value: "test-namespace"
        volumeMounts:
        - name: script-volume
          mountPath: /app/secret_client.py
          subPath: secret_client.py
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
      volumes:
      - name: script-volume
        configMap:
          name: secret-client-script

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: perf-service-5
  namespace: perf-test-ns-2
  labels:
    app: perf-service-5
spec:
  replicas: 1
  selector:
    matchLabels:
      app: perf-service-5
  template:
    metadata:
      labels:
        app: perf-service-5
    spec:
      containers:
      - name: perf-service-5
        image: python:3.11-slim
        command:
        - /bin/bash
        - -c
        - |
          pip install requests && python /app/secret_client.py
        env:
        - name: SECRET_KEY
          value: "username"
        - name: SLEEP_TIME
          value: "2.8"
        - name: NAMESPACE
          value: "test-namespace"
        volumeMounts:
        - name: script-volume
          mountPath: /app/secret_client.py
          subPath: secret_client.py
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
      volumes:
      - name: script-volume
        configMap:
          name: secret-client-script

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: perf-service-6
  namespace: perf-test-ns-2
  labels:
    app: perf-service-6
spec:
  replicas: 1
  selector:
    matchLabels:
      app: perf-service-6
  template:
    metadata:
      labels:
        app: perf-service-6
    spec:
      containers:
      - name: perf-service-6
        image: python:3.11-slim
        command:
        - /bin/bash
        - -c
        - |
          pip install requests && python /app/secret_client.py
        env:
        - name: SECRET_KEY
          value: "connection-string"
        - name: SLEEP_TIME
          value: "3.2"
        - name: NAMESPACE
          value: "test-namespace"
        volumeMounts:
        - name: script-volume
          mountPath: /app/secret_client.py
          subPath: secret_client.py
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
      volumes:
      - name: script-volume
        configMap:
          name: secret-client-script

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: perf-service-7
  namespace: perf-test-ns-2
  labels:
    app: perf-service-7
spec:
  replicas: 1
  selector:
    matchLabels:
      app: perf-service-7
  template:
    metadata:
      labels:
        app: perf-service-7
    spec:
      containers:
      - name: perf-service-7
        image: python:3.11-slim
        command:
        - /bin/bash
        - -c
        - |
          pip install requests && python /app/secret_client.py
        env:
        - name: SECRET_KEY
          value: "password"
        - name: SLEEP_TIME
          value: "1.8"
        - name: NAMESPACE
          value: "test-namespace"
        volumeMounts:
        - name: script-volume
          mountPath: /app/secret_client.py
          subPath: secret_client.py
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
      volumes:
      - name: script-volume
        configMap:
          name: secret-client-script

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: perf-service-8
  namespace: perf-test-ns-3
  labels:
    app: perf-service-8
spec:
  replicas: 1
  selector:
    matchLabels:
      app: perf-service-8
  template:
    metadata:
      labels:
        app: perf-service-8
    spec:
      containers:
      - name: perf-service-8
        image: python:3.11-slim
        command:
        - /bin/bash
        - -c
        - |
          pip install requests && python /app/secret_client.py
        env:
        - name: SECRET_KEY
          value: "username"
        - name: SLEEP_TIME
          value: "2.3"
        - name: NAMESPACE
          value: "test-namespace"
        volumeMounts:
        - name: script-volume
          mountPath: /app/secret_client.py
          subPath: secret_client.py
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
      volumes:
      - name: script-volume
        configMap:
          name: secret-client-script

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: perf-service-9
  namespace: perf-test-ns-3
  labels:
    app: perf-service-9
spec:
  replicas: 1
  selector:
    matchLabels:
      app: perf-service-9
  template:
    metadata:
      labels:
        app: perf-service-9
    spec:
      containers:
      - name: perf-service-9
        image: python:3.11-slim
        command:
        - /bin/bash
        - -c
        - |
          pip install requests && python /app/secret_client.py
        env:
        - name: SECRET_KEY
          value: "connection-string"
        - name: SLEEP_TIME
          value: "2.7"
        - name: NAMESPACE
          value: "test-namespace"
        volumeMounts:
        - name: script-volume
          mountPath: /app/secret_client.py
          subPath: secret_client.py
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
      volumes:
      - name: script-volume
        configMap:
          name: secret-client-script

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: perf-service-10
  namespace: perf-test-ns-3
  labels:
    app: perf-service-10
spec:
  replicas: 1
  selector:
    matchLabels:
      app: perf-service-10
  template:
    metadata:
      labels:
        app: perf-service-10
    spec:
      containers:
      - name: perf-service-10
        image: python:3.11-slim
        command:
        - /bin/bash
        - -c
        - |
          pip install requests && python /app/secret_client.py
        env:
        - name: SECRET_KEY
          value: "password"
        - name: SLEEP_TIME
          value: "1"
        - name: NAMESPACE
          value: "test-namespace"
        volumeMounts:
        - name: script-volume
          mountPath: /app/secret_client.py
          subPath: secret_client.py
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
      volumes:
      - name: script-volume
        configMap:
          name: secret-client-script
EOF

echo "🗑️  Removing old performance services..."
kubectl delete -f multi-service-deployment.yaml --ignore-not-found=true

echo "🚀 Deploying 10 Python-based performance testing services..."
kubectl apply -f multi-service-python-deployment.yaml

echo "⏳ Waiting for services to be ready..."
for i in {1..10}; do
  echo "Waiting for perf-service-$i..."
  kubectl wait --for=condition=ready pod -l app=perf-service-$i --timeout=300s --all-namespaces
done

echo "✅ All 10 Python services deployed and running!"
echo "📊 Current status:"
kubectl get pods --all-namespaces | grep perf-service
