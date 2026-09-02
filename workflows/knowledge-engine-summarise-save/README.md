# Knowledge Engine — Summarise & Save (sub-workflow)

A reusable sub-workflow invoked by N parent workflows (article ingest,
inbox ingest, YouTube ingest, …). Encapsulates the **"feed me an
item, get back a summary + persisted row + a notification"** pattern.

## Pattern

```
Execute Workflow Trigger (called by parent: article | inbox | youtube …)
   ↓
Message a model (Gemini 2.5 Flash — summary + tags)
   ↓
Save to Supabase (insert into knowledge_items)
   ↓
Log Run (insert into knowledge_runs — observability)
   ↓
Discord Reply (post to ingest channel — operator visibility)
```

9 nodes. Designed as a sub-workflow so the parent ingestors stay
small and the summarisation logic lives in one place.

## Required credentials

| Placeholder | n8n credential type | What it needs |
|---|---|---|
| `REPLACE_ME_gemini-key-2-5-flash-openclaw` | Google PaLM API (the type covers Gemini) | Gemini API key with access to `gemini-2.5-flash` |
| `REPLACE_ME_supabase-account` | Supabase API | Supabase URL + service role key for your project |
| `REPLACE_ME_youtube-extractor-discord-bot-account` | Discord Bot API | Discord bot token + the destination channel ID |

Rename the placeholders to match what makes sense in your instance —
they're just hints.

## Required schema

The workflow expects two tables: `knowledge_items` (persisted content)
and `knowledge_runs` (per-call observability). Full DDL with indexes is
in [`schema.sql`](./schema.sql).

- **`knowledge_items`** — one row per ingested artefact. `source_type`
  + `external_id` form a logical dedup key (GIN-indexed `tags` for
  retrieval, `(source_type, created_at DESC)` for recency views).
- **`knowledge_runs`** — one row per sub-workflow invocation. Records
  `model`, `tokens_in`, `tokens_out`, `latency_ms`, and `status`. Lets
  you cost-account the pipeline and triage model errors retrospectively.

Apply with:

```bash
psql "$POSTGRES_URL" -f schema.sql
```

(Or paste into the Supabase SQL Editor — the DDL is plain Postgres.)

## Setup

1. Import `workflow.json` into your n8n instance.
2. Re-bind every credential (Gemini, Supabase, Discord — three
   credentials).
3. Edit `Message a model` node — review the prompt. The default
   prompt extracts: `title`, `summary` (3 short paragraphs),
   `tags` (array), `key_quote`, `thumbnail_url`. Adapt to your
   downstream consumers.
4. Edit `Discord Reply` node — set the channel ID for your team's
   ingest-notifications channel.
5. **This is a sub-workflow.** It expects to be called via an
   `Execute Workflow` node from a parent workflow with input shape:

   ```json
   {
     "source_type": "article",
     "source_url": "https://...",
     "raw_content": "<the article body text>",
     "external_id": "optional source-side id"
   }
   ```

## Inputs

See the JSON shape above. `raw_content` is the only load-bearing
field — the Gemini prompt will infer `title`, generate `summary`
and `tags`, and pick a `key_quote` from the body.

## Outputs

**Returned to parent:**

```json
{
  "id": 92,
  "title": "...",
  "summary": "...",
  "tags": ["..."]
}
```

**Side effects:**

1. One row in `knowledge_items`.
2. One row in `knowledge_runs` with model / tokens / latency.
3. One Discord message in the ingest channel with the title +
   summary preview.

## Customisation guide (for consulting prospects)

The point of this template is to be **easy to fork for a specific
client**. The lift points are:

1. **The prompt.** `Message a model` ships a generic "summary + tags
   + key_quote" extractor. For client work this is the single biggest
   lift — tune the prompt to extract whatever the downstream consumer
   actually needs (action items, sentiment band, named entities,
   compliance flags). Keep the output JSON-schema-validated so the
   `Save to Supabase` node doesn't blow up on drift.
