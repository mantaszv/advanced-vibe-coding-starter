---
title: mini-CRM — B2B SaaS Lean MVP design
date: 2026-04-26
status: approved
ICP: Mažos B2B SaaS sales komandos (2–10 SDR/AE)
tech_stack: Next.js 16.2, React 19.2, Tailwind v4, Supabase, Stripe, Vercel
---

# mini-CRM — B2B SaaS Lean MVP

## 1. Kontekstas ir tikslas

Mini-CRM — paprastas, greitas CRM mažoms B2B SaaS sales komandoms (2–10 SDR/AE).
Pozicionuojame prieš Pipedrive/HubSpot ant **paprastumo + greičio**, ne feature breadth.

**MVP scope (Lean, 4–6 sav.):** Contacts, Companies, Deals (kanban + table),
Activities (notes/tasks/meetings), CSV import, multi-user workspace, Stripe billing.

**Out of scope V1:** email sync, AI fields, sequences, automations, custom fields,
dashboards, sequences, calendar sync.

## 2. Architektūriniai sprendimai

### 2.1 Duomenų modelis — rigid schema su `jsonb` ateities vektoriumi (atidėtas V2)

Hardcoded lentelės žinomiems CRM objektams. `custom_data jsonb` stulpelis **NĖRA**
pridėtas V1 — atidėtas, nes ICP "a" (B2B SaaS sales) pirma vertina greitumą ir aiškią
UX, ne flexibilumą. Pridėjimas vėliau migruoja be schema breaking change.

**Trade-off:** atsisakome Attio "build-your-own-CRM" pozicionavimo; mainais — MVP per
4–6 sav. ne 16, paprastas RLS, type-safe TypeScript per `supabase gen types`.

### 2.2 Multi-tenancy — Single DB + `org_id` + RLS (Supabase native)

Visi tenant'ai dalinasi Postgres schemą; izoliacija per `org_id` kolonėlę ir RLS
policies, kurios skaito `auth.jwt()->'app_metadata'->>'org_id'`.

**Privalomi guardrail'ai:**
1. `org_id` saugomas JWT `app_metadata` (NE user_metadata — tas writeable iš client)
2. `force row level security` ant visų tenant lentelių
3. Performance pattern: `(select auth.jwt()->...)` SELECT wrap → initPlan caching
4. `org_members (org_id, user_id, role)` lentelė + Auth Hook setina JWT claim
5. pgTAP RLS testai CI — fail jei lentelė be 4 policies (SELECT/INSERT/UPDATE/DELETE)

**Trade-off:** prisiimame RLS bug riziką (catastrophic if missed); mainais — 10×
pigesnė infrastruktūra, sinchroninės migracijos, Supabase native tooling. Linear,
Notion, Vercel naudoja tą patį pattern.

## 3. Sistemos topologija

```
Browser (Next.js App Router RSC + Tailwind v4)
   │
   ├─ Server Components (queries) ──┐
   ├─ Server Actions (mutations) ───┤
   └─ Client islands (kanban DnD) ──┘
                                    │
                              Vercel Edge
                                    │
                          Supabase JS (user JWT)
                                    │
   ┌────────────────────────────────┴───────────────┐
   │ Postgres + RLS │ Auth │ Edge Functions │ Storage │
   └────────────────┬─────────────────────┬─────────┘
                    │ Webhook              │
                  Stripe                  Resend
                  (billing)         (transactional email)
```

## 4. Duomenų modelis

### 4.1 Tenancy core

```sql
orgs (id, name, slug UNIQUE, currency, stripe_customer_id,
      stripe_subscription_id, trial_ends_at, seats_paid)
org_members (org_id, user_id, role, joined_at)  -- PK (org_id, user_id)
org_invites (id, org_id, email, role, token, expires_at, accepted_at)
```

### 4.2 CRM core

```sql
contacts (id, org_id, first_name, last_name, email, phone, job_title,
          company_id FK, owner_id FK, created_at, updated_at)
  unique (org_id, lower(email)) where email is not null

companies (id, org_id, name, domain, industry, size_range,
           owner_id FK, created_at, updated_at)
  unique (org_id, lower(domain)) where domain is not null

pipeline_stages (id, org_id, name, position, is_won, is_lost)

deals (id, org_id, title, value_cents, stage_id FK, contact_id FK,
       company_id FK, owner_id FK, expected_close_at, closed_at)

activities (id, org_id, type ENUM(note|task|meeting), body markdown,
            due_at, done_at, contact_id FK, deal_id FK, created_by FK)
```

**Konvencijos:**
- `value_cents bigint` — pinigai centais (Stripe konvencija)
- `on delete cascade` per `org_id` chain — atomic tenant deletion
- Indeksai visose `(org_id, ...)` filtravimo kombinacijose

