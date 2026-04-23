const { BedrockRuntimeClient, InvokeModelCommand } = require("@aws-sdk/client-bedrock-runtime");
const { DynamoDBClient, PutItemCommand } = require("@aws-sdk/client-dynamodb");
const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");
const { randomUUID } = require("crypto");
const fs = require("fs");
const path = require("path");

const bedrock = new BedrockRuntimeClient();
const dynamo = new DynamoDBClient();
const s3 = new S3Client();

const SESSIONS_TABLE = process.env.SESSIONS_TABLE;
const S3_BUCKET = process.env.S3_BUCKET;
const MODEL_ID = "us.anthropic.claude-haiku-4-5-20251001-v1:0";

const templates = {
  neuromodulator: JSON.parse(fs.readFileSync(path.join(__dirname, "neuromodulator-template.json"), "utf8")),
  filler: JSON.parse(fs.readFileSync(path.join(__dirname, "filler-template.json"), "utf8")),
  aesthetic: JSON.parse(fs.readFileSync(path.join(__dirname, "aesthetic-template.json"), "utf8")),
};

exports.handler = async (event) => {
  const body = typeof event.body === "string" ? JSON.parse(event.body) : event.body || event;
  const { transcriptText, templateType } = body;
  const sessionId = body.sessionId || randomUUID();

  if (!transcriptText) {
    return { statusCode: 400, headers: corsHeaders(), body: JSON.stringify({ error: "transcriptText is required" }) };
  }

  const template = templates[templateType] || templates.neuromodulator;

  // Single-pass: extract fields AND score confidence together
  const prompt = `You are a medical charting assistant. Extract structured chart fields from the transcript into the JSON template, AND score each field's confidence.

Rules for extraction:
- Only fill fields clearly evidenced in the transcript
- Leave fields empty ("" for strings, [] for arrays) if not mentioned
- For productsUsed, extract name, units/syringes/quantity, and lot if mentioned
- consentObtained and photographsTaken: true/false based on evidence, default to template values if not mentioned

Rules for confidence (0.0-1.0):
- 1.0 = explicitly stated, 0.7-0.9 = strongly implied, 0.4-0.6 = inferred, 0.1-0.3 = weak evidence, 0.0 = no evidence/defaulted

Return ONLY valid JSON in this exact format, no explanation:
{"chart": <filled template>, "confidence": {<field>: <score>, ...}}

Template:
${JSON.stringify(template, null, 2)}

Transcript:
${transcriptText}`;

  const resp = await bedrock.send(new InvokeModelCommand({
    modelId: MODEL_ID,
    contentType: "application/json",
    accept: "application/json",
    body: JSON.stringify({
      anthropic_version: "bedrock-2023-05-31",
      max_tokens: 2048,
      messages: [{ role: "user", content: prompt }]
    })
  }));

  const bedrockBody = JSON.parse(new TextDecoder().decode(resp.body));
  let chartJson, confidence;
  try {
    const text = bedrockBody.content[0].text;
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    const parsed = JSON.parse(jsonMatch ? jsonMatch[0] : text);
    chartJson = parsed.chart || parsed;
    confidence = parsed.confidence || {};
  } catch {
    chartJson = { error: "Failed to parse chart", raw: bedrockBody.content[0].text };
    confidence = {};
  }

  // Save transcript to S3
  await s3.send(new PutObjectCommand({
    Bucket: S3_BUCKET,
    Key: `sessions/${sessionId}/transcript.txt`,
    Body: transcriptText,
    ContentType: "text/plain"
  }));

  // Save chart to DynamoDB
  await dynamo.send(new PutItemCommand({
    TableName: SESSIONS_TABLE,
    Item: {
      sessionId: { S: sessionId },
      chart: { S: JSON.stringify(chartJson) },
      confidence: { S: JSON.stringify(confidence) },
      transcriptText: { S: transcriptText },
      templateType: { S: templateType || "neuromodulator" },
      s3TranscriptKey: { S: `sessions/${sessionId}/transcript.txt` },
      createdAt: { S: new Date().toISOString() },
      status: { S: "extracted" }
    }
  }));

  return {
    statusCode: 200,
    headers: corsHeaders(),
    body: JSON.stringify({ sessionId, chart: chartJson, confidence })
  };
};

function corsHeaders() {
  return {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type"
  };
}
