const { CognitoIdentityClient, GetIdCommand, GetCredentialsForIdentityCommand } = require("@aws-sdk/client-cognito-identity");

const cognito = new CognitoIdentityClient();
const IDENTITY_POOL_ID = process.env.IDENTITY_POOL_ID;

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers: corsHeaders(), body: "" };
  }

  const { IdentityId } = await cognito.send(new GetIdCommand({ IdentityPoolId: IDENTITY_POOL_ID }));
  const { Credentials } = await cognito.send(new GetCredentialsForIdentityCommand({ IdentityId }));

  return {
    statusCode: 200,
    headers: corsHeaders(),
    body: JSON.stringify({
      accessKeyId: Credentials.AccessKeyId,
      secretAccessKey: Credentials.SecretKey,
      sessionToken: Credentials.SessionToken,
      expiration: Credentials.Expiration.toISOString()
    })
  };
};

function corsHeaders() {
  return {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type"
  };
}