### 4.3 RLS pattern (visoms tenant lentelėms)

```sql
create function auth.org_id() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb
    ->'app_metadata'->>'org_id', '')::uuid;
$$;

alter table <T> enable row level security;
alter table <T> force row level security;

-- 4 policies per lentelę:
create policy <T>_select on <T> for select to authenticated
  using ( org_id = (select auth.org_id()) );

create policy <T>_insert on <T> for insert to authenticated
  with check ( org_id = (select auth.org_id()) );

create policy <T>_update on <T> for update to authenticated
  using ( org_id = (select auth.org_id()) )
  with check ( org_id = (select auth.org_id()) );

create policy <T>_delete on <T> for delete to authenticated
  using ( org_id = (select auth.org_id()) );
```

### 4.4 JWT Auth Hook

`custom_access_token_hook(event jsonb)` užkrauna `org_members.org_id` (pirmasis
joined) į `claims.app_metadata.org_id`. Po `acceptInvite` arba `createWorkspace`
front-end privalo `supabase.auth.refreshSession()` — kitaip RLS grąžins 0 eilučių.

## 5. Maršrutų hierarchija (Next.js App Router)

```
(marketing)/         landing, /pricing
(auth)/              /prisijungti, /kvietimas/[token]
onboarding/          /workspace (create org)
app/[slug]/          sandoriai, kontaktai, imones, uzduotys, nustatymai
api/                 stripe/webhook, health
```

LT URL slug'ai be diakritikos (`imones`, `uzduotys`) — design choice URL'ams;
UI breadcrumbs/tabs rodo pilną LT su diakritika ("Įmonės", "Užduotys"). Kodas,
props, DB kolonėlės — angliškai.

### 5.1 Render strategija

| Route | Render | Mutations |
|---|---|---|
| `(marketing)` | Static + ISR | — |
| `(auth)` | Dynamic SSR | Server Actions |
| `app/[slug]/sandoriai` | RSC + Client kanban (DnD) | Server Actions + optimistic |
| `app/[slug]/kontaktai` | RSC table | Server Actions |
| `api/stripe/webhook` | Edge Function | — |

Server Actions visur, kur galima. Kanban — vienintelė client-heavy zona
(`@dnd-kit/core`).

## 6. Auth + onboarding

1. `/prisijungti` → magic link (Resend) arba Google OAuth
2. Middleware: ar yra `org_members` įrašas?
   - NE → `/onboarding/workspace`
   - TAIP → `/app/{primary_slug}`
3. `createWorkspace`: INSERT orgs (trial=14d, seats_paid=0) + INSERT org_members
   (owner) + 5 default pipeline_stages + Stripe customer (no sub) + refreshSession
4. Invite flow: `/kvietimas/[token]` → if logged in auto-accept; else login redirect

## 7. Billing model

- **mini-CRM Team** — €19/seat/mo monthly arba €15/seat/mo (annual, 21% off)
- 14 d. free trial be CC
- Stripe: 1 product, 2 prices, subscription per org (quantity = members count)
- Invite/remove member → `stripe.subscriptions.update({ quantity })` su prorations

### 7.1 Trial UX

| Liko trial dienų | UX |
|---|---|
| > 7 | Tylu |
| 3–7 | Diskretiškas top banner |
| 1–3 | Persistent CTA banner |
| ≤ 0, < 30 d. po trial | Read-only mode + modal blocker |
| > 30 d. po trial | Hard block — tik `/atsiskaitymas` |

### 7.2 Stripe webhook events

| Event | Handler |
|---|---|
| `checkout.session.completed` | Activate subscription |
| `customer.subscription.updated` | Sync `seats_paid`, `current_period_end` |
| `customer.subscription.deleted` | Schedule data retention |
| `invoice.payment_failed` | Email owner, soft block po 7 d. |
| `invoice.payment_succeeded` | Reset failed counter |

**Idempotency:** `stripe_events_processed (event_id PK, processed_at)` lentelė
prieš procesinant — payment-guard reikalavimas. `webhooks.constructEvent` signature
verification privalomas.

## 8. Komponentų hierarchija

```
src/
├── app/                      # Routes
├── components/
│   ├── ui/                   # shadcn/ui primitives
│   ├── kanban/               # KanbanBoard, Column, DealCard (client)
│   ├── deals/                # DealForm, DealDetailPanel
│   ├── contacts/             # ContactList, ContactImport, ContactForm
│   └── shared/               # EmptyState, DataTable, OrgSwitcher
├── lib/
│   ├── supabase/             # server.ts, browser.ts, middleware.ts
│   ├── stripe/               # client.ts, webhook-handler.ts
│   ├── validation/           # zod schemas (1:1 su DB)
│   └── auth/                 # require-session, require-org
├── actions/                  # Server Actions per domain
└── hooks/                    # use-optimistic-deals
```

