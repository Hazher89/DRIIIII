export type ResendSendConfig = {
  apiKey: string;
  from: string;
  fromName: string;
  replyTo?: string;
  test: boolean;
};

export function readResendSendConfig():
  | ResendSendConfig
  | { error: string } {
  const apiKey = Deno.env.get("RESEND_API_KEY")?.trim();
  if (!apiKey) {
    return { error: "Mangler RESEND_API_KEY" };
  }

  const from =
    Deno.env.get("RESEND_FROM")?.trim() ||
    Deno.env.get("SMTP_FROM")?.trim() ||
    "ikkesvar@driftpro.no";
  const fromName =
    Deno.env.get("RESEND_FROM_NAME")?.trim() ||
    Deno.env.get("SMTP_FROM_NAME")?.trim() ||
    "DriftPro";
  const test = (Deno.env.get("EMAIL_TEST") ?? "").toLowerCase() === "true";
  const replyTo = Deno.env.get("RESEND_REPLY_TO")?.trim() ||
    Deno.env.get("SMTP_REPLY_TO")?.trim();

  return {
    apiKey,
    from,
    fromName,
    replyTo: replyTo || undefined,
    test,
  };
}

type ResendErrorBody = {
  message?: string;
  name?: string;
};

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

export async function sendViaResend(
  cfg: ResendSendConfig,
  to: string,
  subject: string,
  text: string,
): Promise<{ ok: true; id?: string } | { ok: false; error: string }> {
  const email = to.trim().toLowerCase();
  if (!email || !email.includes("@")) {
    return { ok: false, error: "Ugyldig mottakeradresse" };
  }

  if (cfg.test) {
    return { ok: true, id: "test-mode" };
  }

  const payload: Record<string, unknown> = {
    from: `"${cfg.fromName}" <${cfg.from}>`,
    to: [email],
    subject: subject.trim(),
  };
  if (isHtmlEmailBody(text)) {
    payload.html = text;
    payload.text = htmlToPlainText(text);
  } else {
    payload.text = text;
  }
  if (cfg.replyTo) {
    payload.reply_to = cfg.replyTo;
  }

  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${cfg.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    const body = await res.json().catch(() => ({})) as
      | { id?: string }
      | ResendErrorBody;

    if (!res.ok) {
      const err = (body as ResendErrorBody).message ||
        (body as ResendErrorBody).name ||
        `Resend HTTP ${res.status}`;
      return { ok: false, error: String(err).slice(0, 500) };
    }

    return { ok: true, id: (body as { id?: string }).id };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return { ok: false, error: msg.slice(0, 500) };
  }
}
