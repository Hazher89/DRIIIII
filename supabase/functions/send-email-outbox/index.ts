import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { readSmtpConfig, sendViaSmtp } from "../_shared/domeneshop_smtp.ts";
import { readResendSendConfig, sendViaResend } from "../_shared/resend_send.ts";

type EmailRow = {
  id: string;
  to_email: string;
  subject: string;
  body: string;
  attempts: number;
};

type SendResult = { ok: true } | { ok: false; error: string };

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const resendCfg = readResendSendConfig();
  const smtpCfg = readSmtpConfig();
  const useResend = !("error" in resendCfg);
  const useSmtp = !("error" in smtpCfg);

  if (!useResend && !useSmtp) {
    return json({
      error:
        "Mangler RESEND_API_KEY (anbefalt) eller SMTP_USER/SMTP_PASS (fallback)",
    }, 500);
  }

  const provider = useResend ? "resend" : "smtp";
  const testMode = useResend
    ? resendCfg.test
    : useSmtp
    ? smtpCfg.test
    : false;
  const from = useResend ? resendCfg.from : useSmtp ? smtpCfg.from : "";

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return json({ error: "Mangler Supabase miljøvariabler" }, 500);
  }

  const supabase = createClient(supabaseUrl, serviceKey);

  let filterIds: string[] | null = null;
  try {
    const body = await req.json();
    if (Array.isArray(body?.ids) && body.ids.length > 0) {
      filterIds = body.ids.map((id: unknown) => String(id)).filter(Boolean);
    }
  } catch {
    // empty body is fine
  }

  let query = supabase
    .from("email_outbox")
    .select("id, to_email, subject, body, attempts")
    .is("sent_at", null)
    .order("created_at", { ascending: true });

  if (filterIds?.length) {
    query = query.in("id", filterIds);
  } else {
    query = query.lt("attempts", 5).limit(20);
  }

  const { data: rows, error: fetchError } = await query;

  if (fetchError) {
    return json({ error: fetchError.message }, 500);
  }

  const pending = (rows ?? []) as EmailRow[];
  let sent = 0;
  let failed = 0;
  const details: Array<{ id: string; ok: boolean; error?: string }> = [];

  async function deliver(
    to: string,
    subject: string,
    body: string,
  ): Promise<SendResult> {
    if (useResend) {
      const r = await sendViaResend(resendCfg, to, subject, body);
      return r.ok ? { ok: true } : { ok: false, error: r.error };
    }
    return await sendViaSmtp(smtpCfg, to, subject, body);
  }

  for (const row of pending) {
    const result = await deliver(row.to_email, row.subject, row.body);

    if (result.ok) {
      await supabase
        .from("email_outbox")
        .update({
          sent_at: new Date().toISOString(),
          error_message: null,
          attempts: row.attempts + 1,
        })
        .eq("id", row.id);
      sent++;
      details.push({ id: row.id, ok: true });
    } else {
      await supabase
        .from("email_outbox")
        .update({
          error_message: result.error ?? "Ukjent feil",
          attempts: row.attempts + 1,
        })
        .eq("id", row.id);
      failed++;
      details.push({ id: row.id, ok: false, error: result.error });
    }

    // Resend: 5 req/s — SMTP: ~1/s hos Domeneshop
    if (!testMode && pending.length > 1) {
      await new Promise((r) => setTimeout(r, useResend ? 220 : 1100));
    }
  }

  return json({
    processed: pending.length,
    sent,
    failed,
    provider,
    testMode,
    from,
    details,
  });
});
