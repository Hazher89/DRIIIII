import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/i;

async function findAuthUserIdByEmail(
  admin: ReturnType<typeof createClient>,
  emailNorm: string,
): Promise<string | null> {
  const want = emailNorm.toLowerCase();
  const perPage = 1000;
  for (let page = 1; page <= 50; page++) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage });
    if (error) throw error;
    const users = data?.users ?? [];
    const hit = users.find((u) => (u.email ?? "").toLowerCase() === want);
    if (hit?.id) return hit.id;
    if (users.length < perPage) break;
  }
  return null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

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
    const profileId = String(body.profile_id ?? "").trim();
    const newEmail = String(body.new_email ?? "").trim().toLowerCase();

    if (!profileId || !newEmail) {
      return new Response(JSON.stringify({ error: "profile_id og new_email er påkrevd" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (!EMAIL_RE.test(newEmail)) {
      return new Response(JSON.stringify({ error: "Ugyldig e-postadresse" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: requester, error: reqErr } = await admin
      .from("profiles")
      .select("id, role, company_id")
      .eq("id", userData.user.id)
      .single();

    if (reqErr || !requester) {
      return new Response(JSON.stringify({ error: "Fant ikke profil" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (requester.role !== "superadmin") {
      return new Response(JSON.stringify({ error: "Kun superadmin kan endre ansatt-e-post" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: target, error: targetErr } = await admin
      .from("profiles")
      .select("id, email, role, company_id, partner_id")
      .eq("id", profileId)
      .single();

    if (targetErr || !target) {
      return new Response(JSON.stringify({ error: "Ansatt ikke funnet" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (target.partner_id != null || target.role === "samarbeidspartner") {
      return new Response(
        JSON.stringify({ error: "Bruk partner-portalen for å endre e-post på samarbeidspartnere" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const oldEmail = String(target.email ?? "").trim().toLowerCase();
    if (oldEmail === newEmail) {
      return new Response(JSON.stringify({ ok: true, email: newEmail, unchanged: true }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const existingAuthId = await findAuthUserIdByEmail(admin, newEmail);
    if (existingAuthId && existingAuthId !== profileId) {
      return new Response(
        JSON.stringify({ error: "E-posten er allerede i bruk av en annen bruker" }),
        { status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const { data: emailConflict } = await admin
      .from("profiles")
      .select("id")
      .ilike("email", newEmail)
      .neq("id", profileId)
      .maybeSingle();

    if (emailConflict?.id) {
      return new Response(
        JSON.stringify({ error: "E-posten er allerede registrert på en annen ansatt" }),
        { status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const { data: elaConflict } = await admin
      .from("employee_login_accounts")
      .select("id, profile_id")
      .ilike("login_email", newEmail)
      .maybeSingle();

    if (elaConflict?.profile_id && elaConflict.profile_id !== profileId) {
      return new Response(
        JSON.stringify({ error: "E-posten er allerede knyttet til et annet ansattnummer" }),
        { status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const { error: authUpdateErr } = await admin.auth.admin.updateUserById(profileId, {
      email: newEmail,
      email_confirm: true,
    });

    if (authUpdateErr) {
      return new Response(JSON.stringify({ error: authUpdateErr.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { error: profErr } = await admin
      .from("profiles")
      .update({ email: newEmail, updated_at: new Date().toISOString() })
      .eq("id", profileId);

    if (profErr) throw profErr;

    const { data: elaRows } = await admin
      .from("employee_login_accounts")
      .select("id")
      .eq("profile_id", profileId);

    if (elaRows && elaRows.length > 0) {
      const { error: elaErr } = await admin
        .from("employee_login_accounts")
        .update({ login_email: newEmail, updated_at: new Date().toISOString() })
        .eq("profile_id", profileId);
      if (elaErr) throw elaErr;
    }

    return new Response(
      JSON.stringify({
        ok: true,
        email: newEmail,
        previous_email: oldEmail,
        employee_login_updated: (elaRows?.length ?? 0) > 0,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: e instanceof Error ? e.message : String(e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
