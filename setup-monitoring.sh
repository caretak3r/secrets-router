#!/bin/bash
# Set up Kubernetes Performance Monitoring with Grafana and Prometheus

echo "🚀 Setting up Kubernetes Performance Monitoring Stack..."

# Create monitoring namespace
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Deploy Prometheus using Helm
echo "📦 Installing Prometheus..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace \
    --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClass="standard" \
    --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage="8Gi" \
    --set prometheus.prometheusSpec.retention="15d" \
    --set prometheus.prometheusSpec.enableAdminAPI="false" \
    --set grafana.adminPassword="admin123" \
    --set grafana.service.type="NodePort" \
    --set grafana.service.nodePort="30030" \
    --timeout=10m

echo "⏳ Waiting for Prometheus to be ready..."
kubectl wait --for=condition=ready pod -l release=prometheus -n monitoring --timeout=300s

echo "⏳ Waiting for Grafana to be ready..."
kubectl wait --for=condition=ready pod -l release=prometheus-grafana -n monitoring --timeout=300s

# Create custom dashboards for secrets-broker monitoring
cat <<'EOF' > secrets-broker-dashboard.json
{
  "dashboard": {
    "id": null,
    "title": "Secrets Broker Performance Dashboard",
    "tags": ["secrets-broker", "kubernetes", "dapr"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Request Rate (req/s)",
        "type": "graph",
        "targets": [
          {
            "expr": "sum(rate(http_requests_total{job=\"secrets-router\"}[5m])) by (namespace, method, status_code)",
            "legendFormat": "{{method}} {{namespace}} {{status_code}}"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
        "yAxes": [{"label": "Requests/sec"}]
      },
      {
        "id": 2,
        "title": "Response Time (ms)",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket{job=\"secrets-router\"}[5m])) by (le, namespace))",
            "legendFormat": "50th percentile {{namespace}}"
          },
          {
            "expr": "histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{job=\"secrets-router\"}[5m])) by (le, namespace))",
            "legendFormat": "95th percentile {{namespace}}"
          },
          {
            "expr": "histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{job=\"secrets-router\"}[5m])) by (le, namespace))",
            "legendFormat": "99th percentile {{namespace}}"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
        "yAxes": [{"label": "Response Time (ms)"}, {"label": "Requests/sec"}]
      },
      {
        "id": 3,
        "title": "Error Rate (%)",
        "type": "singlestat",
        "targets": [
          {
            "expr": "sum(rate(http_requests_total{job=\"secrets-router\", status_code=~\"5..\"}[5m])) / sum(rate(http_requests_total{job=\"secrets-router\"}[5m])) * 100",
            "legendFormat": "Error Rate"
          }
        ],
        "gridPos": {"h": 4, "w": 6, "x": 0, "y": 8},
        "valueMaps": [{"value": "null", "text": "N/A"}],
        "thresholds": {"steps": [{"color": "green", "value": null}, {"color": "yellow", "value": 1}, {"color": "red", "value": 5}]}
      },
      {
        "id": 4,
        "title": "Memory Usage (MB)",
        "type": "graph",
        "targets": [
          {
            "expr": "container_memory_usage_bytes{pod=~\"secrets-router-.*\"} / 1024 / 1024",
            "legendFormat": "{{pod}}"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 16},
        "yAxes": [{"label": "Memory (MB)"}]
      },
      {
        "id": 5,
        "title": "CPU Usage (%)",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(container_cpu_usage_seconds_total{pod=~\"secrets-router-.*\"}[5m]) * 100",
            "legendFormat": "{{pod}}"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 16},
        "yAxes": [{"label": "CPU (%)"}]
      },
      {
        "id": 6,
        "title": "Active Connections",
        "type": "graph",
        "targets": [
          {
            "expr": "sum(dapr_http_client_connected_total{app_id=\"secrets-router\"}) by (app_id)",
            "legendFormat": "Connected Clients"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 24},
        "yAxes": [{"label": "Connections"}]
      },
      {
        "id": 7,
        "title": "Secret Store Latency (ms)",
        "type": "graph",
        "targets": [
          {
            "expr": "dapr_component_metric_latency_seconds{app_id=\"secrets-router\", error_type=\"none\"} * 1000",
            "legendFormat": "{{component}} {{method_type}}"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 24},
        "yAxes": [{"label": "Latency (ms)"}]
      },
      {
        "id": 8,
        "title": "Top Requested Secrets",
        "type": "table",
        "targets": [
          {
            "expr": "topk(10, sum(increase(http_requests_total{job=\"secrets-router\"}[1h])) by (path))",
            "format": "table",
            "instant": true
          }
        ],
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 32},
        "transformations": [{"id": "filterFieldsByName", "options": {"include": {"names": ["Time", "path", "Value"]}}}]
      }
    ],
    "refresh": "5s"
  }
}
EOF

# Create dashboard ConfigMap
kubectl create configmap secrets-broker-dashboard \
    --from-file=secrets-broker-dashboard.json=/dev/stdin \
    --namespace=monitoring \
    --dry-run=client -o yaml <<EOF | kubectl apply -f -
{
  "apiVersion": "v1",
  "kind": "ConfigMap",
  "metadata": {
    "name": "secrets-broker-dashboard",
    "namespace": "monitoring",
    "labels": {
      "grafana_dashboard": "1"
    }
  },
  "data": {
    "secrets-broker-dashboard.json": "$(cat secrets-broker-dashboard.json | sed 's/"/\\"/g')"
  }
}
EOF

echo "📊 Creating service monitoring configuration..."

# Enable Prometheus metrics for Dapr
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --set prometheus.prometheusSpec.additionalScrapeConfigs[+.].jobName="dapr",
    --set prometheus.prometheusSpec.additionalScrapeConfigs[+.].kubernetes_sd_configs[0].namespaces[0].name="dapr-system",
    --set prometheus.prometheusSpec.additionalScrapeConfigs[0].relabel_configs[0].source_labels="__meta_kubernetes_pod_annotation_prometheus_io_scrape",
    --set prometheus.prometheusSpec.additionalScrapeConfigs[0].relabel_configs[0].action="keep",
    --set prometheus.prometheusSpec.additionalScrapeConfigs[0].relabel_configs[0].regex="true"


# Get access details
GRAFANA_URL=$(kubectl get svc prometheus-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}{.status.loadBalancer.ingress[0].hostname}')

if [ -z "$GRAFANA_URL" ]; then
    GRAFANA_URL="localhost:30030"
    echo "📈 Grafana available at: http://localhost:30030"
    echo "👤 Username: admin"
    echo "🔑 Password: admin123"
fi

echo "🔗 Services:"
echo "  📊 Grafana: http://${GRAFANA_URL}/"
echo "  🔍 Prometheus: http://localhost:30090"
echo ""
echo "🚀 Port forwarding commands:"
echo "  kubectl port-forward svc/prometheus-grafana 30030:3000 -n monitoring"
echo "  kubectl port-forward svc/prometheus-kube-prometheus-prometheus 30090:9090 -n monitoring"
echo ""
echo "✅ Monitoring stack deployed successfully!"
