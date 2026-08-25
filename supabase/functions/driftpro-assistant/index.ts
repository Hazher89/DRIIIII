import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const geminiKey = Deno.env.get("GEMINI_API_KEY")?.trim();
    if (!geminiKey) {
      return new Response(
        JSON.stringify({
          error: "gemini_not_configured",
          message: "GEMINI_API_KEY mangler i Edge Function secrets.",
        }),
        {
          status: 503,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const authHeader = req.headers.get("Authorization") ?? "";

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData.user) {
      return new Response(JSON.stringify({ error: "Ikke innlogget" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await req.json();
    const question = String(body?.question ?? "").trim();
    const contexts = (Array.isArray(body?.contexts) ? body.contexts : []) as ContextChunk[];

    if (question.length < 2) {
      return new Response(JSON.stringify({ error: "Spørsmål mangler" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const contextBlock = contexts
      .slice(0, 8)
      .map((c, i) => {
        const title = String(c.title ?? `Kilde ${i + 1}`);
        const source = String(c.source ?? "DriftPro");
        const text = String(c.body ?? "").slice(0, 1800);
        return `### ${title} (${source})\n${text}`;
      })
      .join("\n\n");

    const system = `Du er DriftPro-assistent for MAVI Logistikk.
Svar på norsk (bokmål), kort og konkret.
Bruk KUN informasjonen i KONTEKST nedenfor (SOP/opplæring, bilutleie, hjelpetekster).
Hvis svaret ikke finnes i konteksten: si ærlig at du ikke fant det i DriftPros dokumentasjon, og foreslå support (hazher@mavilogistikk.no).
Ikke finn på regler. Ikke nevn at du er Gemini med mindre brukeren spør.`;

    const prompt = `${system}

KONTEKST:
${contextBlock || "(ingen treff)"}

SPØRSMÅL FRA ANSATT:
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
          maxOutputTokens: 1024,
        },
      }),
    });

    const geminiJson = await geminiRes.json();
    if (!geminiRes.ok) {
      const errMsg =
        geminiJson?.error?.message ??
        `Gemini-feil (${geminiRes.status})`;
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
      return new Response(
        JSON.stringify({ error: "Tomt svar fra Gemini" }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
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
