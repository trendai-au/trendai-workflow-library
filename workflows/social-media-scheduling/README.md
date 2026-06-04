# Social Media Scheduling — Sheets queue → FB / LinkedIn / Discord


<!-- E09.4-2-video-start -->
## Video

[![Watch the 2-minute walk-through](https://img.youtube.com/vi/pzhYQzkrT_s/maxresdefault.jpg)](https://www.youtube.com/watch?v=pzhYQzkrT_s)

**[Watch on YouTube → https://www.youtube.com/watch?v=pzhYQzkrT_s](https://www.youtube.com/watch?v=pzhYQzkrT_s)**

A 2-minute walk-through of the workflow: what it does, how the nodes wire up, and what you change to fork it for your stack. Part of the [TrendAI Workflow Library "Workflows" playlist](https://www.youtube.com/playlist?list=PLnl2DWExbS90Bw74p_gL9o8Ut9F88C8PX).
<!-- E09.4-2-video-end -->

A production-shaped n8n workflow that turns a Google Sheet into a
**multi-channel post scheduler**: write a row with `post_text`,
`channel`, and `schedule_at`, and the workflow picks it up on the next
cron tick, optionally has Gemini rewrite it for the channel's voice,
fires the post via the channel's API, and writes the status + result
URL back to the same row.

The input surface is a **Google Sheet** because that's the lowest-
friction queue for non-technical operators — drag-fill 3 rows for
fan-out across channels and you're done. Swap the queue for Postgres
when you need atomic claim semantics or want to drive scheduling from
an app — `schema.sql` ships the production-grade variant.

## Pattern

```
Schedule Trigger - Every Minute (cron)
   ↓
Read Sheet Rows (Google Sheets - get all)
   ↓
Filter Queued + Due (code — status='queued' AND schedule_at <= now() AND channel in {fb,li,discord})
   ↓
Build Per-Channel Prompt (code — attach channel persona + length budget; default _post_text_final = source)
   ↓
Switch - Rewrite Enabled? (switch v3.2)
   ├─ rewrite=true → Call Gemini 2.5 Flash (HTTP — JSON mode, thinkingBudget: 0)
   │                    ↓
   │                 Parse Gemini Output (code — set _post_text_final to rewrite, fall back to source on empty)
   │                    ↓
   │                 Merge Rewrite + Pass-Through (index 0)
   │
   └─ rewrite=false ───────────────────────────── Merge Rewrite + Pass-Through (index 1)
                                                          ↓
                                              Switch - Route by Channel (switch v3.2)
                                                          ├─ fb       → Post to FB Page         (HTTP)
                                                          ├─ li       → Post to LinkedIn Company (HTTP)
                                                          └─ discord  → Post to Discord Webhook  (HTTP)
                                                                                ↓ (all 3 → same Code node)
                                                                Normalise Post Result (code — extract result_url, success, error per channel)
                                                                                ↓
                                                                  Update Sheet Row (Google Sheets — appendOrUpdate on [post_id, channel])
```

14 nodes. The Gemini rewrite is **off by default per row** — flip the
`rewrite_enabled` column to `TRUE` when you want a per-channel rewrite.
The composite match key `[post_id, channel]` means one logical post
fanning to FB + LI + Discord is **3 rows in the sheet** (one per
channel), and the workflow updates the corresponding row's status
independently as each channel posts.

## Required credentials

| Placeholder | n8n credential type | What it needs |
|---|---|---|
| `REPLACE_ME_gsheets-posts-queue` | Google Sheets OAuth2 | Read + write access to the queue sheet (used by both Read Sheet Rows and Update Sheet Row) |
| `REPLACE_ME_gemini-2-5-flash` | Google PaLM API (covers Gemini) | Gemini API key with access to `gemini-2.5-flash` — only used if a row has `rewrite_enabled=TRUE` |
| `REPLACE_ME_fb_page_access_token` (inline, body) | (no credential — token inline in jsonBody) | Long-lived Page access token for the target FB Page |
| `REPLACE_ME_fb_page_id` (inline, URL) | (no credential — page ID inline in URL) | Numeric Page ID for the target FB Page |
| `REPLACE_ME_linkedin_access_token` (inline, header) | (no credential — token inline in Authorization header) | LinkedIn Marketing Developer Platform access token with `w_organization_social` scope |
| `REPLACE_ME_linkedin_org_id` (inline, body) | (no credential — org ID inline in jsonBody) | Numeric Organization ID for the target LinkedIn Company Page |
| `REPLACE_ME_discord_webhook_url` (inline, URL) | (no credential — webhook URL is the secret) | Discord channel webhook URL |

Why inline tokens instead of n8n credentials for FB / LI / Discord?
Each of these APIs uses a long-lived bearer token (FB Page token, LI
access token) or a webhook URL where the URL itself is the secret —
none of them is a standard OAuth2 flow that n8n can manage
out-of-the-box for *one* Page / Org. Storing them as plain values in
the HTTP nodes keeps the template forkable without bespoke credential
gymnastics. For production, **promote each one to an n8n Header Auth
credential** (or a Set node feeding from a credential-backed source) —
see customisation point 4.

> **Sheets credential reuse.** Both Sheets nodes use the same
> credential ID. Bind it once in n8n's credential store; the second
> node picks it up by ID.

## Input sheet shape

See [`posts-input-sheet.md`](./posts-input-sheet.md) for the canonical
header row + sample data. Header columns the workflow reads:

| Column | Required | Read / write | Notes |
|---|---|---|---|
| `post_id` | yes | read | Operator-supplied; **must be unique per (post_id, channel)** — used as match key on status update |
| `channel` | yes | read | One of `fb` / `li` / `discord`; unknown channels are dropped silently |
| `post_text` | yes | read | The canonical source post — what the channel sees verbatim if `rewrite_enabled=FALSE` |
| `schedule_at` | yes | read | ISO 8601 timestamp; row only fires when `schedule_at <= now()` |
| `rewrite_enabled` | no | read | `TRUE` to run Gemini per-channel rewrite; anything else = pass-through |
| `status` | yes | read + write | Operator sets to `queued`; workflow updates to `posted` or `failed` |
| `posted_at` | no | write | Workflow writes ISO 8601 timestamp on success |
| `result_url` | no | write | Workflow writes channel-specific URL of the live post on success |
| `error` | no | write | Workflow writes truncated error message on failure |

The cron poll runs every minute; once the workflow writes
`status='posted'` (or `'failed'`), the row is no longer "queued" and
won't be re-picked. Re-trigger a failed row by editing `status` back
to `queued` (after fixing whatever the `error` column flagged).

## Setup

1. **Import the workflow.** In n8n: *Workflows → Import from File →*
   pick `workflow.json`.
2. **Re-bind credentials** on every node with `REPLACE_ME_…` — the
   only n8n credentials are the two Sheets nodes (same credential, two
   bindings) and the Gemini HTTP node. The FB / LI / Discord secrets
   are inline in the HTTP node bodies / URLs / headers — replace them
   in-place.
3. **Set the queue sheet** on both Sheet nodes: replace
   `REPLACE_ME_queue_sheet_id` and `REPLACE_ME_queue_sheet_gid` with
   your queue Sheet's document ID and sheet (tab) GID.
4. **Provision channel credentials** (one-time, per channel):
   - **FB Page:** Generate a long-lived Page access token from a
     Business Manager admin user. Replace `REPLACE_ME_fb_page_id` and
     `REPLACE_ME_fb_page_access_token` in the `Post to FB Page` node.
   - **LinkedIn Company:** Register an app on the Marketing Developer
     Platform, get `w_organization_social` scope, exchange for an
     access token. Replace `REPLACE_ME_linkedin_access_token` (in the
     Authorization header) and `REPLACE_ME_linkedin_org_id` (in the
     body URN) in the `Post to LinkedIn Company` node.
   - **Discord:** In the target Discord channel, *Edit channel → Integrations
     → Create Webhook*. Copy the webhook URL into `REPLACE_ME_discord_webhook_url`
     on the `Post to Discord Webhook` node.
5. **Seed the queue sheet** with the header row from
   `posts-input-sheet.md`, then drop a test row with
   `schedule_at = =NOW()` and `status = queued` to verify end-to-end.
6. **Activate the workflow.** Cron polls every minute; tune the
   interval in the `Schedule Trigger - Every Minute` node if you need
   tighter timing (1 min is fine for most scheduling use cases).

## Outputs

Per fired row, three side effects:

1. **Channel API call** — FB Graph / LinkedIn UGC Posts / Discord
   webhook with the (possibly rewritten) text.
2. **Sheet row update** — `status`, `posted_at`, `result_url`, `error`
   columns get the workflow's verdict for that row.
3. **No persistence by default** — the shipped template writes only
   back to the queue sheet. For a per-attempt audit log (retry-friendly,
   survives sheet edits), add the postgres `posts_log` lift point (see
   `schema.sql` + customisation point 2).

All three channel post nodes use `onError: continueRegularOutput` +
`neverError: true` on the HTTP response, so a 4xx/5xx from the channel
API still flows into `Normalise Post Result` — which detects the
failure shape and sets `status='failed'` + populates `error`. The
workflow never drops a row silently.

## Customisation guide (for consulting prospects)

The point of this template is to be **easy to fork for a specific
client**. The lift points are:

1. **The channel set.** Default is FB Page + LinkedIn Company +
   Discord. To add Instagram, Threads, or replace one of the defaults:
   add a new rule to `Switch - Route by Channel`, wire a new HTTP node
   for the target API, and add the channel's response-shape branch to
   `Normalise Post Result`. The Filter node's allowlist
   (`['fb','li','discord']`) needs the new channel added too. **X /
   Twitter intentionally omitted** — see anti-patterns below.

2. **Postgres-queue variant.** For at-most-once claim semantics, real
   indexes, and a per-attempt audit log, replace the two Sheets nodes
   with Postgres nodes per `schema.sql`. The Read becomes a
   `SELECT ... FOR UPDATE SKIP LOCKED` claim; the Update becomes an
   `UPDATE posts_scheduled SET status, posted_at, result_url, error
   WHERE post_id = $1 AND channel = $2`; add a third
   `INSERT INTO posts_log` call inside `Normalise Post Result` (or
   between it and the Update). Sample claim SQL is commented at the
   bottom of `schema.sql`.

3. **Per-channel time-zoning.** The current `schedule_at` is naive
   UTC. To schedule a post for "9 AM in the target audience's time
   zone", add a `timezone` column to the sheet, then in
   `Filter Queued + Due` convert `schedule_at` using the row's TZ
   before the `<= now()` comparison. Useful when a single source post
   fans out across US/EU/AU audiences at locally optimal times.

4. **Promote inline tokens to n8n credentials.** The FB / LI tokens
   are inline strings in the HTTP node bodies for forkability. In
   production, create n8n **Header Auth** credentials (FB:
   `Authorization: Bearer <token>` then move the token out of
   `access_token` query param; LI: same header), bind them via
   `nodeCredentialType: httpHeaderAuth`, and remove the inline
   `REPLACE_ME_*` placeholders. Discord webhook URLs don't have a
   header-auth equivalent — keep the URL inline or move it to a Set
   node fed from `$env.DISCORD_WEBHOOK_URL` for env-driven config.

5. **Attachment support (images / video).** The current workflow posts
   text only. To attach an image: add an `image_url` column to the
   sheet, then per-channel:
   - FB: change body to `{ message, link, access_token }` for link
     unfurl, or use `/photos` endpoint with `url` for image upload.
   - LI: change `shareMediaCategory` to `IMAGE` and add a `media`
     array with a pre-uploaded asset URN. Two-step: first POST to
     `/v2/assets?action=registerUpload`, then PUT the binary, then
     reference the asset URN in the post.
   - Discord: add `embeds[0].image.url` to the webhook body.

6. **Approval gate.** Default behaviour is auto-post when due. To gate
   posts behind manual approval, add a fourth status value `pending_approval`
   and update the Filter to only pick `status='queued'`; have a
   separate "approve" surface (a column-edit, a Cal.com block, an
   email-to-approve flow) flip rows from `pending_approval → queued`.

7. **Rate limiting.** The current workflow posts immediately on cron
   tick — N due rows = N concurrent channel API calls. For large
   queues, add a `SplitInBatches` node after `Filter Queued + Due`
   with `batchSize=5` and a `Wait` node between batches. See
   [n8n_splitinbatches_output_indices](../) for the output-wiring
   gotcha (the "done" output is index 0, not index 1).

## Anti-patterns this template demonstrates avoiding

- **X / Twitter posting.** Deliberately not included. X's API tier
  for posting is rate-limited and prone to enforcement changes; ventures
  on this stack are off X entirely. Use the spared engineering
  capacity to make the FB / LI / Discord posts better.
- **Page-shares-Page on FB.** When fanning content across multiple FB
  Pages, post natively to each Page (one row per Page) — never have
  one Page "share" another Page's post. Page-shares-Page fragments
  engagement metrics and looks like spam in the algorithm. If you run
  three Pages, you get three rows per post, not one Page-shares-Page
  chain.
- **Polling the Sheet on row-add.** The Google Sheets Trigger
  (`rowAdded` event) fires *when the row is added*, not when its
  `schedule_at` arrives — so it would fire a "2026-09-01 9am" row
  *now*. The cron-poll pattern fires on schedule_at instead, which is
  what scheduling means.
- **One row per post with comma-sep channels.** The earliest design
  for this template used one row per post + a `channels='fb,li,discord'`
  column that the workflow expanded internally. It works, but the
  status-update path then has to *re-aggregate* per-channel results
  back into the source row (race-condition risk on concurrent Sheet
  writes). One row per (post × channel) trades a column-drag of typing
  cost for dramatic workflow-clarity and zero race conditions. Other
  schedulers (Buffer, Hootsuite) do the same — what you see in their
  UI is one card per (post × channel), not one card with a channel
  multi-select.
- **Rewrite-always.** Forcing every post through Gemini is wasteful
  (the source post is often already channel-appropriate) and racks up
  API cost. The `rewrite_enabled` per-row toggle lets the operator
  pick when the rewrite is worth doing — e.g. rewrite the LI version,
  pass-through the Discord version of the same announcement.
- **Sheet write-back to the trigger sheet (via trigger node).** This
  template uses a *Cron* trigger that reads on schedule, not the
  Google Sheets Trigger node that watches for row events — so write-back
  to the same sheet is safe (it can't re-trigger a row). Template 4
  (CRM Data Enrichment) uses the Sheets Trigger pattern and separates
  input + output sheets *because* write-back to a trigger sheet can
  re-fire. Two different problems, two different patterns.

## Known limitations

- **No web research / link unfurl.** The Gemini rewrite works from the
  source post text only — it doesn't fetch URLs to summarise their
  content. For posts that include "more here: https://..." the
  rewriter treats the URL as an opaque token. To add link-unfurl
  context, prepend a Brave Search / fetch-URL HTTP node before the
  Gemini call and pass the unfurl summary as additional prompt
  context.
- **Cron polling lag.** The workflow polls once per minute. A post
  scheduled for `2026-06-01 09:00:00 UTC` will fire on the next cron
  tick after that timestamp — so up to 60s late on average. For
  precision better than that, tune the cron to every 15s (be aware of
  Sheets API quota) or move to a Postgres queue with a webhook-driven
  trigger.
- **LinkedIn API quota / token rotation.** LinkedIn access tokens
  expire (60-day default for Marketing Developer Platform). The
  template doesn't refresh tokens — when the token dies, every LI row
  will fail with `LI 401: ... ` in the `error` column. Surface that
  as a monitoring trigger (set up an alert when `status='failed' AND
  channel='li'` count crosses a threshold).
- **No retry.** A failed row stays failed until the operator manually
  flips `status` back to `queued`. For automatic retry-with-backoff,
  add a status `retry_pending` + a separate cron that promotes
  recent failures back to queued (with a `retry_count` cap). This is
  what `posts_log` (per-attempt audit) in `schema.sql` is for.
- **No per-channel character-limit enforcement.** Discord caps at 2000
  chars, LinkedIn at 3000, FB has no practical limit but the
  algorithm penalises >500. The Gemini rewrite respects the prompt's
  `length_target` but the pass-through (rewrite=false) path doesn't
  truncate. Add a Code node before the channel switch that truncates
  `_post_text_final` per-channel if you're feeding long source posts.
- **No idempotency on duplicate cron ticks.** If two cron ticks fire
  on the same row before the first one finishes updating the Sheet
  (rare, but possible if the channel API takes >60s), the row gets
  posted twice. The postgres-queue variant (`FOR UPDATE SKIP LOCKED`)
  fixes this; the Sheets variant relies on cron interval > slowest
  channel post + Sheet update round-trip (~5-10s typical).
