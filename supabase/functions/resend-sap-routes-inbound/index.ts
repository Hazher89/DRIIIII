import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, svix-id, svix-timestamp, svix-signature",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
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

function parseEmailAddress(raw: string): string {
  const s = raw.trim();
  const m = s.match(/<([^>]+)>/);
  return (m?.[1] ?? s).trim().toLowerCase();
}

function subjectMatches(subject: string): boolean {
  return subject.trim().toLowerCase() === "backup form";
}

function senderAllowed(from: string): boolean {
  const email = parseEmailAddress(from);
  return email.endsWith("@elkjop.no");
}

function pdfNameOk(name: string): boolean {
  return name.trim().toLowerCase().endsWith(".pdf");
}

async function verifySvix(
  payload: string,
  headers: Headers,
  secret: string,
): Promise<boolean> {
  const id = headers.get("svix-id");
  const ts = headers.get("svix-timestamp");
  const sig = headers.get("svix-signature");
  if (!id || !ts || !sig) return false;

  const tsNum = Number(ts);
  if (!Number.isFinite(tsNum)) return false;
  const age = Math.abs(Date.now() / 1000 - tsNum);
  if (age > 300) return false;

  const key = secret.startsWith("whsec_") ? secret.slice(6) : secret;
  const keyBytes = Uint8Array.from(atob(key), (c) => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signed = `${id}.${ts}.${payload}`;
  const mac = await crypto.subtle.sign(
    "HMAC",
    cryptoKey,
    new TextEncoder().encode(signed),
  );
  const expected = btoa(String.fromCharCode(...new Uint8Array(mac)));

  for (const part of sig.split(" ")) {
    const [version, signature] = part.split(",");
    if (version !== "v1" || !signature) continue;
    if (signature === expected) return true;
  }
  return false;
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(hash)].map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

type ResendAttachment = {
  id: string;
  filename: string;
  content_type?: string;
  download_url: string;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: cors });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const rawBody = await req.text();
  let event: {
    type?: string;
    data?: {
      email_id?: string;
      from?: string;
      subject?: string;
    };
  };
  try {
    event = JSON.parse(rawBody);
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const webhookSecret = Deno.env.get("RESEND_WEBHOOK_SECRET")?.trim();
  if (webhookSecret) {
    const ok = await verifySvix(rawBody, req.headers, webhookSecret);
    if (!ok) return json({ error: "Invalid webhook signature" }, 401);
  }

  if (event.type !== "email.received") {
    return json({ ok: true, skipped: "event_type" });
  }

  const emailId = event.data?.email_id?.trim();
  const from = event.data?.from?.trim() ?? "";
  const subject = event.data?.subject?.trim() ?? "";

  if (!emailId) return json({ error: "Missing email_id" }, 400);
  if (!senderAllowed(from)) {
    return json({ ok: true, skipped: "sender" });
  }
  if (!subjectMatches(subject)) {
    return json({ ok: true, skipped: "subject" });
  }

  const companyId = Deno.env.get("SAP_ROUTES_COMPANY_ID")?.trim() ||
    "00000000-0000-0000-0000-000000000000";

  const resendKey = requireEnv("RESEND_API_KEY");
  const attRes = await fetch(
    `https://api.resend.com/emails/receiving/${emailId}/attachments`,
    { headers: { Authorization: `Bearer ${resendKey}` } },
  );
  if (!attRes.ok) {
    const t = await attRes.text();
    console.error("Resend attachments failed", attRes.status, t);
    return json({ error: "Could not list attachments" }, 502);
  }

  const attJson = await attRes.json() as { data?: ResendAttachment[] };
  const attachments = (attJson.data ?? []).filter((a) => {
    const ct = (a.content_type ?? "").toLowerCase();
    return ct.includes("pdf") || a.filename.toLowerCase().endsWith(".pdf");
  });

  if (attachments.length === 0) {
    return json({ ok: true, skipped: "no_pdf" });
  }

  const supabase = createClient(
    requireEnv("SUPABASE_URL"),
    requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
  );

  const inserted: string[] = [];
  const skipped: string[] = [];

  for (const att of attachments) {
    if (!pdfNameOk(att.filename)) {
      skipped.push(`${att.filename}:name`);
      continue;
    }

    const dl = await fetch(att.download_url);
    if (!dl.ok) {
      skipped.push(`${att.filename}:download`);
      continue;
    }
    const bytes = new Uint8Array(await dl.arrayBuffer());
    if (bytes.length < 100) {
      skipped.push(`${att.filename}:empty`);
      continue;
    }

    const hash = await sha256Hex(bytes);
    const safeName = att.filename.replace(/[^a-zA-Z0-9._-]/g, "_");
    const storagePath =
      `company_${companyId}/sap_inbox/${Date.now()}_${safeName}`;

    const { error: upErr } = await supabase.storage
      .from("documents")
      .upload(storagePath, bytes, {
        contentType: "application/pdf",
        upsert: false,
      });
    if (upErr) {
      console.error("Storage upload failed", upErr);
      skipped.push(`${att.filename}:storage`);
      continue;
    }

    const { data: dup } = await supabase
      .from("sap_route_inbox")
      .select("id")
      .eq("resend_email_id", emailId)
      .eq("attachment_id", att.id)
      .maybeSingle();

    if (dup?.id) {
      skipped.push(`${att.filename}:duplicate`);
      continue;
    }

    const since = new Date(Date.now() - 48 * 60 * 60 * 1000).toISOString();
    const { data: hashDup } = await supabase
      .from("sap_route_inbox")
      .select("id")
      .eq("company_id", companyId)
      .eq("content_sha256", hash)
      .in("status", ["pending", "imported"])
      .gte("received_at", since)
      .limit(1)
      .maybeSingle();

    if (hashDup?.id) {
      skipped.push(`${att.filename}:content_duplicate`);
      continue;
    }

    const { error: insErr } = await supabase.from("sap_route_inbox").insert({
      company_id: companyId,
      status: "pending",
      sender_email: parseEmailAddress(from),
      sender_name: from.includes("<") ? from.split("<")[0].trim() : null,
      subject,
      file_name: att.filename,
      pdf_storage_path: storagePath,
      resend_email_id: emailId,
      attachment_id: att.id,
      content_sha256: hash,
    });

    if (insErr) {
      console.error("Inbox insert failed", insErr);
      skipped.push(`${att.filename}:db`);
      continue;
    }
    inserted.push(att.filename);
  }

  return json({
    ok: true,
    email_id: emailId,
    inserted: inserted.length,
    files: inserted,
    skipped,
  });
});
