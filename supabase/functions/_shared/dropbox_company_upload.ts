import { createClient } from "jsr:@supabase/supabase-js@2";

type Conn = {
  company_id: string;
  refresh_token: string;
  root_folder: string;
  access_token: string | null;
  token_expires_at: string | null;
  large_file_threshold_bytes: number;
  storage_modules?: Record<string, boolean>;
};

export type DropboxUploadResult = {
  path: string;
  temporaryLink: string | null;
  size: number;
};

function requireEnv(name: string): string {
  const v = Deno.env.get(name)?.trim();
  if (!v) throw new Error(`Mangler secret: ${name}`);
  return v;
}

export function normalizeDropboxRoot(path: string): string {
  let p = path.trim() || "/";
  if (!p.startsWith("/")) p = `/${p}`;
  const trimmed = p.replace(/\/+$/, "");
  return trimmed === "" ? "/" : trimmed;
}

export function resolveDropboxUploadRoot(storedRoot: string): string {
  const fromEnv = Deno.env.get("DROPBOX_ROOT_FOLDER")?.trim();
  if (fromEnv) return normalizeDropboxRoot(fromEnv);
  const stored = normalizeDropboxRoot(storedRoot);
  if (stored.toLowerCase() === "/driftpro") return "/";
  return stored;
}

export function buildDropboxStoragePath(
  root: string,
  companyId: string,
  category: string,
  fileName: string,
): string {
  const safeCat = category.replace(/[^a-zA-Z0-9_-]/g, "_");
  const safeName = fileName.replace(/[^a-zA-Z0-9._-]/g, "_");
  const date = new Date().toISOString().slice(0, 10);
  const base = root === "/" ? "" : root.replace(/\/+$/, "");
  return `${base}/company_${companyId}/${safeCat}/${date}/${Date.now()}_${safeName}`;
}

async function refreshAccessToken(
  conn: Conn,
  admin: ReturnType<typeof createClient>,
): Promise<string> {
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
  const parts = folderPath.split("/").filter(Boolean);
  let cur = "";
  for (const part of parts) {
    cur += `/${part}`;
    const res = await dropboxApi(token, "api", "/files/create_folder_v2", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ path: cur, autorename: false }),
    });
    if (res.ok) continue;
    const err = await res.text();
    if (err.includes("path/conflict/folder")) continue;
    if (err.includes("folder/conflict")) continue;
    if (err.includes("path/conflict")) continue;
  }
}

const NIL_COMPANY = "00000000-0000-0000-0000-000000000000";

function isUsableCompanyId(id: string | null | undefined): boolean {
  if (!id || typeof id !== "string") return false;
  const t = id.trim();
  if (!t || t === NIL_COMPANY) return false;
  return true;
}

/** Finn bedrift med Dropbox — unngå placeholder 00000000. */
export async function resolveDropboxCompanyId(
  admin: ReturnType<typeof createClient>,
  preferred: string | null | undefined,
): Promise<string | null> {
  if (isUsableCompanyId(preferred)) {
    const { data } = await admin
      .from("company_dropbox_connections")
      .select("company_id")
      .eq("company_id", preferred!)
      .maybeSingle();
    if (data?.company_id) return data.company_id as string;
  }
  const { data: rows } = await admin
    .from("company_dropbox_connections")
    .select("company_id")
    .limit(5);
  const first = rows?.[0]?.company_id;
  return typeof first === "string" && first ? first : null;
}

