# UCEMS patch and file ownership tracker

| Release | Date | Files / directories | Purpose | Status |
|---|---|---|---|---|
| 001 | 2026-11-22 | `ucems-stitch-starter/assets/runtime.js` | Demo role-based navigation | Previous browser-only project |
| **002** | **2026-11-22** | **`ucems-supabase-fullstack/` (all files listed below)** | **Supabase full-stack source release** | **Delivered for local setup & Supabase verification** |
| **003** | **2026-11-23** | **SRS v1.2 alignment slice** | **Named positions, per-position permissions, automatic configured authority routing, explicit badge authorization, and legacy organizer migration** | **Source updated; migration needs disposable Supabase verification** |

**Patch 002 is a new project baseline**, because the existing browser-only script cannot safely implement authentication, RLS, payments or versioned approvals by itself. It does not overwrite Patch 001. Keep your old folder as a backup.

## Exact baseline files

```
ucems-supabase-fullstack/
  README.md
  .gitignore
  docs/ACCEPTANCE_TESTS.md
  docs/ARCHITECTURE.md
  docs/KNOWN_LIMITATIONS.md
  docs/PATCH_TRACKER.md
  web/.env.example
  web/package.json
  web/index.html
  web/src/client.js
  web/src/data.js
  web/src/main.js
  web/src/ui.js
  web/src/style.css
  web/stitch-reference/   (original HTML, design documents and previews)
  mobile/.env.example
  mobile/package.json
  mobile/app.json
  mobile/App.js
  supabase/config.toml
  supabase/.env.example
  supabase/migrations/202611220001_ucems.sql
  supabase/migrations/202611230002_srs_foundations.sql
  supabase/functions/create-checkout/index.ts
  supabase/functions/stripe-webhook/index.ts
  tests/check_project.py
```

## Future patches

User-requested fixes will arrive as **only changed files**, with:
1. patch number and purpose;
2. exact project-relative replacement paths;
3. prerequisites and migration instructions;
4. regression test checklist;
5. version dependencies.

Never copy the old `ucems-stitch-starter/assets/runtime.js` into this new app. It uses demo session storage and does not connect to Supabase.
