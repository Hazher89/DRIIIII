/** Profesjonell DriftPro / MAVI HTML-ramme rundt alle utgående e-poster. */

const BRAND_GREEN = "#217346";
const BRAND_DARK = "#0f3d28";
const MUTED = "#5f6b66";
const BORDER = "#e2ebe6";
const BG = "#f4f7f5";

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function isAlreadyBranded(html: string): boolean {
  return html.includes('data-driftpro-mail="1"') ||
    html.includes("data-driftpro-mail='1'");
}

function isHtmlEmailBody(body: string): boolean {
  const t = body.trim().toLowerCase();
  return t.startsWith("<!doctype") || t.startsWith("<html") ||
    t.includes("<body") || t.includes("<p>") || t.includes("<div");
}

function plainToHtmlBlocks(text: string): string {
  const escaped = escapeHtml(text.trim());
  if (!escaped) return "<p style=\"margin:0;color:#1a1a1a;\">—</p>";
  return escaped
    .split(/\n{2,}/)
    .map((para) => {
      const withBreaks = para.replace(/\n/g, "<br/>");
      return `<p style="margin:0 0 14px 0;color:#1a1a1a;font-size:15px;line-height:1.55;">${withBreaks}</p>`;
    })
    .join("");
}

function extractInnerContent(html: string): string {
  const bodyMatch = /<body[^>]*>([\s\S]*)<\/body>/i.exec(html);
  if (bodyMatch?.[1]) return bodyMatch[1].trim();
  return html.trim();
}

export type BrandEmailOptions = {
  subject?: string;
  preheader?: string;
  fromLabel?: string;
  footerNote?: string;
};

/**
 * Pakker plain text eller eksisterende HTML i DriftPro-design.
 * Idempotent: hopper over hvis allerede merket.
 */
export function wrapDriftProEmailHtml(
  body: string,
  opts: BrandEmailOptions = {},
): string {
  const raw = (body ?? "").trim();
  if (!raw) return raw;
  if (isHtmlEmailBody(raw) && isAlreadyBranded(raw)) return raw;

  const inner = isHtmlEmailBody(raw)
    ? extractInnerContent(raw)
    : plainToHtmlBlocks(raw);

  const subject = (opts.subject ?? "").trim();
  const preheader = (opts.preheader ?? subject).trim();
  const fromLabel = (opts.fromLabel ?? "DriftPro · MAVI Logistikk").trim();
  const footerNote = (opts.footerNote ??
    "Denne e-posten er sendt automatisk fra DriftPro. Svar ikke direkte på denne adressen med mindre annet er oppgitt.")
    .trim();

  const titleBlock = subject
    ? `<h1 style="margin:0 0 6px 0;font-size:20px;line-height:1.3;color:${BRAND_DARK};font-weight:700;">${escapeHtml(subject)}</h1>`
    : "";

  return `<!DOCTYPE html>
<html lang="nb">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>${escapeHtml(subject || "DriftPro")}</title>
</head>
<body data-driftpro-mail="1" style="margin:0;padding:0;background:${BG};font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">
    ${escapeHtml(preheader)}
  </div>
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:${BG};padding:28px 12px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:640px;background:#ffffff;border-radius:16px;overflow:hidden;border:1px solid ${BORDER};box-shadow:0 8px 28px rgba(15,61,40,0.08);">
          <tr>
            <td style="background:linear-gradient(135deg,${BRAND_DARK} 0%,${BRAND_GREEN} 100%);padding:22px 28px;">
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                <tr>
                  <td style="color:#ffffff;font-size:13px;letter-spacing:0.08em;text-transform:uppercase;font-weight:700;">
                    DriftPro
                  </td>
                  <td align="right" style="color:rgba(255,255,255,0.85);font-size:12px;font-weight:600;">
                    MAVI Logistikk
                  </td>
                </tr>
              </table>
              <div style="margin-top:10px;color:rgba(255,255,255,0.92);font-size:14px;font-weight:500;">
                ${escapeHtml(fromLabel)}
              </div>
            </td>
          </tr>
          <tr>
            <td style="padding:28px 28px 8px 28px;">
              ${titleBlock}
              <div style="height:3px;width:48px;background:${BRAND_GREEN};border-radius:2px;margin:12px 0 20px 0;"></div>
              <div style="color:#1a1a1a;">
                ${inner}
              </div>
            </td>
          </tr>
          <tr>
            <td style="padding:8px 28px 28px 28px;">
              <div style="border-top:1px solid ${BORDER};padding-top:18px;color:${MUTED};font-size:12px;line-height:1.5;">
                ${escapeHtml(footerNote)}
                <div style="margin-top:10px;font-weight:600;color:${BRAND_GREEN};">
                  driftpro.no · mavilogistikk.no
                </div>
              </div>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}
