# Screencast script — Social Media Scheduling

**Target length:** 2:30–3:00
**Audience:** marketers / solo founders evaluating "do I need Buffer /
Hootsuite / Later, or can I get the same outcome from a Google Sheet
and n8n?"
**Recording surface:** OBS / Loom; screen-share Google Sheets + n8n +
the target FB Page / LinkedIn Company Page / Discord channel.

---

## Scene 1 — Hook (0:00–0:20)

**Visual:** Google Sheet open. Three rows already typed — same post
text, three different channels (`fb`, `li`, `discord`), one with
`rewrite_enabled=TRUE`. All `status=queued`, all `schedule_at=NOW()+1m`.

**Voice (script):**
> Three rows in a Google Sheet — one for Facebook, one for LinkedIn,
> one for Discord. Same announcement, optionally rewritten per channel
> by Gemini. Wait one minute, and all three posts go live. Status,
> timestamp, and the live URL get written back to the row.

## Scene 2 — The pattern (0:20–0:55)

**Visual:** n8n editor on the workflow canvas. Trace the path with the
cursor: cron → filter → optional rewrite → per-channel switch →
normalise → update sheet.

**Voice:**
> A cron tick every minute reads the Sheet, filters rows that are
> queued *and* due, optionally runs Gemini to rewrite per-channel voice,
> then routes to the right channel API. All three API responses
> normalise into the same shape and write status, posted_at,
> result_url back to the source row.

## Scene 3 — The Sheet shape (0:55–1:25)

**Visual:** zoom on the Sheet header row. Highlight `post_id`,
`channel`, `rewrite_enabled`, `status`, and the write-back columns.

**Voice:**
> One row per `(post_id, channel)` — that's the trick. Buffer and
> Hootsuite do the same thing in their UI: one card per channel, not
> one card with a channel multi-select. Per-row gives us atomic
> status, atomic retry, and zero race conditions when the channels
> respond at different speeds.

## Scene 4 — The rewrite toggle (1:25–1:55)

**Visual:** click into `Build Per-Channel Prompt` code node. Show the
per-channel persona and length budget. Then jump back to the Sheet
and highlight the `rewrite_enabled` column.

**Voice:**
> Rewrite is *off* by default per row. When you want a LinkedIn-voiced
> rewrite of the same announcement, flip the cell to TRUE. The prompt
> attaches the channel's persona — LinkedIn gets professional + longer,
> Discord gets casual + shorter, FB stays middle-ground. The pass-
> through path costs nothing; the rewrite path costs one Gemini call.

## Scene 5 — The X exclusion (1:55–2:20)

**Visual:** back to the canvas, hover the `Switch - Route by Channel`
node. Show the three branches: fb, li, discord. No fourth branch.

**Voice:**
> No X / Twitter. The X API tier for posting is rate-limited and
> changes under your feet — and the algorithm doesn't reward
> automated content the way it used to. Spare that engineering
> capacity. Use it on making the three channels you *do* post to
> better.

## Scene 6 — Wrap (2:20–2:45)

**Visual:** flip to the FB Page, the LinkedIn Company Page, and the
Discord channel — all three posts live. Back to the Sheet, all three
rows now show `status=posted` with timestamps and result URLs.

**Voice:**
> Three posts live across three channels in under 60 seconds. The
> postgres-queue variant in `schema.sql` ships when you need atomic
> claim semantics, per-attempt audit log, or retry-with-backoff. Link
> to the workflow + setup guide in the description.

---

## Shot list

- [ ] Google Sheet (queue) — header + three test rows
- [ ] n8n editor on the workflow canvas (zoom on Switch + rewrite path)
- [ ] `Build Per-Channel Prompt` code node (zoomed)
- [ ] FB Page showing the live post
- [ ] LinkedIn Company Page showing the live post (rewritten copy)
- [ ] Discord channel showing the live post
- [ ] Sheet again with status=posted + result_url filled
- [ ] End card: repo URL + workflow folder path

## Recording notes

- Need a real FB Page token, LI access token, and Discord webhook for
  the demo. Use a throwaway TrendAI brand Page + a personal LinkedIn
  test page + a sandbox Discord server. Delete the test posts after
  recording.
- The `rewrite_enabled=TRUE` on the LinkedIn row gives the demo visual
  payoff (FB + Discord see the source copy verbatim, LI shows a
  rewritten version).
- Show the X-exclusion explicitly — it's a positioning differentiator
  vs Buffer/Hootsuite, not a bug.
