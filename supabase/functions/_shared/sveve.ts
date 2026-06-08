export const SVEVE_ENDPOINT = "https://sveve.no/SMS/SendMessage";

export type SveveResponse = {
  response?: {
    msgOkCount?: number;
    fatalError?: string;
    errors?: Array<{ number?: string; message?: string }>;
    ids?: number[];
  };
};

export type SveveConfig = {
  user: string;
  passwd: string;
  from: string;
  test: boolean;
};

export function readSveveConfig(): SveveConfig | { error: string } {
  const user = Deno.env.get("SVEVE_USER");
  const passwd = Deno.env.get("SVEVE_PASSWD");
  if (!user || !passwd) {
    return { error: "Mangler SVEVE_USER eller SVEVE_PASSWD i Edge Function-secrets" };
  }
  return {
    user,
    passwd,
    from: (Deno.env.get("SVEVE_FROM") ?? "MAVI").slice(0, 11),
    test: Deno.env.get("SVEVE_TEST") === "true",
  };
}

export async function sendViaSveve(
  user: string,
  passwd: string,
  to: string,
  msg: string,
  from: string,
  test: boolean,
): Promise<{ ok: boolean; id?: number; error?: string }> {
  const res = await fetch(SVEVE_ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=utf-8" },
    body: JSON.stringify({ user, passwd, to, msg, from, f: "json", test }),
  });

  const text = await res.text();
  let parsed: SveveResponse;
  try {
    parsed = JSON.parse(text) as SveveResponse;
  } catch {
    return { ok: false, error: `Ugyldig Sveve-svar (${res.status}): ${text.slice(0, 200)}` };
  }

  const r = parsed.response;
  if (r?.fatalError) return { ok: false, error: r.fatalError };
  if (r?.errors?.length) {
    return { ok: false, error: r.errors.map((e) => e.message).filter(Boolean).join("; ") };
  }
  if ((r?.msgOkCount ?? 0) > 0) return { ok: true, id: r.ids?.[0] };
  return { ok: false, error: "Ingen melding sendt (msgOkCount=0)" };
}
