/** Utgående e-post via Microsoft Graph (Mail.Send). */

import { getGraphAccessToken, graphMailbox } from "./ms_graph_auth.ts";

export type GraphSendConfig = {
  mailbox: string;
  fromName: string;
  replyTo?: string;
  test: boolean;
};

export function readGraphSendConfig(): GraphSendConfig | { error: string } {
  const tenant = Deno.env.get("MS_GRAPH_TENANT_ID")?.trim();
  const clientId = Deno.env.get("MS_GRAPH_CLIENT_ID")?.trim();
  const secret = Deno.env.get("MS_GRAPH_CLIENT_SECRET")?.trim();
  if (!tenant || !clientId || !secret) {
    return {
      error:
        "Mangler MS_GRAPH_TENANT_ID / MS_GRAPH_CLIENT_ID / MS_GRAPH_CLIENT_SECRET",
    };
  }

  const fromName =
    Deno.env.get("MS_GRAPH_FROM_NAME")?.trim() ||
    Deno.env.get("RESEND_FROM_NAME")?.trim() ||
    "DriftPro";
  const replyTo =
    Deno.env.get("MS_GRAPH_REPLY_TO")?.trim() ||
    Deno.env.get("RESEND_REPLY_TO")?.trim() ||
    undefined;
  const test = (Deno.env.get("EMAIL_TEST") ?? "").toLowerCase() === "true";

  return {
    mailbox: graphMailbox(),
    fromName,
    replyTo,
    test,
  };
}

function isHtmlEmailBody(body: string): boolean {
  const t = body.trim().toLowerCase();
  return t.startsWith("<!doctype") || t.startsWith("<html");
}

function htmlToPlainText(html: string): string {
  return html
    .replace(/<style[\s\S]*?<\/style>/gi, "")
    .replace(/<script[\s\S]*?<\/script>/gi, "")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p>/gi, "\n\n")
    .replace(/<\/tr>/gi, "\n")
    .replace(/<\/h[1-6]>/gi, "\n\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

/**
 * Sender e-post som [mailbox] via Graph sendMail.
 * Krever Application permission Mail.Send + admin consent.
 */
export async function sendViaGraph(
  cfg: GraphSendConfig,
  to: string,
  subject: string,
  body: string,
): Promise<{ ok: true } | { ok: false; error: string }> {
  const email = to.trim().toLowerCase();
  if (!email || !email.includes("@")) {
    return { ok: false, error: "Ugyldig mottakeradresse" };
  }

  if (cfg.test) {
    return { ok: true };
  }

  const html = isHtmlEmailBody(body);
  const content = html ? body : body;
  const contentType = html ? "HTML" : "Text";

  // Graph sendMail expects HTML or Text; for HTML also include plain in body only as HTML content.
  const message: Record<string, unknown> = {
    subject: subject.trim() || "(uten emne)",
    body: {
      contentType,
      content: html ? content : (content || htmlToPlainText(content)),
    },
    toRecipients: [
      {
        emailAddress: {
          address: email,
        },
      },
    ],
    from: {
      emailAddress: {
        address: cfg.mailbox,
        name: cfg.fromName,
      },
    },
  };

  if (cfg.replyTo) {
    message.replyTo = [
      {
        emailAddress: {
          address: cfg.replyTo,
        },
      },
    ];
  }

  try {
    const token = await getGraphAccessToken();
    const mailbox = encodeURIComponent(cfg.mailbox);
    const res = await fetch(
      `https://graph.microsoft.com/v1.0/users/${mailbox}/sendMail`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message,
          saveToSentItems: true,
        }),
      },
    );

    if (res.status === 202 || res.status === 200) {
      return { ok: true };
    }

    const errText = await res.text().catch(() => "");
    let detail = errText.slice(0, 400);
    try {
      const j = JSON.parse(errText) as {
        error?: { message?: string; code?: string };
      };
      detail = j.error?.message || j.error?.code || detail;
    } catch {
      // keep raw
    }
    return {
      ok: false,
      error: `Graph sendMail ${res.status}: ${detail}`.slice(0, 500),
    };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return { ok: false, error: msg.slice(0, 500) };
  }
}
