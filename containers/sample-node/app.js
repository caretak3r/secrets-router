const axios = require('axios');

const SECRETS_ROUTER_URL = process.env.SECRETS_ROUTER_URL || 'http://secrets-router:8080';
const TEST_SECRET_NAME = process.env.TEST_SECRET_NAME || 'database-credentials';
const TEST_SECRET_KEY = process.env.TEST_SECRET_KEY || 'password';
const TEST_NAMESPACE = process.env.NAMESPACE; // Optional

async function testSecretsRouter() {
  console.log('🔍 Testing Secrets Router service...');
  console.log(`Service URL: ${SECRETS_ROUTER_URL}`);
  console.log(`Testing secret: ${TEST_SECRET_NAME}/${TEST_SECRET_KEY}`);
  
  try {
    // First test health endpoint
    console.log('\n📋 Testing health check...');
    const healthResponse = await axios.get(`${SECRETS_ROUTER_URL}/healthz`);
    console.log('✅ Health check:', healthResponse.data);
    
    // Test readiness endpoint
    console.log('\n📋 Testing readiness check...');
    const readinessResponse = await axios.get(`${SECRETS_ROUTER_URL}/readyz`);
    console.log('✅ Readiness check:', readinessResponse.data);
    
    // Test secret retrieval with and without namespace
    console.log('\n🔑 Testing secret retrieval...');
    
    // Test without namespace (uses default)
    try {
      const secretUrl1 = `${SECRETS_ROUTER_URL}/secrets/${TEST_SECRET_NAME}/${TEST_SECRET_KEY}`;
      console.log(`Requesting: GET ${secretUrl1}`);
      const response1 = await axios.get(secretUrl1);
      console.log('✅ Secret without namespace:', JSON.stringify(response1.data, null, 2));
    } catch (error) {
      console.log('❌ Request without namespace failed:', error.response?.data || error.message);
    }
    
    // Test with namespace if provided
    if (TEST_NAMESPACE) {
      try {
        const secretUrl2 = `${SECRETS_ROUTER_URL}/secrets/${TEST_SECRET_NAME}/${TEST_SECRET_KEY}?namespace=${TEST_NAMESPACE}`;
        console.log(`Requesting: GET ${secretUrl2}`);
        const response2 = await axios.get(secretUrl2);
        console.log('✅ Secret with namespace:', JSON.stringify(response2.data, null, 2));
      } catch (error) {
        console.log('❌ Request with namespace failed:', error.response?.data || error.message);
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
