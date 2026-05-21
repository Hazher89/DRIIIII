import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const AUTH_BASE = "https://auth.tidsbanken.net/api";
const MIN_BASE = "https://min.tidsbanken.net";
const LIST_URL = `${MIN_BASE}/api/planlegging/ansattpanel/ansattliste`;

type PresenceRow = {
  employee_number: string;
  first_name: string;
  last_name: string;
  status: string;
  status_label: string;
  department_code: string | null;
  since_time: string | null;
  planned_from: string | null;
  planned_to: string | null;
  raw: Record<string, unknown>;
};

type AnsattListeItem = {
  Id: number;
  Fornavn?: string;
  Etternavn?: string;
  Innstemplet?: boolean;
  AvdelingId?: string;
  AvdelingNavn?: string;
  Aktiv?: boolean;
  Sluttet?: boolean;
};

type TimelineItem = {
  FraKlokken?: string;
  ArbeidsTypeNavn?: string;
  AvdelingNavn?: string;
};

type AuthSettings = {
  FirmaId?: number;
  UserId?: number;
  FirmaNavn?: string;
};

type LoginProbe = {
  needs_firma: boolean;
  needs_ansatt: boolean;
  has_firma_session: boolean;
  has_user_session: boolean;
};

/** Cookie-jar som håndterer flere Set-Cookie (Deno/Edge). */
class CookieJar {
  private jar = new Map<string, string>();

  ingestOne(setCookie: string) {
    const first = setCookie.split(";")[0]?.trim();
    if (!first?.includes("=")) return;
    const eq = first.indexOf("=");
    const name = first.slice(0, eq).trim();
    const value = first.slice(eq + 1).trim();
    if (name) this.jar.set(name, value);
  }

  ingestResponse(res: Response) {
    const cookies = res.headers.getSetCookie?.() ?? [];
    if (cookies.length > 0) {
      for (const c of cookies) this.ingestOne(c);
      return;
    }
    const single = res.headers.get("set-cookie");
    if (single) this.ingestOne(single);
  }

  has(name: string): boolean {
    return this.jar.has(name);
  }

  header(): string {
    return [...this.jar.entries()].map(([k, v]) => `${k}=${v}`).join("; ");
  }
}

function browserHeaders(extra: Record<string, string> = {}): HeadersInit {
  return {
    Accept: "application/json, text/plain, */*",
    "X-Requested-With": "XMLHttpRequest",
    "User-Agent": "Mozilla/5.0 (compatible; DriftPro-Tidsbanken-Sync/1.0)",
    Origin: "https://auth.tidsbanken.net",
    Referer: "https://auth.tidsbanken.net/",
    ...extra,
  };
}

async function tbFetch(
  url: string,
  jar: CookieJar,
  init: RequestInit = {},
): Promise<Response> {
  const headers = new Headers(browserHeaders());
  const extra = new Headers(init.headers);
  extra.forEach((v, k) => headers.set(k, v));
  const cookie = jar.header();
  if (cookie) headers.set("Cookie", cookie);

  const res = await fetch(url, {
    ...init,
    headers,
    redirect: "follow",
  });
  jar.ingestResponse(res);
  return res;
}

function isHtmlResponse(text: string, contentType: string): boolean {
  const ct = contentType.toLowerCase();
  if (ct.includes("text/html")) return true;
  const t = text.trim().toLowerCase();
  return t.startsWith("<!doctype") || t.startsWith("<html");
}

async function parseJsonList(res: Response): Promise<AnsattListeItem[] | null> {
  const text = await res.text();
  const ct = res.headers.get("content-type") ?? "";
  if (isHtmlResponse(text, ct)) return null;
  try {
    const data = JSON.parse(text) as unknown;
    if (!Array.isArray(data)) return null;
    return data as AnsattListeItem[];
  } catch {
    return null;
  }
}

