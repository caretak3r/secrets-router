#!/bin/bash
# Add metrics annotations to deployments for Prometheus monitoring

echo "🔍 ADDING METRICS ANNOTATIONS TO DEPLOYMENTS..."

# Add metrics annotations to secrets-router deployment
echo "Adding metrics annotations to secrets-router..."
kubectl patch deployment demo-broker-secrets-router -n demo -p '{"spec":{"template":{"metadata":{"annotations":{"prometheus.io/scrape":"true","prometheus.io/path":"/metrics","prometheus.io/port":"8080","prometheus.io/scheme":"http"}}}}' || echo "⚠️ Patch failed, continuing..."

# Delete and redeploy test-client with updated annotations
echo "Recreating test-client with metrics..."
kubectl delete deployment test-client -n demo --ignore-not-found=true
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-client
  namespace: demo
  labels:
    app: test-client
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-client
  template:
    metadata:
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/path: "/healthz"
        prometheus.io/port: "8080"
        prometheus.io/scheme: "http"
    spec:
      containers:
      - name: test-client
        image: curlimages/curl:latest
        command:
        - /bin/sh
        - -c
        - |
          while true; do
            sleep 10
            echo "$(date): Testing secret access from test client..."
            curl -s http://localhost:8080/secrets/database-credentials/password?namespace=demo || echo "ERROR: Could not reach" && sleep 5
          done
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          readinessProbe:
            httpGet:
            path: /healthz
            port: 8080
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: test-client
  namespace: demo
  labels:
    app: test-client
spec:
  selector:
    matchLabels:
      app: test-client
  ports:
  - port: 8081
    targetPort: 8080
  type: ClusterIP
EOF
kubectl wait --for=condition=ready pod -l app=test-client -n demo --timeout=60s || echo "⚠️ Service not fully ready"

# Add metrics annotations to secrets-router deployment
echo "Updating secrets-router deployment with metrics... (this will restart the pods)"
kubectl patch deployment demo-broker-secrets-router -n demo -p '{"spec":{"template":{"metadata":{"annotations":{"prometheus.io/scrape":"true","prometheus.io/port":"8080","prometheus.io/path":"/metrics","prometheus.io/scheme":"http"}}}}' || echo "⚠️ Patch failed"

echo "🔍 DEPLOYMENT STATUS AFTER METRICS SETUP:" && kubectl get pods -n demo
