import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "npm:jose@5.9.6";

type OrderWebhookPayload = {
  type?: string;
  table?: string;
  schema?: string;
  record?: Record<string, unknown> | null;
  old_record?: Record<string, unknown> | null;
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const firebaseProjectId = Deno.env.get("FIREBASE_PROJECT_ID") ?? "";
const firebaseClientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL") ?? "";
const firebasePrivateKey = Deno.env.get("FIREBASE_PRIVATE_KEY") ?? "";

const supabase = createClient(supabaseUrl, serviceRoleKey);

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  if (!supabaseUrl || !serviceRoleKey || !firebaseProjectId || !firebaseClientEmail || !firebasePrivateKey) {
    return json({ error: "Missing required environment variables" }, 500);
  }

  const payload = (await request.json()) as OrderWebhookPayload;
  const record = payload.record ?? {};
  const previous = payload.old_record ?? {};
  const newStatus = String(record.status ?? "");
  const oldStatus = String(previous.status ?? "");

  if (newStatus != "accepted" || oldStatus == "accepted") {
    return json({ skipped: true, reason: "Order did not transition to accepted" });
  }

  const orderId = String(record.id ?? "");
  if (!orderId) {
    return json({ skipped: true, reason: "Missing order id" });
  }

  const { data: tokenRows, error: tokenError } = await supabase
    .from("users")
    .select("id, push_tokens")
    .eq("role", "driver")
    .not("push_tokens", "is", null);

  if (tokenError) {
    return json({ error: tokenError.message }, 500);
  }

  const tokens = [
    ...new Set(
      (tokenRows ?? []).flatMap((row) => normalizePushTokens(row.push_tokens)),
    ),
  ];
  if (tokens.length === 0) {
    return json({ sent: 0, skipped: true, reason: "No registered push tokens" });
  }

  const restaurantName = await fetchRestaurantName(record.restaurant_id);
  const address = String(record.delivery_address ?? "").trim();
  const accessToken = await createGoogleAccessToken();

  const title = restaurantName
    ? `New accepted order from ${restaurantName}`
    : "New accepted delivery order";
  const body = address
    ? `Delivery to ${address}`
    : "Open the driver app to review the delivery details.";

  const sendResults = await Promise.all(
    tokens.map(async (token) => {
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token,
              notification: {
                title,
                body,
              },
              data: {
                orderId,
                status: newStatus,
                screen: "order_details",
              },
              android: {
                priority: "high",
                notification: {
                  channel_id: "accepted_orders",
                  sound: "default",
                },
              },
              apns: {
                headers: {
                  "apns-priority": "10",
                },
                payload: {
                  aps: {
                    sound: "default",
                  },
                },
              },
            },
          }),
        },
      );

      if (response.ok) {
        return { token, ok: true as const };
      }

      const errorText = await response.text();
      if (errorText.includes("UNREGISTERED") || errorText.includes("registration-token-not-registered")) {
        const owners = await supabase
          .from("users")
          .select("id, push_tokens")
          .eq("role", "driver")
          .contains("push_tokens", [token]);

        if (!owners.error) {
          await Promise.all(
            (owners.data ?? []).map((user) =>
              supabase
                .from("users")
                .update({
                  push_tokens: normalizePushTokens(user.push_tokens).filter(
                    (entry) => entry !== token,
                  ),
                })
                .eq("id", user.id),
            ),
          );
        }
      }

      return { token, ok: false as const, errorText };
    }),
  );

  const successCount = sendResults.filter((result) => result.ok).length;
  return json({
    sent: successCount,
    failed: sendResults.length - successCount,
  });
});

async function fetchRestaurantName(restaurantId: unknown): Promise<string | null> {
  if (!restaurantId) {
    return null;
  }

  const { data } = await supabase
    .from("restaurants")
    .select("name")
    .eq("id", String(restaurantId))
    .maybeSingle();

  return data?.name ?? null;
}

async function createGoogleAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const algorithm = "RS256";
  const privateKey = await importPKCS8(normalizePrivateKey(firebasePrivateKey), algorithm);

  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  })
    .setProtectedHeader({ alg: algorithm, typ: "JWT" })
    .setIssuer(firebaseClientEmail)
    .setSubject(firebaseClientEmail)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(privateKey);

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!response.ok) {
    throw new Error(`Unable to obtain Google access token: ${await response.text()}`);
  }

  const body = await response.json();
  return String(body.access_token);
}

function normalizePrivateKey(key: string): string {
  return key.replaceAll("\\n", "\n");
}

function normalizePushTokens(raw: unknown): string[] {
  if (Array.isArray(raw)) {
    return raw
      .filter((value): value is string => typeof value === "string")
      .map((value) => value.trim())
      .filter(Boolean);
  }

  if (typeof raw === "string" && raw.trim()) {
    return [raw.trim()];
  }

  return [];
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
    },
  });
}
