/**
 * DriftPro e-postmal — mørk neon-vibe matching app-ikonet.
 * Kun logo: cyan neon-merke på sort.
 */

const LOGO_NEON =
  "https://ksnnyccthotjbrmgjgdc.supabase.co/storage/v1/object/public/avatars/branding/driftpro-neon-512.png";

const BLACK = "#05070A";
const SURFACE = "#0B1016";
const PANEL = "#111821";
const LINE = "#1C2A38";
const CYAN = "#00D4FF";
const CYAN_SOFT = "#7AEBFF";
const CYAN_DIM = "rgba(0,212,255,0.14)";
const WHITE = "#F4FBFF";
const MUTED = "#8AA0B2";
const AMBER = "#FFC857";
const AMBER_BG = "rgba(255,200,87,0.12)";
const RED = "#FF6B7A";
const RED_BG = "rgba(255,107,122,0.12)";
const GREEN = "#3DFFB5";
const GREEN_BG = "rgba(61,255,181,0.12)";

const FONT =
  "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif";

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function isAlreadyBranded(html: string): boolean {
  return html.includes('data-driftpro-mail="1"');
}

function isHtmlEmailBody(body: string): boolean {
  const t = body.trim().toLowerCase();
  return t.startsWith("<!doctype") || t.startsWith("<html") ||
    t.includes("<body") || t.includes("<p>") || t.includes("<div");
}

function extractInnerContent(html: string): string {
  const bodyMatch = /<body[^>]*>([\s\S]*)<\/body>/i.exec(html);
  if (bodyMatch?.[1]) return bodyMatch[1].trim();
  return html.trim();
}

type Kv = { k: string; v: string };

function parsePlain(text: string): { fields: Kv[]; notes: string[] } {
  const fields: Kv[] = [];
  const notes: string[] = [];
  for (const raw of text.split(/\n/)) {
    const line = raw.trim();
    if (!line) continue;
    if (/^åpne driftpro/i.test(line)) continue;
    const m = /^([^:\n]{2,32}):\s*(.+)$/.exec(line);
    if (m && !m[1].includes("http")) {
      const key = m[1].trim();
      const val = m[2].trim();
      if (/kommentar|merknad|beskrivelse|melding/i.test(key)) {
        notes.push(val);
      } else {
        fields.push({ k: key, v: val });
      }
      continue;
    }
    notes.push(line);
  }
  return { fields, notes };
}

function statusStyle(value: string): { bg: string; fg: string; border: string } {
  const v = value.toLowerCase();
  if (/vent|pending|ny|åpen/.test(v)) {
    return { bg: AMBER_BG, fg: AMBER, border: "rgba(255,200,87,0.35)" };
  }
  if (/godkj|approv|ok|ferdig|lukket/.test(v)) {
    return { bg: GREEN_BG, fg: GREEN, border: "rgba(61,255,181,0.35)" };
  }
  if (/avvis|reject|avslag|nek/.test(v)) {
    return { bg: RED_BG, fg: RED, border: "rgba(255,107,122,0.35)" };
  }
  return { bg: CYAN_DIM, fg: CYAN_SOFT, border: "rgba(0,212,255,0.28)" };
}

function renderContent(fields: Kv[], notes: string[]): string {
  let html = "";

  const status = fields.find((f) => /status/i.test(f.k));
  const rest = fields.filter((f) => !/status/i.test(f.k));

  if (status) {
    const s = statusStyle(status.v);
    html += `<div style="margin:0 0 28px 0;">
      <span style="display:inline-block;font-family:${FONT};font-size:11px;font-weight:700;letter-spacing:0.16em;text-transform:uppercase;color:${s.fg};background:${s.bg};border:1px solid ${s.border};padding:8px 14px;border-radius:999px;">
        ${escapeHtml(status.v)}
      </span>
    </div>`;
  }

  if (rest.length) {
    const rows = rest.map((f, i) => {
      const last = i === rest.length - 1;
      return `<tr>
        <td style="padding:16px 0 ${last ? "16px" : "16px"} 0;border-bottom:${last ? "0" : `1px solid ${LINE}`};">
          <div style="font-family:${FONT};font-size:11px;font-weight:700;letter-spacing:0.14em;text-transform:uppercase;color:${CYAN};opacity:0.75;margin:0 0 6px 0;">
            ${escapeHtml(f.k)}
          </div>
          <div style="font-family:${FONT};font-size:17px;font-weight:600;letter-spacing:-0.02em;color:${WHITE};line-height:1.35;">
            ${escapeHtml(f.v)}
          </div>
        </td>
      </tr>`;
    }).join("");
    html += `<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:${PANEL};border:1px solid ${LINE};border-radius:18px;padding:4px 20px;">
      ${rows}
    </table>`;
  }

  for (const note of notes) {
    html += `<div style="margin:22px 0 0 0;padding:18px 20px;background:${CYAN_DIM};border:1px solid rgba(0,212,255,0.28);border-radius:18px;font-family:${FONT};">
      <div style="font-size:11px;font-weight:700;letter-spacing:0.14em;text-transform:uppercase;color:${CYAN};margin:0 0 8px 0;">Kommentar</div>
      <div style="font-size:15px;line-height:1.6;color:${WHITE};">
        ${escapeHtml(note).replace(/\n/g, "<br/>")}
      </div>
    </div>`;
  }

  return html ||
    `<p style="margin:0;font-family:${FONT};color:${MUTED};">—</p>`;
}

