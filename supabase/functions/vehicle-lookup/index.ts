// Vegvesen kjøretøyoppslag — krever secret VEGVESEN_API_KEY i Supabase
// Bestill nøkkel: https://www.vegvesen.no/fag/teknologi/apne-data/

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

function normalizePlate(raw: string): string {
  return raw.replace(/\s/g, "").toUpperCase();
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const apiKey = Deno.env.get("VEGVESEN_API_KEY");
  if (!apiKey) {
    return json({
      error: "VEGVESEN_API_KEY ikke satt i Supabase secrets",
      configured: false,
    }, 503);
  }

  let plate = "";
  try {
    const body = await req.json();
    plate = normalizePlate(String(body?.registration_number ?? body?.plate ?? ""));
  } catch {
    return json({ error: "Ugyldig JSON" }, 400);
  }

  if (plate.length < 2) {
    return json({ error: "Mangler registreringsnummer" }, 400);
  }

  const url =
    `https://akfell-datautlevering.atlas.vegvesen.no/kjoretoyopplysninger-api/api/v1/detaljer/kjennemerke/${encodeURIComponent(plate)}`;

  try {
    const res = await fetch(url, {
      headers: {
        "SVV-Authorization": `Apikey ${apiKey}`,
        Accept: "application/json",
      },
    });

    if (!res.ok) {
      const t = await res.text();
      return json({
        error: `Vegvesen ${res.status}`,
        detail: t.slice(0, 500),
        configured: true,
      }, res.status === 404 ? 404 : 502);
    }

    const data = await res.json();
    const kjoretoy = data?.kjoretoydata?.[0] ?? data?.kjoretoydataListe?.[0] ?? data;
    const tekn = kjoretoy?.godkjenning?.tekniskGodkjenning?.tekniskeData
      ?? kjoretoy?.tekniskeData
      ?? {};
    const dim = tekn?.dimensjoner ?? tekn?.vekter ?? {};
    const eu = kjoretoy?.periodiskKjoretoyKontroll
      ?? kjoretoy?.godkjenning?.tekniskGodkjenning?.kjoretoyklassifisering;

    const payloadKg =
      dim?.nyttelast ??
      dim?.tillattTotalvekt ??
      tekn?.vekter?.nyttelast ??
      null;

    const modelYear =
      kjoretoy?.forstegangsregistrering?.registrertForstegangNorgeDato
        ? parseInt(String(kjoretoy.forstegangsregistrering.registrertForstegangNorgeDato).slice(0, 4), 10)
        : kjoretoy?.registrering?.forstegangsregistrertDato
          ? parseInt(String(kjoretoy.registrering.forstegangsregistrertDato).slice(0, 4), 10)
          : null;

    const euNext =
      eu?.kontrollfrist ??
      kjoretoy?.periodiskKjoretoyKontroll?.kontrollfrist ??
      null;

    const euLast =
      eu?.sistGodkjent ??
      kjoretoy?.periodiskKjoretoyKontroll?.sistGodkjent ??
      null;

    return json({
      configured: true,
      registration_number: plate,
      model_year: modelYear,
      payload_kg: typeof payloadKg === "number" ? payloadKg : parseInt(String(payloadKg ?? ""), 10) || null,
      eu_next_at: euNext ? String(euNext).slice(0, 10) : null,
      eu_last_at: euLast ? String(euLast).slice(0, 10) : null,
      make: kjoretoy?.godkjenning?.tekniskGodkjenning?.tekniskeData?.generelt?.merke?.[0]?.merke
        ?? kjoretoy?.kjennemerke?.[0]?.kjoretoymerke,
      model: kjoretoy?.godkjenning?.tekniskGodkjenning?.tekniskeData?.generelt?.handelsbetegnelse?.[0],
      raw: data,
    });
  } catch (e) {
    return json({ error: String(e), configured: true }, 500);
  }
});
