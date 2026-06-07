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

export function buildDropboxStoragePath(
  root: string,
  companyId: string,
  category: string,
  fileName: string,
): string {
  const safeCat = category.replace(/[^a-zA-Z0-9_-]/g, "_");
  const safeName = fileName.replace(/[^a-zA-Z0-9._-]/g, "_");
  const date = new Date().toISOString().slice(0, 10);
  return `${root}/company_${companyId}/${safeCat}/${date}/${Date.now()}_${safeName}`;
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

/** Last opp til Dropbox for bedrift. Returnerer null hvis ikke koblet / modul av / under threshold. */
export async function tryUploadToDropbox(
  admin: ReturnType<typeof createClient>,
  companyId: string,
  opts: {
    fileName: string;
    category: string;
    bytes: Uint8Array;
  },
): Promise<DropboxUploadResult | null> {
  const { data: connRow } = await admin
    .from("company_dropbox_connections")
    .select("*")
    .eq("company_id", companyId)
    .maybeSingle();

  if (!connRow) return null;

  const conn = connRow as Conn;
  const token = await refreshAccessToken(conn, admin);
  const root = normalizeDropboxRoot(conn.root_folder);
  const dropboxPath = buildDropboxStoragePath(
    root,
    companyId,
    opts.category,
    opts.fileName,
  );
  const folder = dropboxPath.substring(0, dropboxPath.lastIndexOf("/"));
  await ensureFolder(token, folder);

  const upRes = await dropboxApi(token, "content", "/files/upload", {
    method: "POST",
    headers: { "Content-Type": "application/octet-stream" },
    dropboxArg: { path: dropboxPath, mode: "add", autorename: true },
    body: opts.bytes,
  });

  const upText = await upRes.text();
  if (!upRes.ok) throw new Error(upText.slice(0, 300));

  const meta = JSON.parse(upText) as { path_display?: string };
  const path = meta.path_display ?? dropboxPath;

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
