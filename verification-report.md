# Verification Report — MSI Transcribe POC

**Date**: 2026-04-23T03:50Z
**Verifier**: verifier-1
**Result**: ❌ FAIL

---

## Resources Verified

### ✅ S3 Bucket — msi-transcribe-poc-transcripts-779846822196
- Exists, AES256 server-side encryption enabled
- Public access fully blocked (all 4 flags true)

### ✅ DynamoDB Table — msi-transcribe-poc-sessions
- Status: ACTIVE
- Billing: PAY_PER_REQUEST
- Key schema: sessionId (S) HASH

### ✅ Cognito Identity Pool — us-east-1:1e71ebd2-85a0-4f9d-9d19-0758c1eb1443
- AllowUnauthenticatedIdentities: true
- AllowClassicFlow: true
- Successfully vended temporary credentials (verified via GetId + GetCredentialsForIdentity)

### ✅ Custom Vocabulary — msi-transcribe-poc-medical-spa
- Status: READY
- Language: en-US

### ✅ Lambda Function — msi-transcribe-poc-extract-chart
- Runtime: nodejs20.x, Handler: index.handler
- Memory: 256MB, Timeout: 60s
- Environment: SESSIONS_TABLE=msi-transcribe-poc-sessions, S3_BUCKET=msi-transcribe-poc-transcripts-779846822196
- State: Active

### ✅ API Gateway — msi-transcribe-poc-api
- Stage: prod
- URL: https://43d73l96s9.execute-api.us-east-1.amazonaws.com/prod
- CORS OPTIONS /extract-chart: 200, headers correct (Allow-Origin: *, Allow-Methods: POST,OPTIONS, Allow-Headers: Content-Type)

---

## Endpoint Tests

### ❌ POST /extract-chart — HTTP 502
**Command**:
```
curl -X POST https://43d73l96s9.execute-api.us-east-1.amazonaws.com/prod/extract-chart \
  -H "Content-Type: application/json" \
  -d '{"transcriptText":"Patient is a 42-year-old female presenting for Botox treatment to the glabella and frontalis. 20 units Botox administered. Consent obtained.","sessionId":"test-verify-002"}'
```
**Response**: `{"message": "Internal server error"}` (HTTP 502)

**Root cause**: AccessDeniedException from Bedrock. Lambda uses cross-region inference profile model ID `us.anthropic.claude-3-haiku-20240307-v1:0` which routes to `us-west-2`. IAM policy only grants `bedrock:InvokeModel` on `arn:aws:bedrock:us-east-1::foundation-model/*` and `arn:aws:bedrock:us-east-1:779846822196:inference-profile/*`. The `us-west-2` foundation model ARN is not covered.

**Lambda error log**:
```
AccessDeniedException: User: arn:aws:sts::779846822196:assumed-role/msi-transcribe-poc-lambda-role/msi-transcribe-poc-extract-chart
is not authorized to perform: bedrock:InvokeModel on resource:
arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-3-haiku-20240307-v1:0
because no identity-based policy allows the bedrock:InvokeModel action
```

**Fix**: Either:
1. Change IAM policy Bedrock Resource to `arn:aws:bedrock:*::foundation-model/*` (wildcard region), OR
2. Change Lambda MODEL_ID to `anthropic.claude-3-haiku-20240307-v1:0` (direct model, no cross-region routing)

### ✅ OPTIONS /extract-chart — HTTP 200
CORS preflight working correctly.

---

## Not Yet Deployed (Expected)

- **Subtask 4**: Charts CRUD endpoints (GET/PUT /charts) — not yet built
- **Subtask 5**: Demo UI (CloudFront + S3 website) — not yet built
- **DEMO-GUIDE.md**: Exists in /shared-repo/ but references a Demo UI that doesn't exist yet

---

## Summary

Infrastructure is solid — all AWS resources created correctly with proper configuration. The blocking issue is a **Bedrock IAM policy region mismatch** causing the core extract-chart Lambda to fail with AccessDeniedException. This must be fixed before subtasks 4-5 can proceed.