2. **The persistence target.** Supabase is the default because of its
   instant REST surface + built-in auth. Swap for plain Postgres (use
   the `postgres` node) or any DB with an HTTP insert endpoint. The
   `knowledge_runs` observability table is intentionally separate from
   the content table so you can move them independently.
3. **The notification surface.** Discord is the default for solo /
   small-team operator visibility. Slack works identically (different
   webhook + payload shape). For multi-team setups, route on
   `source_type` so each ingest pipeline pings its own channel — add a
   Switch node before the notification step.
4. **The parent workflows.** This sub-workflow is meant to be called
   from N ingest parents. The canonical TrendAI Knowledge Engine has
   four parents (article-ingest, inbox-ingest, youtube-ingest, manual-
   ingest) all sharing this one summariser. Each parent does *source-
   specific extraction* (Readability for articles, IMAP for inbox,
   transcript fetch for YouTube), then calls this sub-workflow with
   the normalised input shape. Build parents for whatever sources
   matter to your client.
5. **The model.** Default is `gemini-2.5-flash` with thinking disabled
   (cheap + fast for a non-reasoning summarisation task). For higher-
   stakes content (legal docs, compliance review), swap the HTTP node
   for `gemini-2.5-pro` (remove the `thinkingConfig.thinkingBudget=0`
   override or it'll degrade), or for OpenAI / Anthropic via their
   respective HTTP shapes. Adjust the prompt to the new model's
   strengths.
6. **Dedup on re-ingest.** The shipped workflow always inserts. For
   re-ingest-friendly behaviour (e.g. an article is re-fetched), wrap
   `Save to Supabase` in an UPSERT on `(source_type, external_id)` —
   the index is already there. The `knowledge_runs` row stays
   insert-only so the run history isn't clobbered.

## Anti-patterns this template demonstrates avoiding

- **N parent workflows each summarise themselves.** If every ingest
  parent ran its own summarisation, prompt tuning would mean editing
  N nodes (and inevitably they'd drift). The sub-workflow extracts
  the *one* place the prompt lives — one tune, N parents benefit.
- **Persistence-only or notification-only.** Some pipelines either
  write to a DB *or* notify, not both. This template does both because
  they answer different questions: the DB is "what did we ingest"
  (queryable, durable), Discord is "what just happened" (operator
  attention). Drop the notification only if you have a separate
  observability surface (Grafana, etc.).
- **No `knowledge_runs` observability.** Skipping the per-call log
  works fine right up until you need to debug a cost spike or a quiet
  model degradation. `knowledge_runs` is cheap (one INSERT per
  invocation) and pays back the first time you ask "why did
  yesterday's batch take 4× longer than usual".
- **Inline `thinking_budget` for a reasoning task.** The override
  `thinkingConfig.thinkingBudget=0` is correct for Flash on a non-
  reasoning summarisation prompt. Carrying it forward to `gemini-2.5-
  pro` silently degrades quality — Pro is a reasoning model and
  benefits from thinking budget. Per-model overrides should match the
  model.
- **Sync-only parents.** Parents call this sub-workflow synchronously
  via Execute Workflow — fine when sources are small. For high-volume
  ingest, parents should *enqueue* (write a row to a queue table) and
  a separate consumer drains the queue calling this sub-workflow.
  Same prompt, decoupled rates.

## Known limitations

- **Single model.** Hard-coded to `gemini-2.5-flash`. To A/B another
  model, fork this workflow rather than param-driving — the prompt
  is tuned for Flash.
- **`thinkingConfig.thinkingBudget=0` set inline** — disabling
  thinking for a non-reasoning task. If you swap in `gemini-2.5-pro`
  (reasoning model), remove this override or it'll degrade.
- **Discord rate limits** can drop the notification step under bursty
  ingest; the row still lands in Supabase. Treat Discord as
  best-effort observability, not a guarantee.
- **No retry on Supabase write.** If `Save to Supabase` fails, the
  workflow errors out. The parent workflow should handle retry.

## See also

- [`case-study.md`](case-study.md) — sample input/output + observed
  metrics
- This was the canonical Summarise & Save in TrendAI's Knowledge Engine
  (4-workflow ingest pipeline: yt + article + inbox + this sub).
