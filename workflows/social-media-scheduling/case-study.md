# Case Study — Social Media Scheduling

What does a real fan-out look like end-to-end? This walkthrough shows
one source post going to FB Page, LinkedIn Company, and Discord — with
Gemini rewrite ON for LI + FB and OFF for Discord (the typical mix).

## Scenario

A SaaS founder wants to announce a v2 dashboard release. They draft
the source message once:

> Shipped our v2 analytics dashboard today. Three weeks of pairing
> with two design partners; biggest unlock was letting them rename our
> KPIs in-place. Live now for everyone on the Growth plan.

They want it on LinkedIn (long-form, professional tone), Facebook
(warmer, accessible), and Discord (just a heads-up to the community).
They open the queue sheet and drag-fill 3 rows:

| post_id | channel | post_text | schedule_at | rewrite_enabled | status |
|---|---|---|---|---|---|
| `launch-001` | `li` | *(source above)* | `2026-06-01T09:00:00Z` | `TRUE` | `queued` |
| `launch-001` | `fb` | *(source above)* | `2026-06-01T09:00:00Z` | `TRUE` | `queued` |
| `launch-001` | `discord` | `v2 dashboard is live — let us know if anything looks off` | `2026-06-01T09:00:00Z` | `FALSE` | `queued` |

(They wrote a shorter Discord copy directly in the sheet because they
know the community tone better than Gemini does — `rewrite_enabled=FALSE`
means the source text is posted verbatim.)

## What happens

At `2026-06-01T09:00:30Z` the cron tick fires. The workflow:

1. Reads all queue rows.
2. Filters down to the 3 rows above (`status='queued'`, `schedule_at <= now()`, channel supported).
3. Each row enters the per-channel prompt builder. The LI + FB rows go
   to Gemini for rewrite; the Discord row skips through the pass-through
   branch.

### Gemini rewrite — LinkedIn version

Per-channel persona (from `Build Per-Channel Prompt`):
- Voice: professional, insight-led, first-person plural
- Length target: 180-400 words
- Emoji policy: none
- Formatting: hook in first 2 lines, short paragraphs

Gemini returns (typical shape):

```
We just shipped v2 of our analytics dashboard.

Three weeks of close pairing with two design partners taught us
something we didn't expect: the single biggest unlock wasn't a new
chart type or a faster query engine. It was letting customers rename
our KPIs in-place.

What we called "weekly active users" they called "active studios."
What we called "trial-to-paid conversion" they called "first deposit."
Once the names matched the language they already used internally, the
dashboard stopped being a tool we'd built for them and started being
a tool they'd built for themselves.

It's a small lesson with a slightly bigger implication: the unit of
adoption isn't features, it's vocabulary. Match the vocabulary first,
and the features become discoverable on their own terms.

v2 is live for everyone on the Growth plan today. If you've been
waiting for in-place rename, this is your week.

What's the metric you've always wanted to rename in your own analytics?
```

(~190 words. Hook in first line; insight in middle; soft CTA via the
question at the end. No emojis, no markdown, scanable paragraphs.)

### Gemini rewrite — Facebook version

Per-channel persona:
- Voice: conversational, slightly warmer
- Length target: 80-200 words
- Emoji policy: 1-2 contextual emojis OK
- Formatting: short paragraphs, blank line between thoughts

Gemini returns:

```
v2 of our analytics dashboard is live today 🎉

Three weeks of pairing with two design partners, and the thing that
ended up making the biggest difference was something we almost didn't
build: letting customers rename our KPIs in-place.

Turns out "active studios" feels nothing like "weekly active users",
even when they're the exact same number. The names you put on a
metric end up being the names your team uses in meetings.

Live now for everyone on the Growth plan. We'd love to hear which
metric you'd rename first if you could.
```

(~110 words. Casual hook with one emoji. Same core message, lighter
tone, ends with a softer prompt for engagement.)

### Discord — pass-through

`rewrite_enabled=FALSE`, so the workflow skips Gemini and posts the
source text verbatim:

```
v2 dashboard is live — let us know if anything looks off
```

## What lands back in the sheet

| post_id | channel | status | posted_at | result_url | error |
|---|---|---|---|---|---|
| `launch-001` | `li` | `posted` | `2026-06-01T09:00:34Z` | `https://www.linkedin.com/feed/update/urn:li:share:7239847239847239847/` | |
| `launch-001` | `fb` | `posted` | `2026-06-01T09:00:33Z` | `https://www.facebook.com/123456789012345_678901234567890` | |
| `launch-001` | `discord` | `posted` | `2026-06-01T09:00:32Z` | `https://discord.com/channels/111222333444555666/777888999000111222/333444555666777888` | |