export type BrandEmailOptions = {
  subject?: string;
  preheader?: string;
  fromLabel?: string;
  footerNote?: string;
};

export function wrapDriftProEmailHtml(
  body: string,
  opts: BrandEmailOptions = {},
): string {
  const raw = (body ?? "").trim();
  if (!raw) return raw;
  if (isHtmlEmailBody(raw) && isAlreadyBranded(raw)) return raw;

  const subject = (opts.subject ?? "").trim() || "Varsel";
  const preheader = (opts.preheader ?? subject).trim();
  const footerNote = (opts.footerNote ??
    "Automatisk melding fra MAVI/DriftPro. Du trenger ikke svare på denne e-posten.")
    .trim();

  let content: string;
  if (isHtmlEmailBody(raw)) {
    content = extractInnerContent(raw);
  } else {
    const { fields, notes } = parsePlain(raw);
    content = renderContent(fields, notes);
  }

  return `<!DOCTYPE html>
<html lang="nb">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <meta name="color-scheme" content="dark"/>
  <meta name="supported-color-schemes" content="dark"/>
  <title>${escapeHtml(subject)}</title>
  <style>
    :root { color-scheme: dark; }
  </style>
</head>
<body data-driftpro-mail="1" style="margin:0;padding:0;background:${BLACK};">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;">
    ${escapeHtml(preheader)}
  </div>

  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:${BLACK};">
    <tr>
      <td align="center" style="padding:0;">

        <!-- Top glow bar -->
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
          <tr>
            <td style="height:3px;background:linear-gradient(90deg,#003847 0%,${CYAN} 50%,#003847 100%);font-size:0;line-height:0;">&nbsp;</td>
          </tr>
        </table>

        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:600px;">
          <tr>
            <td align="center" style="padding:40px 24px 8px 24px;">
              <img src="${LOGO_NEON}" width="88" height="88" alt="DriftPro" style="display:block;width:88px;height:88px;border:0;border-radius:22px;box-shadow:0 0 40px rgba(0,212,255,0.35);"/>
              <div style="font-family:${FONT};margin-top:18px;font-size:22px;font-weight:750;letter-spacing:0.18em;text-transform:uppercase;color:${WHITE};">
                Drift<span style="color:${CYAN};">Pro</span>
              </div>
              <div style="font-family:${FONT};margin-top:6px;font-size:12px;font-weight:600;letter-spacing:0.22em;text-transform:uppercase;color:${MUTED};">
                MAVI Logistikk
              </div>
            </td>
          </tr>

          <tr>
            <td style="padding:20px 20px 8px 20px;">
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:${SURFACE};border:1px solid ${LINE};border-radius:24px;overflow:hidden;">
                <!-- Cyan edge -->
                <tr>
                  <td style="height:2px;background:linear-gradient(90deg,transparent 0%,${CYAN} 40%,${CYAN_SOFT} 50%,${CYAN} 60%,transparent 100%);font-size:0;line-height:0;">&nbsp;</td>
                </tr>
                <tr>
                  <td style="padding:32px 28px 8px 28px;font-family:${FONT};">
                    <div style="font-size:11px;font-weight:700;letter-spacing:0.2em;text-transform:uppercase;color:${CYAN};margin:0 0 12px 0;">
                      Systemvarsel
                    </div>
                    <h1 style="margin:0;font-size:28px;line-height:1.2;font-weight:750;letter-spacing:-0.03em;color:${WHITE};">
                      ${escapeHtml(subject)}
                    </h1>
                  </td>
                </tr>
                <tr>
                  <td style="padding:24px 28px 8px 28px;font-family:${FONT};">
                    ${content}
                  </td>
                </tr>
                <tr>
                  <td style="padding:28px 28px 32px 28px;font-family:${FONT};">
                    <a href="https://driftpro.no" style="display:block;background:${CYAN};color:${BLACK};text-decoration:none;font-size:16px;font-weight:800;letter-spacing:0.04em;text-transform:uppercase;padding:16px 20px;border-radius:14px;text-align:center;box-shadow:0 0 28px rgba(0,212,255,0.45);">
                      Åpne DriftPro
                    </a>
                    <div style="margin-top:14px;text-align:center;font-size:12px;letter-spacing:0.08em;color:${MUTED};">
                      driftpro.no
                    </div>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <tr>
            <td align="center" style="padding:28px 28px 48px 28px;font-family:${FONT};font-size:12px;line-height:1.6;color:${MUTED};">
              ${escapeHtml(footerNote)}<br/>
              <span style="color:${CYAN};font-weight:700;letter-spacing:0.08em;">MAVI / DriftPro</span>
            </td>
          </tr>
        </table>

      </td>
    </tr>
  </table>
</body>
</html>`;
}
