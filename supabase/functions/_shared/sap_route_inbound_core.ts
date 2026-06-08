import { createClient } from "jsr:@supabase/supabase-js@2";
import { tryUploadToDropbox } from "./dropbox_company_upload.ts";

export type ResendAttachment = {
  id: string;
  filename: string;
  content_type?: string;
  download_url?: string;
};

export type SapInboundProcessResult = {
  email_id: string;
  inserted: string[];
  skipped: string[];
  error?: string;
};

export function parseEmailAddress(raw: string): string {
  const s = raw.trim();
  const m = s.match(/<([^>]+)>/);
  return (m?.[1] ?? s).trim().toLowerCase();
}

export function subjectMatches(subject: string): boolean {
  return subject.trim().toLowerCase() === "backup form";
}

export function senderAllowed(from: string): boolean {
  return parseEmailAddress(from).endsWith("@elkjop.no");
}

function pdfNameOk(name: string): boolean {
  return name.trim().toLowerCase().endsWith(".pdf");
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(hash)].map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function fetchAttachments(
  resendKey: string,
  emailId: string,
  hint?: ResendAttachment[],
): Promise<ResendAttachment[]> {
  const fromHint = (hint ?? []).filter((a) => {
    const ct = (a.content_type ?? "").toLowerCase();
    return ct.includes("pdf") || a.filename.toLowerCase().endsWith(".pdf");
  });
  if (fromHint.length > 0 && fromHint.every((a) => a.download_url)) {
    return fromHint;
  }

  const attRes = await fetch(
    `https://api.resend.com/emails/receiving/${emailId}/attachments`,
    { headers: { Authorization: `Bearer ${resendKey}` } },
  );
  if (!attRes.ok) {
    const t = await attRes.text();
    throw new Error(`Resend attachments ${attRes.status}: ${t.slice(0, 300)}`);
  }

  const attJson = await attRes.json() as { data?: ResendAttachment[] };
  return (attJson.data ?? []).filter((a) => {
    const ct = (a.content_type ?? "").toLowerCase();
    return ct.includes("pdf") || a.filename.toLowerCase().endsWith(".pdf");
  });
}

export async function processSapInboundEmail(
  supabase: ReturnType<typeof createClient>,
  opts: {
    resendKey: string;
    companyId: string;
    emailId: string;
    from: string;
    subject: string;
    attachmentHint?: ResendAttachment[];
    /** Tillat innsetting selv om identisk PDF ble importert for >48t siden. */
    ignoreContentDedup?: boolean;
  },
): Promise<SapInboundProcessResult> {
  const {
    resendKey,
    companyId,
    emailId,
    from,
    subject,
    attachmentHint,
    ignoreContentDedup = false,
  } = opts;

  const result: SapInboundProcessResult = {
    email_id: emailId,
    inserted: [],
    skipped: [],
  };

  if (!senderAllowed(from)) {
    result.skipped.push("sender");
    return result;
  }
  if (!subjectMatches(subject)) {
    result.skipped.push("subject");
    return result;
  }

  let attachments: ResendAttachment[];
  try {
    attachments = await fetchAttachments(resendKey, emailId, attachmentHint);
  } catch (e) {
    result.error = e instanceof Error ? e.message : String(e);
    return result;
  }

  if (attachments.length === 0) {
    result.skipped.push("no_pdf");
    return result;
  }

  for (const att of attachments) {
    if (!pdfNameOk(att.filename)) {
      result.skipped.push(`${att.filename}:name`);
      continue;
    }
    if (!att.download_url) {
      result.skipped.push(`${att.filename}:no_download_url`);
      continue;
    }

    const dl = await fetch(att.download_url);
    if (!dl.ok) {
      result.skipped.push(`${att.filename}:download`);
      continue;
    }
    const bytes = new Uint8Array(await dl.arrayBuffer());
    if (bytes.length < 100) {
      result.skipped.push(`${att.filename}:empty`);
      continue;
    }

    const hash = await sha256Hex(bytes);
    const safeName = att.filename.replace(/[^a-zA-Z0-9._-]/g, "_");
    let storagePath =
      `company_${companyId}/sap_inbox/${Date.now()}_${safeName}`;
    let stored = false;

    try {
      const dropbox = await tryUploadToDropbox(supabase, companyId, {
        fileName: safeName,
        category: "sap_inbox",
        bytes,
      });
      if (dropbox) {
        storagePath = dropbox.path.startsWith("dropbox://")
          ? dropbox.path
          : `dropbox://${dropbox.path}`;
        stored = true;
      }
    } catch (e) {
      console.error("Dropbox SAP upload failed, fallback to Supabase", e);
    }

    if (!stored) {
      const { error: upErr } = await supabase.storage
        .from("documents")
        .upload(storagePath, bytes, {
          contentType: "application/pdf",
          upsert: false,
        });
      if (upErr) {
        console.error("Supabase storage upload failed", upErr);
        result.skipped.push(`${att.filename}:storage`);
        continue;
      }
      stored = true;
    }

    const { data: dup } = await supabase
      .from("sap_route_inbox")
      .select("id")
      .eq("resend_email_id", emailId)
      .eq("attachment_id", att.id)
      .maybeSingle();

    if (dup?.id) {
      result.skipped.push(`${att.filename}:duplicate`);
      continue;
    }

    if (!ignoreContentDedup) {
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
        result.skipped.push(`${att.filename}:content_duplicate`);
        continue;
      }
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
      result.skipped.push(`${att.filename}:db`);
      continue;
    }
    result.inserted.push(att.filename);
  }

  return result;
}

export function sapRoutesCompanyId(): string {
  return Deno.env.get("SAP_ROUTES_COMPANY_ID")?.trim() ||
    "00000000-0000-0000-0000-000000000000";
}
