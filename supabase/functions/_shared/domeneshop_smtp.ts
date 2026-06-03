import nodemailer from "npm:nodemailer@6.9.16";

export type SmtpConfig = {
  host: string;
  port: number;
  user: string;
  pass: string;
  from: string;
  fromName: string;
  test: boolean;
};

export function readSmtpConfig(): SmtpConfig | { error: string } {
  const user = Deno.env.get("SMTP_USER")?.trim();
  const pass = Deno.env.get("SMTP_PASS")?.trim();
  if (!user || !pass) {
    return { error: "Mangler SMTP_USER / SMTP_PASS (ikkesvar@driftpro.no)" };
  }

  const from = Deno.env.get("SMTP_FROM")?.trim() || user;
  const fromName = Deno.env.get("SMTP_FROM_NAME")?.trim() || "DriftPro";
  const test = (Deno.env.get("EMAIL_TEST") ?? "").toLowerCase() === "true";

  return {
    host: Deno.env.get("SMTP_HOST")?.trim() || "smtp.domeneshop.no",
    port: Number(Deno.env.get("SMTP_PORT")?.trim() || "587"),
    user,
    pass,
    from,
    fromName,
    test,
  };
}

export async function sendViaSmtp(
  cfg: SmtpConfig,
  to: string,
  subject: string,
  text: string,
): Promise<{ ok: true } | { ok: false; error: string }> {
  if (cfg.test) {
    return { ok: true };
  }

  const transporter = nodemailer.createTransport({
    host: cfg.host,
    port: cfg.port,
    secure: cfg.port === 465,
    requireTLS: cfg.port === 587,
    auth: { user: cfg.user, pass: cfg.pass },
    connectionTimeout: 20_000,
    greetingTimeout: 20_000,
  });

  try {
    await transporter.sendMail({
      from: `"${cfg.fromName}" <${cfg.from}>`,
      to: to.trim().toLowerCase(),
      subject: subject.trim(),
      text: text,
      replyTo: Deno.env.get("SMTP_REPLY_TO")?.trim() || undefined,
    });
    return { ok: true };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return { ok: false, error: msg.slice(0, 500) };
  } finally {
    try {
      transporter.close();
    } catch {
      /* ignore */
    }
  }
}
