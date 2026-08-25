# DriftPro-assistent (Gemini)

## Oppsett (engangs)

1. Åpne [Google AI Studio](https://aistudio.google.com/apikey) og lag en **API key**.
2. I Supabase Dashboard → **Edge Functions** → **Secrets**:
   - `GEMINI_API_KEY` = nøkkelen
   - valgfritt `GEMINI_MODEL` = `gemini-2.0-flash` (standard)
3. Deploy:

```bash
supabase functions deploy driftpro-assistant --project-ref ksnnyccthotjbrmgjgdc
```

## Hvordan «trening» fungerer

Google trenes **ikke** på MAVI-data. DriftPro gjør RAG:

1. Ansatt stiller spørsmål
2. Appen søker i SOP / bilutleie / hjelpetekster
3. De beste utdragene sendes til Gemini sammen med spørsmålet
4. Gemini svarer på norsk, begrenset til konteksten

For mer dekning: legg flere dokumenter inn i `AssistantCorpus` (eller utvid SOP-asset).
