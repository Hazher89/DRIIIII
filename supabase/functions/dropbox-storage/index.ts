import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

type Conn = {
  company_id: string;
  refresh_token: string;
  root_folder: string;
  access_token: string | null;
  token_expires_at: string | null;
  large_file_threshold_bytes: number;
  storage_modules?: Record<string, boolean>;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function htmlPage(title: string, body: string, status = 200) {
  return new Response(
    `<!DOCTYPE html><html><head><meta charset="utf-8"><title>${title}</title></head>
<body style="font-family:system-ui,sans-serif;padding:2rem;max-width:36rem;margin:auto">
<h2>${title}</h2>${body}</body></html>`,
    { status, headers: { "Content-Type": "text/html; charset=utf-8" } },
  );
}

const PRODUCTION_APP_URL = "https://driftpro.no";

function normalizeAppBase(raw: string | undefined | null): string {
  let base = raw?.trim() || Deno.env.get("DRIFTPRO_APP_URL")?.trim() || PRODUCTION_APP_URL;
  if (base.includes("drifpro.no")) {
    base = base.replace(/drifpro\.no/g, "driftpro.no");
  }
  return base.replace(/\/+$/, "");
}

function isLocalDevReturnUrl(raw: string): boolean {
  try {
    const host = new URL(raw).hostname.toLowerCase();
    return host === "localhost" || host === "127.0.0.1";
  } catch {
    return false;
  }
}

function isProductionReturnUrl(raw: string): boolean {
  try {
    const u = new URL(raw);
    const host = u.hostname.toLowerCase();
    return (host === "driftpro.no" || host === "www.driftpro.no") &&
      u.protocol === "https:";
  } catch {
    return false;
  }
}

/** Live: alltid driftpro.no. Kun localhost brukes under lokal utvikling. */
function resolveAppReturnUrl(returnUrl?: string): string {
  if (returnUrl && isLocalDevReturnUrl(returnUrl)) {
    return returnUrl.replace(/\/+$/, "");
  }
  if (returnUrl && isProductionReturnUrl(returnUrl)) {
    return returnUrl.replace(/\/+$/, "");
  }
  return normalizeAppBase(PRODUCTION_APP_URL);
}

function redirectToApp(query = "dropbox=connected", returnUrl?: string) {
  const base = resolveAppReturnUrl(returnUrl);
  return Response.redirect(`${base}/more/dropbox?${query}`, 302);
}

function appHomeLink(returnUrl?: string): string {
  return `${resolveAppReturnUrl(returnUrl)}/`;
}

function requireEnv(name: string): string {
  const v = Deno.env.get(name)?.trim();
  if (!v) throw new Error(`Mangler secret: ${name}`);
  return v;
}

/** App folder: bruk "/". Full Dropbox: "/DriftPro" (eller DROPBOX_ROOT_FOLDER). */
function normalizeRoot(path: string): string {
  let p = path.trim() || "/";
  if (!p.startsWith("/")) p = `/${p}`;
  const trimmed = p.replace(/\/+$/, "");
  return trimmed === "" ? "/" : trimmed;
}

async function refreshAccessToken(conn: Conn, admin: ReturnType<typeof createClient>): Promise<string> {
  const appKey = requireEnv("DROPBOX_APP_KEY");
  const appSecret = requireEnv("DROPBOX_APP_SECRET");

  if (conn.access_token && conn.token_expires_at) {
    const exp = new Date(conn.token_expires_at).getTime();
    if (exp > Date.now() + 60_000) return conn.access_token;
  }

  const basic = btoa(`${appKey}:${appSecret}`);
  const res = await fetch("https://api.dropboxapi.com/oauth2/token", {
    method: "POST",
    headers: {
      Authorization: `Basic ${basic}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: conn.refresh_token,
    }),
  });

  const text = await res.text();
  if (!res.ok) throw new Error(`Dropbox token: ${text.slice(0, 200)}`);

  const data = JSON.parse(text) as { access_token: string; expires_in?: number };
  const expiresAt = data.expires_in
    ? new Date(Date.now() + data.expires_in * 1000).toISOString()
    : null;

  await admin.from("company_dropbox_connections").update({
    access_token: data.access_token,
    token_expires_at: expiresAt,
    updated_at: new Date().toISOString(),
  }).eq("company_id", conn.company_id);

  return data.access_token;
}

async function dropboxApi(
  token: string,
  host: "api" | "content",
  path: string,
  init: RequestInit & { dropboxArg?: Record<string, unknown> } = {},
) {
  const base = host === "content"
    ? "https://content.dropboxapi.com/2"
    : "https://api.dropboxapi.com/2";
  const headers = new Headers(init.headers);
  headers.set("Authorization", `Bearer ${token}`);
  if (init.dropboxArg) {
    headers.set("Dropbox-API-Arg", JSON.stringify(init.dropboxArg));
  }
  const { dropboxArg: _, ...rest } = init;
  return fetch(`${base}${path}`, { ...rest, headers });
}

async function ensureFolder(token: string, folderPath: string) {
  const res = await dropboxApi(token, "api", "/files/create_folder_v2", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ path: folderPath, autorename: false }),
  });
  if (res.ok) return;
  const err = await res.text();
  if (err.includes("path/conflict/folder")) return;
  if (err.includes("folder/conflict")) return;
}

async function ensureFolderPath(token: string, fullPath: string) {
  const normalized = fullPath.replace(/\/+$/, "") || "/";
  const parts = normalized.split("/").filter((p) => p.length > 0);
  let current = "";
  for (const part of parts) {
    if (part === "." || part === "..") continue;
    current += `/${sanitizeSegment(part, "mappe")}`;
    await ensureFolder(token, current);
  }
}

function sanitizeSegment(raw: string, fallback = "fil"): string {
  let s = (raw ?? "").trim();
  if (!s) return fallback;
  s = s.replace(/\.\./g, "_");
  s = s.replace(/[/\\]/g, "_");
  s = s.replace(/[^a-zA-Z0-9._-]/g, "_");
  s = s.replace(/_+/g, "_");
  s = s.replace(/^\.+/, "");
  s = s.replace(/\.+$/, "");
  return s || fallback;
}

function extractSupabaseDocumentsPath(ref: string): string | null {
  const r = ref.trim();
  if (!r) return null;
  if (r.startsWith("dropbox://")) return null;
  if (r.startsWith("http://") || r.startsWith("https://")) {
    try {
      const u = new URL(r);
      const idx = u.pathname.split("/").indexOf("documents");
      if (idx >= 0) {
        return decodeURIComponent(u.pathname.split("/").slice(idx + 1).join("/"));
      }
    } catch {
      return null;
    }
    return null;
  }
  return r.replace(/^\/+/, "");
}

function storageRefCandidates(ref: string): Array<{ kind: "dropbox" | "supabase"; path: string }> {
  const seen = new Set<string>();
  const out: Array<{ kind: "dropbox" | "supabase"; path: string }> = [];
  const add = (kind: "dropbox" | "supabase", path: string) => {
    const p = path.trim();
    if (!p) return;
    const key = `${kind}:${p}`;
    if (seen.has(key)) return;
    seen.add(key);
    out.push({ kind, path: p });
  };

  const raw = ref.trim();
  if (!raw) return out;

  if (raw.startsWith("dropbox://")) {
    const p = raw.slice("dropbox://".length);
    add("dropbox", p.startsWith("/") ? p : `/${p}`);
    return out;
  }

  const supa = extractSupabaseDocumentsPath(raw);
  if (supa) add("supabase", supa);

  const noLead = raw.replace(/^\/+/, "");
  add("supabase", noLead);

  if (/^\/?company_[0-9a-f-]{36}\//i.test(raw)) {
    const dropPath = raw.startsWith("/") ? raw : `/${raw}`;
    add("dropbox", dropPath);
  }

  return out;
}

async function downloadDropboxBytes(token: string, path: string): Promise<Uint8Array | null> {
  const dlRes = await dropboxApi(token, "content", "/files/download", {
    method: "POST",
    dropboxArg: { path },
  });
  if (!dlRes.ok) return null;
  return new Uint8Array(await dlRes.arrayBuffer());
}

async function downloadSupabaseBytes(
  admin: ReturnType<typeof createClient>,
  path: string,
): Promise<Uint8Array | null> {
  const clean = path.replace(/^\/+/, "");
  const { data, error } = await admin.storage.from("documents").download(clean);
  if (error || !data) return null;
  return new Uint8Array(await data.arrayBuffer());
}

function bytesToBase64(bin: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bin.length; i += chunk) {
    binary += String.fromCharCode(...bin.subarray(i, i + chunk));
  }
  return btoa(binary);
}

function buildStoragePath(
  root: string,
  companyId: string,
  category: string,
  fileName: string,
): string {
  const safeCat = sanitizeSegment(category, "filer");
  const safeName = sanitizeSegment(fileName, "fil.pdf");
  const safeCompany = sanitizeSegment(companyId, "bedrift");
  const date = new Date().toISOString().slice(0, 10);
  return `${root}/company_${safeCompany}/${safeCat}/${date}/${Date.now()}_${safeName}`;
}

async function companyExists(
  admin: ReturnType<typeof createClient>,
  id: string,
): Promise<boolean> {
  const { data } = await admin.from("companies").select("id").eq("id", id).maybeSingle();
  return !!data?.id;
}

/** Samme rekkefølge som Flutter discoverBootstrapCompanyId / getCurrentCompanyId. */
async function resolveCompanyId(
  admin: ReturnType<typeof createClient>,
  profile: { company_id: string | null },
): Promise<string | null> {
  const tryId = async (id: string | null | undefined): Promise<string | null> => {
    const trimmed = id?.trim();
    if (!trimmed) return null;
    return (await companyExists(admin, trimmed)) ? trimmed : null;
  };

  const fromProfile = await tryId(profile.company_id);
  if (fromProfile) return fromProfile;

  try {
    const { data: rpc } = await admin.rpc("get_bootstrap_company_id");
    const fromRpc = await tryId(typeof rpc === "string" ? rpc : null);
    if (fromRpc) return fromRpc;
  } catch (_) {
    /* RPC finnes kanskje ikke */
  }

  const { data: dept } = await admin
    .from("departments")
    .select("company_id")
    .not("company_id", "is", null)
    .limit(1)
    .maybeSingle();
  const fromDept = await tryId(dept?.company_id as string | undefined);
  if (fromDept) return fromDept;

  const { data: companies } = await admin.from("companies").select("id").limit(5);
  for (const row of companies ?? []) {
    const ok = await tryId(row.id as string);
    if (ok) return ok;
  }

  return null;
}

/** Dropbox redirect — ingen Supabase JWT. */
async function handleOAuthCallback(
  req: Request,
  admin: ReturnType<typeof createClient>,
): Promise<Response> {
  const url = new URL(req.url);
  const code = url.searchParams.get("code");
  const stateRaw = url.searchParams.get("state");
  const oauthErr = url.searchParams.get("error_description") ?? url.searchParams.get("error");

  if (oauthErr) {
    return htmlPage(
      "Dropbox avbrutt",
      `<p>${oauthErr}</p><p><a href="https://driftpro.no">Tilbake til DriftPro</a></p>`,
      400,
    );
  }
  if (!code || !stateRaw) {
    return htmlPage(
      "Mangler data fra Dropbox",
      "<p>Prøv å koble på nytt fra Mer → Dropbox-lagring.</p>",
      400,
    );
  }

  let state: { company_id: string; uid: string; return_url?: string };
  try {
    state = JSON.parse(atob(stateRaw));
  } catch {
    return htmlPage("Ugyldig state", "<p>Start tilkobling på nytt fra appen.</p>", 400);
  }

  let companyId = await resolveCompanyId(admin, { company_id: state.company_id });
  if (!companyId) {
    const { data: prof } = await admin
      .from("profiles")
      .select("company_id")
      .eq("id", state.uid)
      .maybeSingle();
    companyId = await resolveCompanyId(admin, { company_id: prof?.company_id as string | null });
  }
  if (!companyId) {
    return htmlPage(
      "Fant ikke bedrift",
      "<p>Ingen bedrift i databasen. Kontakt support eller kjør bedrifts-oppsett i Supabase.</p>",
      400,
    );
  }

  try {
    const appKey = requireEnv("DROPBOX_APP_KEY");
    const appSecret = requireEnv("DROPBOX_APP_SECRET");
    const redirectUri = requireEnv("DROPBOX_REDIRECT_URI");
    const basic = btoa(`${appKey}:${appSecret}`);

    const tokenRes = await fetch("https://api.dropboxapi.com/oauth2/token", {
      method: "POST",
      headers: {
        Authorization: `Basic ${basic}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        code,
        grant_type: "authorization_code",
        redirect_uri: redirectUri,
      }),
    });

    const tokenText = await tokenRes.text();
    if (!tokenRes.ok) {
      console.error("dropbox token exchange failed", tokenText);
      return htmlPage(
        "Kunne ikke fullføre Dropbox-tilkobling",
        `<p>Sjekk at <code>DROPBOX_REDIRECT_URI</code> i Supabase er identisk med Redirect URI i Dropbox-appen.</p>
<pre style="background:#f4f4f4;padding:12px;overflow:auto;font-size:12px">${tokenText.slice(0, 500)}</pre>`,
        500,
      );
    }

    const tokens = JSON.parse(tokenText) as {
      access_token: string;
      refresh_token?: string;
      expires_in?: number;
      account_id?: string;
    };

    let refreshToken = tokens.refresh_token?.trim() ?? "";
    if (!refreshToken) {
      const { data: existing } = await admin
        .from("company_dropbox_connections")
        .select("refresh_token")
        .eq("company_id", companyId)
        .maybeSingle();
      refreshToken = (existing?.refresh_token as string | undefined)?.trim() ?? "";
    }
    if (!refreshToken) {
      return htmlPage(
        "Mangler refresh token",
        "<p>I Dropbox: fjern app-tilgang under Account → Connected apps, og koble DriftPro på nytt.</p>",
        500,
      );
    }

    let accountEmail: string | null = null;
    const accRes = await fetch("https://api.dropboxapi.com/2/users/get_current_account", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${tokens.access_token}`,
        "Content-Type": "application/json",
      },
      body: "null",
    });
    if (accRes.ok) {
      const acc = await accRes.json() as { email?: string };
      accountEmail = acc.email ?? null;
    }

    const root = normalizeRoot(Deno.env.get("DROPBOX_ROOT_FOLDER") ?? "/");
    const companyFolder = root === "/"
      ? `/company_${companyId}`
      : `${root}/company_${companyId}`;
    if (root !== "/") await ensureFolder(tokens.access_token, root);
    await ensureFolder(tokens.access_token, companyFolder);

    const expiresAt = tokens.expires_in
      ? new Date(Date.now() + tokens.expires_in * 1000).toISOString()
      : null;

    const { error: upErr } = await admin.from("company_dropbox_connections").upsert({
      company_id: companyId,
      dropbox_account_id: tokens.account_id ?? null,
      account_email: accountEmail,
      root_folder: root,
      refresh_token: refreshToken,
      access_token: tokens.access_token,
      token_expires_at: expiresAt,
      connected_by: state.uid,
      connected_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    });
    if (upErr) {
      console.error("dropbox upsert failed", upErr);
      return htmlPage("Databasefeil", `<p>${upErr.message}</p>`, 500);
    }

    return redirectToApp("dropbox=connected", state.return_url);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("oauth_callback", msg);
    return htmlPage("Feil", `<p>${msg}</p>`, 500);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const url = new URL(req.url);
    const action = url.searchParams.get("action") ?? "";

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const admin = createClient(supabaseUrl, serviceKey);

    // Dropbox redirect uten JWT — må være først
    if (action === "oauth_callback" && req.method === "GET") {
      return await handleOAuthCallback(req, admin);
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: userData } = await userClient.auth.getUser();
    if (!userData?.user) return json({ error: "Unauthorized" }, 401);

    const { data: profile } = await admin
      .from("profiles")
      .select("company_id, role")
      .eq("id", userData.user.id)
      .maybeSingle();

    if (!profile) return json({ error: "Fant ikke profil" }, 400);

    const companyId = await resolveCompanyId(admin, profile);
    if (!companyId) {
      return json({ error: "Fant ikke gyldig bedrift på brukeren" }, 400);
    }

    const role = (profile.role as string | null)?.toLowerCase() ?? "";

    if (action === "auth_url" && req.method === "GET") {
      if (role !== "admin" && role !== "superadmin") {
        return json({ error: "Kun administrator" }, 403);
      }
      const appKey = requireEnv("DROPBOX_APP_KEY");
      const redirectUri = requireEnv("DROPBOX_REDIRECT_URI");
      const returnUrl = url.searchParams.get("return_url")?.trim();
      const resolvedReturn = returnUrl
        ? resolveAppReturnUrl(returnUrl)
        : resolveAppReturnUrl();
      const state = btoa(JSON.stringify({
        company_id: companyId,
        uid: userData.user.id,
        return_url: resolvedReturn,
      }));
      const authUrl = new URL("https://www.dropbox.com/oauth2/authorize");
      authUrl.searchParams.set("client_id", appKey);
      authUrl.searchParams.set("response_type", "code");
      authUrl.searchParams.set("redirect_uri", redirectUri);
      authUrl.searchParams.set("token_access_type", "offline");
      authUrl.searchParams.set("state", state);
      return json({ auth_url: authUrl.toString() });
    }

    if (action === "resolve_file_bytes" && req.method === "POST") {
      const { ref } = await req.json() as { ref?: string };
      if (!ref?.trim()) return json({ error: "ref er påkrevd" }, 400);

      const { data: connRow } = await admin
        .from("company_dropbox_connections")
        .select("*")
        .eq("company_id", companyId)
        .maybeSingle();

      const candidates = storageRefCandidates(ref);
      let lastError = "Fant ikke fil";

      for (const c of candidates) {
        if (c.kind === "dropbox" && connRow) {
          try {
            const token = await refreshAccessToken(connRow as Conn, admin);
            const bytes = await downloadDropboxBytes(token, c.path);
            if (bytes && bytes.length > 0) {
              return json({
                ok: true,
                provider: "dropbox",
                path: c.path,
                bytes_base64: bytesToBase64(bytes),
                size: bytes.length,
              });
            }
          } catch (e) {
            lastError = e instanceof Error ? e.message : String(e);
          }
        }
        if (c.kind === "supabase") {
          try {
            const bytes = await downloadSupabaseBytes(admin, c.path);
            if (bytes && bytes.length > 0) {
              return json({
                ok: true,
                provider: "supabase",
                path: c.path,
                bytes_base64: bytesToBase64(bytes),
                size: bytes.length,
              });
            }
          } catch (e) {
            lastError = e instanceof Error ? e.message : String(e);
          }
        }
      }

      return json({ ok: false, error: lastError.slice(0, 300) }, 404);
    }

    const { data: connRow, error: connErr } = await admin
      .from("company_dropbox_connections")
      .select("*")
      .eq("company_id", companyId)
      .maybeSingle();

    if (connErr) throw connErr;
    if (!connRow) {
      return json({
        error: "Dropbox er ikke koblet. Administrator må koble under Innstillinger → Dropbox.",
      }, 400);
    }

    const conn = connRow as Conn;
    const token = await refreshAccessToken(conn, admin);
    const root = normalizeRoot(conn.root_folder);

    if (action === "upload" && req.method === "POST") {
      const body = await req.json() as {
        file_name: string;
        category: string;
        bytes_base64: string;
        mime_type?: string;
      };

      if (!body.file_name || !body.category || !body.bytes_base64) {
        return json({ error: "file_name, category og bytes_base64 er påkrevd" }, 400);
      }

      const bytes = Uint8Array.from(atob(body.bytes_base64), (c) => c.charCodeAt(0));
      const dropboxPath = buildStoragePath(root, companyId, body.category, body.file_name);
      const folder = dropboxPath.substring(0, dropboxPath.lastIndexOf("/"));
      await ensureFolderPath(token, folder);

      const upRes = await dropboxApi(token, "content", "/files/upload", {
        method: "POST",
        headers: { "Content-Type": "application/octet-stream" },
        dropboxArg: { path: dropboxPath, mode: "add", autorename: true },
        body: bytes,
      });

      const upText = await upRes.text();
      if (!upRes.ok) return json({ error: upText.slice(0, 300) }, 500);

      const meta = JSON.parse(upText) as { path_display?: string; id?: string };

      const linkRes = await dropboxApi(token, "api", "/files/get_temporary_link", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ path: meta.path_display ?? dropboxPath }),
      });
      const linkJson = linkRes.ok
        ? await linkRes.json() as { link: string }
        : { link: null };

      return json({
        ok: true,
        provider: "dropbox",
        path: meta.path_display ?? dropboxPath,
        dropbox_id: meta.id,
        size: bytes.length,
        temporary_link: linkJson.link,
      });
    }

    if (action === "download_bytes" && req.method === "POST") {
      const { path } = await req.json() as { path: string };
      if (!path?.startsWith("/")) return json({ error: "path må starte med /" }, 400);

      const dlRes = await dropboxApi(token, "content", "/files/download", {
        method: "POST",
        dropboxArg: { path },
      });
      if (!dlRes.ok) {
        const err = await dlRes.text();
        return json({ error: err.slice(0, 300) }, 500);
      }
      const buf = await dlRes.arrayBuffer();
      const bin = new Uint8Array(buf);
      let binary = "";
      const chunk = 0x8000;
      for (let i = 0; i < bin.length; i += chunk) {
        binary += String.fromCharCode(...bin.subarray(i, i + chunk));
      }
      return json({
        ok: true,
        bytes_base64: btoa(binary),
        size: bin.length,
      });
    }

    if (action === "temporary_link" && req.method === "POST") {
      const { path } = await req.json() as { path: string };
      if (!path?.startsWith("/")) return json({ error: "path må starte med /" }, 400);

      const linkRes = await dropboxApi(token, "api", "/files/get_temporary_link", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ path }),
      });
      const linkText = await linkRes.text();
      if (!linkRes.ok) return json({ error: linkText }, 500);
      const linkJson = JSON.parse(linkText) as { link: string };
      return json({ link: linkJson.link });
    }

    return json({ error: "Ukjent action" }, 400);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return json({ error: msg }, 500);
  }
});