/** Last opp til Dropbox for bedrift. Returnerer null hvis ikke koblet. */
export async function tryUploadToDropbox(
  admin: ReturnType<typeof createClient>,
  companyId: string,
  opts: {
    fileName: string;
    category: string;
    bytes: Uint8Array;
    /** Fast sti (uten root) — overskrives. F.eks. vision_live/<camera_id>/latest.jpg */
    fixedRelativePath?: string;
  },
): Promise<DropboxUploadResult | null> {
  const resolvedId = await resolveDropboxCompanyId(admin, companyId);
  if (!resolvedId) return null;

  const { data: connRow } = await admin
    .from("company_dropbox_connections")
    .select("*")
    .eq("company_id", resolvedId)
    .maybeSingle();

  if (!connRow) return null;

  const conn = connRow as Conn;
  // Bruk ekte company_id i sti — ikke placeholder 00000000.
  companyId = resolvedId;
  const token = await refreshAccessToken(conn, admin);
  const root = resolveDropboxUploadRoot(conn.root_folder);
  const dropboxPath = opts.fixedRelativePath
    ? (() => {
      const rel = opts.fixedRelativePath.startsWith("/")
        ? opts.fixedRelativePath
        : `/${opts.fixedRelativePath}`;
      const base = root === "/" ? "" : root.replace(/\/+$/, "");
      return `${base}${rel}`;
    })()
    : buildDropboxStoragePath(
      root,
      companyId,
      opts.category,
      opts.fileName,
    );
  const folder = dropboxPath.substring(0, dropboxPath.lastIndexOf("/"));
  await ensureFolder(token, folder);

  const mode = opts.fixedRelativePath ? "overwrite" : "add";

  async function doUpload(path: string) {
    return dropboxApi(token, "content", "/files/upload", {
      method: "POST",
      headers: { "Content-Type": "application/octet-stream" },
      dropboxArg: { path, mode, autorename: !opts.fixedRelativePath },
      body: opts.bytes,
    });
  }

  let uploadPath = dropboxPath;
  let upRes = await doUpload(uploadPath);
  let upText = await upRes.text();
  if (!upRes.ok && upText.includes("malformed_path") && root !== "/") {
    uploadPath = opts.fixedRelativePath
      ? (opts.fixedRelativePath.startsWith("/")
        ? opts.fixedRelativePath
        : `/${opts.fixedRelativePath}`)
      : buildDropboxStoragePath("/", companyId, opts.category, opts.fileName);
    const folder2 = uploadPath.substring(0, uploadPath.lastIndexOf("/"));
    await ensureFolder(token, folder2);
    upRes = await doUpload(uploadPath);
    upText = await upRes.text();
  }
  if (!upRes.ok) throw new Error(upText.slice(0, 300));

  const meta = JSON.parse(upText) as { path_display?: string };
  const path = meta.path_display ?? uploadPath;

  const linkRes = await dropboxApi(token, "api", "/files/get_temporary_link", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ path }),
  });
  const linkJson = linkRes.ok
    ? await linkRes.json() as { link: string }
    : { link: null };

  return {
    path,
    temporaryLink: linkJson.link,
    size: opts.bytes.length,
  };
}

/** Hent midlertidig lenke for eksisterende Dropbox-sti. */
export async function tryTemporaryLink(
  admin: ReturnType<typeof createClient>,
  companyId: string,
  path: string,
): Promise<string | null> {
  const resolvedId = (await resolveDropboxCompanyId(admin, companyId)) ?? companyId;
  const { data: connRow } = await admin
    .from("company_dropbox_connections")
    .select("*")
    .eq("company_id", resolvedId)
    .maybeSingle();
  if (!connRow) return null;
  const token = await refreshAccessToken(connRow as Conn, admin);
  // Prøv path som lagret + lowercase-variant (Dropbox er case-insensitive men API kan være streng).
  const candidates = [path];
  if (path !== path.toLowerCase()) candidates.push(path.toLowerCase());
  for (const p of candidates) {
    const linkRes = await dropboxApi(token, "api", "/files/get_temporary_link", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ path: p }),
    });
    if (linkRes.ok) {
      const linkJson = await linkRes.json() as { link?: string };
      if (linkJson.link) return linkJson.link;
    }
  }
  return null;
}

/** Kortvarig access token + root for direkte opplasting fra worker (store MP4). */
export async function tryCompanyDropboxAuth(
  admin: ReturnType<typeof createClient>,
  companyId: string,
): Promise<{ accessToken: string; rootFolder: string; companyId: string } | null> {
  const resolvedId = await resolveDropboxCompanyId(admin, companyId);
  if (!resolvedId) return null;
  const { data: connRow } = await admin
    .from("company_dropbox_connections")
    .select("*")
    .eq("company_id", resolvedId)
    .maybeSingle();
  if (!connRow) return null;
  const conn = connRow as Conn;
  const accessToken = await refreshAccessToken(conn, admin);
  return {
    accessToken,
    rootFolder: resolveDropboxUploadRoot(conn.root_folder),
    companyId: resolvedId,
  };
}
