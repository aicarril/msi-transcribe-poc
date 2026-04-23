# DEMO-GUIDE.md — MSI Transcribe POC

## Opening Script

> "Hi, I'd like to show you how we can eliminate manual charting for medical spa providers. Today, a provider spends several minutes after each appointment typing up treatment notes. With this POC, the provider simply speaks during or after the appointment, and the system automatically transcribes the audio — using a custom medical spa vocabulary — and fills out the treatment chart using AI. The provider reviews, makes any corrections, and saves. Let me show you how it works."

---

## Prerequisites

Before the demo, confirm:
- You are using **Google Chrome** (mic access required)
- Your laptop microphone is working
- You have the live URLs below open in browser tabs
- You have the sample dictation script (Section 6) ready to read aloud

---

## Step-by-Step Demo

### Step 1: Show the Problem

- **Say**: "Right now, after every Botox or filler appointment, the provider has to manually type up the treatment chart — patient info, products used, dosage, injection sites, post-treatment instructions. With 20 appointments a day, that's a lot of repetitive data entry."
- **Do**: Show a blank Neuromodulator Treatment Form template (the JSON below or a printed version).
- **Show**: ~15 empty fields that need to be filled for every appointment.
- **Explain**: "This is the form MSI's Meevo platform needs filled out. Our system does this automatically from the provider's voice."

### Step 2: Open the Demo UI

- **Say**: "Let me show you the charting interface we built."
- **Do**: Open the Demo UI URL (see Live URLs below — update after subtask 5 deployment) in Chrome.
- **Show**: A two-panel interface — transcript on the left, chart form on the right.
- **Explain**: "This is what the provider would see inside Meevo. Left side shows the live transcription, right side shows the auto-filled chart."

### Step 3: Start a Live Transcription Session

- **Say**: "I'm going to start a session and speak as if I'm a provider finishing up a Botox appointment."
- **Do**: Click the **"Start Session"** button. Allow microphone access if prompted.
- **Show**: The mic indicator activates. The status shows "Listening..."
- **Explain**: "The browser is now streaming audio directly to Amazon Transcribe using a WebSocket connection. We're using a custom vocabulary with 29 medical spa terms — things like Botox, Dysport, glabella, nasolabial — so the transcription is accurate for this domain."

### Step 4: Speak the Sample Dictation

- **Say**: "I'll read a sample dictation now. Watch the transcript appear in real time."
- **Do**: Read the sample dictation script (see below) clearly into your microphone.
- **Show**: Text appears on the left panel in real time as you speak. Medical terms like "Botox," "glabella," and "nasolabial folds" should be transcribed correctly.
- **Explain**: "Notice how 'glabella' and 'nasolabial' are transcribed correctly — without the custom vocabulary, these would come through as gibberish. That's the custom vocabulary at work."

### Step 5: End Session and Extract Chart

- **Say**: "Now I'll end the session and let the AI extract the chart fields."
- **Do**: Click **"End Session"**.
- **Show**: A brief loading indicator, then the chart fields on the right panel auto-populate:
  - Treatment Performed: "Neuromodulator injection — Botox"
  - Areas of Treatment: ["Forehead", "Glabella", "Crow's feet"]
  - Products Used: Botox, 44 units total
  - Technique: "Standard injection technique, 30-gauge needle"
  - Post-Treatment Instructions: "No rubbing, avoid exercise for 24 hours..."
- **Explain**: "The full transcript was sent to Amazon Bedrock — specifically Claude — which extracted the structured fields into the chart template. It also runs a second pass to score confidence on each field. It only fills in what was actually mentioned. Fields without evidence are left empty, not hallucinated."

### Step 6: Show Confidence Scores

- **Say**: "Notice the confidence indicators next to each field."
- **Do**: Point to the confidence badges or scores next to each chart field.
- **Show**: High-confidence fields (e.g., productsUsed, areasOfTreatment) show green/high scores. Fields with less evidence show lower scores.
- **Explain**: "The system runs a dual-pass extraction. The first pass fills the chart, the second pass scores each field's confidence. This helps the provider know which fields to double-check."

