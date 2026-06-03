import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { readSveveConfig, sendViaSveve } from "../_shared/sveve.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

/** GoTrue mangler stabilt «getUserByEmail»; paginer til treff eller sluttliste. */
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

function randomPassword(len = 10): string {
  const chars = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789";
  let out = "";
  const arr = new Uint8Array(len);
  crypto.getRandomValues(arr);
  for (let i = 0; i < len; i++) out += chars[arr[i] % chars.length];
  return out;
}

/** Matcher `public.normalize_phone_no` / Dart `normalizePhoneNo`. */
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

    const body = await req.json();
    const {
      partner_id,
      company_id,
      partner_vehicle_id,
      portal_account_id,
      username,
      login_email,
      phone,
      password,
      driver_name,
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
      let selectQ = admin
        .from("partner_portal_accounts")
        .select("id, profile_id, phone")
        .eq("partner_id", partner_id)
        .eq("is_active", true);
      if (portal_account_id) {
        selectQ = selectQ.eq("id", portal_account_id);
      } else if (isOwner) {
        selectQ = selectQ.eq("account_kind", "owner");
      } else if (partner_vehicle_id) {
        selectQ = selectQ.eq("partner_vehicle_id", partner_vehicle_id);
      }
      const { data: toDeactivate } = await selectQ;

      for (const acc of toDeactivate ?? []) {
        await admin
          .from("partner_portal_accounts")
          .update({ is_active: false, phone: null })
          .eq("id", acc.id);

        if (acc.phone) {
          await admin.rpc("purge_pending_sms_for_phone", {
            p_company_id: company_id,
            p_phone: acc.phone,
          });
        }
        if (acc.profile_id) {
          await admin
            .from("profiles")
            .update({
              is_active: false,
              phone: null,
              phone_normalized: null,
            })
            .eq("id", acc.profile_id);
        }
      }

      if (!isOwner && partner_vehicle_id) {
        await admin.from("partner_vehicles").update({ phone: null }).eq("id", partner_vehicle_id);
      }

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

    const normalizedPhone = normalizePhoneNo(String(phone).trim());
    if (!normalizedPhone) {
      return new Response(
        JSON.stringify({ error: "Ugyldig norsk mobilnummer (8 siffer, 4/9xxx)" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
    let user = String(username ?? "").trim().toLowerCase();
    const displayName =
      driver_name && String(driver_name).trim().length > 0
        ? String(driver_name).trim()
        : user;
    if (!user) {
      return new Response(JSON.stringify({ error: "username required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const scopeId = isOwner ? String(partner_id) : String(partner_vehicle_id ?? partner_id);
    const scopeHex = scopeId.replace(/-/g, "");
    const scopeShort = scopeHex.length >= 8 ? scopeHex.slice(0, 8) : scopeHex.padEnd(8, "0");
    const email =
      login_email && String(login_email).includes("@")
        ? String(login_email).trim().toLowerCase()
        : `${isOwner ? "o" : "d"}.${scopeShort}@portal.driftpro.no`;

    if (!isOwner && partner_vehicle_id) {
      await admin.from("partner_vehicles").update({
        phone: normalizedPhone,
        ...(driver_name && String(driver_name).trim()
          ? { driver_name: String(driver_name).trim() }
          : {}),
      }).eq("id", partner_vehicle_id);
    }

    let existingQuery = admin
      .from("partner_portal_accounts")
      .select("id, profile_id, login_email, username")
      .eq("partner_id", partner_id)
      .eq("is_active", true);

    if (portal_account_id) {
      existingQuery = existingQuery.eq("id", portal_account_id);
    } else if (isOwner) {
      existingQuery = existingQuery
        .eq("account_kind", "owner")
        .eq("phone", normalizedPhone);
    } else {
      existingQuery = existingQuery.eq("partner_vehicle_id", partner_vehicle_id);
    }

    const { data: existing } = await existingQuery.maybeSingle();

    if (existing?.username && String(existing.username).trim().length > 0) {
      user = String(existing.username).trim().toLowerCase();
    }

    let pw = password && String(password).length >= 6 ? String(password) : randomPassword(10);
    if (existing && !regenerate_password && password && String(password).length >= 6) {
      pw = String(password);
    } else if (existing && !regenerate_password && (!password || String(password).length < 6)) {
      pw = randomPassword(10);
    }

    let profileId: string | null = existing?.profile_id ?? null;
    const authEmail = (existing?.login_email ?? email).toLowerCase();

    const userMetadata: Record<string, unknown> = {
      portal_provision: true,
      company_id,
      partner_id,
      partner_vehicle_id: isOwner ? null : partner_vehicle_id ?? null,
      phone: normalizedPhone,
      full_name: displayName,
    };

    let existingAuthId = await findAuthUserIdByEmail(admin, authEmail);

    if (existingAuthId) {
      const { error: updateErr } = await admin.auth.admin.updateUserById(existingAuthId, {
        password: pw,
        email_confirm: true,
        user_metadata: userMetadata,
      });
      if (updateErr) throw updateErr;
      profileId = existingAuthId;
    } else {
      const { data: created, error: createErr } = await admin.auth.admin.createUser({
        email: authEmail,
        password: pw,
        email_confirm: true,
        user_metadata: userMetadata,
      });

      if (createErr) {
        existingAuthId = await findAuthUserIdByEmail(admin, authEmail);
        if (existingAuthId) {
          await admin.auth.admin.updateUserById(existingAuthId, {
            password: pw,
            user_metadata: userMetadata,
          });
          profileId = existingAuthId;
        } else {
          const msg = createErr.message ?? String(createErr);
          throw new Error(
            `Kunne ikke opprette Auth-bruker: ${msg}. Kjør migrasjon partner_portal_user_fix i Supabase.`,
          );
        }
      } else if (created?.user) {
        profileId = created.user.id;
      }
    }

    if (profileId) {
      const { error: profErr } = await admin.from("profiles").upsert({
        id: profileId,
        email: authEmail,
        full_name: displayName,
        role: "samarbeidspartner",
        company_id,
        partner_id,
        partner_vehicle_id: isOwner ? null : partner_vehicle_id,
        phone: normalizedPhone,
        is_onboarded: true,
        is_approved: true,
        is_active: true,
        access_settings: {},
      });
      if (profErr) {
        console.error("profiles upsert:", profErr);
        throw new Error(`Profil kunne ikke lagres: ${profErr.message}`);
      }
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
    let smsQueued = false;
    let smsError: string | null = null;
    if (send_credentials_sms) {
      const { data: smsId, error: smsErr } = await admin.rpc("notify_partner_portal_credentials_sms", {
        p_company_id: company_id,
        p_phone: normalizedPhone,
        p_username: user,
        p_password: pw,
        p_is_owner: isOwner,
      });
      if (smsErr) {
        smsError = smsErr.message;
        console.error("notify_partner_portal_credentials_sms failed:", smsErr);
      } else if (!smsId) {
        smsError = `Kunne ikke legge SMS i kø for ${normalizedPhone}`;
      } else {
        smsQueued = true;
        const { data: smsRow, error: rowErr } = await admin
          .from("sms_outbox")
          .select("id, to_phone, message, attempts")
          .eq("id", smsId)
          .maybeSingle();

        if (rowErr || !smsRow) {
          smsError = rowErr?.message ?? "Fant ikke SMS-rad etter køing";
        } else {
          const sveve = readSveveConfig();
          if ("error" in sveve) {
            smsError = sveve.error;
          } else {
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
              await admin
                .from("sms_outbox")
                .update({
                  error_message: result.error ?? "Ukjent feil",
                  attempts: (smsRow.attempts ?? 0) + 1,
                })
                .eq("id", smsRow.id);
              smsError = result.error ?? "Sveve avviste SMS";
            }
          }
        }
      }
    }

    return new Response(
      JSON.stringify({
        ok: true,
        username: user,
        login_email: authEmail,
        password: pw,
        sms_sent: smsSent,
        sms_queued: smsQueued,
        phone: normalizedPhone,
        ...(smsError ? { sms_error: smsError } : {}),
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
