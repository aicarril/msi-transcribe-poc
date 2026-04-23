const { DynamoDBClient, PutItemCommand, GetItemCommand, UpdateItemCommand, ScanCommand } = require("@aws-sdk/client-dynamodb");
const { LambdaClient, InvokeCommand } = require("@aws-sdk/client-lambda");
const { randomUUID } = require("crypto");

const dynamo = new DynamoDBClient();
const lambda = new LambdaClient();
const TABLE = process.env.SESSIONS_TABLE;
const EXTRACT_FN = process.env.EXTRACT_FUNCTION_NAME;

const cors = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type"
};

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") return { statusCode: 200, headers: cors, body: "" };

  const method = event.httpMethod;
  const path = event.resource;
  const pathId = event.pathParameters?.id;
  const body = event.body ? JSON.parse(event.body) : {};

  try {
    // POST /sessions
    if (method === "POST" && path === "/sessions") {
      const sessionId = randomUUID();
      await dynamo.send(new PutItemCommand({
        TableName: TABLE,
        Item: {
          sessionId: { S: sessionId },
          patientId: { S: body.patientId || "" },
          providerId: { S: body.providerId || "" },
          mode: { S: body.mode || "live" },
          templateType: { S: body.templateName || "neuromodulator" },
          status: { S: "active" },
          createdAt: { S: new Date().toISOString() }
        }
      }));
      return { statusCode: 200, headers: cors, body: JSON.stringify({ sessionId, status: "active" }) };
    }

    // POST /sessions/{id}/end
    if (method === "POST" && path === "/sessions/{id}/end") {
      const { transcriptText } = body;
      if (!transcriptText) return { statusCode: 400, headers: cors, body: JSON.stringify({ error: "transcriptText required" }) };

      // Get session to find templateType
      const session = await dynamo.send(new GetItemCommand({ TableName: TABLE, Key: { sessionId: { S: pathId } } }));
      const templateType = session.Item?.templateType?.S || "neuromodulator";

      // Invoke extract-chart Lambda
      const resp = await lambda.send(new InvokeCommand({
        FunctionName: EXTRACT_FN,
        Payload: JSON.stringify({ body: JSON.stringify({ transcriptText, sessionId: pathId, templateType }) })
      }));
      const extractResult = JSON.parse(new TextDecoder().decode(resp.Payload));
      const extractBody = JSON.parse(extractResult.body || "{}");

      // Update session status
      await dynamo.send(new UpdateItemCommand({
        TableName: TABLE,
        Key: { sessionId: { S: pathId } },
        UpdateExpression: "SET #s = :s, transcriptText = :t, chart = :c, confidence = :conf, endedAt = :e",
        ExpressionAttributeNames: { "#s": "status" },
        ExpressionAttributeValues: {
          ":s": { S: "completed" },
          ":t": { S: transcriptText },
          ":c": { S: JSON.stringify(extractBody.chart || {}) },
          ":conf": { S: JSON.stringify(extractBody.confidence || {}) },
          ":e": { S: new Date().toISOString() }
        }
      }));

      return { statusCode: 200, headers: cors, body: JSON.stringify({ sessionId: pathId, chart: extractBody.chart, confidence: extractBody.confidence }) };
    }

    // POST /sessions/{id}/save
    if (method === "POST" && path === "/sessions/{id}/save") {
      await dynamo.send(new UpdateItemCommand({
        TableName: TABLE,
        Key: { sessionId: { S: pathId } },
        UpdateExpression: "SET chart = :c, #s = :s, savedAt = :t",
        ExpressionAttributeNames: { "#s": "status" },
        ExpressionAttributeValues: {
          ":c": { S: JSON.stringify(body.chart || {}) },
          ":s": { S: "saved" },
          ":t": { S: new Date().toISOString() }
        }
      }));
      return { statusCode: 200, headers: cors, body: JSON.stringify({ sessionId: pathId, status: "saved" }) };
    }

    // GET /sessions/{id}
    if (method === "GET" && path === "/sessions/{id}") {
      const result = await dynamo.send(new GetItemCommand({ TableName: TABLE, Key: { sessionId: { S: pathId } } }));
      if (!result.Item) return { statusCode: 404, headers: cors, body: JSON.stringify({ error: "Session not found" }) };
      return { statusCode: 200, headers: cors, body: JSON.stringify(unmarshall(result.Item)) };
    }

    // GET /sessions
    if (method === "GET" && path === "/sessions") {
      const result = await dynamo.send(new ScanCommand({ TableName: TABLE, Limit: 50 }));
      const items = (result.Items || []).map(unmarshall);
      return { statusCode: 200, headers: cors, body: JSON.stringify({ sessions: items }) };
    }

    return { statusCode: 404, headers: cors, body: JSON.stringify({ error: "Not found" }) };
  } catch (err) {
    console.error(err);
    return { statusCode: 500, headers: cors, body: JSON.stringify({ error: err.message }) };
  }
};

function unmarshall(item) {
  const out = {};
  for (const [k, v] of Object.entries(item)) {
    if (v.S !== undefined) {
      // Try to parse JSON strings for chart/confidence
      if (k === "chart" || k === "confidence") {
        try { out[k] = JSON.parse(v.S); } catch { out[k] = v.S; }
      } else {
        out[k] = v.S;
      }
    } else if (v.N !== undefined) out[k] = Number(v.N);
    else if (v.BOOL !== undefined) out[k] = v.BOOL;
    else out[k] = v.S || v.N || v.BOOL;
  }
  return out;
}