async function probeAuthSettings(jar: CookieJar): Promise<AuthSettings | null> {
  const res = await tbFetch(`${AUTH_BASE}/GenerateAuthSettingsIfLoggedIn`, jar, {
    method: "GET",
  });
  if (!res.ok) return null;
  const text = await res.text();
  if (isHtmlResponse(text, res.headers.get("content-type") ?? "")) return null;
  try {
    return JSON.parse(text) as AuthSettings;
  } catch {
    return null;
  }
}

async function probeLoginNeeds(jar: CookieJar): Promise<LoginProbe> {
  const settings = await probeAuthSettings(jar);
  const hasFirma = jar.has("TBSignIn") || jar.has("TBSignInToken");
  const hasUser = (settings?.UserId ?? 0) > 0;

  // Prøv ansattliste uten ny innlogging
  const listRes = await tbFetch(LIST_URL, jar, {
    method: "GET",
    headers: {
      Accept: "application/json",
      Origin: MIN_BASE,
      Referer: `${MIN_BASE}/ansoversikt.asp`,
    },
  });
  const list = listRes.ok ? await parseJsonList(listRes) : null;
  if (list && list.length > 0) {
    return {
      needs_firma: false,
      needs_ansatt: false,
      has_firma_session: hasFirma,
      has_user_session: hasUser,
    };
  }

  return {
    needs_firma: !hasFirma,
    needs_ansatt: !hasUser,
    has_firma_session: hasFirma,
    has_user_session: hasUser,
  };
}

async function loginFirma(jar: CookieJar, firmaId: string, firmaPass: string): Promise<void> {
  const res = await tbFetch(
    `${AUTH_BASE}/Authorize/Firma?navn=${encodeURIComponent(firmaId)}&passord=${encodeURIComponent(firmaPass)}`,
    jar,
    { method: "GET" },
  );
  if (!res.ok) {
    throw new Error(`Firma-innlogging feilet (HTTP ${res.status})`);
  }
  const body = await res.text();
  if (isHtmlResponse(body, res.headers.get("content-type") ?? "")) {
    throw new Error("Firma-innlogging returnerte login-side (sjekk Firma-ID/passord)");
  }
}

async function loginAnsatt(jar: CookieJar, ansattId: string, pin: string): Promise<void> {
  const res = await tbFetch(
    `${AUTH_BASE}/Authorize/AnsattIdOgPin?ansattId=${encodeURIComponent(ansattId)}&pin=${encodeURIComponent(pin)}`,
    jar,
    { method: "GET" },
  );
  if (!res.ok) {
    throw new Error(`Ansatt-innlogging feilet (HTTP ${res.status})`);
  }
  const body = await res.text();
  if (isHtmlResponse(body, res.headers.get("content-type") ?? "")) {
    throw new Error("Ansatt-innlogging returnerte login-side (sjekk ansattnr/PIN)");
  }
}

/** Smart innlogging: leser hva Tidsbanken trenger, logger inn i riktig rekkefølge. */
async function smartLogin(jar: CookieJar): Promise<string[]> {
  const firmaId = Deno.env.get("TIDSBANKEN_FIRMA_ID")?.trim();
  const firmaPass = Deno.env.get("TIDSBANKEN_FIRMA_PASSWORD")?.trim();
  const ansattId = Deno.env.get("TIDSBANKEN_ANSATT_ID")?.trim();
  const ansattPin = Deno.env.get("TIDSBANKEN_ANSATT_PIN")?.trim();

  if (!firmaId || !firmaPass || !ansattId || !ansattPin) {
    throw new Error(
      "Mangler Tidsbanken Secrets (TIDSBANKEN_FIRMA_ID, FIRMA_PASSWORD, ANSATT_ID, ANSATT_PIN).",
    );
  }

  const steps: string[] = [];

  let probe = await probeLoginNeeds(jar);
  steps.push(
    `probe:firma=${probe.has_firma_session},user=${probe.has_user_session},need_firma=${probe.needs_firma},need_ansatt=${probe.needs_ansatt}`,
  );

  if (!probe.needs_firma && !probe.needs_ansatt) {
    steps.push("allerede_innlogget");
    return steps;
  }

  // Tidsbanken krever som regel firma først, deretter ansatt/PIN
  if (probe.needs_firma || !jar.has("TBSignInToken")) {
    await loginFirma(jar, firmaId, firmaPass);
    steps.push("firma_ok");
    probe = await probeLoginNeeds(jar);
    steps.push(`etter_firma:user=${probe.has_user_session}`);
  }

  if (probe.needs_ansatt || !probe.has_user_session) {
    await loginAnsatt(jar, ansattId, ansattPin);
    steps.push("ansatt_ok");
  }

  // Varm opp ansattsiden (samme som nettleser)
  await tbFetch(`${MIN_BASE}/ansoversikt.asp`, jar, {
    method: "GET",
    headers: { Accept: "text/html", Referer: `${MIN_BASE}/` },
  });
  steps.push("ansoversikt_warmup");

  const settings = await probeAuthSettings(jar);
  if (!settings?.UserId) {
    // Siste forsøk: full login på nytt
    await loginFirma(jar, firmaId, firmaPass);
    await loginAnsatt(jar, ansattId, ansattPin);
    steps.push("full_relogin");
  }

  return steps;
}

