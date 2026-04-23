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

const template = JSON.parse(fs.readFileSync(path.join(__dirname, "neuromodulator-template.json"), "utf8"));

exports.handler = async (event) => {
  const body = typeof event.body === "string" ? JSON.parse(event.body) : event.body || event;
  const { transcriptText, templateType } = body;
  const sessionId = body.sessionId || randomUUID();

  if (!transcriptText) {
    return { statusCode: 400, headers: corsHeaders(), body: JSON.stringify({ error: "transcriptText is required" }) };
  }

  const prompt = `You are a medical charting assistant. Extract structured chart fields from the following medical spa transcript into the JSON template below.

Rules:
- Only fill fields that are clearly evidenced in the transcript
- Leave fields empty ("" for strings, [] for arrays) if not mentioned
- For productsUsed, extract name, units, and lot if mentioned
- For areasOfTreatment, list each distinct treatment area
- consentObtained and photographsTaken should be true/false based on transcript evidence, default to the template values if not mentioned
- Return ONLY valid JSON, no explanation

Template:
${JSON.stringify(template, null, 2)}

Transcript:
${transcriptText}`;

  const bedrockResp = await bedrock.send(new InvokeModelCommand({
    modelId: "anthropic.claude-3-haiku-20240307-v1:0",
    contentType: "application/json",
    accept: "application/json",
    body: JSON.stringify({
      anthropic_version: "bedrock-2023-05-31",
      max_tokens: 2048,
      messages: [{ role: "user", content: prompt }]
    })
  }));

  const bedrockBody = JSON.parse(new TextDecoder().decode(bedrockResp.body));
  let chartJson;
  try {
    const text = bedrockBody.content[0].text;
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    chartJson = JSON.parse(jsonMatch ? jsonMatch[0] : text);
  } catch {
    chartJson = { error: "Failed to parse chart from LLM response", raw: bedrockBody.content[0].text };
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
    body: JSON.stringify({ sessionId, chart: chartJson })
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
