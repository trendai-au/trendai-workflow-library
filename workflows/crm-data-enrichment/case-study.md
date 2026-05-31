# Case study — CRM Data Enrichment

This template is shipped as a **design reference**, not as the
artefact of a 4-week production deployment. The numbers below are
design assumptions and band-distribution targets — useful for
sizing your own pilot. Adjust them once you've run the workflow
against real outbound for a couple of weeks.

## Sample run — `hot` band

**Inbound row** (from the input sheet):

```
email             | name        | company   | role            | source
priya@acme.io     | Priya Patel | Acme Labs | Head of Growth  | LinkedIn
```

**Workflow path:**

1. `Validate + Normalise Contact` — email lowercased, company kept
   as-is.
2. `Build Gemini Enrichment Prompt` — assembles the system + record
   prompt and stashes it in `_gemini_prompt`.
3. `Call Gemini 2.5 Flash` — Gemini returns:

   ```json
   {
     "company": {
       "name": "Acme Labs",
       "industry": "SaaS",
       "size_band": "11-50",
       "hq_country": "AU",
       "business_model": "B2B",
       "signals": ["Australian SaaS", "growth-stage", "B2B SaaS"]
     },
     "contact": {
       "role_seniority": "vp",
       "role_function": "marketing"
     },
     "outreach": {
       "hook": "Their growth-stage AU SaaS profile lines up exactly with the lead-enrichment workflows our consulting clients ship.",
       "confidence": "medium"
     },
     "confidence_notes": "Confident on the SaaS/AU/growth-stage classification; size band is an inference from typical Head-of-Growth roles at this profile."
   }
   ```

4. `Load ICP Profiles` — returns the 3 seeded ICPs.
5. `Score Against ICPs`:
   - vs. `AU SMB SaaS founders`: industry✓ size✓ seniority✗ (vp not in {founder,c_level}) business_model✓ → 3 hits × 25 × 1.20 = **90**.
   - vs. `Mid-market marketing ops`: industry✓ size✗ (11-50 not in {51-200,201-1000}) seniority✓ business_model✓ → 3 × 25 × 1.00 = 75.
   - vs. `Trade services digitisation`: industry✗ → 1 × 25 × 0.85 = 21 (only business_model matched).
   - Best: `AU SMB SaaS founders` at **score 90 → band `hot`**.
6. `Insert contacts_enriched` — UPSERT row, returns `id`.
7. `Write to Output Sheet` — flat row appended.
8. `Route on Score Band` — `band = hot` → output 0.
9. `Notify Hot Lead - Discord` posts:

   ```
   **Hot lead** — score 90 (AU SMB SaaS founders)
   Contact: Priya Patel <priya@acme.io>
   Company: Acme Labs — SaaS / 11-50
   Role: vp / marketing
   Hook: Their growth-stage AU SaaS profile lines up exactly with the lead-enrichment workflows our consulting clients ship.
   ```

10. `Merge Branches` (terminal — workflow ends).

## Sample run — `warm` band

**Inbound row:**

```
email                | name        | company   | role             | source
liam@bigshop.com.au  | Liam Chen   | Bigshop   | Marketing Manager| Event
```

**Gemini enrichment** (abridged):

```json
{
  "company": { "industry": "Ecommerce", "size_band": "201-1000", "business_model": "B2C", "signals": ["AU Ecommerce"] },
  "contact": { "role_seniority": "manager", "role_function": "marketing" },
  "outreach": { "hook": "...", "confidence": "medium" }
}
```

**Scoring:**
- vs. `AU SMB SaaS founders`: industry✗ size✗ seniority✗ → 25 (business_model B2C not in {B2B,B2B2C}) ✗. Actually 0 → 0.
- vs. `Mid-market marketing ops`: industry✓ size✓ seniority✓ business_model✓ → 4 × 25 × 1.00 = **100**.

Wait — that's a `hot` band, not `warm`. Let me re-shape this to a
genuine warm example:

**Inbound row (warm):**

```
email                | name        | company   | role         | source
sam@buildco.com.au   | Sam Reilly  | BuildCo   | Ops Lead     | Referral
```

**Gemini enrichment** (abridged):

```json
{
  "company": { "industry": "Construction", "size_band": "51-200", "business_model": "B2B", "signals": ["AU construction"] },
  "contact": { "role_seniority": "manager", "role_function": "ops" },
  "outreach": { "hook": "Mid-size AU construction ops manager — typical buyer for the project-tracking automations we sell.", "confidence": "medium" }
}
```

**Scoring:**
- vs. `AU SMB SaaS founders`: industry✗ → 25 (business_model match only) → 25 × 1.20 = 30.
- vs. `Mid-market marketing ops`: industry✗ size✓ seniority✓ business_model✓ → 75.
- vs. `Trade services digitisation`: industry✓ size✓ (empty array = unconstrained match) seniority✓ (empty array = unconstrained match) business_model✓ → 4 × 25 × 0.85 = **85** → `hot`.

This contact lands in `hot` against the broad "Trade services" ICP
even though the role seniority is only `manager`. That's
**intentional**: ICPs with empty axis allowlists score every match
on that axis as a hit, so a broad-axis ICP can produce high scores
on contacts that wouldn't fit a narrow ICP. The `weight` of 0.85
slightly discounts it so a 4-axis match still beats a 3-axis match
on a stricter ICP — but a 4-hit broad ICP still wins against a
narrow ICP unless the weight is dropped further. **Lift point**:
tune the weights of broad-axis ICPs lower (e.g. 0.60) if you want
to be more conservative with the broad bucket.

