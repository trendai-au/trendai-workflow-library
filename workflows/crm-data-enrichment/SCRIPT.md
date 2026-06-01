# Screencast script — CRM Data Enrichment

**Target length:** 2:30–3:00
**Audience:** B2B founders / SDRs evaluating "can I score my leads
automatically without paying for Clearbit + Apollo + Outreach?"
**Recording surface:** OBS / Loom; screen-share Google Sheets +
n8n editor + a Discord channel.

---

## Scene 1 — Hook (0:00–0:20)

**Visual:** Google Sheet open. Operator types a row with just an email
and a name. Hit Enter. Cut to the *output* Sheet — within ~75 seconds
the row appears with enriched fields: industry, role seniority, ICP
band, score, and a one-line outreach hook.

**Voice (script):**
> One Gemini call. Three sheet columns in. Twelve enriched columns
> out, ICP-banded, with a custom outreach hook per lead. Cheaper than
> Clearbit, faster than Apollo, and the ICP rules live in *your*
> database — not the vendor's. Here's how.

## Scene 2 — The pattern (0:20–0:55)

**Visual:** n8n editor on the workflow canvas. Zoom on the Pattern
diagram from the README. Trace the path with the cursor.

**Voice:**
> A new row in the input Sheet triggers the workflow. We normalise the
> contact, build a Gemini prompt, get back structured enrichment in
> one call, then load *your* ICP definitions from Postgres. The score
> is computed deterministically against those ICPs — Gemini never sees
> the ICP rules. That separation is the whole point.

## Scene 3 — The ICP table (0:55–1:30)

**Visual:** open `schema.sql`, scroll to the `icp_profiles` table and
the three seeded ICPs. Highlight the four allowlist columns
(industries, size bands, role seniorities, business models) + `weight`.

**Voice:**
> Each ICP has four axis allowlists and a weight multiplier. An empty
> allowlist on an axis means "unconstrained". A contact's score is the
> sum of axis matches times the weight, capped at 100, then banded
> into hot / warm / cold. Re-baseline your ICPs by editing this table
> — no workflow change, no re-running Gemini, no model fine-tuning.
> Just SQL.

## Scene 4 — The score computation (1:30–2:00)

**Visual:** click into the `Score Against ICPs` code node. Show the
match-axis-by-axis loop and the band thresholds.

**Voice:**
> The scoring is deterministic Javascript, not LLM. That means it's
> auditable — for any cold lead you can show the client exactly which
> axis missed and why. That's a much harder conversation when the
> "score" came from an opaque vendor model.

## Scene 5 — The hot-lead branch (2:00–2:30)

**Visual:** flip to Discord channel showing a hot-lead ping. Then back
to n8n showing `Notify Hot Lead - Discord` with `onError:
continueRegularOutput` highlighted.

**Voice:**
> Hot leads ping Discord — switch this for Slack, Teams, or email to
> your AE the same way. The Discord call uses `onError: continue` so a
> webhook failure doesn't break the pipeline — the contact still
> lands in Postgres and the output Sheet, just without the ping.

## Scene 6 — Wrap (2:30–2:50)

**Visual:** back to the output Sheet, scroll across the enriched
columns including `outreach_hook`. Hover one to show the full text.

**Voice:**
> The outreach hook is per-lead, ICP-aware, and ready to paste into
> your first-touch email. Fork the workflow, replace the three seeded
> ICPs with yours, and you're scoring leads inside an hour. Link in
> the description.

---

## Shot list

- [ ] Input Google Sheet (header row + one in-progress row)
- [ ] Output Google Sheet (enriched columns visible)
- [ ] n8n editor on the workflow canvas
- [ ] `schema.sql` open in code editor (icp_profiles section)
- [ ] `Score Against ICPs` code node (zoomed)
- [ ] Discord channel with hot-lead notification
- [ ] End card: repo URL + workflow folder path

## Recording notes

- Use sanitised placeholders on-screen — no real Gemini key, no real
  Discord webhook URL.
- The end-to-end demo needs a Gemini key during recording (the
  enrichment call is the live demo). Use a throwaway key + delete
  after recording.
- ICP seed data in `schema.sql` is illustrative; mention that on
  camera ("these three ICPs are illustrative — replace with yours").
