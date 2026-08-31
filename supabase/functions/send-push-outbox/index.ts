import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  parseServiceAccount,
  sendFcmLegacy,
  sendFcmV1,
  type FcmMessage,
} from "../_shared/fcm_send.ts";

type PushRow = {
  id: string;
  fcm_token: string;
  title: string;
  body: string;
  data: Record<string, unknown> | null;
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
  try {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }

    const serviceAccount = parseServiceAccount(Deno.env.get("FCM_SERVICE_ACCOUNT_JSON"));
    const serverKey = Deno.env.get("FCM_SERVER_KEY")?.trim();

    if (!serviceAccount && !serverKey) {
      return json({
        error:
          "Mangler FCM_SERVICE_ACCOUNT_JSON (anbefalt) eller FCM_SERVER_KEY i Edge Function secrets",
        sent: 0,
      }, 500);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !supabaseServiceKey) {
      return json({ error: "Mangler Supabase miljøvariabler" }, 500);
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

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
      .from("push_outbox")
      .select("id, fcm_token, title, body, data, attempts")
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

    const pending = (rows ?? []) as PushRow[];
    let sent = 0;
    let failed = 0;
    const details: Array<{ id: string; ok: boolean; error?: string }> = [];

    for (const row of pending) {
      const message: FcmMessage = {
        token: row.fcm_token,
        title: row.title,
        body: row.body,
        data: row.data,
      };

      try {
        const result = serviceAccount
          ? await sendFcmV1(serviceAccount, message)
          : await sendFcmLegacy(serverKey!, message);

        if (result.ok) {
          await supabase
            .from("push_outbox")
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
            .from("push_outbox")
            .update({
              error_message: result.error.slice(0, 500),
              attempts: row.attempts + 1,
            })
            .eq("id", row.id);
          failed++;
          details.push({ id: row.id, ok: false, error: result.error });
        }
      } catch (e) {
        const err = e instanceof Error ? e.message : String(e);
        await supabase
          .from("push_outbox")
          .update({
            error_message: err.slice(0, 500),
            attempts: row.attempts + 1,
          })
          .eq("id", row.id);
        failed++;
        details.push({ id: row.id, ok: false, error: err });
      }
    }

    return json({
      processed: pending.length,
      sent,
      failed,
      transport: serviceAccount ? "fcm_v1" : "fcm_legacy",
      details,
    });
  } catch (e) {
    const err = e instanceof Error ? e.message : String(e);
    return json({ error: err, sent: 0 }, 500);
  }
});