**File-size-guard:** ≤ 300 LOC/file, ≤ 200 LOC/component, ≤ 50 LOC/function.

## 9. Tech stack įrankiai

| Sluoksnis | Pasirinkimas | Pagrindas |
|---|---|---|
| Framework | Next.js 16.2 (App Router, Server Actions stable) | RSC + Server Actions = mažiau client JS |
| UI | React 19.2, Tailwind v4 (Oxide, `@theme inline`) | OKLCH spalvos, 10× greitesnis build |
| Komponentai | shadcn/ui | Owned code, ne dependency |
| DB | Supabase Postgres + RLS | Native pattern, JWT app_metadata |
| Auth | Supabase Auth (magic link + Google OAuth) | RLS integracija |
| Email | Resend | Transactional only (invites, magic links, billing) |
| Billing | Stripe (Checkout + Customer Portal) | Per-seat subscription |
| Deploy | Vercel (Next.js) + Supabase (DB) | Edge Functions Stripe webhook |
| Drag-drop | `@dnd-kit/core` | Accessibility, lengvas |
| Forms | Native form + Server Actions + zod | Type-safe, mažiau JS |

## 10. Testavimas

| Layer | Tool | Coverage | Kas padengiama |
|---|---|---|---|
| Unit | Vitest | ≥ 80% paveiktų | zod schemos, helpers |
| RLS | pgTAP | 100% tenant lentelių | Cross-tenant izoliacija |
| E2E | Playwright | Kritinis flow | Sign-up→deal→won, invite, billing |
| Smoke | Playwright | Production | Po kiekvieno PR deploy |

### 10.1 Kritiniai E2E scenarijai

1. Sign-up + workspace + first deal (drag iki "Won")
2. Invite + accept (kviestasis mato CRM)
3. Cross-tenant izoliacija (Alice ≠ Bob duomenys)
4. Billing trial → Stripe checkout → active
5. CSV import (validation + 100 rows)

## 11. CI/CD pipeline

GitHub Actions: lint → unit → rls-tests (local Supabase) → e2e → guards
(`.claude/hooks/pre-commit.sh`) → deploy:preview → deploy:prod (tik main).

**Migracijos:**
- Privaloma `UP` + `DOWN` (db-migration-guard)
- Destruktyvios — eksplicit `-- ROLLBACK_PLAN:` komentaras
- Production deploy per CI (`supabase db push`), NE rankiniu būdu

## 12. Observability (V1 minimum)

- Vercel Analytics (Core Web Vitals)
- Supabase Logs (Postgres + Edge Function)
- Stripe Dashboard (subscription events)
- Resend Dashboard (email deliverability)

V2: Sentry, PostHog.

## 13. Apribojimai ir rizikos

- **RLS bug catastrophe** — vienas blogas policy = cross-tenant data leak.
  Mitigacija: pgTAP testai + `force RLS` + CI gate, kuris skanuoja `pg_policies`.
- **Stripe webhook drop** — neatlikus subscription update orgs.seats_paid divergens.
  Mitigacija: idempotency lentelė + cron job, kuris reconcile'ina seats kas 24h.
- **Trial abuse** — naujas email = naujas trial. Mitigacija (V2): domain dedup.
- **JWT refresh klaida** — po `createWorkspace` jei nesirefresh'ina session,
  user mato tuščią CRM. Mitigacija: integration test'as flow'ui.

## 14. Fazės plano santrauka (writing-plans skilliui)

1. **Setup** — repo init, Next.js 16.2 scaffold, Tailwind v4, shadcn/ui, Supabase
   local dev, env vars
2. **Auth + tenancy** — Supabase Auth Hook, orgs/org_members lentelės, RLS,
   onboarding flow, pgTAP testai
3. **CRM core** — contacts, companies, deals, pipeline_stages, activities lentelės
   + RLS + Server Actions + zod validation
4. **UI** — sandoriai (kanban + table), kontaktai (list + import), imones,
   uzduotys, nustatymai/komanda + nustatymai/pipeline
5. **Billing** — Stripe products, checkout flow, webhook Edge Function, trial UX,
   read-only enforcement
6. **CSV import** — file upload, column mapping, validation preview, batch insert
7. **E2E + polish** — Playwright critical flows, empty states, error boundaries,
   Vercel deploy

Numatytas timeline: 4–6 sav., solo arba duo dev.
