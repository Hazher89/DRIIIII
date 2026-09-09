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
 * Secrets:
 * - MS_GRAPH_TENANT_ID
 * - MS_GRAPH_CLIENT_ID
 * - MS_GRAPH_CLIENT_SECRET
 * - MS_GRAPH_MAILBOX (valgfri, default driftpro@mavilogistikk.no)
 * - SAP_ROUTES_COMPANY_ID
 * - SAP_GRAPH_SYNC_SECRET (valgfri, men anbefalt for manuell/cron-kall)
 */

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-sap-graph-sync-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

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

function encodeMailbox(mailbox: string): string {
  return encodeURIComponent(mailbox);
}

async function listCandidateMessages(
  mailbox: string,
  hours: number,
  limit: number,
): Promise<GraphMessage[]> {
  const since = new Date(Date.now() - hours * 60 * 60 * 1000).toISOString();
  // Graph $filter: received recently + has attachments. Subject filter applied in code
  // (safer across locales / exact match).
  const filter = `receivedDateTime ge ${since} and hasAttachments eq true`;
  const path =
    `/users/${encodeMailbox(mailbox)}/messages` +
    `?$filter=${encodeURIComponent(filter)}` +
    `&$select=id,subject,from,receivedDateTime,hasAttachments,isRead` +
    `&$orderby=receivedDateTime desc` +
    `&$top=${Math.min(Math.max(limit, 1), 50)}`;

  const res = await graphFetch(path);
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`Graph messages ${res.status}: ${t.slice(0, 500)}`);
  }
  const body = await res.json() as { value?: GraphMessage[] };
  return body.value ?? [];
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
      // Tillat app-kall med bruker-JWT (Supabase functions.invoke),
      // eller cron/curl med sync-secret.
      const hasUserJwt = auth.toLowerCase().startsWith("bearer ") &&
        auth.length > 20;
      if (got !== syncSecret && !hasUserJwt) {
        return json({ error: "Unauthorized" }, 401);
      }
    }

    let hours = 72;
    let limit = 30;
    let markRead = true;
    try {
      const body = await req.json() as {
        hours?: number;
        limit?: number;
        markRead?: boolean;
      };
      if (typeof body.hours === "number") hours = body.hours;
      if (typeof body.limit === "number") limit = body.limit;
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

    const messages = await listCandidateMessages(mailbox, hours, limit);
    const summary = {
      mailbox,
      scanned: messages.length,
      matched: 0,
      inserted: [] as string[],
      skipped: [] as string[],
      errors: [] as string[],
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
      try {
        const pdfs = await listPdfAttachments(mailbox, msg.id);
        if (pdfs.length === 0) {
          summary.skipped.push(`${msg.id}:no_pdf`);
          continue;
        }

        let anyInserted = false;
        for (const pdf of pdfs) {
          const { fileName, bytes } = await downloadAttachmentBytes(
            mailbox,
            msg.id,
            pdf.id,
          );
          const outcome = await insertSapPdfToInbox(supabase, {
            companyId,
            emailId,
            attachmentId: pdf.id,
            from,
            subject,
            fileName,
            bytes,
          });
          if (outcome === "inserted") {
            summary.inserted.push(fileName);
            anyInserted = true;
          } else {
            summary.skipped.push(outcome);
          }
        }

        if (markRead && (anyInserted || pdfs.length > 0)) {
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
