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
## Oversikt
MAVI utfører Elkjöp monteringstjenester hos kunden.
Enkle: sjåfør ved levering. Avanserte: MAVI ved levering, eller 0–5 dager (Bring); montør ringer innen kl. 20 samme dag.

## InstallWash (enkel)
Inkludert: frakople, emballasje, plassering, vann/avløp, strøm, vater, funksjonstest, retur emballasje.
Kunde: plass klar, maks 1,2 m til strøm/vann/avløp, godkjent våtrom.
Ikke: vibrasjonsdempere/stableramme, skjøting, fagperson-installasjon.

## InstallCooker (enkel)
Inkludert: frakople, plassering, støpsel (ikke 4/5 ledere), strøm, høydejustering, funksjonstest 100°, emballasje.
Kunde: plass, høyde, maks 0,5 m til strøm.
Ikke: gasskomfyr.

## InstallFridge/Freezer enkel (ikke SBS)
Inkludert: frakople, plassering, strøm kun med av/på-knapp, info om 3 timer, justering, emballasje.
Ikke: omhengsling, funksjonstest, strøm uten av/på.

## TVonStand (enkel)
Inkludert: fot, plassering, inntil 3 eksisterende komponenter, strøm, funksjonstest skjerm.
Ikke: vegg, WIFI/kanalsøk, skjule kabler, nye komponenter.

## TVonWall (avansert)
Inkludert: utpakking, inntil 3 eksisterende komponenter, veggmontering, funksjonstest.
Kunde: bæring i vegg, veggfeste separat om ikke inkludert.
Ikke: WIFI/kanalsøk, skjule kabler, veggforsterkning.

## InstallSBS / Dish / Hood / Micro / Hob / Oven / Fridge front / TurnDoor
Se klient-kontekst for detaljer. Ikke finn på utover dette.
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
        .slice(0, 8)
        .map((c, i) => {
          const title = String(c.title ?? `Kilde ${i + 1}`);
          const source = String(c.source ?? "Montering");
          const text = String(c.body ?? "").slice(0, 1800);
          return `### ${title} (${source})\n${text}`;
        })
        .join("\n\n") || SERVER_FALLBACK;

    const system = `Du er DriftPros offentlige monteringshjelper for MAVI Logistikk.
Svar på norsk (bokmål), vennlig og lett forståelig — som en dyktig kundeservice.
Du svarer KUN om Elkjöp/MAVI monteringstjenester hos kunden (inkludert / kunden sørger for / ikke inkludert, enkel vs avansert, når montør ringer).
Regler:
1) Svar direkte på spørsmålet først.
2) Bruk KUN konteksten. Finn ikke på priser, booking, ordrestatus eller intern DriftPro-info (HMS, fravær, ansatte).
3) Skill tydelig mellom enkle (sjåfør) og avanserte (montør) tjenester når relevant.
4) Hvis noe mangler i konteksten: si det ærlig og foreslå å spørre butikken der kunden handlet.
5) Ikke HTML. Ikke nevn Gemini eller AI-modellen.`;

    const prompt = `${system}

KONTEKST:
${contextBlock}

SPØRSMÅL FRA BESØKENDE:
${question}

SVAR:`;

    const model = Deno.env.get("GEMINI_MODEL")?.trim() || "gemini-2.0-flash";
    const url =
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${geminiKey}`;

    const geminiRes = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: 0.2,
          maxOutputTokens: 1200,
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
