import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type ContextChunk = {
  title?: string;
  source?: string;
  body?: string;
};

/** Enkel in-memory rate limit per IP (soft — resettes ved cold start). */
const rateBuckets = new Map<string, { count: number; resetAt: number }>();

function rateLimited(ip: string): boolean {
  const now = Date.now();
  const windowMs = 60_000;
  const max = 30;
  const cur = rateBuckets.get(ip);
  if (!cur || now > cur.resetAt) {
    rateBuckets.set(ip, { count: 1, resetAt: now + windowMs });
    return false;
  }
  cur.count += 1;
  return cur.count > max;
}

/** Fallback hvis klient ikke sender kontekster. */
const SERVER_FALLBACK = `
## Hjelp til levering og montering
Du forklarer hva kunde/butikk/CCC skal gjøre. Aldri interne MAVI-rutiner.

## Omboking
Varen må faktisk være klar/ankommet før ombooking. CCC/butikk booker om.

## Tidligere dato
Hold matrise/booking. Unntak ved gjentatte feilleveranser: via CCC, varen må være klar.

## Tidsvindu
Ingen garanti for spesifikt klokkeslett inni vinduet. Book om dagen om kunden ikke kan hele vinduet.

## Status i dag
Ingen live status her — kontakt CCC med ordrenummer.

## Montering oppfølging
Klage/ny sjekk: CCC setter opp SA. Vannlekkasje: prioriter via CCC.

## Fire personer
Etter levering: SA via CCC. Før levering: ombook og merk behov. Samme dag: ikke forvent ekstra mannskap alltid.

## Ekstra tjeneste
I dag/i morgen: kan ofte legges til under levering (betalingslenke). Senere: SA via CCC.

## Kundedata / curbside
Adresse/tlf/navn og curbside→deliverysite endres av CCC/butikk.

## Kansellering
MAVI kansellerer ikke ordre — CCC/butikk må. Be dem også stoppe utkjøring.

## Montering (kort)
Enkle: sjåfør. Avanserte: montør. Svar inkludert / kunden sørger for / ikke inkludert.
`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const ip =
      req.headers.get("cf-connecting-ip") ??
      req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
      "unknown";
    if (rateLimited(ip)) {
      return new Response(JSON.stringify({ error: "rate_limited" }), {
        status: 429,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const geminiKey = Deno.env.get("GEMINI_API_KEY")?.trim();
    if (!geminiKey) {
      return new Response(
        JSON.stringify({
          error: "gemini_not_configured",
          message: "GEMINI_API_KEY mangler.",
        }),
        {
          status: 503,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const raw = await req.text();
    if (raw.length > 48_000) {
      return new Response(JSON.stringify({ error: "payload_too_large" }), {
        status: 413,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = JSON.parse(raw);
    const question = String(body?.question ?? "").trim();
    const contexts = (Array.isArray(body?.contexts)
      ? body.contexts
      : []) as ContextChunk[];

    if (question.length < 2 || question.length > 800) {
      return new Response(JSON.stringify({ error: "invalid_question" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const contextBlock =
      contexts
        .slice(0, 10)
        .map((c, i) => {
          const title = String(c.title ?? `Kilde ${i + 1}`);
          const source = String(c.source ?? "Hjelp");
          const text = String(c.body ?? "").slice(0, 1600);
          return `### ${title} (${source})\n${text}`;
        })
        .join("\n\n") || SERVER_FALLBACK;

    const system = `Du er DriftPros offentlige hjelper for MAVI Logistikk (levering + montering for Elkjøp).
Skriv på norsk bokmål — varm, klar og intelligent, som en dyktig menneskelig kundeservice (ikke som en FAQ-robot).

MÅLGRUPPE: kunder, butikk og CCC. Du forklarer hva DE skal gjøre.

STRENGE REGLER:
1) Formuler alltid svarene med egne ord. Ikke lim inn, siter eller speil konteksttekst ordrett.
2) Bruk konteksten kun som bakgrunnskunnskap om hvordan ting fungerer.
3) Aldri avslør interne MAVI-rutiner: systemnavn (SAP, FU, FO search, Hubanero, Goran, ConnectTeam), interne filer, interne mailmapper, interne priser for ekstra mannskap, interne roller, eller hvordan hub planlegger.
4) Si heller: «kontakt butikk / Elkjøp CCC», «book om», «legg inn notat på ordren», «be om standalone service (SA)».
5) Ikke finn på priser, booking, live ordrestatus eller leveringsgarantier.
6) Skill enkel (sjåfør) vs avansert (montør) montering når relevant.
7) Start med det viktigste svaret, deretter korte, nyttige punkter om nødvendig.
8) Hvis noe mangler i konteksten: si det ærlig og foreslå butikk/CCC.
9) Ikke HTML. Ikke nevn Gemini, AI eller «konteksten».`;

    const prompt = `${system}

KUNNSKAP (bakgrunn — ikke siter ordrett):
${contextBlock}

SPØRSMÅL:
${question}

Skriv et naturlig, godt svar:`;

    const model = Deno.env.get("GEMINI_MODEL")?.trim() || "gemini-3.6-flash";
    const url =
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${geminiKey}`;

    const geminiRes = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: 0.55,
          maxOutputTokens: 1400,
          topP: 0.9,
        },
      }),
    });

    const geminiJson = await geminiRes.json();
    if (!geminiRes.ok) {
      const errMsg =
        geminiJson?.error?.message ?? `Gemini-feil (${geminiRes.status})`;
      return new Response(JSON.stringify({ error: errMsg }), {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const text =
      geminiJson?.candidates?.[0]?.content?.parts
        ?.map((p: { text?: string }) => p.text ?? "")
        .join("")
        ?.trim() ?? "";

    if (!text) {
      return new Response(JSON.stringify({ error: "empty_answer" }), {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(
      JSON.stringify({
        ok: true,
        answer: text,
        model,
        used_contexts: contexts.length,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ error: e instanceof Error ? e.message : String(e) }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
