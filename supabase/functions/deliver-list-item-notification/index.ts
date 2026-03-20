import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { GoogleAuth } from "npm:google-auth-library@9.14.2";

type InsertWebhookPayload = {
  type: "INSERT";
  table: string;
  schema: string;
  record: NotificationEventRow;
  old_record: null;
};

type NotificationEventRow = {
  id: string;
  event_type: string;
  household_id: string | null;
  actor_user_id: string | null;
  payload: { list_id?: string; list_item_id?: string; name?: string };
  processed_at: string | null;
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function verifyBearer(req: Request, secret: string): Promise<boolean> {
  const auth = req.headers.get("authorization") ?? "";
  const expected = `Bearer ${secret}`;
  if (auth === expected) return true;
  const alt = req.headers.get("x-notification-webhook-secret");
  return alt === secret;
}

async function getFcmAccessToken(
  serviceAccountJson: string,
): Promise<{ accessToken: string; projectId: string }> {
  const credentials = JSON.parse(serviceAccountJson) as {
    project_id: string;
  };
  if (!credentials.project_id) {
    throw new Error("Service account JSON missing project_id");
  }
  const auth = new GoogleAuth({
    credentials,
    scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
  });
  const client = await auth.getClient();
  const tokenResponse = await client.getAccessToken();
  const accessToken = tokenResponse?.token;
  if (!accessToken) {
    throw new Error("Could not obtain Google access token for FCM");
  }
  return { accessToken, projectId: credentials.project_id };
}

async function sendFcmDataMessage(
  accessToken: string,
  projectId: string,
  deviceToken: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<void> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: deviceToken,
          notification: { title, body },
          data,
        },
      }),
    },
  );
  if (!res.ok) {
    const text = await res.text();
    console.error("FCM send failed", res.status, text);
    throw new Error(`FCM ${res.status}: ${text}`);
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const webhookSecret = Deno.env.get("NOTIFICATION_WEBHOOK_SECRET");
  if (!webhookSecret) {
    console.error("NOTIFICATION_WEBHOOK_SECRET is not set");
    return jsonResponse({ error: "Server misconfigured" }, 500);
  }
  if (!await verifyBearer(req, webhookSecret)) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  const saJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!saJson) {
    console.error("FIREBASE_SERVICE_ACCOUNT_JSON is not set");
    return jsonResponse({ error: "Server misconfigured" }, 500);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    console.error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
    return jsonResponse({ error: "Server misconfigured" }, 500);
  }

  let payload: InsertWebhookPayload;
  try {
    payload = (await req.json()) as InsertWebhookPayload;
  } catch {
    return jsonResponse({ error: "Invalid JSON" }, 400);
  }

  if (payload.type !== "INSERT" || payload.table !== "notification_events") {
    return jsonResponse({ ok: true, skipped: "wrong_table_or_type" });
  }

  const record = payload.record;
  if (record.event_type !== "list_item_added") {
    return jsonResponse({ ok: true, skipped: "event_type" });
  }
  if (record.processed_at) {
    return jsonResponse({ ok: true, skipped: "already_processed" });
  }
  if (!record.household_id || !record.actor_user_id) {
    await markProcessed(supabaseUrl, serviceKey, record.id);
    return jsonResponse({ ok: true, skipped: "missing_household_or_actor" });
  }

  const itemName = typeof record.payload?.name === "string"
    ? record.payload.name
    : "An item";
  const listId = record.payload?.list_id ?? "";
  const listItemId = record.payload?.list_item_id ?? "";

  const supabase = createClient(supabaseUrl, serviceKey);

  const { data: members, error: membersError } = await supabase
    .from("household_members")
    .select("user_id")
    .eq("household_id", record.household_id)
    .eq("status", "active");

  if (membersError) {
    console.error("household_members", membersError);
    return jsonResponse({ error: "query_failed" }, 500);
  }

  const recipientIds = (members ?? [])
    .map((m) => m.user_id as string)
    .filter((id) => id && id !== record.actor_user_id);

  if (recipientIds.length === 0) {
    await markProcessed(supabaseUrl, serviceKey, record.id);
    return jsonResponse({ ok: true, sent: 0, reason: "no_recipients" });
  }

  const { data: tokenRows, error: tokensError } = await supabase
    .from("user_device_tokens")
    .select("token")
    .in("user_id", recipientIds);

  if (tokensError) {
    console.error("user_device_tokens", tokensError);
    return jsonResponse({ error: "tokens_query_failed" }, 500);
  }

  const tokens = [...new Set(
    (tokenRows ?? []).map((r) => r.token as string).filter(Boolean),
  )];

  const { accessToken, projectId } = await getFcmAccessToken(saJson);

  const title = "New grocery item";
  const body = `${itemName} was added to your household list`;
  const data: Record<string, string> = {
    type: "list_item_added",
    list_id: listId,
    list_item_id: listItemId,
    household_id: record.household_id,
  };

  let sent = 0;
  for (const deviceToken of tokens) {
    try {
      await sendFcmDataMessage(
        accessToken,
        projectId,
        deviceToken,
        title,
        body,
        data,
      );
      sent++;
    } catch (e) {
      console.error("send exception", e);
    }
  }

  await markProcessed(supabaseUrl, serviceKey, record.id);
  return jsonResponse({ ok: true, sent, devices: tokens.length });
});

async function markProcessed(
  supabaseUrl: string,
  serviceKey: string,
  eventId: string,
): Promise<void> {
  const supabase = createClient(supabaseUrl, serviceKey);
  const { error } = await supabase
    .from("notification_events")
    .update({ processed_at: new Date().toISOString() })
    .eq("id", eventId);
  if (error) {
    console.error("markProcessed", error);
  }
}
