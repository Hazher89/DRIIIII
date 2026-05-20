import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { readSveveConfig, sendViaSveve } from "../_shared/sveve.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function randomPassword(len = 10): string {
  const chars = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789";
  let out = "";
  const arr = new Uint8Array(len);
  crypto.getRandomValues(arr);
  for (let i = 0; i < len; i++) out += chars[arr[i] % chars.length];
  return out;
}

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
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceKey);

    const body = await req.json();
    const username = String(body?.username ?? "").trim().toLowerCase();
    if (!username || username.length < 2) {
      return new Response(JSON.stringify({ error: "Skriv brukernavnet ditt" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: account, error: accErr } = await admin
      .from("partner_portal_accounts")
      .select("id, partner_id, company_id, partner_vehicle_id, username, login_email, phone, profile_id, account_kind, is_active")
      .eq("is_active", true)
      .eq("username", username)
      .maybeSingle();

    if (accErr) {
      return new Response(JSON.stringify({ error: accErr.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (!account) {
      return new Response(
        JSON.stringify({
          error: "Fant ikke brukernavn. Sjekk staving eller kontakt MAVI.",
        }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const phoneRaw = account.phone as string | null;
    const normalizedPhone = phoneRaw ? normalizePhoneNo(phoneRaw) : null;
    if (!normalizedPhone) {
      return new Response(
        JSON.stringify({
          error: "Ingen telefon registrert på kontoen. Kontakt MAVI for hjelp.",
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const pw = randomPassword(10);
    const authEmail = String(account.login_email).toLowerCase();
    const profileId = account.profile_id as string | null;

    if (profileId) {
      const { error: updateErr } = await admin.auth.admin.updateUserById(profileId, {
        password: pw,
        email_confirm: true,
      });
      if (updateErr) {
        return new Response(JSON.stringify({ error: updateErr.message }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    } else {
      return new Response(
        JSON.stringify({ error: "Kontoen er ikke ferdig opprettet. Kontakt MAVI." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const isOwner = account.account_kind === "owner" || account.partner_vehicle_id == null;

    let smsSent = false;
    let smsError: string | null = null;
    const { data: smsId, error: smsErr } = await admin.rpc("notify_partner_portal_credentials_sms", {
      p_company_id: account.company_id,
      p_phone: normalizedPhone,
      p_username: account.username,
      p_password: pw,
      p_is_owner: isOwner,
    });

    if (smsErr) {
      smsError = smsErr.message;
    } else if (smsId) {
      const sveve = readSveveConfig();
      if ("error" in sveve) {
        smsError = sveve.error;
      } else {
        const { data: smsRow } = await admin
          .from("sms_outbox")
          .select("id, to_phone, message, attempts")
          .eq("id", smsId)
          .maybeSingle();
        if (smsRow) {
          const result = await sendViaSveve(
            sveve.user,
            sveve.passwd,
            smsRow.to_phone,
            smsRow.message,
            sveve.from,
            sveve.test,
          );
          if (result.ok) {
            await admin
              .from("sms_outbox")
              .update({
                sent_at: new Date().toISOString(),
                sveve_message_id: result.id ?? null,
                error_message: null,
                attempts: (smsRow.attempts ?? 0) + 1,
              })
              .eq("id", smsRow.id);
            smsSent = true;
          } else {
            smsError = result.error ?? "SMS ble ikke sendt";
          }
        }
      }
    }

    if (!smsSent) {
      return new Response(
        JSON.stringify({
          error: smsError ?? "Kunne ikke sende SMS med nytt passord. Prøv igjen eller kontakt MAVI.",
        }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    return new Response(
      JSON.stringify({
        ok: true,
        sms_sent: true,
        message: "Nytt passord er sendt på SMS til nummeret som er registrert på kontoen din.",
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
