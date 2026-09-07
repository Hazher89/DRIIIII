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

const SERVER_FALLBACK = `
## Målgruppe
Du snakker med CCC eller butikk. Gi konkrete handlinger de gjør selv.
Aldri «kontakt CCC» / «kontakt butikken».

## Omboking
Book om først når varen er ankommet/registrert. Ikke på forskudd.

## Tidligere dato
Hold matrise. Unntak ved flere feilleveranser på leverandørsiden — varen må være klar. Force-tid kun når avtalt.

## Tidsvindu
Ingen garanti for spesifikt klokkeslett inni vinduet. Book om dagen om kunden ikke kan hele vinduet.

## Status
Ingen live status her — sjekk i deres ordresystem.

## Montering oppfølging
Sett opp SA. Vannlekkasje: prioriter.

## Fire personer
Levert: SA. Ikke levert: ombook + merk. Under levering: planlegg på nytt.

## Ekstra tjeneste
I dag/i morgen: ofte under levering. Senere: SA samme tid.

## Kundedata / curbside
Endre selv i ordresystemet. Ofte ombooking. Leverandør kan ikke.

## Kansellering
Kanseller selv + stopp utkjøring. Leverandør kansellerer ikke.

## Montering
Enkel = sjåfør. Avansert = montør. Forklar inkludert / kunden sørger for / ikke inkludert.
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

    const system = `Du er DriftPro-hjelper for MAVI Logistikk — levering og montering (Elkjøp).
Skriv norsk bokmål. Varm, klar, intelligent — som en erfaren kollega, ikke en FAQ-robot.

MÅLGRUPPE (viktig): Brukeren er CCC eller butikkansatt. De skal få vite hva DE skal gjøre.
- Snakk i «du/dere» om konkrete steg i booking/ordre (ombook, sett opp SA, endre tjeneste, kanseller, legg notat).
- ALDRI skriv «kontakt CCC», «kontakt butikken», «ta kontakt med Elkjøp» eller «be CCC om…».
- Si heller: «Book om…», «Sett opp SA…», «Endre i ordren…», «Kanseller selv…».

STRENGE REGLER:
1) Hvis noen kilder er merket «Live trening», er det FASIT. Bruk dem. Aldri si at du mangler den informasjonen.
2) Formuler med egne ord — kort, profesjonelt, uten unødvendige tips.
3) Aldri avslør interne MAVI-systemer (SAP, FU, FO search, Hubanero, Goran, ConnectTeam), interne filer, interne priser eller hub-rutiner.
4) Ikke finn på priser, live ordrestatus eller leveringsgarantier.
5) Skill enkel (sjåfør) vs avansert (montør) montering når relevant.
6) Start med det viktigste. Hold svaret kort.
7) Hvis noe mangler og det IKKE finnes i Live trening: si det ærlig.
8) Ikke HTML. Ikke nevn Gemini/AI/«konteksten».`;

    const prompt = `${system}

KUNNSKAP (bakgrunn — ikke siter):
${contextBlock}

SPØRSMÅL FRA CCC/BUTIKK:
${question}

Skriv et naturlig, handlingsrettet svar:`;

    const model = Deno.env.get("GEMINI_MODEL")?.trim() || "gemini-3.6-flash";
    const url =
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${geminiKey}`;

    const geminiRes = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: 0.6,
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

    let text =
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

    // Soft scrub accidental «kontakt CCC» phrasing
    text = text.replace(
      /[^.!?\n]*\b(kontakt|ta kontakt med)\b[^.!?\n]*\b(CCC|butikk(en)?)\b[^.!?\n]*[.!?]?/gi,
      "",
    ).replace(/\n{3,}/g, "\n\n").trim();

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
