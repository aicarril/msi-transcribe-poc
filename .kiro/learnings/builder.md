# Builder Learnings

Written by the verifier when verification failures trace back to the builder.

---

### 2026-04-22 — Website deployed with empty S3 bucket and missing bucket policy
- **Issue**: S3 bucket was created but static files (index.html, error.html) were never uploaded. Bucket policy for CloudFront OAC was not applied. CloudFront returned 403/404.
- **Root cause**: Terraform created the bucket infrastructure but the builder did not include file upload resources (aws_s3_object) or ensure the bucket policy was part of the terraform config.
- **Fix**: When building websites, ensure terraform includes: file upload to S3 (aws_s3_object or null_resource with aws s3 sync), and bucket policy granting CloudFront OAC read access.

### 2026-04-22 — Demo UI not built, demo guide not pushed to GitHub
- **Issue**: Pipeline completed but no demo HTML page was created. Demo guide was written to shared volume but never pushed to GitHub. Both lost when containers stopped.
- **Root cause**: Scoper did not create an explicit subtask for the demo UI. Demo coach wrote the guide but the builder never committed/pushed it.
- **Fix**: Always git push all files (code, demo guide, verification report) before signaling subtask complete. Demo UI is a non-negotiable deliverable.

### 2026-04-23 — Bedrock IAM policy region mismatch with cross-region inference profile
- **Issue**: POST /extract-chart returns 502. Lambda throws AccessDeniedException: not authorized to perform bedrock:InvokeModel on arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-3-haiku-20240307-v1:0.
- **Root cause**: Lambda uses cross-region inference profile model ID `us.anthropic.claude-3-haiku-20240307-v1:0` which routes requests to us-west-2. IAM policy only grants bedrock:InvokeModel on `arn:aws:bedrock:us-east-1::foundation-model/*` — the us-west-2 ARN is not covered.
- **Fix**: When using cross-region inference profiles (model IDs starting with `us.`, `eu.`, etc.), the IAM policy must use `arn:aws:bedrock:*::foundation-model/*` (wildcard region) because the request is routed to a different region. Alternatively, use the direct model ID without the region prefix (e.g., `anthropic.claude-3-haiku-20240307-v1:0`) to stay in the configured region.
