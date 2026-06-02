import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const DEFAULT_PASSWORD = "000000";

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
    const companyId = String(body.company_id ?? "");
    const fullName = String(body.full_name ?? "").trim();
    const departmentId = body.department_id ? String(body.department_id) : null;
    const jobTitle = body.job_title ? String(body.job_title).trim() : null;
    const role = String(body.role ?? "ansatt");

    if (!companyId || !fullName) {
      return new Response(JSON.stringify({ error: "company_id og full_name er påkrevd" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: requester, error: profErr } = await admin
      .from("profiles")
      .select("id, role, company_id, department_id")
      .eq("id", userData.user.id)
      .single();

    if (profErr || !requester) {
      return new Response(JSON.stringify({ error: "Fant ikke profil" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const reqRole = requester.role as string;
    if (!["admin", "superadmin", "leder"].includes(reqRole)) {
      return new Response(JSON.stringify({ error: "Mangler tilgang" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (requester.company_id !== companyId && reqRole !== "superadmin") {
      return new Response(JSON.stringify({ error: "Feil selskap" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (reqRole === "leder") {
      if (!departmentId || departmentId !== requester.department_id) {
        return new Response(JSON.stringify({ error: "Leder kan kun legge til i egen avdeling" }), {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      if (["admin", "superadmin", "leder"].includes(role)) {
        return new Response(JSON.stringify({ error: "Leder kan kun opprette ansatte" }), {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    const base = fullName.toLowerCase().replace(/[^a-z0-9]+/g, ".");
    const email = `${base || "employee"}.${Date.now()}@internal.driftpro.no`;

    let userId = await findAuthUserIdByEmail(admin, email);
    if (!userId) {
      const { data: createdUser, error: createErr } = await admin.auth.admin.createUser({
        email,
        password: DEFAULT_PASSWORD,
        email_confirm: true,
        user_metadata: {
          employee_provision: true,
          company_id: companyId,
          department_id: departmentId,
          full_name: fullName,
          job_title: jobTitle,
          internal_org_chart: true,
        },
      });
      if (createErr) throw createErr;
      userId = createdUser.user?.id ?? null;
    }

    if (!userId) {
      return new Response(JSON.stringify({ error: "Kunne ikke opprette auth-bruker" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const accessSettings = {
      hms: true,
      fravaer: true,
      avvik: true,
      avdelinger: true,
      ansatte: true,
    };

    const { data: profile, error: upsertErr } = await admin
      .from("profiles")
      .upsert({
        id: userId,
        email,
        full_name: fullName,
        company_id: companyId,
        department_id: departmentId,
        job_title: jobTitle,
        role: role === "leder" || role === "admin" || role === "superadmin" ? role : "ansatt",
        access_settings: accessSettings,
        is_onboarded: true,
        is_approved: true,
        is_active: true,
      }, { onConflict: "id" })
      .select()
      .single();

    if (upsertErr) throw upsertErr;

    await admin.rpc("ensure_absence_quota", {
      p_user_id: userId,
      p_year: new Date().getFullYear(),
    });

    return new Response(
      JSON.stringify({
        ok: true,
        profile,
        default_password: DEFAULT_PASSWORD,
        login_email: email,
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
