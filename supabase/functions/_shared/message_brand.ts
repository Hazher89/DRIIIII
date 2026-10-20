/** Felles merkevare for SMS og e-posttekst. */

export const BRAND_LABEL = "MAVI/DriftPro";

/** SMS-avsender hos Sveve (maks 11 tegn). */
export const SMS_FROM = "MAVI";

/** Sikrer at SMS alltid starter med MAVI/DriftPro. */
export function brandSmsMessage(message: string): string {
  const t = (message ?? "").trim();
  if (!t) return t;

  if (/^mavi\s*\/\s*driftpro\b/i.test(t)) {
    return t.replace(/^mavi\s*\/\s*driftpro\b\s*:?\s*/i, `${BRAND_LABEL}: `);
  }
  if (/^driftpro\b\s*:/i.test(t)) {
    return t.replace(/^driftpro\b\s*:\s*/i, `${BRAND_LABEL}: `);
  }
  if (/^mavi\b\s*:/i.test(t) && !/^mavi\s*\/\s*driftpro/i.test(t)) {
    return t.replace(/^mavi\b\s*:\s*/i, `${BRAND_LABEL}: `);
  }
  return `${BRAND_LABEL}: ${t}`;
}
