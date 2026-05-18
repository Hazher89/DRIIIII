import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceKey);

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await req.json();
    const {
      partner_id,
      company_id,
      partner_vehicle_id,
      username,
      login_email,
      phone,
      password,
      delete_account,
    } = body;

    if (!partner_id || !company_id || !username || !login_email) {
      return new Response(JSON.stringify({ error: "Missing fields" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const email = String(login_email).trim().toLowerCase();
    const user = String(username).trim().toLowerCase();

    if (partner_vehicle_id && phone) {
      await admin.from("partner_vehicles").update({ phone }).eq("id", partner_vehicle_id);
    }

    if (delete_account) {
      await admin
        .from("partner_portal_accounts")
        .update({ is_active: false })
        .eq("partner_vehicle_id", partner_vehicle_id);
      return new Response(JSON.stringify({ ok: true, deleted: true }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    let profileId: string | null = null;

    if (password && String(password).length >= 6) {
      const { data: created, error: createErr } = await admin.auth.admin.createUser({
        email,
        password: String(password),
        email_confirm: true,
      });
      if (createErr && !createErr.message.includes("already")) {
        const { data: listed } = await admin.auth.admin.listUsers();
        const existing = listed?.users?.find((u) => u.email?.toLowerCase() === email);
        if (existing) {
          await admin.auth.admin.updateUserById(existing.id, { password: String(password) });
          profileId = existing.id;
        } else {
          throw createErr;
        }
      } else if (created?.user) {
        profileId = created.user.id;
        await admin.from("profiles").upsert({
          id: profileId,
          email,
          full_name: user,
          role: "samarbeidspartner",
          company_id,
          partner_id,
          partner_vehicle_id: partner_vehicle_id ?? null,
          phone: phone ?? null,
          is_onboarded: true,
          is_approved: true,
          is_active: true,
        });
      }
    }

    const { data: existing } = await admin
      .from("partner_portal_accounts")
      .select("id")
      .eq("partner_vehicle_id", partner_vehicle_id)
      .maybeSingle();

    const row = {
      partner_id,
      company_id,
      partner_vehicle_id: partner_vehicle_id ?? null,
      username: user,
      login_email: email,
      phone: phone ?? null,
      profile_id: profileId,
      is_active: true,
    };

    if (existing?.id) {
      await admin.from("partner_portal_accounts").update(row).eq("id", existing.id);
    } else {
      await admin.from("partner_portal_accounts").insert(row);
    }

    return new Response(JSON.stringify({ ok: true, login_email: email }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
