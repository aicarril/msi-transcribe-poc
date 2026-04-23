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

### 2026-04-23 — Bedrock model ID is legacy, Lambda returns 502
- **Issue**: POST /extract-chart returns 502. Lambda fails with ResourceNotFoundException: "This Model is marked by provider as Legacy."
- **Root cause**: Builder used direct model ID `anthropic.claude-3-haiku-20240307-v1:0` which is LEGACY. AWS Bedrock now requires inference profile IDs for these models (e.g., `us.anthropic.claude-3-haiku-20240307-v1:0`).
- **Fix**: Use inference profile IDs instead of direct model IDs. Check `aws bedrock list-inference-profiles` for active profiles. For Haiku, use `us.anthropic.claude-3-haiku-20240307-v1:0` or newer `us.anthropic.claude-haiku-4-5-20251001-v1:0`.
