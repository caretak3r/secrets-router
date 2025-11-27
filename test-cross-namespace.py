import urllib.request
import urllib.error

url = "http://secrets-broker-test-secrets-router.test-namespace.svc.cluster.local:8080/secrets/default-namespace-secret/api-key?namespace=default"

try:
    response = urllib.request.urlopen(url)
    print(response.read().decode())
except urllib.error.HTTPError as e:
    print(f'Error: {e.code} - {e.reason}')
    print(f'URL: {url}')
    if e.code == 404:
        print('Secret not found or endpoint not accessible')
