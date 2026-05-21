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

    if (!req.headers.get("Authorization")) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: rows, error: listErr } = await admin
      .from("employee_login_accounts")
      .select("*")
      .is("profile_id", null)
      .eq("is_active", true);

    if (listErr) {
      return new Response(JSON.stringify({ error: listErr.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    let created = 0;
    let updated = 0;
    let skipped = 0;
    const errors: string[] = [];

    for (const row of rows ?? []) {
      const email = String(row.login_email).toLowerCase();
      const fullName = `${row.first_name} ${row.last_name}`.trim();
      const address = [row.address_line, row.postal_code, row.city]
        .filter(Boolean)
        .join(", ");
      const phone = row.phone ? normalizePhoneNo(String(row.phone)) : null;

      try {
        let userId = await findAuthUserIdByEmail(admin, email);
        if (!userId) {
          const { data: createdUser, error: createErr } = await admin.auth.admin.createUser({
            email,
            password: DEFAULT_PASSWORD,
            email_confirm: true,
            user_metadata: {
              employee_provision: true,
              company_id: row.company_id,
              department_id: row.department_id,
              employee_number: row.employee_number,
              phone: phone ?? row.phone,
              full_name: fullName,
              address,
            },
          });
          if (createErr) throw createErr;
          userId = createdUser.user?.id ?? null;
          if (userId) created++;
        } else {
          const { error: pwErr } = await admin.auth.admin.updateUserById(userId, {
            password: DEFAULT_PASSWORD,
            email_confirm: true,
            user_metadata: {
              employee_provision: true,
              company_id: row.company_id,
              department_id: row.department_id,
              employee_number: row.employee_number,
              phone: phone ?? row.phone,
              full_name: fullName,
              address,
            },
          });
          if (pwErr) throw pwErr;
          updated++;
        }

        if (!userId) {
          skipped++;
          continue;
        }

        await admin.from("employee_login_accounts").update({
          profile_id: userId,
          updated_at: new Date().toISOString(),
        }).eq("id", row.id);
      } catch (e) {
        errors.push(`${row.employee_number}: ${e instanceof Error ? e.message : String(e)}`);
      }
    }

    return new Response(
      JSON.stringify({
        ok: true,
        default_password: DEFAULT_PASSWORD,
        total_pending: rows?.length ?? 0,
        created,
        updated,
        skipped,
        errors,
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