### Step 7: Review and Save

- **Say**: "The provider can now review and correct anything before saving."
- **Do**: Click into one of the chart fields (e.g., add a follow-up date). Click **"Save"**.
- **Show**: The chart is saved. A success confirmation appears.
- **Explain**: "The chart and raw transcript are both stored — the chart in DynamoDB, the transcript in S3. Everything stays within AWS for HIPAA compliance. The provider stays in control and can edit anything before it's finalized."

### Step 8: Show Stored Data (Optional Technical Deep-Dive)

- **Say**: "Under the hood, let me show you what's stored."
- **Do**: Open the AWS Console → DynamoDB → Table: `msi-transcribe-poc-sessions` → Explore items. Click on the session you just created.
- **Show**: The DynamoDB item with `sessionId`, `chart` (JSON), `confidence` (JSON), `transcriptText`, `createdAt`, `status`.
- **Do**: Open S3 → Bucket: `msi-transcribe-poc-transcripts-779846822196` → `sessions/{sessionId}/transcript.txt`.
- **Show**: The raw transcript text file.
- **Explain**: "Both the structured chart and the raw transcript are preserved. This gives MSI an audit trail and the ability to re-extract charts if templates change."

---

## Sample Dictation Script

Read this aloud during the demo:

> "Patient is a 42-year-old female presenting for neuromodulator treatment. Chief complaint is moderate to severe glabellar lines and horizontal forehead lines. After reviewing the treatment plan and obtaining informed consent, I administered Botox cosmetic. I injected 20 units into the glabella region using five injection points at four units each. I then injected 12 units across the forehead using six injection points at two units each. Finally, I injected 12 units into the crow's feet area, six units per side, using three injection points per side. Total dose was 44 units of Botox. I used a 30-gauge needle with standard injection technique. Skin assessment prior to treatment showed no erythema or edema. No adverse reactions during the procedure. Post-treatment instructions given: avoid rubbing the treated areas, no strenuous exercise for 24 hours, remain upright for four hours. Photographs were taken before and after treatment. Follow-up scheduled in two weeks to assess results. Patient tolerated the procedure well."

---

## Live URLs and Resources