To actually land in `warm` band (40-74), a contact needs to hit
2 axes on a weighted ICP. Example: an `Ecommerce / 11-50 /
ic / B2B` contact against the `Mid-market marketing ops` ICP →
industry✓ size✗ seniority✗ business_model✓ → 2 × 25 × 1.00 = **50 →
warm**.

## Sample run — `cold` band

**Inbound row:**

```
email                | name      | company | role  | source
test@gmail.com       |           |         |       |
```

**Validate** — email lowercased, no company to infer (free webmail),
record passes through with mostly-empty fields.

**Gemini enrichment** — almost everything `unknown` / empty (no
company anchor, no role).

**Scoring** — every ICP axis fails. Score **0 → band `cold`**.

**Workflow path** — postgres insert + output sheet write happen as
normal; Switch routes to output 2 (cold); Merge terminates. No
Discord ping.

This is the right behaviour: incomplete leads should not silently
get dropped — they should land in `contacts_enriched` with
`band='cold'` so you can pull them later (a follow-up enrichment
script, a "fix in sheet" pass, or a "discard" pass).

## Band distribution — design target

For a healthy outbound list, expect this band distribution after
running the workflow over a meaningful sample:

| Band | Healthy share | What it means |
|---|---:|---|
| hot  | 5-15% | Tight ICP fit. These get same-day SDR follow-up. |
| warm | 25-40% | Partial fit. Nurture sequence or quarterly re-touch. |
| cold | 50-70% | Out of ICP or insufficient signal. Quarterly bulk send or drop. |

**If hot > 25%** — your ICPs are too broad. Tighten the axis
allowlists or drop the `weight` on broad-axis ICPs.

**If hot < 3%** — your ICPs are too narrow (everyone scores
2-axis) or your lead source isn't matched to your ICP at all. Look
at the `industry` distribution in `contacts_enriched` first.

**If cold > 80%** — likely a data quality issue. Check that your
input sheet has `company` filled in (the validate step infers it
from email domain but free webmail breaks that).

## Per-stage latency budget (design assumption)

| Stage | Operation | Target p50 | Target p95 |
|---|---|---:|---:|
| Sheets trigger | poll (every 1 min) | n/a | n/a |
| Validate + prompt build | code | ~10ms | ~30ms |
| Gemini 2.5 Flash | HTTP (JSON mode, thinkingBudget: 0) | ~1.0s | ~2.2s |
| Postgres reads (ICPs) | indexed lookup | ~20ms | ~80ms |
| Score against ICPs | code | ~5ms | ~15ms |
| Postgres write (UPSERT) | indexed | ~30ms | ~100ms |
| Output sheet write | Google Sheets API | ~600ms | ~1.5s |
| Discord (hot only) | HTTP, fire-and-forget | ~300ms | ~800ms |
| **End-to-end (hot)** | | **~2.0s** | **~4.7s** |
| **End-to-end (warm/cold)** | | **~1.7s** | **~3.9s** |

Gemini is the dominant latency; everything else is sub-second. If
you swap the input source from Sheets to a Webhook, the trigger
becomes ~5ms instead of "up to 60s" — which matters if you're
demoing live to a prospect.

## What to measure once it's running

Add these to your observability stack (a `crm_enrichment_runs`
table mirroring the knowledge-engine template's `knowledge_runs`
is a reasonable starting point):

- **Band distribution drift.** Plot the rolling 7-day band shares.
  A drift from 10% hot → 30% hot in a week usually means a lead
  source changed (a campaign launched, a list got loaded) — not
  that the workflow improved. Investigate before celebrating.
- **`outreach_confidence` distribution.** Low confidence on most
  contacts means Gemini doesn't have enough signal. Surface this
  to the operator so they enrich the input sheet (add company /
  role) before re-running.
- **ICP win share.** Which ICP scores the highest most often? If
  it's always the same ICP, your ICP table is collapsing to one
  meaningful entry — consider re-baselining.
- **Time-to-first-touch on hot leads.** From `enriched_at` to the
  SDR's first reply. The whole point of the Discord ping is to
  shrink this. Track it.
- **Reply rate by band.** The headline outcome metric. If `hot`
  doesn't outperform `warm`, your ICP definitions don't actually
  predict response — re-baseline against contacts who *replied*
  in the last 90 days.

## Anti-pattern callouts

- **Don't let Gemini compute the score.** The temptation is to ask
  the model for an "ICP fit 0-100". Don't — it makes the score
  unreviewable and you can't change ICPs without re-running every
  contact. Keep `Score Against ICPs` deterministic and local.
- **Don't enrich at outbound time.** A bulk-import + enrich-now
  pattern means SDRs work from fresh data. A "enrich on first
  click" pattern means stale data for everyone except the few
  contacts an SDR happens to look at. The Sheets trigger pattern
  encourages enrich-now; resist the urge to add a lazy mode.
- **Don't notify every band.** A Discord ping on every cold lead
  becomes background noise within a week and the team mutes it.
  The Switch is configured to ping `hot` only — keep it that way
  and use the output sheet (or a Looker / Metabase dashboard) for
  the rest.
- **Don't reuse the input sheet as the output sheet.** Sheets
  trigger row detection can re-fire on rows you write back to —
  not guaranteed (depends on n8n version + which column changed)
  but the failure mode is invisible until you've created an
  infinite enrichment loop on a single contact. Separate input
  and output sheets full stop.
