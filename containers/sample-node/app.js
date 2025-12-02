const axios = require('axios');

const SECRETS_ROUTER_URL = process.env.SECRETS_ROUTER_URL || 'http://secrets-router:8080';
const NAMESPACE = process.env.NAMESPACE; // Optional

// Discover configured secrets from environment variables
function getConfiguredSecrets() {
  const secrets = {};
  for (const [key, value] of Object.entries(process.env)) {
    if (key.startsWith('SECRET_')) {
      // Remove SECRET_ prefix and convert to lowercase for the secret name
      const secretName = key.slice(7).toLowerCase().replace(/_/g, '-');
      secrets[secretName] = value;
    }
  }
  return secrets;
}

async function testSecretsRouter() {
  console.log('🔍 Testing Secrets Router service...');
  console.log(`Service URL: ${SECRETS_ROUTER_URL}`);
  
  const configuredSecrets = getConfiguredSecrets();
  
  if (Object.keys(configuredSecrets).length === 0) {
    console.log('⚠️  No secrets configured. Set SECRET_* environment variables to test secret access.');
    return;
  }
  
  console.log(`Found ${Object.keys(configuredSecrets).length} configured secrets: ${Object.keys(configuredSecrets).join(', ')}`);
  
  try {
    // First test health endpoint
    console.log('\n📋 Testing health check...');
    const healthResponse = await axios.get(`${SECRETS_ROUTER_URL}/healthz`);
    console.log('✅ Health check:', healthResponse.data);
    
    // Test readiness endpoint
    console.log('\n📋 Testing readiness check...');
    const readinessResponse = await axios.get(`${SECRETS_ROUTER_URL}/readyz`);
    console.log('✅ Readiness check:', readinessResponse.data);
    
    // Test each configured secret
    for (const [secretName, secretPath] of Object.entries(configuredSecrets)) {
      console.log(`\n🔑 Testing secret: ${secretName} -> ${secretPath}`);
      
      // Test without namespace
      try {
        const secretUrl = `${SECRETS_ROUTER_URL}/secrets/${secretPath}/value`;
        console.log(`Requesting: GET ${secretUrl}`);
        const response = await axios.get(secretUrl);
        console.log('✅ Secret retrieved:', JSON.stringify(response.data, null, 2));
      } catch (error) {
        console.log('❌ Secret retrieval failed:', error.response?.data || error.message);
      }
      
      // Test with namespace if provided
      if (NAMESPACE) {
        try {
          const secretUrlWithNs = `${SECRETS_ROUTER_URL}/secrets/${secretPath}/value?namespace=${NAMESPACE}`;
          console.log(`Requesting: GET ${secretUrlWithNs}`);
          const response = await axios.get(secretUrlWithNs);
          console.log('✅ Secret with namespace:', JSON.stringify(response.data, null, 2));
        } catch (error) {
          console.log('❌ Secret retrieval with namespace failed:', error.response?.data || error.message);
        }
      }
    }
    
    console.log('\n🎉 Node.js client test completed successfully!');
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    if (error.response) {
      console.error('Response data:', JSON.stringify(error.response.data, null, 2));
      console.error('Response status:', error.response.status);
    }
    process.exit(1);
  }
}

// Run tests on startup
testSecretsRouter();
