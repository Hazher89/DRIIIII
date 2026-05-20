import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { readSveveConfig, sendViaSveve } from "../_shared/sveve.ts";

type SmsRow = {
  id: string;
  to_phone: string;
  message: string;
  attempts: number;
};

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

  const cfg = readSveveConfig();
  if ("error" in cfg) return json({ error: cfg.error }, 500);

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
    .from("sms_outbox")
    .select("id, to_phone, message, attempts")
    .is("sent_at", null)
    .order("created_at", { ascending: true });

  if (filterIds?.length) {
    query = query.in("id", filterIds);
  } else {
    query = query.lt("attempts", 5).limit(25);
  }

  const { data: rows, error: fetchError } = await query;

  if (fetchError) {
    return json({ error: fetchError.message }, 500);
  }

  const pending = (rows ?? []) as SmsRow[];
  let sent = 0;
  let failed = 0;
  const details: Array<{ id: string; ok: boolean; error?: string }> = [];

  for (const row of pending) {
    const result = await sendViaSveve(
      cfg.user,
      cfg.passwd,
      row.to_phone,
      row.message,
      cfg.from,
      cfg.test,
    );

    if (result.ok) {
      await supabase
        .from("sms_outbox")
        .update({
          sent_at: new Date().toISOString(),
          sveve_message_id: result.id ?? null,
          error_message: null,
          attempts: row.attempts + 1,
        })
        .eq("id", row.id);
      sent++;
      details.push({ id: row.id, ok: true });
    } else {
      await supabase
        .from("sms_outbox")
        .update({
          error_message: result.error ?? "Ukjent feil",
          attempts: row.attempts + 1,
        })
        .eq("id", row.id);
      failed++;
      details.push({ id: row.id, ok: false, error: result.error });
    }
  }

  return json({
    processed: pending.length,
    sent,
    failed,
    testMode: cfg.test,
    details,
  });
});
