/** Microsoft Graph client-credentials for DriftPro mailbox sync. */

export type GraphToken = {
  accessToken: string;
  expiresAtMs: number;
};

let cached: GraphToken | null = null;

function requireEnv(name: string): string {
  const v = Deno.env.get(name)?.trim();
  if (!v) throw new Error(`Mangler secret: ${name}`);
  return v;
}

export function graphMailbox(): string {
  return (
    Deno.env.get("MS_GRAPH_MAILBOX")?.trim() ||
    "driftpro@mavilogistikk.no"
  ).toLowerCase();
}

export async function getGraphAccessToken(): Promise<string> {
  const now = Date.now();
  if (cached && cached.expiresAtMs > now + 60_000) {
    return cached.accessToken;
  }

  const tenantId = requireEnv("MS_GRAPH_TENANT_ID");
  const clientId = requireEnv("MS_GRAPH_CLIENT_ID");
  const clientSecret = requireEnv("MS_GRAPH_CLIENT_SECRET");

  const body = new URLSearchParams({
    client_id: clientId,
    client_secret: clientSecret,
    scope: "https://graph.microsoft.com/.default",
    grant_type: "client_credentials",
  });

  const res = await fetch(
    `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/token`,
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body,
    },
  );
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`Graph token ${res.status}: ${t.slice(0, 400)}`);
  }
  const json = await res.json() as {
    access_token?: string;
    expires_in?: number;
  };
  if (!json.access_token) {
    throw new Error("Graph token mangler access_token");
  }
  cached = {
    accessToken: json.access_token,
    expiresAtMs: now + (json.expires_in ?? 3600) * 1000,
  };
  return cached.accessToken;
}

export async function graphFetch(
  path: string,
  init: RequestInit = {},
): Promise<Response> {
  const token = await getGraphAccessToken();
  const url = path.startsWith("http")
    ? path
    : `https://graph.microsoft.com/v1.0${path}`;
  const headers = new Headers(init.headers);
  headers.set("Authorization", `Bearer ${token}`);
  if (!headers.has("Content-Type") && init.body) {
    headers.set("Content-Type", "application/json");
  }
  return fetch(url, { ...init, headers });
}
