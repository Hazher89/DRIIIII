import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function randomPassword(len = 10): string {
  const chars = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789";
  let out = "";
  const arr = new Uint8Array(len);
  crypto.getRandomValues(arr);
  for (let i = 0; i < len; i++) out += chars[arr[i] % chars.length];
  return out;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceKey);

    if (!req.headers.get("Authorization")) {
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
      account_kind = "driver",
      delete_account,
      send_credentials_sms = true,
      regenerate_password = false,
    } = body;

    const kind = account_kind === "owner" ? "owner" : "driver";
    const isOwner = kind === "owner";

    if (!partner_id || !company_id) {
      return new Response(JSON.stringify({ error: "Missing partner_id or company_id" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (delete_account) {
      let q = admin.from("partner_portal_accounts").update({ is_active: false }).eq("partner_id", partner_id);
      if (isOwner) {
        q = q.eq("account_kind", "owner");
      } else if (partner_vehicle_id) {
        q = q.eq("partner_vehicle_id", partner_vehicle_id);
      }
      await q;
      return new Response(JSON.stringify({ ok: true, deleted: true }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (!phone || String(phone).trim().length < 8) {
      return new Response(JSON.stringify({ error: "Telefonnummer påkrevd (min 8 siffer)" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const normalizedPhone = String(phone).trim();
    const user = String(username ?? "").trim().toLowerCase();
    if (!user) {
      return new Response(JSON.stringify({ error: "username required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const cidShort = String(company_id).replace(/-/g, "").slice(0, 8);
    const email =
      login_email && String(login_email).includes("@")
        ? String(login_email).trim().toLowerCase()
        : `${user}@${isOwner ? "eier" : "mavi"}.${cidShort}.portal`;

    if (!isOwner && partner_vehicle_id) {
      await admin.from("partner_vehicles").update({ phone: normalizedPhone }).eq("id", partner_vehicle_id);
    }

    let existingQuery = admin
      .from("partner_portal_accounts")
      .select("id, profile_id, login_email")
      .eq("partner_id", partner_id)
      .eq("is_active", true);

    if (isOwner) {
      existingQuery = existingQuery.eq("account_kind", "owner");
    } else {
      existingQuery = existingQuery.eq("partner_vehicle_id", partner_vehicle_id);
    }

    const { data: existing } = await existingQuery.maybeSingle();

    let pw = password && String(password).length >= 6 ? String(password) : randomPassword(10);
    if (existing && !regenerate_password && password && String(password).length >= 6) {
      pw = String(password);
    } else if (existing && !regenerate_password && (!password || String(password).length < 6)) {
      pw = randomPassword(10);
    }

    let profileId: string | null = existing?.profile_id ?? null;
    const authEmail = existing?.login_email ?? email;

    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email: authEmail,
      password: pw,
      email_confirm: true,
    });

    if (createErr) {
      const { data: listed } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
      const found = listed?.users?.find((u) => u.email?.toLowerCase() === authEmail.toLowerCase());
      if (found) {
        await admin.auth.admin.updateUserById(found.id, { password: pw });
        profileId = found.id;
      } else {
        throw createErr;
      }
    } else if (created?.user) {
      profileId = created.user.id;
    }

    if (profileId) {
      await admin.from("profiles").upsert({
        id: profileId,
        email: authEmail,
        full_name: user,
        role: "samarbeidspartner",
        company_id,
        partner_id,
        partner_vehicle_id: isOwner ? null : partner_vehicle_id,
        phone: normalizedPhone,
        is_onboarded: true,
        is_approved: true,
        is_active: true,
      });
    }

    const row = {
      partner_id,
      company_id,
      partner_vehicle_id: isOwner ? null : partner_vehicle_id,
      username: user,
      login_email: authEmail,
      phone: normalizedPhone,
      profile_id: profileId,
      account_kind: kind,
      is_active: true,
    };

    if (existing?.id) {
      await admin.from("partner_portal_accounts").update(row).eq("id", existing.id);
    } else {
      await admin.from("partner_portal_accounts").insert(row);
    }

    let smsSent = false;
    if (send_credentials_sms) {
      const { error: smsErr } = await admin.rpc("notify_partner_portal_credentials_sms", {
        p_company_id: company_id,
        p_phone: normalizedPhone,
        p_username: user,
        p_password: pw,
        p_is_owner: isOwner,
      });
      smsSent = !smsErr;
    }

    return new Response(
      JSON.stringify({
        ok: true,
        username: user,
        login_email: authEmail,
        password: pw,
        sms_sent: smsSent,
        account_kind: kind,
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
