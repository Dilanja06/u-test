# UniEvents / UCEMS — Supabase Full-Stack Academic V1

**Release:** PATCH-002 (Supabase backend foundation + integrated web + mobile)
**Date:** 2026-11-22
**Status:** Source-code handoff. Not deployed and **not verified against a live Supabase project** because no project credentials were provided. Read `docs/KNOWN_LIMITATIONS.md` before demonstrating.

This replaces the earlier **browser-only** starter with a consistent role-aware application backed by Supabase. Stitch screen references remain in `web/stitch-reference/`. It is a **new project folder**, not a drop-in replacement for one old `runtime.js` file. Future patches will list exact paths to replace.

## 1. Requirements

- Node.js 22.13+ and npm
- A Supabase account/project (hosted is easiest; **Docker not needed**)
- Optional: Supabase CLI for deploying Stripe Edge Functions
- Optional: Stripe **test-mode** credentials (do not configure live keys)
- Optional: Expo Go / Android device and camera for mobile QR scanning

## 2. Set up Supabase first

1. Create a project at https://supabase.com/dashboard, wait for it to finish provisioning.
2. Open **Project Settings → API Keys** (or the API/Connect panel). Copy:
   - Project URL (`https://<project-ref>.supabase.co`)
   - **Publishable** key (`sb_publishable_...`; a legacy anon key also works).
   - Do **not** copy the secret/service-role key into browser/mobile configuration.
3. Under **Authentication → Providers → Email**, enable email/password authentication. For a local academic demo you can configure confirmation according to your project policy; for real deployments, keep email verification and restrict identities to university accounts.
4. Open **SQL Editor → New query** and run the SQL migrations in order: `202611220001_ucems.sql`, `202611220002_club_logos.sql`, `202611220003_admin_club_management.sql`, `202611220004_role_based_proposal_review.sql`, `202611220005_admin_account_role_management.sql`, `202611220006_prevent_self_role_management.sql`, `202611230001_admin_self_role_grants.sql`, then `202611230002_srs_foundations.sql`. If earlier migrations are already applied, run only the unapplied migrations. Apply each migration once.
5. Create a new user by signing up in the web interface (Step 3 below), and confirm their email if Supabase requires it.
6. Bootstrap the **first admin** in the SQL Editor, replacing the example email with the exact address you registered:

```sql
insert into public.user_roles(user_id,role)
select id,'admin' from auth.users where email = 'admin@example.edu'
on conflict do nothing;
```

7. **Sign out and sign back in**, choose your `admin` role from the role selector after the roles have loaded.

**Important:** Migrations are intended to be applied once and in order. The SRS foundations migration maps seats 1–5 to President, Vice President, Secretary, Vice Secretary, and Treasurer, respectively. All per-club/per-position permissions start disabled; the matrix currently exposes implemented actions only, and an Admin must grant each permission before committee members can use its protected action. Admins configure the Higher Authority recipients used for every proposal; if no recipients are configured, Coordinator approval creates a visible routing exception instead of silently completing review. Legacy organizer assignments remain visible until an Admin manually maps each account to a vacant position; permission grants must then be configured separately. The migration preserves historic reviewer/badge data, but prior badges without an authorization record are not shown as verified earned badges.

## 3. Run the web application

```bash
cd ucems-supabase-fullstack/web
cp .env.example .env
```

Edit `web/.env`:

```env
VITE_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_YOUR_KEY
```

Then:

```bash
npm install
npm run check
npm run dev
```

Open **http://localhost:5173** (or the port displayed by Vite). You must have internet access for Supabase and to install npm packages.

Web works **without Stripe** for club management, proposals, free events, free memberships, and roles. Paid fees remain pending until Stripe test Checkout is enabled.

## Development demo previews

When running `npm run dev`, the login screen offers buttons to preview the student, committee, coordinator, higher-authority, and admin interfaces. These previews use mock in-memory data: they require no Supabase accounts or Docker, do not authenticate, and do not save changes. The preview code and buttons are excluded from production builds.

## 4. Create the four-role workflow demo

Create separate user accounts using the web signup form (or invite users in Supabase Auth). Confirm their emails, then sign in as the first admin.
Administrator actions in the web console (club creation, role grants, club staff assignments, and club updates) show a confirmation prompt before they are sent to Supabase.

1. Admin → Create club (e.g., *Technology Society*).
2. Admin → Assign club coordinator, using a registered user.
3. Admin → Assign the five named committee positions to registered accounts.
4. Admin → Administration → Committee permissions → choose a club and position, then grant only the needed permissions. Grants are off by default.
5. Admin → Administration → Account access → Search for accounts and grant `authority` roles; all roles can also be updated or removed there.
6. Admin → Administration → Authority routing recipients → choose the active authority accounts that should review every proposal. No recipient is implied by an authority role alone.
7. Committee user → Select `committee` role → Event proposals → Create draft, if `event.create` is granted.
8. Committee → Submit to lecturer, if `event.proposal.submit` is granted. Coordinator approval automatically routes to the configured recipient set.
9. Lecturer → Review queue → Approve or request corrections.
10. Configured Higher Authorities → Review queue → Approve the current version.
11. Committee → Publish, if `event.publish` is granted. Students immediately see the event in the dashboard, explorer and calendar.
12. If changes are requested at lecturer **or** higher-authority review, committee resubmits a new version → lecturer approval repeats → the current configured authorities must approve.

