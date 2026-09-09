import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { graphFetch, graphMailbox } from "../_shared/ms_graph_auth.ts";
import {
  insertSapPdfToInbox,
  parseEmailAddress,
  sapRoutesCompanyId,
  senderAllowed,
  subjectMatches,
} from "../_shared/sap_route_inbound_core.ts";

/**
 * Synker SAP Backup Form-PDF fra Office 365 (driftpro@mavilogistikk.no)
 * inn i sap_route_inbox via Microsoft Graph.
 *
 * Rask path: hopper over Graph-nedlasting når mail allerede ligger i innboks.
 */

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-sap-graph-sync-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const HARD_SCAN_CAP = 5000;
const PAGE_SIZE = 50;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

type GraphMessage = {
  id: string;
  subject?: string;
  from?: { emailAddress?: { address?: string; name?: string } };
  receivedDateTime?: string;
  hasAttachments?: boolean;
  isRead?: boolean;
};

type GraphAttachment = {
  id: string;
  name?: string;
  contentType?: string;
  size?: number;
  "@odata.type"?: string;
  contentBytes?: string;
};

type ExistingInboxRow = {
  resend_email_id: string | null;
  attachment_id: string | null;
  file_name: string | null;
};

function encodeMailbox(mailbox: string): string {
  return encodeURIComponent(mailbox);
}

async function listCandidateMessages(
  mailbox: string,
  hours: number,
): Promise<GraphMessage[]> {
  const since = new Date(Date.now() - hours * 60 * 60 * 1000).toISOString();
  const filter = `receivedDateTime ge ${since}`;
  let next:
    | string
    | null =
      `/users/${encodeMailbox(mailbox)}/messages` +
      `?$filter=${encodeURIComponent(filter)}` +
      `&$select=id,subject,from,receivedDateTime,hasAttachments,isRead` +
      `&$orderby=receivedDateTime desc` +
      `&$top=${PAGE_SIZE}`;

  const all: GraphMessage[] = [];
  while (next) {
    const res = await graphFetch(next);
    if (!res.ok) {
      const t = await res.text();
      throw new Error(`Graph messages ${res.status}: ${t.slice(0, 500)}`);
    }
    const body = await res.json() as {
      value?: GraphMessage[];
      "@odata.nextLink"?: string;
    };
    all.push(...(body.value ?? []));
    if (all.length >= HARD_SCAN_CAP) {
      console.warn(`SAP Graph scan capped at ${HARD_SCAN_CAP}`);
      break;
    }
    next = body["@odata.nextLink"] ?? null;
  }
  return all;
}

async function listPdfAttachments(
  mailbox: string,
  messageId: string,
): Promise<GraphAttachment[]> {
  const path =
    `/users/${encodeMailbox(mailbox)}/messages/${messageId}/attachments` +
    `?$select=id,name,contentType,size`;
  const res = await graphFetch(path);
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`Graph attachments ${res.status}: ${t.slice(0, 400)}`);
  }
  const body = await res.json() as { value?: GraphAttachment[] };
  return (body.value ?? []).filter((a) => {
    const name = (a.name ?? "").toLowerCase();
    const ct = (a.contentType ?? "").toLowerCase();
    return name.endsWith(".pdf") || ct.includes("pdf");
  });
}

async function downloadAttachmentBytes(
  mailbox: string,
  messageId: string,
  attachmentId: string,
): Promise<{ fileName: string; bytes: Uint8Array }> {
  const path =
    `/users/${encodeMailbox(mailbox)}/messages/${messageId}` +
    `/attachments/${attachmentId}`;
  const res = await graphFetch(path);
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`Graph attachment download ${res.status}: ${t.slice(0, 400)}`);
  }
  const att = await res.json() as GraphAttachment;
  const fileName = att.name ?? "sap_route.pdf";
  if (!att.contentBytes) {
    throw new Error(`Attachment ${fileName} mangler contentBytes`);
  }
  const bin = Uint8Array.from(atob(att.contentBytes), (c) => c.charCodeAt(0));
  return { fileName, bytes: bin };
}

async function markMessageRead(mailbox: string, messageId: string): Promise<void> {
  const path = `/users/${encodeMailbox(mailbox)}/messages/${messageId}`;
  const res = await graphFetch(path, {
    method: "PATCH",
    body: JSON.stringify({ isRead: true }),
  });
  if (!res.ok) {
    const t = await res.text();
    console.warn("Kunne ikke markere lest", messageId, t.slice(0, 200));
  }
}

