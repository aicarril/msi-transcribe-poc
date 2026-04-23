# Verification Report — Subtask 1: Terraform Foundation

**Date**: 2026-04-23  
**Verifier**: verifier-1  
**Overall**: ✅ PASS (all 5 checks passed)

---

## Step 1: S3 Bucket

**Resource**: `msi-transcribe-poc-transcripts-779846822196`  
**Result**: ✅ PASS

```
=== head-bucket ===
{
  "HTTPStatusCode": 200,
  "BucketRegion": "us-east-1"
}

=== get-bucket-encryption ===
{
  "Rules": [
    {
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      },
      "BucketKeyEnabled": false
    }
  ]
}

=== get-public-access-block ===
{
  "BlockPublicAcls": true,
  "IgnorePublicAcls": true,
  "BlockPublicPolicy": true,
  "RestrictPublicBuckets": true
}
```

- Bucket exists in us-east-1
- Server-side encryption: AES256
- All public access blocked

---

## Step 2: DynamoDB Table

**Resource**: `msi-transcribe-poc-sessions`  
**Result**: ✅ PASS

```
=== describe-table ===
{
  "TableName": "msi-transcribe-poc-sessions",
  "TableStatus": "ACTIVE",
  "KeySchema": [
    {
      "AttributeName": "sessionId",
      "KeyType": "HASH"
    }
  ],
  "BillingMode": "PAY_PER_REQUEST"
}
```

- Table is ACTIVE
- Partition key: `sessionId` (String, HASH)
- Billing: PAY_PER_REQUEST (on-demand)

---

## Step 3: Cognito Identity Pool

**Resource**: `us-east-1:1e71ebd2-85a0-4f9d-9d19-0758c1eb1443`  
**Result**: ✅ PASS

```
=== describe-identity-pool ===
{
  "IdentityPoolName": "msi-transcribe-poc-identity-pool",
  "AllowUnauthenticatedIdentities": true,
  "AllowClassicFlow": true
}

=== get-id + get-credentials-for-identity ===
{
  "IdentityId": "us-east-1:b5927e29-349b-c91b-9f6d-8e583b6f125f",
  "HasAccessKeyId": true,
  "HasSecretKey": true,
  "HasSessionToken": true
}
```

- Unauthenticated identities: enabled
- Classic flow: enabled
- Successfully obtained temporary credentials (AccessKeyId, SecretKey, SessionToken)

---

## Step 4: Cognito Unauth Role (Transcribe Permission)

**Resource**: `msi-transcribe-poc-cognito-unauth-role`  
**Result**: ✅ PASS

```
=== get-role ===
{
  "RoleName": "msi-transcribe-poc-cognito-unauth-role",
  "Arn": "arn:aws:iam::779846822196:role/msi-transcribe-poc-cognito-unauth-role"
}

=== inline policy: msi-transcribe-poc-cognito-unauth-policy ===
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": ["transcribe:StartStreamTranscriptionWebSocket"],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
```

- Role exists and is attached to Cognito Identity Pool
- Has `transcribe:StartStreamTranscriptionWebSocket` permission

---

## Step 5: Lambda Execution Role

**Resource**: `msi-transcribe-poc-lambda-role`  
**Result**: ✅ PASS

```
=== get-role ===
{
  "RoleName": "msi-transcribe-poc-lambda-role",
  "Arn": "arn:aws:iam::779846822196:role/msi-transcribe-poc-lambda-role"
}

=== inline policy: msi-transcribe-poc-lambda-policy ===
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
      "Effect": "Allow",
      "Resource": "arn:aws:logs:us-east-1:779846822196:*"
    },
    {
      "Action": ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Scan"],
      "Effect": "Allow",
      "Resource": "arn:aws:dynamodb:us-east-1:779846822196:table/msi-transcribe-poc-sessions"
    },
    {
      "Action": ["s3:PutObject", "s3:GetObject"],
      "Effect": "Allow",
      "Resource": "arn:aws:s3:::msi-transcribe-poc-transcripts-779846822196/*"
    },
    {
      "Action": ["bedrock:InvokeModel"],
      "Effect": "Allow",
      "Resource": "arn:aws:bedrock:us-east-1::foundation-model/*"
    }
  ]
}
```