async function fetchEmployeeList(jar: CookieJar): Promise<AnsattListeItem[]> {
  const res = await tbFetch(LIST_URL, jar, {
    method: "GET",
    headers: {
      Accept: "application/json",
      Origin: MIN_BASE,
      Referer: `${MIN_BASE}/ansoversikt.asp`,
    },
  });

  const text = await res.text();
  const ct = res.headers.get("content-type") ?? "";
  if (isHtmlResponse(text, ct)) {
    throw new Error(
      `Ansattliste returnerte login-side (HTTP ${res.status}). Tidsbanken-session mangler.`,
    );
  }
  try {
    const data = JSON.parse(text) as unknown;
    if (!Array.isArray(data)) {
      throw new Error("Ansattliste er ikke en JSON-liste");
    }
    if (data.length === 0) {
      throw new Error("Ansattliste er tom — innlogging kan ha feilet");
    }
    return data as AnsattListeItem[];
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    throw new Error(`Kunne ikke lese ansattliste: ${msg}. Snutt: ${text.slice(0, 80)}`);
  }
}

function formatSince(iso?: string): string | null {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  return `${d.getHours().toString().padStart(2, "0")}:${d.getMinutes().toString().padStart(2, "0")}`;
}

async function fetchTimeline(
  jar: CookieJar,
  ansattId: number,
): Promise<TimelineItem | null> {
  const url =
    `${MIN_BASE}/api/timelinje/TimelinjeInnstemplet/ForAnsattpanel/${ansattId}`;
  const res = await tbFetch(url, jar, {
    method: "GET",
    headers: {
      Accept: "application/json",
      Origin: MIN_BASE,
      Referer: `${MIN_BASE}/ansoversikt.asp`,
    },
  });
  if (!res.ok) return null;
  const text = await res.text();
  if (isHtmlResponse(text, res.headers.get("content-type") ?? "")) return null;
  try {
    const arr = JSON.parse(text) as TimelineItem[];
    return arr?.[0] ?? null;
  } catch {
    return null;
  }
}

/** Noen sesjoner har Innstemplet=false men aktiv tidslinje — sjekk begge. */
async function isEmployeeClockedIn(
  jar: CookieJar,
  a: AnsattListeItem,
): Promise<{ inne: boolean; tl: TimelineItem | null }> {
  if (a.Innstemplet === true) {
    const tl = await fetchTimeline(jar, a.Id);
    return { inne: true, tl };
  }
  const tl = await fetchTimeline(jar, a.Id);
  if (tl?.FraKlokken) {
    const started = new Date(tl.FraKlokken);
    const today = new Date();
    if (
      started.getFullYear() === today.getFullYear() &&
      started.getMonth() === today.getMonth() &&
      started.getDate() === today.getDate()
    ) {
      return { inne: true, tl };
    }
  }
  return { inne: false, tl: null };
}

