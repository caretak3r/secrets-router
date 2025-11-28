#!/bin/bash
# Deploy 10 services accessing a shared secret for performance testing

# Create shared secret in test-namespace
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: shared-database-secret
  namespace: test-namespace
type: Opaque
stringData:
  password: shared-db-password-12345
  username: shared-db-user
  connection-string: "postgresql://localhost:5432/shared_db"
EOF

# Create performance test namespaces
for i in {1..3}; do
  kubectl create namespace perf-test-ns-$i --dry-run=client -o yaml | kubectl apply -f -
done

# Deploy 10 services across namespaces
cat <<EOF > multi-service-deployment.yaml
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
          apt-get update && apt-get install -y curl
          while true; do
            curl -s "http://secrets-broker-test-secrets-router.test-namespace.svc.cluster.local:8080/secrets/shared-database-secret/password?namespace=test-namespace"
            sleep 2
          done
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi

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
          apt-get update && apt-get install -y curl
          while true; do
            curl -s "http://secrets-broker-test-secrets-router.test-namespace.svc.cluster.local:8080/secrets/shared-database-secret/username?namespace=test-namespace"
            sleep 3
          done
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi

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
          apt-get update && apt-get install -y curl
          while true; do
            curl -s "http://secrets-broker-test-secrets-router.test-namespace.svc.cluster.local:8080/secrets/shared-database-secret/connection-string?namespace=test-namespace"
            sleep 2.5
          done
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi

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
          apt-get update && apt-get install -y curl
          while true; do
            curl -s "http://secrets-broker-test-secrets-router.test-namespace.svc.cluster.local:8080/secrets/shared-database-secret/password?namespace=test-namespace"
            sleep 1.5
          done
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi

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
          apt-get update && apt-get install -y curl
          while true; do
            curl -s "http://secrets-broker-test-secrets-router.test-namespace.svc.cluster.local:8080/secrets/shared-database-secret/username?namespace=test-namespace"
            sleep 2.8
          done
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi

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
          apt-get update && apt-get install -y curl
          while true; do
            curl -s "http://secrets-broker-test-secrets-router.test-namespace.svc.cluster.local:8080/secrets/shared-database-secret/connection-string?namespace=test-namespace"
            sleep 3.2
          done
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi

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
          apt-get update && apt-get install -y curl
          while true; do
            curl -s "http://secrets-broker-test-secrets-router.test-namespace.svc.cluster.local:8080/secrets/shared-database-secret/password?namespace=test-namespace"
            sleep 1.8
          done
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi

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
          apt-get update && apt-get install -y curl
          while true; do
            curl -s "http://secrets-broker-test-secrets-router.test-namespace.svc.cluster.local:8080/secrets/shared-database-secret/username?namespace=test-namespace"
            sleep 2.3
          done
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi

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
          apt-get update && apt-get install -y curl
          while true; do
            curl -s "http://secrets-broker-test-secrets-router.test-namespace.svc.cluster.local:8080/secrets/shared-database-secret/connection-string?namespace=test-namespace"
            sleep 2.7
          done
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi

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
          apt-get update && apt-get install -y curl
          while true; do
            curl -s "http://secrets-broker-test-secrets-router.test-namespace.svc.cluster.local:8080/secrets/shared-database-secret/password?namespace=test-namespace" &
            curl -s "http://secrets-broker-test-secrets-router.test-namespace.svc.cluster.local:8080/secrets/shared-database-secret/username?namespace=test-namespace" &
            wait
            sleep 1
          done
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
EOF

echo "🚀 Deploying 10 performance testing services..."
kubectl apply -f multi-service-deployment.yaml

echo "⏳ Waiting for services to be ready..."
for i in {1..10}; do
  echo "Waiting for perf-service-$i..."
  kubectl wait --for=condition=ready pod -l app=perf-service-$i --timeout=300s --all-namespaces
done

echo "✅ All 10 services deployed and running!"
echo "📊 Current status:"
kubectl get pods --all-namespaces | grep perf-service
