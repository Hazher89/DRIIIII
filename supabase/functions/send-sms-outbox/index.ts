import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const SVEVE_ENDPOINT = "https://sveve.no/SMS/SendMessage";

type SmsRow = {
  id: string;
  to_phone: string;
  message: string;
  attempts: number;
};

type SveveResponse = {
  response?: {
    msgOkCount?: number;
    fatalError?: string;
    errors?: Array<{ number?: string; message?: string }>;
    ids?: number[];
  };
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

async function sendViaSveve(
  user: string,
  passwd: string,
  to: string,
  msg: string,
  from: string,
  test: boolean,
): Promise<{ ok: boolean; id?: number; error?: string }> {
  const payload = {
    user,
    passwd,
    to,
    msg,
    from,
    f: "json",
    test,
  };

  const res = await fetch(SVEVE_ENDPOINT, {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=utf-8",
    },
    body: JSON.stringify(payload),
  });

  const text = await res.text();
  let parsed: SveveResponse;
  try {
    parsed = JSON.parse(text) as SveveResponse;
  } catch {
    return { ok: false, error: `Ugyldig Sveve-svar (${res.status}): ${text.slice(0, 200)}` };
  }

  const r = parsed.response;
  if (r?.fatalError) {
    return { ok: false, error: r.fatalError };
  }
  if (r?.errors?.length) {
    return { ok: false, error: r.errors.map((e) => e.message).join("; ") };
  }
  if ((r?.msgOkCount ?? 0) > 0) {
    return { ok: true, id: r.ids?.[0] };
  }
  return { ok: false, error: "Ingen melding sendt (msgOkCount=0)" };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, content-type",
      },
    });
  }

  const sveveUser = Deno.env.get("SVEVE_USER");
  const svevePass = Deno.env.get("SVEVE_PASSWD");
  const sveveFrom = Deno.env.get("SVEVE_FROM") ?? "DriftPro";
  const sveveTest = Deno.env.get("SVEVE_TEST") === "true";

  if (!sveveUser || !svevePass) {
    return json({ error: "Mangler SVEVE_USER eller SVEVE_PASSWD secrets" }, 500);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return json({ error: "Mangler Supabase miljøvariabler" }, 500);
  }

  const supabase = createClient(supabaseUrl, serviceKey);

  const { data: rows, error: fetchError } = await supabase
    .from("sms_outbox")
    .select("id, to_phone, message, attempts")
    .is("sent_at", null)
    .lt("attempts", 5)
    .order("created_at", { ascending: true })
    .limit(25);

  if (fetchError) {
    return json({ error: fetchError.message }, 500);
  }

  const pending = (rows ?? []) as SmsRow[];
  let sent = 0;
  let failed = 0;
  const details: Array<{ id: string; ok: boolean; error?: string }> = [];

  // Sveve: maks 5 samtidige kall — send sekvensielt
  for (const row of pending) {
    const result = await sendViaSveve(
      sveveUser,
      svevePass,
      row.to_phone,
      row.message,
      sveveFrom.slice(0, 11),
      sveveTest,
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
    testMode: sveveTest,
    details,
  });
});
