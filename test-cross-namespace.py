import requests
import sys

url = "http://secrets-broker-test-secrets-router.test-namespace.svc.cluster.local:8080/secrets/default-namespace-secret/api-key?namespace=default"

try:
    response = requests.get(url, timeout=10)
    response.raise_for_status()
    print(response.text)
except requests.exceptions.HTTPError as e:
    print(f'Error: {e.response.status_code} - {e.response.reason_phrase}')
    print(f'URL: {url}')
    if e.response.status_code == 404:
        print('Secret not found or endpoint not accessible')
except requests.exceptions.RequestException as e:
    print(f'Request Error: {e}')
    sys.exit(1)
