# Productization

How this library is positioned, what's productized vs raw, and how to
get a custom variant built for your stack.

## What "productized" means here

A workflow in this repo is **productized** when it ships:

1. A **standardised README** — title hero, pattern diagram, required
   credentials (table form), required schema, setup checklist (one
   numbered list), inputs, outputs, customisation guide for consulting
   prospects, anti-patterns it avoids, and known limitations.
2. A **`schema.sql`** when the workflow touches a database, with full
   DDL — tables, constraints, indexes, triggers, and seed data where
   the seed makes the workflow demo-able out of the box.
3. A **`case-study.md`** — sample input, sample output, observed
   metrics from production usage, what broke and how the design
   responds to it.
4. A **`SCRIPT.md`** — 2–3 min screencast script ready to record,
   with a scene-by-scene voice + visual plan, a shot list, and
   recording notes. Recordings are produced separately; the script
   lives in-repo so it stays version-controlled alongside the
   workflow it documents.
5. **Sanitisation guarantees** — no real tokens, no tenant URLs, no
   real schema names; every credential reference is a
   `REPLACE_ME_<purpose>` placeholder per
   [SANITISATION-CHECKLIST.md](SANITISATION-CHECKLIST.md).

The [Featured 5](README.md#featured-5) are the productized set as of
this release. The other workflows in `workflows/` are **raw** — they
ship the workflow JSON + a README, but the README hasn't been brought
through the full shape and they may not have `schema.sql` or
`SCRIPT.md`. They're still useful; they're just not the curated
front-of-store.

## What "productized" does *not* mean

- **Not a managed service.** Forking and re-binding credentials in
  your own n8n instance is on you. The library doesn't host
  anything — there's no SaaS surface, no API key, no dashboard.
- **Not a paid product.** MIT licensed, free to fork, modify,
  commercialise. No tier, no usage cap, no auth wall.
- **Not a turnkey integration.** Every workflow has client-specific
  lift points called out in its README (the *Customisation guide*
  section). A workflow that says "swap the HubSpot upsert for
  Pipedrive" expects you (or a consultant) to do that swap.
- **Not warranted.** Use in production at your own risk. The case
  studies report what worked in *TrendAI's* stack — yours will have
  different failure modes.

## When to fork vs commission

**Fork it yourself if:**
- You have an n8n instance running and an engineer comfortable with
  re-binding credentials + editing node configs.
- Your client-specific lift is one or two of the documented
  customisation points (CRM swap, notification surface swap, schema
  rename).
- You want to learn the patterns by running them. The case studies
  + anti-patterns make this an explicit teaching surface.

**Commission a custom build if:**
- You want a workflow shaped for a specific niche (a regulated
  industry, a non-default CRM, a multi-tenant deployment).
- The customisation lift crosses multiple workflows (e.g. all five
  Featured workflows wired into a single consulting engagement).
- You need the postgres-queue variant of social-media-scheduling, or
  the RAG variant of customer-support-chatbot, or any of the
  customisation points called "see customisation point N — not in
  this template".
- You want the productized treatment (README + schema + case-study
  + script) applied to a workflow that doesn't exist here yet.

## How to commission

Email **hello@trendai.au** with:

1. The workflow(s) closest to what you want, by name.
2. The customisation points (from the workflow's README) that you
   need lifted.
3. Your n8n instance shape — self-hosted or cloud, version, what
   credentials are already wired up, what's missing.
4. Your timeline + budget.

We respond within two business days (AU time). Engagements are
typically priced fixed-scope per workflow + an optional retainer for
ongoing maintenance.

There's no purchase button on this repo — and that's deliberate.
Custom n8n work without a scoping conversation up front tends to
ship the wrong shape; a 30-minute call before any quote saves both
of us a refund cycle later.

## Roadmap

The Featured 5 will expand over time. Candidates already in the
pipeline:

- **invoice-intake-and-categorise** — webhook → OCR → Gemini line-
  item classification → accounting-software push (Xero / QuickBooks
  Online).
- **calendar-availability-aggregator** — multi-Cal.com / Google
  Calendar → unified availability → Cal.com block injection for
  team scheduling.
- **review-monitor** — multi-source review aggregation (Google
  Business Profile, Facebook, Trustpilot) → sentiment-banded
  Discord alerts + response drafts.

These are not yet in the library. Watch this file (or the repo's
release notes) for additions.

## License + provenance

MIT — see [LICENSE](LICENSE).

All workflows are from a single operator's stack
(`@trendai-au` on GitHub). The case-studies report TrendAI's own
production experience. If you build a significantly improved variant
of a featured workflow, PRs welcome — see
[CONTRIBUTING.md](CONTRIBUTING.md) for what we look for.
