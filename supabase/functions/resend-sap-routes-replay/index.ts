import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  parseEmailAddress,
  processSapInboundEmail,
  sapRoutesCompanyId,
  senderAllowed,
  subjectMatches,
  type ResendAttachment,
} from "../_shared/sap_route_inbound_core.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
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

type ReceivedEmail = {
  id: string;
  from: string;
  to?: string[];
  subject?: string;
  created_at?: string;
  attachments?: ResendAttachment[];
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: cors });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const replaySecret = Deno.env.get("SAP_REPLAY_SECRET")?.trim();
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  const auth = req.headers.get("Authorization")?.trim() ?? "";
  const replayHeader = req.headers.get("x-sap-replay-secret")?.trim() ?? "";
  const apikey = req.headers.get("apikey")?.trim() ?? "";
  const bearer = auth.startsWith("Bearer ") ? auth.slice(7).trim() : auth;
  const ok = (replaySecret && (replayHeader === replaySecret || bearer === replaySecret)) ||
    (serviceKey && (bearer === serviceKey || apikey === serviceKey));
  if (!ok) {
    return json({ error: "Unauthorized" }, 401);
  }

  let body: { hours?: number; limit?: number; ignore_content_dedup?: boolean } =
    {};
  try {
    body = await req.json();
  } catch {
    // default body
  }

  const hours = Math.min(Math.max(body.hours ?? 72, 1), 168);
  const limit = Math.min(Math.max(body.limit ?? 50, 1), 100);
  const ignoreContentDedup = body.ignore_content_dedup === true;
  const sinceMs = Date.now() - hours * 60 * 60 * 1000;

  const resendKey = requireEnv("RESEND_API_KEY");
  const companyId = sapRoutesCompanyId();
  const supabase = createClient(requireEnv("SUPABASE_URL"), serviceKey);

  const listRes = await fetch(
    `https://api.resend.com/emails/receiving?limit=${limit}`,
    { headers: { Authorization: `Bearer ${resendKey}` } },
  );
  if (!listRes.ok) {
    const t = await listRes.text();
    return json({ error: `Resend list failed: ${listRes.status}`, detail: t.slice(0, 400) }, 502);
  }

  const listJson = await listRes.json() as { data?: ReceivedEmail[] };
  const emails = listJson.data ?? [];

  const processed: unknown[] = [];
  let totalInserted = 0;

  for (const email of emails) {
    const created = email.created_at ? Date.parse(email.created_at) : NaN;
    if (Number.isFinite(created) && created < sinceMs) continue;

    const toList = (email.to ?? []).map((t) => parseEmailAddress(t));
    if (toList.length > 0 && !toList.some((t) => t === "ruter@driftpro.no")) {
      continue;
    }
    if (!senderAllowed(email.from) || !subjectMatches(email.subject ?? "")) {
      continue;
    }

    const result = await processSapInboundEmail(supabase, {
      resendKey,
      companyId,
      emailId: email.id,
      from: email.from,
      subject: email.subject ?? "",
      attachmentHint: email.attachments,
      ignoreContentDedup,
    });

    totalInserted += result.inserted.length;
    processed.push({
      email_id: email.id,
      subject: email.subject,
      created_at: email.created_at,
      inserted: result.inserted,
      skipped: result.skipped,
      error: result.error,
    });
  }

  return json({
    ok: true,
    company_id: companyId,
    scanned: emails.length,
    processed: processed.length,
    total_inserted: totalInserted,
    results: processed,
  });
});