All three URLs are live and click-throughable.

## Latency budget — per-channel

| Stage | Time | Notes |
|---|---:|---|
| Cron tick fires | t=0 | Up to 60s wait from `schedule_at` ⇒ now() |
| Read sheet rows | ~1.5s | Depends on sheet size; ~1k rows is ~2s |
| Filter + per-channel prompt build | ~50ms | Pure JS, in-process |
| Gemini call (rewrite path) | ~1.5-3s | 2.5 Flash with `thinkingBudget: 0` + JSON mode |
| FB Page POST | ~400-800ms | Graph API consistent |
| LinkedIn POST | ~600-1200ms | More variable; UGC Posts API latency drifts |
| Discord webhook POST | ~150-300ms | Fast, low-variability |
| Sheet update | ~600-1000ms | Per row; concurrent writes serialise |
| **End-to-end (per row, rewrite ON)** | **~4-6s** | Critical path: Gemini + channel POST + sheet write |
| **End-to-end (per row, rewrite OFF)** | **~2-3s** | Skips the Gemini hop |

## Band-distribution sanity check (engagement)

After 4 weeks of operating, healthy posting flow looks like:

| Channel | Posts / week | Avg engagement rate | Reweight if you see… |
|---|---:|---:|---|
| LinkedIn Company | 3-5 | 3-6% | <2% → rewrite prompt is too generic; tighten the voice block |
| Facebook Page | 2-4 | 1-3% | <0.5% → likely posting at wrong time of day; add `timezone` column (customisation point 3) |
| Discord | 5-10 | n/a (read-by-default) | reactions count = signal; <10% reaction rate = community fatigued |

If LI engagement is high but FB is dead, the issue is almost always
**timing** (FB Page algorithm punishes off-hours posting harder than
LinkedIn does), not the rewrite quality. Surface `posted_at` in your
analytics layer and correlate with engagement to find the local
optimum.

## 5 metrics worth instrumenting once you're live

1. **Per-channel publish success rate** —
   `posted / (posted + failed)` per channel, last 7 days. Catches
   token-expiry incidents (especially LinkedIn) before the operator
   notices a quiet feed.
2. **Per-channel time-to-post** —
   `posted_at - schedule_at` distribution. p50 should be ~30s
   (half the cron interval); p99 > 90s means the cron is being
   throttled or the channel API is slow.
3. **Rewrite-vs-passthrough volume mix** —
   `count(rewrite_enabled=TRUE) / count(*)` per channel. Tells you
   how much Gemini cost you're carrying for what value; if rewrite
   is on for 100% of LI but engagement is the same as the
   pass-through 0% of Discord, the rewrite isn't earning its cost.
4. **Failure cluster by error type** —
   Group `error` column by the first 40 chars; a spike of one error
   signature (e.g. `LI 401: invalid_token`) is the canary for an
   expired credential.
5. **Stale-queued count** —
   `count(status='queued' AND schedule_at < now() - interval '5 minutes')`.
   Should always be 0 once the workflow is healthy. Non-zero =
   workflow is down OR a row has a malformed `channel` / `schedule_at`
   the filter is rejecting silently.

## 4 anti-pattern callouts (from operating this in prod)

1. **Posting all channels at the same `schedule_at`.** Optimal
   posting times differ by channel (LI: 7-9am business-day, FB:
   12-3pm weekday, Discord: whenever your community is online). The
   "one logical post, 3 rows" pattern lets each row have its own
   `schedule_at` — use that. Co-scheduling all 3 at 9am feels tidy
   but you'll get the worst-of-three on every channel.
2. **Editing the source text after posting.** The result_url points
   to the live post on the channel; editing the source row in the
   queue sheet AFTER `status='posted'` does **not** edit the live
   post. The sheet is a queue, not a CMS. To edit a live post, you
   have to go to the channel's own editor — the workflow has no
   "update post" path.
3. **Re-using a `post_id` for a different post.** The composite
   match key is `[post_id, channel]`. If you re-use `launch-001`
   for a v3 announcement after v2 already posted, the workflow's
   Sheet update will *overwrite* the v2 row's `posted_at` /
   `result_url`, losing the audit trail. Always pick fresh post_ids
   (timestamp-based generators work well: `2026-06-01-launch`).
4. **Posting to Discord with `@everyone` enabled.** The Discord
   webhook in this template passes the text verbatim — including
   any `@everyone` / `@here` mentions Gemini might generate during
   rewrite. The system prompt tells Gemini not to invent mentions,
   but the safer pattern is to set `allowed_mentions: { parse: [] }`
   in the Discord webhook body if you're not sure. Add that to the
   Discord HTTP node body in production.