/** Laster kjente Graph-innboks-rader slik at vi slipper å laste ned PDF på nytt. */
async function loadExistingGraphInbox(
  supabase: ReturnType<typeof createClient>,
  companyId: string,
): Promise<{
  byEmail: Map<string, ExistingInboxRow[]>;
  keys: Set<string>;
}> {
  const { data, error } = await supabase
    .from("sap_route_inbox")
    .select("resend_email_id, attachment_id, file_name")
    .eq("company_id", companyId)
    .like("resend_email_id", "graph:%");
  if (error) {
    console.warn("Could not preload inbox", error.message);
    return { byEmail: new Map(), keys: new Set() };
  }
  const byEmail = new Map<string, ExistingInboxRow[]>();
  const keys = new Set<string>();
  for (const row of (data ?? []) as ExistingInboxRow[]) {
    const emailId = (row.resend_email_id ?? "").trim();
    if (!emailId) continue;
    const list = byEmail.get(emailId) ?? [];
    list.push(row);
    byEmail.set(emailId, list);
    const att = (row.attachment_id ?? "").trim();
    if (att) keys.add(`${emailId}|${att}`);
  }
  return { byEmail, keys };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: cors });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const syncSecret = Deno.env.get("SAP_GRAPH_SYNC_SECRET")?.trim();
    if (syncSecret) {
      const got = req.headers.get("x-sap-graph-sync-secret")?.trim();
      const auth = req.headers.get("Authorization")?.trim() ?? "";
      const hasUserJwt = auth.toLowerCase().startsWith("bearer ") &&
        auth.length > 20;
      if (got !== syncSecret && !hasUserJwt) {
        return json({ error: "Unauthorized" }, 401);
      }
    }

    let hours = 168;
    let markRead = true;
    try {
      const body = await req.json() as {
        hours?: number;
        limit?: number;
        markRead?: boolean;
      };
      if (typeof body.hours === "number" && body.hours > 0) {
        hours = Math.min(body.hours, 24 * 30);
      }
      if (typeof body.markRead === "boolean") markRead = body.markRead;
    } catch {
      // empty body ok
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim();
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
    if (!supabaseUrl || !serviceKey) {
      return json({ error: "Mangler SUPABASE_URL / SERVICE_ROLE" }, 500);
    }

    const supabase = createClient(supabaseUrl, serviceKey);
    const companyId = sapRoutesCompanyId();
    const mailbox = graphMailbox();

    const [messages, existing] = await Promise.all([
      listCandidateMessages(mailbox, hours),
      loadExistingGraphInbox(supabase, companyId),
    ]);

    const summary = {
      mailbox,
      hours,
      scanned: messages.length,
      matched: 0,
      inserted: [] as string[],
      already: [] as string[],
      skipped: [] as string[],
      errors: [] as string[],
      downloads: 0,
    };

    for (const msg of messages) {
      const subject = msg.subject ?? "";
      const fromAddr = msg.from?.emailAddress?.address ?? "";
      const fromName = msg.from?.emailAddress?.name;
      const from = fromName ? `${fromName} <${fromAddr}>` : fromAddr;

      if (!senderAllowed(fromAddr) || !subjectMatches(subject)) {
        continue;
      }
      summary.matched += 1;

      const emailId = `graph:${msg.id}`;
      const knownRows = existing.byEmail.get(emailId) ?? [];
      // Allerede i DB → ingen Graph attachment-kall / PDF-nedlasting.
      if (knownRows.length > 0) {
        for (const row of knownRows) {
          summary.already.push(row.file_name || emailId);
        }
        continue;
      }

      try {
        const pdfs = await listPdfAttachments(mailbox, msg.id);
        if (pdfs.length === 0) {
          summary.skipped.push(`${msg.id}:no_pdf`);
          continue;
        }

        let anyStored = false;
        for (const pdf of pdfs) {
          const key = `${emailId}|${pdf.id}`;
          if (existing.keys.has(key)) {
            summary.already.push(pdf.name || pdf.id);
            anyStored = true;
            continue;
          }

          const { fileName, bytes } = await downloadAttachmentBytes(
            mailbox,
            msg.id,
            pdf.id,
          );
          summary.downloads += 1;

          const outcome = await insertSapPdfToInbox(supabase, {
            companyId,
            emailId,
            attachmentId: pdf.id,
            from,
            subject,
            fileName,
            bytes,
            ignoreContentDedup: true,
          });
          if (outcome === "inserted") {
            summary.inserted.push(fileName);
            anyStored = true;
            existing.keys.add(key);
            const list = existing.byEmail.get(emailId) ?? [];
            list.push({
              resend_email_id: emailId,
              attachment_id: pdf.id,
              file_name: fileName,
            });
            existing.byEmail.set(emailId, list);
          } else if (outcome.includes(":duplicate")) {
            summary.already.push(fileName);
            anyStored = true;
          } else {
            summary.skipped.push(outcome);
          }
        }

        if (markRead && anyStored) {
          await markMessageRead(mailbox, msg.id);
        }
      } catch (e) {
        summary.errors.push(
          `${msg.id}:${e instanceof Error ? e.message : String(e)}`,
        );
      }
    }

    return json({
      ok: true,
      company_id: companyId,
      sender_parsed_example: parseEmailAddress("test@elkjop.no"),
      ...summary,
    });
  } catch (e) {
    console.error(e);
    return json({
      error: e instanceof Error ? e.message : String(e),
    }, 500);
  }
});
