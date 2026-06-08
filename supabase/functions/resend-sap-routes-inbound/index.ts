import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  parseEmailAddress,
  processSapInboundEmail,
  sapRoutesCompanyId,
  type ResendAttachment,
} from "../_shared/sap_route_inbound_core.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, svix-id, svix-timestamp, svix-signature",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function requireEnv(name: string): string {
  const v = Deno.env.get(name)?.trim();
  if (!v) throw new Error(`Mangler secret: ${name}`);
  return v;
}

async function verifySvix(
  payload: string,
  headers: Headers,
  secret: string,
): Promise<boolean> {
  const id = headers.get("svix-id");
  const ts = headers.get("svix-timestamp");
  const sig = headers.get("svix-signature");
  if (!id || !ts || !sig) return false;

  const tsNum = Number(ts);
  if (!Number.isFinite(tsNum)) return false;
  const age = Math.abs(Date.now() / 1000 - tsNum);
  if (age > 300) return false;

  const key = secret.startsWith("whsec_") ? secret.slice(6) : secret;
  const keyBytes = Uint8Array.from(atob(key), (c) => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signed = `${id}.${ts}.${payload}`;
  const mac = await crypto.subtle.sign(
    "HMAC",
    cryptoKey,
    new TextEncoder().encode(signed),
  );
  const expected = btoa(String.fromCharCode(...new Uint8Array(mac)));

  for (const part of sig.split(" ")) {
    const [version, signature] = part.split(",");
    if (version !== "v1" || !signature) continue;
    if (signature === expected) return true;
  }
  return false;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: cors });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const rawBody = await req.text();
  let event: {
    type?: string;
    data?: {
      email_id?: string;
      from?: string;
      subject?: string;
      to?: string[];
      attachments?: ResendAttachment[];
    };
  };
  try {
    event = JSON.parse(rawBody);
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const webhookSecret = Deno.env.get("RESEND_WEBHOOK_SECRET")?.trim();
  if (webhookSecret) {
    const ok = await verifySvix(rawBody, req.headers, webhookSecret);
    if (!ok) {
      console.error("Invalid webhook signature", {
        hasSvixId: !!req.headers.get("svix-id"),
        hasSvixTs: !!req.headers.get("svix-timestamp"),
        hasSvixSig: !!req.headers.get("svix-signature"),
      });
      return json({ error: "Invalid webhook signature" }, 401);
    }
  }

  if (event.type !== "email.received") {
    return json({ ok: true, skipped: "event_type" });
  }

  const emailId = event.data?.email_id?.trim();
  const from = event.data?.from?.trim() ?? "";
  const subject = event.data?.subject?.trim() ?? "";

  if (!emailId) return json({ error: "Missing email_id" }, 400);

  const toList = (event.data?.to ?? []).map((t) => parseEmailAddress(t));
  if (toList.length > 0 && !toList.some((t) => t === "ruter@driftpro.no")) {
    console.log("Skipped: not ruter@driftpro.no", { to: toList });
    return json({ ok: true, skipped: "recipient" });
  }

  const supabase = createClient(
    requireEnv("SUPABASE_URL"),
    requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
  );

  const result = await processSapInboundEmail(supabase, {
    resendKey: requireEnv("RESEND_API_KEY"),
    companyId: sapRoutesCompanyId(),
    emailId,
    from,
    subject,
    attachmentHint: event.data?.attachments,
  });

  if (result.error) {
    console.error("SAP inbound failed", emailId, result.error);
    return json({ error: result.error }, 502);
  }

  console.log("SAP inbound processed", {
    emailId,
    inserted: result.inserted.length,
    skipped: result.skipped,
  });

  return json({
    ok: true,
    email_id: emailId,
    inserted: result.inserted.length,
    files: result.inserted,
    skipped: result.skipped,
  });
});
