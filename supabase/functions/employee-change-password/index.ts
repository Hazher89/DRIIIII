import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { readSveveConfig, sendViaSveve } from "../_shared/sveve.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function normalizePhoneNo(phone: string): string | null {
  const d = phone.replace(/[^0-9]/g, "");
  if (!d) return null;
  if (d.length === 8 && /^[49]/.test(d)) return `47${d}`;
  if (d.length === 10 && /^47[49]/.test(d)) return d;
  if (d.length === 11 && d.startsWith("047")) return d.slice(1);
  if (d.length >= 10 && d.startsWith("47")) return d.slice(0, Math.min(d.length, 11));
  return null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authHeader = req.headers.get("Authorization") ?? "";

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const admin = createClient(supabaseUrl, serviceKey);

    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData.user) {
      return new Response(JSON.stringify({ error: "Ikke innlogget" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await req.json();
    const newPassword = String(body?.new_password ?? "").trim();
    if (newPassword.length < 6) {
      return new Response(
        JSON.stringify({ error: "Passord må være minst 6 tegn (Supabase-krav)" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const uid = userData.user.id;
    const { data: profile, error: profErr } = await admin
      .from("profiles")
      .select("id, company_id, phone, employee_number, partner_id")
      .eq("id", uid)
      .maybeSingle();

    if (profErr || !profile) {
      return new Response(JSON.stringify({ error: "Fant ikke profil" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (profile.partner_id) {
      return new Response(JSON.stringify({ error: "Kun for MAVI-ansatte" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const phoneRaw = profile.phone as string | null;
    const normalizedPhone = phoneRaw ? normalizePhoneNo(phoneRaw) : null;
    if (!normalizedPhone) {
      return new Response(
        JSON.stringify({ error: "Ingen mobilnummer på profilen — kan ikke sende SMS" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const { error: updateErr } = await admin.auth.admin.updateUserById(uid, {
      password: newPassword,
    });
    if (updateErr) {
      return new Response(JSON.stringify({ error: updateErr.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const employeeNumber = String(profile.employee_number ?? "").trim() || "—";
    let smsSent = false;
    let smsError: string | null = null;

    const { data: smsId, error: smsErr } = await admin.rpc("notify_employee_password_sms", {
      p_company_id: profile.company_id,
      p_phone: normalizedPhone,
      p_employee_number: employeeNumber,
      p_password: newPassword,
    });

    if (smsErr) {
      smsError = smsErr.message;
    } else if (smsId) {
      const sveve = readSveveConfig();
      if (sveve) {
        const { data: row } = await admin
          .from("sms_outbox")
          .select("to_phone, message")
          .eq("id", smsId)
          .maybeSingle();
        if (row) {
          try {
            await sendViaSveve(sveve, row.to_phone, row.message);
            smsSent = true;
            await admin.from("sms_outbox").update({ sent_at: new Date().toISOString() }).eq("id", smsId);
          } catch (e) {
            smsError = e instanceof Error ? e.message : String(e);
          }
        }
      }
    }

    await admin
      .from("employee_login_accounts")
      .update({ must_change_password: false, updated_at: new Date().toISOString() })
      .eq("profile_id", uid);

    return new Response(
      JSON.stringify({
        ok: true,
        sms_sent: smsSent,
        sms_error: smsError,
        message: smsSent
          ? "Passord oppdatert. Nytt passord er sendt på SMS."
          : "Passord oppdatert. SMS-kø opprettet eller Sveve ikke konfigurert.",
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
