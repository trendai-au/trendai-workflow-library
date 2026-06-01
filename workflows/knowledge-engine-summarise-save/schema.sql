-- Knowledge Engine — Summarise & Save (sub-workflow)
-- Two tables: knowledge_items (persisted content) + knowledge_runs
-- (per-call observability). Designed for Supabase / Postgres; works
-- on either since there are no Supabase-specific extensions.

CREATE TABLE IF NOT EXISTS knowledge_items (
  id                BIGSERIAL PRIMARY KEY,
  source_type       TEXT NOT NULL,           -- 'article' | 'inbox' | 'youtube' | ...
  external_id       TEXT,                    -- source-specific ID (yt video id, message id, ...)
  source_url        TEXT,
  slug              TEXT,
  title             TEXT,
  author_or_source  TEXT,
  published_at      TIMESTAMPTZ,
  raw_content       TEXT,                    -- raw text in
  ai_summary        TEXT,                    -- model output
  summary_html      TEXT,
  thumbnail_url     TEXT,
  source_metadata   JSONB,
  shared_at         TIMESTAMPTZ,             -- set by the consumer that publishes it onward
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  tags              TEXT[],
  content_md        TEXT
);

CREATE INDEX IF NOT EXISTS knowledge_items_source_type_created_at_idx
  ON knowledge_items (source_type, created_at DESC);

CREATE INDEX IF NOT EXISTS knowledge_items_external_id_idx
  ON knowledge_items (source_type, external_id)
  WHERE external_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS knowledge_items_tags_gin
  ON knowledge_items USING GIN (tags);

CREATE TABLE IF NOT EXISTS knowledge_runs (
  run_id        BIGSERIAL PRIMARY KEY,
  source_type   TEXT NOT NULL,
  source_url    TEXT,
  status        TEXT NOT NULL,               -- 'ok' | 'error'
  model         TEXT,                        -- e.g. 'gemini-2.5-flash'
  tokens_in     INTEGER,
  tokens_out    INTEGER,
  latency_ms    INTEGER,
  error         TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS knowledge_runs_status_created_at_idx
  ON knowledge_runs (status, created_at DESC);

CREATE INDEX IF NOT EXISTS knowledge_runs_source_type_idx
  ON knowledge_runs (source_type, created_at DESC);
