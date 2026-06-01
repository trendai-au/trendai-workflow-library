-- voice-agent — postgres schema
-- One row per Vapi inbound call. Mirror of the form-intake `submissions`
-- table shape: persist-first, per-step status columns, idempotent retries.
--
-- Apply with:  psql "$POSTGRES_URL" -f schema.sql

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.voice_calls (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Vapi correlation
    vapi_call_id          text UNIQUE NOT NULL,
    vapi_assistant_id     text,
    phone_number          text,
    direction             text CHECK (direction IN ('inbound', 'outbound')),

    -- Call lifecycle
    started_at            timestamptz,
    ended_at              timestamptz,
    duration_seconds      integer,
    ended_reason          text,
    recording_url         text,

    -- Extracted lead fields (from tool-call output or transcript LLM parse)
    firstname             text,
    lastname              text,
    company               text,
    email                 text,
    need                  text,
    timing                text,
    callback_consent      boolean,

    -- Raw artefacts (always persisted, even on partial failure)
    transcript            text,
    summary               text,
    structured_data       jsonb,
    raw_payload           jsonb NOT NULL,

    -- Downstream propagation state (per-step verdicts so partial failure is recoverable)
    status                text NOT NULL DEFAULT 'received'
                            CHECK (status IN ('received', 'parsed', 'hubspot_ok', 'email_ok',
                                              'completed', 'probe_completed', 'failed')),
    hubspot_contact_id    text,
    hubspot_synced_at     timestamptz,
    hubspot_error         text,
    operator_notified_at  timestamptz,
    operator_notify_error text,

    -- Retry plumbing (sweep job reads next_retry_at)
    last_attempt_at       timestamptz,
    attempt_count         integer NOT NULL DEFAULT 0,
    next_retry_at         timestamptz,

    received_at           timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS voice_calls_status_idx
    ON public.voice_calls (status);

CREATE INDEX IF NOT EXISTS voice_calls_next_retry_idx
    ON public.voice_calls (next_retry_at)
    WHERE next_retry_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS voice_calls_phone_idx
    ON public.voice_calls (phone_number);

-- updated_at trigger
CREATE OR REPLACE FUNCTION public.voice_calls_set_updated_at()
RETURNS trigger AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS voice_calls_updated_at ON public.voice_calls;
CREATE TRIGGER voice_calls_updated_at
    BEFORE UPDATE ON public.voice_calls
    FOR EACH ROW EXECUTE FUNCTION public.voice_calls_set_updated_at();
