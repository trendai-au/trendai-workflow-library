# CRM Data Enrichment — Sheets in, ICP-scored leads out


<!-- E09.4-2-video-start -->
## Video

[![Watch the 2-minute walk-through](https://img.youtube.com/vi/kf_DdG4gWlM/maxresdefault.jpg)](https://www.youtube.com/watch?v=kf_DdG4gWlM)

**[Watch on YouTube → https://www.youtube.com/watch?v=kf_DdG4gWlM](https://www.youtube.com/watch?v=kf_DdG4gWlM)**

A 2-minute walk-through of the workflow: what it does, how the nodes wire up, and what you change to fork it for your stack. Part of the [TrendAI Workflow Library "Workflows" playlist](https://www.youtube.com/playlist?list=PLnl2DWExbS90Bw74p_gL9o8Ut9F88C8PX).
<!-- E09.4-2-video-end -->

A production-shaped n8n workflow that turns a thin contact record
(name + email + company) into a structured B2B enrichment + an
ICP-band classification, ready for differentiated outbound treatment.

The input surface is a **Google Sheet** because that's the lowest-
friction CRM most consulting prospects already have. Swap the trigger
for a Webhook (Pipedrive / HubSpot / typeform) by changing one node —
the rest of the workflow is source-agnostic.

## Pattern

```
Google Sheets Trigger (rowAdded — input sheet)
   ↓
Validate + Normalise Contact (code — required-field check, lowercase email,
                              infer company from domain if blank)
   ↓
Build Gemini Enrichment Prompt (code — system + record + JSON schema)
   ↓
Call Gemini 2.5 Flash (HTTP — JSON response mode, thinkingBudget: 0)
   ↓
Parse Gemini Output (code — extract enrichment, safe defaults on drift)
   ↓
Load ICP Profiles (postgres — is_active rows as JSON aggregate)
   ↓
Score Against ICPs (code — 4-axis match × weight → 0-100 score → band)
   ↓
Insert contacts_enriched (postgres — UPSERT on email)
   ↓
Write to Output Sheet (Google Sheets — appendOrUpdate matching on email)
   ↓
Route on Score Band (switch v3.2 — 3 outputs)
   ├─ hot   → Notify Hot Lead - Discord (HTTP) ─┐
   ├─ warm  ────────────────────────────────────┤
   └─ cold  ────────────────────────────────────┤
                                                 ↓
                                       Merge Branches (3-input — terminal)
```

12 nodes. The enrichment + ICP score + structured outreach hook all
come from **one** Gemini call. Side effects (postgres insert, output
sheet write) run once per contact regardless of band — the Switch only
gates the *differentiated* treatment (Discord ping on hot leads).

## Required credentials

| Placeholder | n8n credential type | What it needs |
|---|---|---|
| `REPLACE_ME_gsheets-trigger-contacts-input` | Google Sheets Trigger OAuth2 | Read access to the **input** sheet |
| `REPLACE_ME_gsheets-contacts-output` | Google Sheets OAuth2 | Write access to the **output** sheet |
| `REPLACE_ME_gemini-2-5-flash` | Google PaLM API (covers Gemini) | Gemini API key with access to `gemini-2.5-flash` |
| `REPLACE_ME_postgres-crm-enrichment-rw` | Postgres | A user that can read/write the two tables (see `schema.sql`) |
| `REPLACE_ME_discord_webhook_url` | (no credential — plain URL) | Discord channel webhook URL, hard-coded in `Notify Hot Lead - Discord` |

Discord is used unauthenticated via channel webhook URL (the URL is
the secret). Swap for Slack / Teams / email by changing the one HTTP
node — see the customisation guide below.

> **Single Sheets credential?** You can use the same Google account
> for both Sheets credentials — just create both credential entries
> in n8n's store (one of `googleSheetsTriggerOAuth2Api`, one of
> `googleSheetsOAuth2Api`) bound to the same OAuth login.

## Required schema

The workflow expects two Postgres tables: `icp_profiles` and
`contacts_enriched`. Full DDL with constraints, indexes, and three
seeded illustrative ICPs is in [`schema.sql`](./schema.sql).

- **`icp_profiles`** — your configurable ICP definitions. Each ICP
  has four axis allowlists (industries, size bands, role seniorities,
  business models) plus a `weight` multiplier. Empty allowlist on an
  axis means "unconstrained on this axis". The seed file ships three
  illustrative ICPs covering hot/warm/cold band examples.
- **`contacts_enriched`** — one row per email. UPSERT on `email` so
  re-running enrichment on the same contact refreshes the record in
  place. Indexed by `(band, icp_score DESC)` for fast hot-lead pulls.

Apply with:

```bash
psql "$POSTGRES_URL" -f schema.sql
```

## Input sheet shape

See [`contacts-input-sheet.md`](./contacts-input-sheet.md) for the
canonical header row + sample data. Header columns the workflow reads:

| Column | Required | Notes |
|---|---|---|
| `email` | yes | Lowercased + trimmed; rejected if no `@` |
| `name` | no | Free text |
| `company` | no | Inferred from email domain if blank (skip on free webmail) |
| `role` | no | Free text — fed to Gemini for seniority inference |
| `source` | no | Where the lead came from (LinkedIn, event, referral, …) |

Any extra columns are ignored. The workflow does **not** write back to
the input sheet — it writes to a separate **output** sheet (the
`appendOrUpdate` node matches on `email`).

## Setup

1. **Import the workflow.** In n8n: *Workflows → Import from File →*
   pick `workflow.json`.
2. **Re-bind credentials** on every node with `REPLACE_ME_…` — open
   the node, pick (or create) a credential of the matching type, Save.
3. **Set the input sheet** on `Google Sheets Trigger - New Contact`:
   replace `REPLACE_ME_input_sheet_id` and `REPLACE_ME_input_sheet_gid`
   with your input Sheet's document ID and sheet (tab) GID.
4. **Set the output sheet** on `Write to Output Sheet` (same fields,
   different sheet — create a blank one with the columns from the
   `schema` block in the workflow JSON, or let n8n create them on
   first append).
5. **Set the Discord webhook URL** on the `Notify Hot Lead - Discord`
   node: replace `REPLACE_ME_discord_webhook_url` with your channel
   webhook URL, Save.
6. **Apply the schema** (`schema.sql`) against the Postgres database
   bound to the credential.
7. **Edit the ICP profiles** to match your real ICPs (the seeded ones
   are illustrative). The workflow re-loads them on every contact, so
   you can tune ICPs without re-importing the workflow.
8. **Activate the workflow.** Sheet polling runs once per minute by
   default; tune in the trigger node if you need faster.

## Outputs

Per enriched contact, three writes happen:

1. **Postgres `contacts_enriched`** — full record, UPSERT on email.
2. **Output Google Sheet** — flat row, appendOrUpdate on email.
3. **Discord** — only on `band = hot`; one-line summary with score,
   ICP name, contact, company, role, outreach hook.

The Discord post uses `onError: continueRegularOutput` so a webhook
failure doesn't break the merge — the contact still lands in postgres
and the output sheet.

## Customisation guide (for consulting prospects)

The point of this template is to be **easy to fork for a specific
client**. The lift points are:

1. **The ICP definitions** in `icp_profiles`. This is the single most
   client-specific surface. Use the seed rows as a structural guide,
   then replace with your client's actual ICPs. Tune `weight` to bias
   ICP fit when you have multiple ICPs that could match the same
   contact.
2. **The system prompt** in `Build Gemini Enrichment Prompt`. The
   enum lists (industries, size bands, role seniorities, role
   functions, business models) are the contract between Gemini's
   output and the database CHECK constraints — keep them in sync if
   you extend them. Add or remove enum values, then mirror the change
   in `schema.sql`'s CHECK constraints.
3. **The trigger source.** Replace `Google Sheets Trigger` with
   *Webhook* (typeform / Pipedrive / HubSpot / Tally) by swapping the
   first node. The Validate node already handles the rest because
   `$input.first().json` is source-agnostic — just make sure the
   webhook payload has `email`, `name`, `company`, `role`, `source`
   fields (or rename in the Validate node).
4. **The output destination.** The output Google Sheet is the easy
   default. For a real CRM, swap `Write to Output Sheet` for HubSpot
   *Create/Update Contact* or Pipedrive *Person — Update*. The
   postgres insert stays as the source of truth.
5. **The hot-lead notification.** Discord is the default. Slack works
   the same (different webhook URL + payload shape). Email-to-AE
   follows the form-intake template's Brevo pattern. Add a Cal.com
   *block* call for instant-booking hot leads — see
   [reference_cal_com_webhook_db_subscription](../../) for the
   integration pattern.
6. **Add live web research.** Default-off: Gemini works from its
   internal knowledge, which keeps the template cred-free. To add
   live research, insert a Brave Search / Tavily HTTP node between
   `Validate` and `Build Gemini Prompt`, pass the top 3 result
   snippets as additional context in the prompt, and tell Gemini to
   cite which signal came from where in `confidence_notes`. Adds ~1s
   latency and a search-API credential to the template.

## Anti-patterns this template demonstrates avoiding

- **Multi-call enrichment.** Some pipelines call Clearbit, then
  Apollo, then a model. One Gemini call with structured-output
  prompting is cheaper, lower-latency, and gives you the full record
  + outreach hook in one shot — at the cost of relying on the model's
  internal knowledge. Add web research as a *prefix*, not a parallel
  call.
- **ICP scoring at the model.** The model returns axis facts
  (industry, size, seniority). The *score* is computed deterministically
  against your ICP table — so re-baselining your ICPs doesn't require
  re-running Gemini, and your scoring is auditable. The model never
  sees the ICP definitions.
- **Sheet write-back to the trigger sheet.** Writing back to the same
  sheet the trigger watches can cause re-triggering loops depending
  on n8n's row-detection logic. The template writes to a *separate*
  output sheet to sidestep this entirely.
- **Synchronous Discord.** The Discord notification uses
  `onError: continueRegularOutput` so a webhook failure doesn't break
  the enrichment pipeline — the contact still lands in postgres and
  the output sheet, just without the ping.
- **Inventing facts.** The system prompt explicitly tells Gemini to
  use `unknown` / empty strings when it doesn't know, rather than
  hallucinating company facts. Validate `confidence_notes` in spot
  checks — if a contact's signals look made up, tighten the prompt's
  "do not fabricate" instruction.

## Known limitations

- **No web research by default.** Gemini works from internal
  knowledge only. For contacts at small / new / non-English companies
  Gemini may return mostly `unknown`. See customisation point 6 to
  add Brave/Tavily.
- **Polling lag.** Google Sheets Trigger polls once per minute by
  default — first enrichment can take up to ~75s after the row lands.
  Webhook source is real-time; Sheets is "good enough" for batched
  outreach.
- **Free-webmail company inference.** When `company` is blank and
  the email is `@gmail.com` / `@outlook.com` / etc., the Validate
  node leaves company empty (rather than guessing "gmail"). Gemini
  then has nothing to anchor on — expect mostly `unknown` enrichment.
- **No rate limiting on Gemini.** Bulk imports of large sheets can
  hit Gemini quota. For lists >500 rows, throttle the input by
  uploading in chunks or add a `SplitInBatches` node before the
  Gemini call (see [n8n_splitinbatches_output_indices](../) for the
  output-wiring gotcha).
- **Single output sheet.** The template writes all bands to one
  output sheet. For visual sorting in a CRM-shaped sheet, add filter
  views in Google Sheets keyed on the `band` column — no workflow
  change needed.
- **No re-enrichment scheduler.** Contacts get enriched once on
  insert. To refresh stale enrichments, add a Cron node that selects
  `contacts_enriched WHERE enriched_at < now() - interval '90 days'`
  and replays the prompt chain. Not in this template.
