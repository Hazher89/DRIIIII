import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const rateBuckets = new Map<string, { count: number; resetAt: number }>();

function rateLimited(ip: string): boolean {
  const now = Date.now();
  const windowMs = 60_000;
  const max = 40;
  const cur = rateBuckets.get(ip);
  if (!cur || now > cur.resetAt) {
    rateBuckets.set(ip, { count: 1, resetAt: now + windowMs });
    return false;
  }
  cur.count += 1;
  return cur.count > max;
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** CCC/butikk: navn, tlf, ordre 21/22/60, kundenr 39/41. */
function isAllowedQuery(raw: string): boolean {
  const t = raw.trim();
  if (t.length < 3) return false;
  const digits = t.replace(/\D/g, "");
  if (digits.length >= 4) return true;
  const letters = t.replace(/[^a-zA-ZæøåÆØÅäöÄÖüÜ]/g, "");
  return letters.length >= 3;
}

function storagePathFromRef(ref: string): string | null {
  const t = ref.trim();
  if (!t) return null;
  if (t.startsWith("dropbox://")) return null;
  if (t.startsWith("http://") || t.startsWith("https://")) {
    try {
      const u = new URL(t);
      const parts = u.pathname.split("/").filter(Boolean);
      const idx = parts.indexOf("documents");
      if (idx >= 0 && idx + 1 < parts.length) {
        return decodeURIComponent(parts.slice(idx + 1).join("/"));
      }
    } catch {
      return null;
    }
    return null;
  }
  return t.replace(/^\//, "");
}

function dropboxPathFromRef(ref: string): string | null {
  const t = ref.trim();
  if (t.startsWith("dropbox://")) {
    const p = t.slice("dropbox://".length);
    return p.startsWith("/") ? p : `/${p}`;
  }
  if (t.startsWith("/") && (t.includes("/partners/") || t.includes("driver_deviations"))) {
    return t;
  }
  return null;
}

type DropboxConn = {
  company_id: string;
  refresh_token: string;
  access_token: string | null;
  token_expires_at: string | null;
};

async function dropboxAccessToken(
  admin: ReturnType<typeof createClient>,
  companyId: string,
  cache: Map<string, string>,
): Promise<string | null> {
  if (cache.has(companyId)) return cache.get(companyId)!;
  const appKey = Deno.env.get("DROPBOX_APP_KEY")?.trim();
  const appSecret = Deno.env.get("DROPBOX_APP_SECRET")?.trim();
  if (!appKey || !appSecret) return null;

  const { data: conn } = await admin
    .from("company_dropbox_connections")
    .select("company_id, refresh_token, access_token, token_expires_at")
    .eq("company_id", companyId)
    .maybeSingle();
  if (!conn?.refresh_token) return null;
  const c = conn as DropboxConn;

  if (c.access_token && c.token_expires_at) {
    const exp = new Date(c.token_expires_at).getTime();
    if (exp > Date.now() + 60_000) {
      cache.set(companyId, c.access_token);
      return c.access_token;
    }
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
      refresh_token: c.refresh_token,
    }),
  });
  if (!res.ok) return null;
  const data = await res.json() as { access_token: string; expires_in?: number };
  const expiresAt = data.expires_in
    ? new Date(Date.now() + data.expires_in * 1000).toISOString()
    : null;
  await admin.from("company_dropbox_connections").update({
    access_token: data.access_token,
    token_expires_at: expiresAt,
    updated_at: new Date().toISOString(),
  }).eq("company_id", companyId);
  cache.set(companyId, data.access_token);
  return data.access_token;
}

async function resolveMediaUrl(
  admin: ReturnType<typeof createClient>,
  ref: string,
  companyId: string,
  dropboxTokenCache: Map<string, string>,
): Promise<string | null> {
  const dbx = dropboxPathFromRef(ref);
  if (dbx) {
    const token = await dropboxAccessToken(admin, companyId, dropboxTokenCache);
    if (!token) return null;
    const linkRes = await fetch(
      "https://api.dropboxapi.com/2/files/get_temporary_link",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ path: dbx }),
      },
    );
    if (!linkRes.ok) return null;
    const linkJson = await linkRes.json() as { link?: string };
    return linkJson.link ?? null;
  }

  const path = storagePathFromRef(ref);
  if (!path) return null;
  const { data: signed, error } = await admin.storage
    .from("documents")
    .createSignedUrl(path, 3600);
  if (error || !signed?.signedUrl) return null;
  return signed.signedUrl;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const ip =
    req.headers.get("cf-connecting-ip") ??
    req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
    "unknown";
  if (rateLimited(ip)) {
    return json({ error: "For mange søk. Vent litt og prøv igjen." }, 429);
  }

  try {
    const body = await req.json();
    const query = String(body?.query ?? "").trim();
    if (!isAllowedQuery(query)) {
      return json({
        ok: true,
        items: [],
        hint:
          "Skriv kundenavn, telefon, ordre (21/22/60) eller kundenummer (39/41).",
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceKey);

    const q = query.toLowerCase();
    const { data: rows, error } = await admin
      .from("partner_driver_deviations")
      .select(
        "id, customer_name, freight_unit, customer_ref, order_ref, customer_phone, comment, route_date, created_at, status, image_urls, video_urls, reporter_name, company_id",
      )
      .ilike("search_text", `%${q}%`)
      .order("created_at", { ascending: false })
      .limit(25);

    if (error) {
      console.error("public-driver-deviation-lookup search:", error);
      return json({ error: "Søk feilet. Prøv igjen." }, 500);
    }

    const dropboxTokenCache = new Map<string, string>();
    const items = [];
    for (const row of rows ?? []) {
      const companyId = String(row.company_id ?? "");
      const imageRefs = Array.isArray(row.image_urls) ? row.image_urls : [];
      const videoRefs = Array.isArray(row.video_urls) ? row.video_urls : [];
      const images: string[] = [];
      const videos: string[] = [];

      for (const ref of imageRefs) {
        const url = await resolveMediaUrl(
          admin,
          String(ref),
          companyId,
          dropboxTokenCache,
        );
        if (url) images.push(url);
      }
      for (const ref of videoRefs) {
        const url = await resolveMediaUrl(
          admin,
          String(ref),
          companyId,
          dropboxTokenCache,
        );
        if (url) videos.push(url);
      }

      items.push({
        id: row.id,
        customer_name: row.customer_name,
        freight_unit: row.freight_unit,
        customer_ref: row.customer_ref,
        order_ref: row.order_ref,
        customer_phone: row.customer_phone ?? null,
        comment: row.comment,
        route_date: row.route_date,
        created_at: row.created_at,
        status: row.status,
        reporter_name: row.reporter_name,
        images,
        videos,
        media_count: images.length + videos.length,
        media_incomplete:
          images.length + videos.length < imageRefs.length + videoRefs.length,
      });
    }

    return json({
      ok: true,
      items,
      query,
    });
  } catch (e) {
    console.error("public-driver-deviation-lookup:", e);
    return json({ error: "Uventet feil" }, 500);
  }
});
