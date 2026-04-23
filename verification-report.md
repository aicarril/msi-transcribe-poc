# Verification Report — MSI Transcribe POC

**Date**: 2026-04-23T04:10Z
**Verifier**: verifier-1
**Result**: ✅ PASS (Subtasks 1-3 + credentials endpoint)

---

## Resources Verified

### ✅ S3 Bucket — msi-transcribe-poc-transcripts-779846822196
- Exists, AES256 server-side encryption enabled
- Public access fully blocked
- Transcript write confirmed: `sessions/verify-test-005/transcript.txt` (428 bytes)

### ✅ DynamoDB Table — msi-transcribe-poc-sessions
- Status: ACTIVE, Billing: PAY_PER_REQUEST
- Key schema: sessionId (S) HASH
- Record write confirmed: sessionId=verify-test-005, status=extracted

### ✅ Cognito Identity Pool — us-east-1:1e71ebd2-85a0-4f9d-9d19-0758c1eb1443
- AllowUnauthenticatedIdentities: true, AllowClassicFlow: true
- Credential vending verified via SDK and via GET /credentials endpoint

### ✅ Custom Vocabulary — msi-transcribe-poc-medical-spa
- Status: READY, Language: en-US

### ✅ Lambda — msi-transcribe-poc-extract-chart
- Runtime: nodejs20.x, Memory: 256MB, Timeout: 60s
- Model: us.anthropic.claude-haiku-4-5-20251001-v1:0 (Haiku 4.5)
- Single-pass extract+confidence Bedrock call

### ✅ API Gateway — msi-transcribe-poc-api (prod stage)
- URL: https://43d73l96s9.execute-api.us-east-1.amazonaws.com/prod

---

## Endpoint Tests

### ✅ POST /extract-chart — HTTP 200 (25.7s)
Chart extraction accurate: Botox/glabella+frontalis/30 units/lot BX2024-456/consent+photos all correctly extracted. Confidence scores present. S3+DynamoDB writes confirmed. CORS headers present.

### ✅ GET /credentials — HTTP 200
Returns valid Cognito temporary credentials (accessKeyId, secretAccessKey, sessionToken, expiration ~1hr TTL). CORS headers present.

### ✅ OPTIONS /extract-chart — HTTP 200
### ✅ OPTIONS /credentials — HTTP 200

---

## Issues Found and Resolved During Verification
1. **IAM policy region mismatch** — cross-region inference profile routed to us-west-2, policy only covered us-east-1. Fixed with wildcard region.
2. **Legacy model gating** — Claude 3 Haiku and 3.5 Haiku legacy-gated. Switched to Haiku 4.5.
3. **API Gateway 504 timeout** — two-pass Bedrock calls took 39s. Merged into single-pass (25.7s).

## Not Yet Built
- Charts CRUD endpoints (subtask 4)
- Demo UI with CloudFront (subtask 5)
