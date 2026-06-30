# DriftPro — agent instructions

Use this file when working from Cursor mobile, cloud agents, or any agent without local Mac context.

## Project

- **App:** DriftPro — Flutter logistics / HMS / partner ops app (Norwegian UI)
- **Repo:** `https://github.com/Hazher89/DRIIIII.git`
- **Default branch:** `main`
- **Local path (Mac):** `/Users/hama/DRIFTPRO`

## Stack

- **Frontend:** Flutter (web + mobile), `go_router`, Supabase client
- **Backend:** Supabase (Postgres, Auth, Storage, RLS)
- **Deploy:** Cloudflare Pages — build command `bash build_web.sh`, output `build/web`
- **Production:** `https://driftpro.no`

## Workflow

1. Make focused changes; match existing code style in touched files.
2. Run relevant tests when changing logic, e.g. `flutter test test/path/to_test.dart`
3. **Only commit or push when the user explicitly asks.**
4. Never commit secrets (`.env`, credentials), `supabase/.temp/`, or loose Excel/PDF uploads in repo root.
5. After push to `main`, Cloudflare auto-deploys — watch build logs for compile errors.

## Key areas

| Feature | Path |
|--------|------|
| GM & STORO label scan | `lib/screens/more/gm_storo/`, `lib/core/services/gm_storo/` |
| HMS / SOP training | `lib/screens/hms/training/`, `assets/hms/` |
| Partner route dispatch | `lib/screens/partners/` |
| Supabase migrations | `supabase/migrations/` |
| App routes | `lib/core/router/app_router.dart` |

## Mobile agent notes

- **Cloud agent (no Mac):** works from GitHub clone — enough for most code fixes, tests, and pushes.
- **Remote Control (Mac required):** needs Cursor **3.9.8+** on Mac, Remote Control enabled, Mac awake and online.
- User often tests on **mobile web** at `driftpro.no` — consider `mobile_scanner` web behavior for camera features.

## Language

- User-facing strings: **Norwegian (bokmål)**
- Code comments: English or Norwegian, match surrounding file
