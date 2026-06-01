-- Form Intake — Lead Capture
-- Minimum schema the workflow reads/writes. Lives in its own schema
-- (`form_intake`) so multiple intake workflows can share one DB
-- without colliding on table names.

CREATE SCHEMA IF NOT EXISTS form_intake;

CREATE TABLE IF NOT EXISTS form_intake.submissions (
  submission_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source          TEXT NOT NULL,            -- 'lead-capture' here; 'probe' for health checks
  payload         JSONB NOT NULL,           -- the raw webhook body
  hubspot_status  TEXT,                     -- 'ok' | 'error' | NULL
  email_status    TEXT,                     -- 'ok' | 'error' | NULL
  status          TEXT NOT NULL DEFAULT 'received',
                                            -- 'received' → 'hubspot_ok' → 'email_ok' → 'completed'
                                            -- or 'probe_completed' for probe submissions
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Helpful indexes for retry-sweep jobs.
CREATE INDEX IF NOT EXISTS submissions_status_idx
  ON form_intake.submissions (status, created_at DESC);

CREATE INDEX IF NOT EXISTS submissions_hubspot_status_idx
  ON form_intake.submissions (hubspot_status)
  WHERE hubspot_status = 'error';

CREATE INDEX IF NOT EXISTS submissions_email_status_idx
  ON form_intake.submissions (email_status)
  WHERE email_status = 'error';

-- Keep updated_at fresh on UPDATE.
CREATE OR REPLACE FUNCTION form_intake.touch_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS submissions_touch_updated_at ON form_intake.submissions;
CREATE TRIGGER submissions_touch_updated_at
  BEFORE UPDATE ON form_intake.submissions
  FOR EACH ROW EXECUTE FUNCTION form_intake.touch_updated_at();