- Role exists
- Permissions: ✅ CloudWatch Logs, ✅ DynamoDB (CRUD+Scan), ✅ S3 (Get/Put), ✅ Bedrock (InvokeModel)
- All resources scoped to correct ARNs

---

# Verification Report — Subtask 2: Custom Vocabulary

**Date**: 2026-04-23  
**Verifier**: verifier-1  
**Overall**: ✅ PASS

---

## Step 1: Vocabulary Exists and is READY

**Resource**: `msi-transcribe-poc-medical-spa`  
**Result**: ✅ PASS

```
=== get-vocabulary ===
{
  "VocabularyName": "msi-transcribe-poc-medical-spa",
  "LanguageCode": "en-US",
  "VocabularyState": "READY",
  "LastModifiedTime": "2026-04-23 03:19:10.460000+00:00"
}
```

- Vocabulary state: READY
- Language: en-US
- Note: FailureReason field contains a stale message from a prior attempt (spaces on line 7). Current version is READY with hyphens.

---

## Step 2: All 29 Terms Present

**Result**: ✅ PASS

```
=== vocabulary content (29 terms) ===
Botox, Dysport, Juvederm, Restylane, microneedling, dermaplaning,
chemical-peel, IPL, laser-resurfacing, hyaluronic-acid,
platelet-rich-plasma, PRP, subcutaneous, intramuscular, erythema,
edema, contraindication, glabella, nasolabial, mentalis, orbicularis,
corrugator, procerus, frontalis, masseter, CoolSculpting, PDO-threads,
neuromodulator, dermal-filler
```

- Expected: 29 terms → Actual: 29 terms
- Missing: none
- Extra: none
- Multi-word terms correctly hyphenated per Transcribe requirements

---

# Verification Report — Subtask 3: Chart Extraction Lambda + REST API

**Date**: 2026-04-23  
**Verifier**: verifier-1  
**Overall**: ❌ FAIL

---

## Step 1: Lambda Function Configuration

**Resource**: `msi-transcribe-poc-extract-chart`  
**Result**: ✅ PASS

```
{
  "FunctionName": "msi-transcribe-poc-extract-chart",
  "Runtime": "nodejs20.x",
  "MemorySize": 256,
  "Timeout": 60,
  "Handler": "index.handler",
  "Role": "arn:aws:iam::779846822196:role/msi-transcribe-poc-lambda-role",
  "State": "Active"
}
```

- Lambda exists, Active, correct runtime/memory/timeout

---

## Step 2: POST /extract-chart Endpoint

**Result**: ❌ FAIL — HTTP 502

```
$ curl -X POST https://ld5q3i55aj.execute-api.us-east-1.amazonaws.com/prod/extract-chart \
  -H "Content-Type: application/json" \
  -d '{"transcriptText": "Patient is a 42-year-old female...", "sessionId": "test-verify-001"}'

Response: {"message": "Internal server error"}
HTTP Status: 502
```

**Root cause from CloudWatch Logs:**
```
ERROR: ResourceNotFoundException: Access denied. This Model is marked by provider
as Legacy and you have not been actively using the model in the last 30 days.
Please upgrade to an active model on Amazon Bedrock

Model ID used: anthropic.claude-3-haiku-20240307-v1:0
```

**Fix required**: Change model ID from `anthropic.claude-3-haiku-20240307-v1:0` to inference profile `us.anthropic.claude-3-haiku-20240307-v1:0` (or use `us.anthropic.claude-haiku-4-5-20251001-v1:0` for the latest active Haiku).

Available active Haiku inference profiles:
- `us.anthropic.claude-3-haiku-20240307-v1:0` (ACTIVE)
- `us.anthropic.claude-3-5-haiku-20241022-v1:0` (ACTIVE)
- `us.anthropic.claude-haiku-4-5-20251001-v1:0` (ACTIVE)
