import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/**
 * App Store 5.1.1(v): innlogget bruker kan slette egen konto.
 * Anonymiserer profil + login-kontoer, sletter auth-bruker.
 * HMS-/HR-historikk som lov krever kan beholdes uten personidentitet der FK tillater det.
 */
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

    const body = await req.json().catch(() => ({}));
    const confirm = String(body?.confirm ?? "").trim().toUpperCase();
    if (confirm !== "SLETT") {
      return new Response(
        JSON.stringify({ error: "Bekreft med confirm: SLETT" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const uid = userData.user.id;
    const now = new Date().toISOString();

    // Deaktiver/anonymiser login-kontoer (ansatt / partner-portal) — best effort
    try {
      await admin
        .from("employee_login_accounts")
        .update({
          is_active: false,
          login_email: `deleted_${uid}@deleted.driftpro.local`,
          phone: null,
          updated_at: now,
        })
        .eq("profile_id", uid);
    } catch (e) {
      console.warn("employee_login_accounts update", e);
    }

    try {
      await admin
        .from("partner_portal_accounts")
        .update({
          login_email: `deleted_${uid}@deleted.driftpro.local`,
          updated_at: now,
        })
        .eq("profile_id", uid);
    } catch (e) {
      console.warn("partner_portal_accounts update", e);
    }

    try {
      await admin.from("user_push_devices").delete().eq("profile_id", uid);
    } catch (_) {
      /* optional table */
    }

    // Anonymiser profil (behold rad hvis FK krever det)
    await admin
      .from("profiles")
      .update({
        email: `deleted_${uid}@deleted.driftpro.local`,
        full_name: "Slettet bruker",
        phone: null,
        avatar_url: null,
        employee_number: null,
        address: null,
        national_id_number: null,
        emergency_contact_name: null,
        emergency_contact_phone: null,
        is_active: false,
        updated_at: now,
      })
      .eq("id", uid);

    // Slett auth-bruker sist
    const { error: delErr } = await admin.auth.admin.deleteUser(uid);
    if (delErr) {
      console.error("deleteUser failed", delErr.message);
      return new Response(
        JSON.stringify({
          error: `Konto deaktivert, men auth-sletting feilet: ${delErr.message}. Kontakt support.`,
          deactivated: true,
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    return new Response(
      JSON.stringify({
        ok: true,
        message: "Kontoen er slettet.",
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