| Resource | URL / Identifier |
|---|---|
| **Demo UI** | *(To be deployed in subtask 5 — update this row with CloudFront URL after deployment)* |
| **API Endpoint** | `https://43d73l96s9.execute-api.us-east-1.amazonaws.com/prod/extract-chart` |
| **S3 Bucket** | `msi-transcribe-poc-transcripts-779846822196` |
| **DynamoDB Table** | `msi-transcribe-poc-sessions` |
| **Cognito Identity Pool** | `us-east-1:1e71ebd2-85a0-4f9d-9d19-0758c1eb1443` |
| **Custom Vocabulary** | `msi-transcribe-poc-medical-spa` (29 terms, READY) |
| **Region** | `us-east-1` |
| **AWS Console** | [us-east-1 Console](https://us-east-1.console.aws.amazon.com/) |

---

## Anticipated Questions and Answers

**Q1: Is this HIPAA compliant?**
> Yes. All data stays within AWS. Amazon Transcribe, Bedrock, S3, and DynamoDB are all HIPAA-eligible services. No audio or transcript data leaves the AWS environment. For production, we'd add encryption at rest (already enabled on S3), encryption in transit (all connections use TLS), and proper authentication via Cognito user pools.

**Q2: How accurate is the transcription for medical terms?**
> We use Amazon Transcribe's Custom Vocabulary feature with 29 medical spa-specific terms — product names like Botox and Dysport, anatomical terms like glabella and nasolabial, and procedure terms like microneedling and dermaplaning. This significantly improves accuracy over the base model.

**Q3: What happens if the AI fills in a field incorrectly?**
> The provider always reviews the auto-filled chart before saving. The system runs a dual-pass confidence scoring — fields with weak evidence are flagged so the provider knows what to double-check. The raw transcript is also preserved so the chart can be re-extracted if needed.

**Q4: How long does the chart extraction take?**
> Typically 2-5 seconds after the session ends. We use Claude Haiku on Bedrock, which is optimized for speed. For this use case, even 10 seconds is acceptable since the provider is transitioning between patients.

**Q5: Can this work with different chart templates?**
> Yes. The POC already supports three templates: Neuromodulator, Filler, and Aesthetic. The chart template is a JSON configuration passed to the LLM. Adding new templates (Microneedling, CoolSculpting, etc.) is just adding a new JSON file — no code changes.

**Q6: What's the cost per appointment?**
> Roughly $0.06 per 2-minute dictation: $0.048 for Transcribe (standard) + $0.012 for Custom Vocabulary + ~$0.002 for Bedrock Haiku. At scale (100 spas × 2.5 providers × 20 appointments/day), that's about $60/day or ~$1,200/month for the entire platform.

**Q7: Does it work with accents or background noise?**
> Amazon Transcribe handles a wide range of accents well. Background noise in a treatment room (fans, music) may reduce accuracy. For best results, we recommend the provider use the post-session dictation mode in a quieter setting, which takes about 2 minutes.

**Q8: Can multiple providers use this simultaneously?**
> Yes. Each session gets a unique ID. The architecture is serverless (Lambda, API Gateway, Transcribe Streaming) so it scales automatically. There's no shared state between sessions.

**Q9: What about state-by-state compliance differences?**
> Chart templates are configurable per state. MSI can define different required fields for different states, and the system will extract into whichever template is selected. The LLM only fills fields present in the template.

**Q10: How would this integrate with Meevo?**
> The POC exposes a REST API. Meevo would embed the transcription UI component and call the same API endpoints. The Cognito-based auth would be replaced with Meevo's existing authentication. The integration is straightforward — standard HTTPS API calls and WebSocket for audio streaming.

---

## Troubleshooting

### Microphone not working
- Check Chrome has microphone permission: click the lock icon in the address bar → Site settings → Microphone → Allow
- Make sure no other app (Zoom, Teams) is using the mic
- Try a different browser tab or restart Chrome

### "Start Session" doesn't connect
- Check browser console (F12 → Console) for errors
- Verify Cognito Identity Pool ID is `us-east-1:1e71ebd2-85a0-4f9d-9d19-0758c1eb1443`
- Ensure you're connected to the internet

### Transcription is inaccurate for medical terms
- Confirm the Custom Vocabulary `msi-transcribe-poc-medical-spa` is in READY state (it is as of 2026-04-23)
- Speak clearly and at a moderate pace
- Ensure the vocabulary name is correctly referenced in the Transcribe streaming call

### Chart extraction returns empty or error
- Check that the transcript contains enough detail (use the sample dictation)
- Verify the Lambda is using model ID `us.anthropic.claude-3-haiku-20240307-v1:0` (inference profile, not legacy model)
- Check CloudWatch Logs: `/aws/lambda/msi-transcribe-poc-extract-chart`

### API returns 502 or CORS error
- For 502: check CloudWatch Logs for the Lambda — likely a Bedrock model access issue
- For CORS: ensure the OPTIONS method is deployed on the API Gateway resource
- Redeploy the API Gateway stage if needed

### Quick recovery: bypass mic, show chart extraction directly
If the microphone or transcription breaks mid-demo, say: "Let me show you the chart extraction piece directly." Run:
```bash
curl -s -X POST https://43d73l96s9.execute-api.us-east-1.amazonaws.com/prod/extract-chart \
  -H "Content-Type: application/json" \
  -d '{
    "transcriptText": "Patient is a 42-year-old female presenting for neuromodulator treatment. Chief complaint is moderate to severe glabellar lines and horizontal forehead lines. After obtaining informed consent, I administered Botox cosmetic. 20 units into the glabella, 12 units across the forehead, 12 units into the crows feet. Total 44 units. 30-gauge needle, standard technique. No adverse reactions. Avoid rubbing treated areas, no exercise for 24 hours. Follow-up in two weeks. Photographs taken.",
    "templateType": "neuromodulator"
  }' | python3 -m json.tool
```
This bypasses the mic/transcription and shows the AI chart extraction directly. The audience sees the same structured output.
