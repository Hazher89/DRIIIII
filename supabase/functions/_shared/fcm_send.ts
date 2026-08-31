export type FcmServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

export type FcmMessage = {
  token: string;
  title: string;
  body: string;
  data?: Record<string, unknown> | null;
};

let cachedToken: { value: string; expiresAt: number } | null = null;

function base64UrlEncode(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const pemContents = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const binary = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    binary,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

async function signJwt(account: FcmServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlEncode(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = base64UrlEncode(JSON.stringify({
    iss: account.client_email,
    sub: account.client_email,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  }));
  const unsigned = `${header}.${payload}`;
  const key = await importPrivateKey(account.private_key);
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  return `${unsigned}.${base64UrlEncode(new Uint8Array(signature))}`;
}

export function parseServiceAccount(raw: string | undefined): FcmServiceAccount | null {
  if (!raw?.trim()) return null;
  try {
    const parsed = JSON.parse(raw) as FcmServiceAccount;
    if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
}

function asStringData(data: Record<string, unknown> | null | undefined): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [key, value] of Object.entries(data ?? {})) {
    if (value == null) continue;
    out[key] = typeof value === "string" ? value : JSON.stringify(value);
  }
  return out;
}

async function getAccessToken(account: FcmServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt > now + 60) {
    return cachedToken.value;
  }

  const assertion = await signJwt(account);
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  const payload = await res.json().catch(() => ({}));
  if (!res.ok || !payload.access_token) {
    throw new Error(payload.error_description ?? payload.error ?? "Kunne ikke hente FCM access token");
  }

  cachedToken = {
    value: payload.access_token,
    expiresAt: now + Number(payload.expires_in ?? 3600),
  };
  return payload.access_token;
}

export async function sendFcmV1(
  account: FcmServiceAccount,
  message: FcmMessage,
): Promise<{ ok: true } | { ok: false; error: string }> {
  const accessToken = await getAccessToken(account);
  const data = {
    ...asStringData(message.data),
    title: message.title,
    body: message.body,
  };

  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: message.token,
          notification: {
            title: message.title,
            body: message.body,
          },
          data,
          apns: {
            payload: {
              aps: {
                sound: "default",
              },
            },
          },
        },
      }),
    },
  );

  const payload = await res.json().catch(() => ({}));
  if (res.ok) return { ok: true };

  const err = payload.error?.message ?? JSON.stringify(payload);
  return { ok: false, error: String(err) };
}

export async function sendFcmLegacy(
  serverKey: string,
  message: FcmMessage,
): Promise<{ ok: true } | { ok: false; error: string }> {
  const res = await fetch("https://fcm.googleapis.com/fcm/send", {
    method: "POST",
    headers: {
      Authorization: `key=${serverKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      to: message.token,
      priority: "high",
      notification: {
        title: message.title,
        body: message.body,
        sound: "default",
      },
      data: {
        ...asStringData(message.data),
        title: message.title,
        body: message.body,
      },
    }),
  });

  const payload = await res.json().catch(() => ({}));
  const ok = res.ok && (payload?.success === 1 || payload?.success === undefined);
  if (ok) return { ok: true };

  const err = payload?.results?.[0]?.error ?? JSON.stringify(payload);
  return { ok: false, error: String(err) };
}