async function loadPresenceFromWeb(
  jar: CookieJar,
): Promise<{ rows: PresenceRow[]; list: AnsattListeItem[] }> {
  const list = await fetchEmployeeList(jar);
  const rows: PresenceRow[] = [];

  for (const a of list) {
    if (a.Sluttet === true) continue;
    const nr = String(a.Id);
    const first = (a.Fornavn ?? "").trim();
    const last = (a.Etternavn ?? "").trim();
    const dept = a.AvdelingNavn ?? a.AvdelingId ?? null;

    const { inne, tl } = await isEmployeeClockedIn(jar, a);

    if (inne) {
      const since = formatSince(tl?.FraKlokken);
      const role = tl?.ArbeidsTypeNavn?.trim() ?? "";
      const label = role && since
        ? `Inne : ${role} siden ${since}`
        : role
        ? `Inne : ${role}`
        : since
        ? `Inne siden ${since}`
        : "Inne";
      rows.push({
        employee_number: nr,
        first_name: first,
        last_name: last,
        status: "inne",
        status_label: label,
        department_code: dept,
        since_time: since,
        planned_from: null,
        planned_to: null,
        raw: { ...a, timeline: tl, innstemplet_flag: a.Innstemplet },
      });
    } else {
      rows.push({
        employee_number: nr,
        first_name: first,
        last_name: last,
        status: "ingen",
        status_label: "ingen registrering",
        department_code: dept,
        since_time: null,
        planned_from: null,
        planned_to: null,
        raw: a as unknown as Record<string, unknown>,
      });
    }
  }

  return { rows, list };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const authHeader = req.headers.get("Authorization") ?? "";

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const admin = createClient(supabaseUrl, serviceKey);

    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData?.user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: profile, error: profErr } = await admin
      .from("profiles")
      .select("company_id, role")
      .eq("id", userData.user.id)
      .maybeSingle();

    if (profErr || !profile?.company_id) {
      return new Response(JSON.stringify({ error: "Fant ikke bedrift" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const companyId = profile.company_id as string;
    const role = (profile.role as string | null)?.toLowerCase() ?? "";

    const { data: company, error: compErr } = await admin
      .from("companies")
      .select("tidsbanken_enabled")
      .eq("id", companyId)
      .maybeSingle();

    if (compErr) throw compErr;
    if (!company?.tidsbanken_enabled && role !== "superadmin") {
      return new Response(
        JSON.stringify({ error: "Tidsbanken er ikke aktivert for bedriften" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const jar = new CookieJar();
    const loginSteps = await smartLogin(jar);
    const { rows, list } = await loadPresenceFromWeb(jar);

    const now = new Date().toISOString();
    const clockedIn = rows.filter((r) => r.status === "inne").length;
    const innstempletFlags = list.filter((a) => a.Innstemplet === true).length;

    await admin.from("tidsbanken_presence").delete().eq("company_id", companyId);

    if (rows.length > 0) {
      const insertRows = rows.map((r) => ({
        company_id: companyId,
        employee_number: r.employee_number,
        first_name: r.first_name,
        last_name: r.last_name,
        status: r.status,
        status_label: r.status_label,
        department_code: r.department_code,
        since_time: r.since_time,
        planned_from: r.planned_from,
        planned_to: r.planned_to,
        raw: r.raw,
        synced_at: now,
      }));
      const { error: insErr } = await admin.from("tidsbanken_presence").insert(insertRows);
      if (insErr) throw insErr;
    }

    await admin.from("tidsbanken_sync_state").upsert({
      company_id: companyId,
      last_sync_at: now,
      clocked_in_count: clockedIn,
      total_count: rows.length,
      last_error: clockedIn === 0 && rows.length > 0
        ? `Ingen innstemplt (API flag: ${innstempletFlags}/${list.length}). Sjekk login.`
        : null,
      updated_at: now,
    });

    return new Response(
      JSON.stringify({
        ok: true,
        source: "web",
        synced_at: now,
        total: rows.length,
        clocked_in: clockedIn,
        innstemplet_flags: innstempletFlags,
        login_steps: loginSteps,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return new Response(JSON.stringify({ error: msg }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