There is no per-proposal reviewer picker. Admins configure a global all-proposal recipient set; PostgreSQL snapshots those configured recipients when the Lecturer Coordinator approves a version. If that set is empty, the proposal remains in a routing exception until configuration is fixed and an Admin retries routing. Per-event rule criteria remain pending university policy. The active role selector only lists supported roles from the authenticated user's `user_roles` records. All protected committee actions are rechecked in PostgreSQL.

## 5. Memberships and registration

- Student → Clubs → Apply to join → Committee → Membership requests → Approve.
- Free club membership becomes active immediately after approval.
- Fee-based membership becomes `payment_due`, and is active **only when a verified Stripe test webhook** confirms the test payment.
- Student → Explore events → Register. Free registration becomes `registered`; paid registration requires test checkout.

Payment amounts are configured in **integer USD cents** for this academic demo. This is not a university billing/currency policy or production payment configuration.

## 6. Optional Stripe test-mode payment integration

Do this **only** if you want paid memberships/event fees to finish their test lifecycle. Stripe test mode uses no real money.

1. Obtain `sk_test_...` and a test webhook signing secret `whsec_...` from your Stripe test dashboard.
2. Install/log in to the Supabase CLI, from the **project root**:

```bash
npx supabase@latest login
npx supabase@latest link --project-ref YOUR_PROJECT_REF
```

3. Set your secrets (replace values; avoid storing them in Git):

```bash
npx supabase@latest secrets set STRIPE_TEST_SECRET_KEY=sk_test_REPLACE STRIPE_WEBHOOK_SECRET=whsec_REPLACE APP_URL=http://localhost:5173
```

4. Deploy both functions:

```bash
npx supabase@latest functions deploy create-checkout
npx supabase@latest functions deploy stripe-webhook --no-verify-jwt
```

5. In Stripe **test mode**, create a webhook endpoint with URL:

```
https://YOUR_PROJECT_REF.supabase.co/functions/v1/stripe-webhook
```

Subscribe to `checkout.session.completed`; copy the resulting signing secret into the `STRIPE_WEBHOOK_SECRET` Supabase secret (set it again after you create the endpoint). The webhook verifies the raw signed payload and checks order amount, currency and session ID before activating anything.

6. In the web app, student → Payments → Test checkout. Use Stripe test card details from Stripe's official documentation. The success redirect **never** grants paid status on its own.

Note: Stripe account availability and country support vary; this connector is an academic test-mode example, not a commitment that Stripe is the university's future live payment provider.

## 7. Run the separate Expo mobile application

```bash
cd ucems-supabase-fullstack/mobile
cp .env.example .env
```

Set the **same Supabase URL and publishable key** with `EXPO_PUBLIC_` prefixes, then:

```bash
npm install
npx expo install --fix
npx expo start
```

Open with Expo Go or the Android simulator (SDK 58-compatible). Sign in using an existing account from the web portal. **Students** can browse published events, register, access registered events, display 90-second QR codes and view authorized badges. **Committee members with `attendance.scan`** can scan those QR codes using the camera. Device registration/transfer approval is not implemented yet; do not treat the current token flow as satisfying the SRS device-binding requirement.

The attendance check-in window is from **2 hours before event start** to **2 hours after event end**. Create a sample event with an appropriate event time to demonstrate scanning; tokens last 90 seconds, are single-use and stored as hashes on the server.

## 8. Validate code and inspect status

```bash
cd ucems-supabase-fullstack/web
npm run check
npm run build
```

From the project root:

```bash
python3 tests/check_project.py
```

See `docs/ACCEPTANCE_TESTS.md` for the scenarios that need live Supabase verification. No live-service tests have been run in this environment.

## 9. Important project paths

| Path | Role |
|---|---|
| `web/src/main.jsx` | React entry point and application error boundary |
| `web/src/App.jsx` | React role-aware screens, permission-gated proposal, attendance, and badge workflows |
| `web/src/style.css` | Unified design system and responsive layout |
| `web/src/data.js` | Supabase read models and role-scoped data |
| `web/src/client.js` | Supabase client and RPC wrapper |
| `supabase/migrations/*.sql` | Schema, authorization, RLS, business transitions |
| `supabase/functions/create-checkout` | Authenticated Stripe test session creation |
| `supabase/functions/stripe-webhook` | Signed payment confirmation callback |
| `mobile/App.js` | Separate Expo app for student and committee flows |
| `docs/PATCH_TRACKER.md` | Exact file paths and release tracking |
| `web/stitch-reference/` | Original Stitch previews and design descriptions |

## 10. Security precautions

- Publishable key in frontend: allowed. **Secret/service-role keys in frontend: forbidden.**
- All data access uses RLS; financial and approval state changes use validated RPCs.
- This is **not** ready for real money or unrestricted production enrollment. See the limitations and change-gate documents.
- Supabase project and account setup require your action; no credentials or external services are included.

Official references: https://supabase.com/docs/guides/auth/quickstarts/react · https://supabase.com/docs/guides/database/postgres/row-level-security · https://supabase.com/docs/guides/functions · https://docs.expo.dev/guides/using-supabase/
