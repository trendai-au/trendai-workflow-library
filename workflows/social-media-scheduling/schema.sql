-- Social Media Scheduling — optional Postgres-queue schema
--
-- The shipped template uses a Google Sheet as the queue (lowest friction
-- for non-technical operators). This schema is the **production-grade
-- variant**: swap the Google Sheets nodes for the Postgres queries below
-- and you get atomic claim semantics, real indexes, and a per-channel
-- audit log that doesn't degrade as the queue grows.
--
-- See README.md customisation point 2 (postgres-queue variant) for the
-- one-by-one node replacements.
--
-- Re-runnable: every CREATE uses IF NOT EXISTS. Seed-data INSERTs at
-- the bottom use ON CONFLICT DO NOTHING so re-running is safe.

-- ---------------------------------------------------------------------------
-- 1. posts_scheduled — the queue itself. One row per (post × channel),
--    mirroring the Google Sheet shape so the workflow logic is identical.
--
--    Claim semantics: the consumer SELECTs queued+due rows with
--    FOR UPDATE SKIP LOCKED, immediately UPDATEs status='posting', and
--    commits — guaranteeing at-most-one in-flight worker per row even
--    with concurrent cron ticks.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.posts_scheduled (
    id                  BIGSERIAL PRIMARY KEY,
    post_id             TEXT NOT NULL,
    channel             TEXT NOT NULL
                        CHECK (channel IN ('fb','li','discord','ig','threads')),
    post_text           TEXT NOT NULL,
    schedule_at         TIMESTAMPTZ NOT NULL,
    rewrite_enabled     BOOLEAN NOT NULL DEFAULT false,
    status              TEXT NOT NULL DEFAULT 'queued'
                        CHECK (status IN ('queued','posting','posted','failed','skipped')),
    posted_at           TIMESTAMPTZ,
    result_url          TEXT,
    error               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (post_id, channel)
);

-- Fast claim lookup — partial index on the hot path (queued + due now).
CREATE INDEX IF NOT EXISTS posts_scheduled_due_idx
    ON public.posts_scheduled (schedule_at)
    WHERE status = 'queued';

-- Fast audit lookup — most recent posts first.
CREATE INDEX IF NOT EXISTS posts_scheduled_posted_at_idx
    ON public.posts_scheduled (posted_at DESC)
    WHERE status = 'posted';

-- Fast failure scan — surface failed rows for retry / triage.
CREATE INDEX IF NOT EXISTS posts_scheduled_failed_idx
    ON public.posts_scheduled (updated_at DESC)
    WHERE status = 'failed';

-- ---------------------------------------------------------------------------
-- 2. posts_log — per-attempt audit trail. Every POST attempt (success
--    OR failure) appends a row. This is separate from posts_scheduled
--    because a single queued row may be retried multiple times; we want
--    the queue table to show *current state* and the log table to show
--    *what happened*.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.posts_log (
    id                  BIGSERIAL PRIMARY KEY,
    post_id             TEXT NOT NULL,
    channel             TEXT NOT NULL,
    attempt_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    success             BOOLEAN NOT NULL,
    result_url          TEXT,
    rewrite_applied     BOOLEAN NOT NULL DEFAULT false,
    rewrite_notes       TEXT,
    text_posted         TEXT,
    error               TEXT,
    raw_response        JSONB
);

CREATE INDEX IF NOT EXISTS posts_log_post_channel_idx
    ON public.posts_log (post_id, channel, attempt_at DESC);

CREATE INDEX IF NOT EXISTS posts_log_attempt_at_idx
    ON public.posts_log (attempt_at DESC);

CREATE INDEX IF NOT EXISTS posts_log_failures_idx
    ON public.posts_log (channel, attempt_at DESC)
    WHERE success = false;

-- ---------------------------------------------------------------------------
-- Sample claim query — what the postgres-queue variant of the workflow's
-- Filter Queued + Due node would run instead of "read Google Sheet rows".
--
-- Replace `:max_batch` with however many rows you want per cron tick
-- (start with 50). Returns the claimed rows for the workflow to process.
-- ---------------------------------------------------------------------------
-- WITH claimed AS (
--   SELECT id
--   FROM public.posts_scheduled
--   WHERE status = 'queued' AND schedule_at <= now()
--   ORDER BY schedule_at ASC
--   LIMIT :max_batch
--   FOR UPDATE SKIP LOCKED
-- )
-- UPDATE public.posts_scheduled p
-- SET status = 'posting', updated_at = now()
-- FROM claimed c
-- WHERE p.id = c.id
-- RETURNING p.id, p.post_id, p.channel, p.post_text, p.schedule_at, p.rewrite_enabled;

-- ---------------------------------------------------------------------------
-- Sample seed posts — three illustrative rows covering the three channels
-- and both rewrite modes. Set schedule_at to a past timestamp to fire
-- immediately on the next cron tick.
-- ---------------------------------------------------------------------------
INSERT INTO public.posts_scheduled
    (post_id, channel, post_text, schedule_at, rewrite_enabled, status)
VALUES
    (
        'seed-001',
        'li',
        'Shipped our v2 analytics dashboard today. Three weeks of pairing with two design partners; biggest unlock was letting them rename our KPIs in-place.',
        now() - interval '1 minute',
        true,
        'queued'
    ),
    (
        'seed-001',
        'fb',
        'Shipped our v2 analytics dashboard today. Three weeks of pairing with two design partners; biggest unlock was letting them rename our KPIs in-place.',
        now() - interval '1 minute',
        true,
        'queued'
    ),
    (
        'seed-001',
        'discord',
        'v2 dashboard is live — let us know if anything looks off',
        now() - interval '1 minute',
        false,
        'queued'
    )
ON CONFLICT (post_id, channel) DO NOTHING;

-- ---------------------------------------------------------------------------
-- updated_at maintenance — keep posts_scheduled.updated_at fresh on edit.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS posts_scheduled_touch_updated_at ON public.posts_scheduled;
CREATE TRIGGER posts_scheduled_touch_updated_at
    BEFORE UPDATE ON public.posts_scheduled
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
