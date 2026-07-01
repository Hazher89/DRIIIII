import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import md5 from "npm:md5";
import { tryUploadToDropbox } from "../_shared/dropbox_company_upload.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function requireEnv(name: string): string {
  const v = Deno.env.get(name)?.trim();
  if (!v) throw new Error(`Mangler secret: ${name}`);
  return v;
}

function isServiceRole(authHeader: string | null): boolean {
  if (!authHeader?.startsWith("Bearer ")) return false;
  const token = authHeader.slice(7);
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  return !!serviceKey && token === serviceKey;
}

async function profileHasUniformMonitor(
  admin: ReturnType<typeof createClient>,
  userId: string,
): Promise<boolean> {
  const { data } = await admin
    .from("profiles")
    .select("role, access_settings")
    .eq("id", userId)
    .maybeSingle();
  if (!data) return false;
  if (data.role === "superadmin") return true;
  const settings = data.access_settings as Record<string, unknown> | null;
  return settings?.uniform_monitor === true;
}

type CameraRow = {
  host: string;
  http_port: number;
  camera_user: string;
  camera_password: string;
  snapshot_path: string;
};

function digestAuthHeader(
  wwwAuth: string,
  method: string,
  uri: string,
  user: string,
  pass: string,
): string {
  const params: Record<string, string> = {};
  for (const part of wwwAuth.replace(/^Digest\s+/i, "").split(",")) {
    const m = part.trim().match(/^(\w+)="?([^"]+)"?$/);
    if (m) params[m[1]] = m[2];
  }
  const realm = params.realm ?? "";
  const nonce = params.nonce ?? "";
  const qop = params.qop?.split(",")[0]?.trim();
  const nc = "00000001";
  const cnonce = crypto.randomUUID().replace(/-/g, "").slice(0, 16);
  const ha1 = md5(`${user}:${realm}:${pass}`);
  const ha2 = md5(`${method}:${uri}`);
  if (qop) {
    const response = md5(`${ha1}:${nonce}:${nc}:${cnonce}:${qop}:${ha2}`);
    return `Digest username="${user}", realm="${realm}", nonce="${nonce}", uri="${uri}", qop=${qop}, nc=${nc}, cnonce="${cnonce}", response="${response}"`;
  }
  const response = md5(`${ha1}:${nonce}:${ha2}`);
  return `Digest username="${user}", realm="${realm}", nonce="${nonce}", uri="${uri}", response="${response}"`;
}

async function fetchCameraJpeg(cam: CameraRow): Promise<Uint8Array> {
  const port = cam.http_port === 80 ? "" : `:${cam.http_port}`;
  const path = cam.snapshot_path.startsWith("/")
    ? cam.snapshot_path
    : `/${cam.snapshot_path}`;
  const url = `http://${cam.host}${port}${path}`;

  let res = await fetch(url);
  if (res.status === 401) {
    const www = res.headers.get("www-authenticate") ?? "";
    if (www.toLowerCase().includes("digest")) {
      res = await fetch(url, {
        headers: {
          Authorization: digestAuthHeader(www, "GET", path, cam.camera_user, cam.camera_password),
        },
      });
    } else {
      const auth = btoa(`${cam.camera_user}:${cam.camera_password}`);
      res = await fetch(url, { headers: { Authorization: `Basic ${auth}` } });
    }
  }

  if (!res.ok) throw new Error(`Kamera HTTP ${res.status}`);

  const bytes = new Uint8Array(await res.arrayBuffer());
  if (bytes.length >= 2 && bytes[0] === 0xff && bytes[1] === 0xd8) return bytes;
  throw new Error("Ugyldig JPEG fra kamera");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });

  try {
    const url = new URL(req.url);
    const action = url.searchParams.get("action") ?? "snapshot";
    const admin = createClient(
      requireEnv("SUPABASE_URL"),
      requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
    );

    if (action === "upload" && req.method === "POST") {
      if (!isServiceRole(req.headers.get("Authorization"))) {
        return json({ error: "Krever service role" }, 401);
      }

      const body = await req.json() as {
        company_id: string;
        file_name: string;
        bytes_base64: string;
      };

      if (!body.company_id || !body.file_name || !body.bytes_base64) {
        return json({ error: "company_id, file_name, bytes_base64 påkrevd" }, 400);
      }

      const bytes = Uint8Array.from(atob(body.bytes_base64), (c) => c.charCodeAt(0));
      const result = await tryUploadToDropbox(admin, body.company_id, {
        fileName: body.file_name,
        category: "vision_uniform",
        bytes,
      });

      if (!result) return json({ error: "Dropbox ikke koblet for bedriften" }, 400);

      return json({
        ok: true,
        path: result.path,
        temporary_link: result.temporaryLink,
        size: result.size,
      });
    }

    if (action === "snapshot") {
      const cameraId = url.searchParams.get("camera_id");
      if (!cameraId) return json({ error: "camera_id mangler" }, 400);

      const authHeader = req.headers.get("Authorization");
      const apiKey = req.headers.get("apikey");
      const anonKey = Deno.env.get("SUPABASE_ANON_KEY")?.trim();

      let allowed = isServiceRole(authHeader);
      if (!allowed && authHeader?.startsWith("Bearer ") && apiKey === anonKey) {
        const userClient = createClient(requireEnv("SUPABASE_URL"), anonKey!, {
          global: { headers: { Authorization: authHeader } },
        });
        const { data: userData } = await userClient.auth.getUser();
        if (userData.user) {
          allowed = await profileHasUniformMonitor(admin, userData.user.id);
        }
      }

      if (!allowed) return json({ error: "Ingen tilgang" }, 403);

      const { data: cam, error } = await admin
        .from("vision_cameras")
        .select("host, http_port, camera_user, camera_password, snapshot_path")
        .eq("id", cameraId)
        .eq("enabled", true)
        .maybeSingle();

      if (error || !cam) return json({ error: "Kamera ikke funnet" }, 404);

      const jpeg = await fetchCameraJpeg(cam as CameraRow);
      return new Response(jpeg, {
        status: 200,
        headers: {
          ...cors,
          "Content-Type": "image/jpeg",
          "Cache-Control": "no-store",
        },
      });
    }

    return json({ error: "Ukjent action" }, 400);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return json({ error: msg }, 500);
  }
});
