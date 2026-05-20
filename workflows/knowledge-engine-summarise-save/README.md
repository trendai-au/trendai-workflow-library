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

```sql
CREATE TABLE knowledge_items (
  id              BIGSERIAL PRIMARY KEY,
  source_type     TEXT NOT NULL,           -- 'article' | 'inbox' | 'youtube'
  external_id     TEXT,                    -- source-specific ID
  source_url      TEXT,
  slug            TEXT,
  title           TEXT,
  author_or_source TEXT,
  published_at    TIMESTAMPTZ,
  raw_content     TEXT,                    -- raw text
  ai_summary      TEXT,                    -- model output
  summary_html    TEXT,
  thumbnail_url   TEXT,
  source_metadata JSONB,
  shared_at       TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  tags            TEXT[],
  content_md      TEXT
);

CREATE TABLE knowledge_runs (
  run_id          BIGSERIAL PRIMARY KEY,
  source_type     TEXT NOT NULL,
  source_url      TEXT,
  status          TEXT NOT NULL,           -- 'ok' | 'error'
  model           TEXT,
  tokens_in       INTEGER,
  tokens_out      INTEGER,
  latency_ms      INTEGER,
  error           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

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
