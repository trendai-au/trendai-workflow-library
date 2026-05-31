-- CRM Data Enrichment — required schema
--
-- Two tables: icp_profiles, contacts_enriched.
-- Run against any Postgres >= 13. The workflow expects these in the
-- search_path of the credential it uses (default schema = public).
--
-- Re-runnable: every CREATE uses IF NOT EXISTS. Seed-data INSERTs at
-- the bottom use ON CONFLICT DO NOTHING so re-running is safe.

-- ---------------------------------------------------------------------------
-- 1. icp_profiles — configurable ICP definitions. The workflow's
--    Score Against ICPs node loads is_active=true rows and picks the
--    best match per contact (highest weighted axis-hit count).
--
--    Each axis is a TEXT[] of allowed values; empty array means
--    "unconstrained on this axis" (auto-match). All four axes hitting
--    gives 100; one axis missing gives 75; etc. The weight column
--    multiplies the raw score before the band cut.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.icp_profiles (
    id                          BIGSERIAL PRIMARY KEY,
    name                        TEXT UNIQUE NOT NULL,
    description                 TEXT,
    target_industries           TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    target_size_bands           TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    target_role_seniorities     TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    target_business_models      TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    weight                      NUMERIC(3,2) NOT NULL DEFAULT 1.00
                                CHECK (weight > 0 AND weight <= 2.00),
    is_active                   BOOLEAN NOT NULL DEFAULT true,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS icp_profiles_active_idx
    ON public.icp_profiles (is_active, weight DESC)
    WHERE is_active = true;

-- ---------------------------------------------------------------------------
-- 2. contacts_enriched — one row per email. Upserted on (email).
--    Stores both the raw input fields (for audit) and the full
--    Gemini-derived enrichment + ICP match.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.contacts_enriched (
    id                  BIGSERIAL PRIMARY KEY,
    email               TEXT UNIQUE NOT NULL,
    name                TEXT,

    -- Raw input fields (kept so re-runs can see what the model saw)
    company_input       TEXT,
    role_input          TEXT,
    source              TEXT,

    -- Gemini enrichment fields
    company_name        TEXT,
    industry            TEXT NOT NULL DEFAULT 'Unknown',
    size_band           TEXT NOT NULL DEFAULT 'unknown'
                        CHECK (size_band IN ('solo','2-10','11-50','51-200','201-1000','1000+','unknown')),
    hq_country          TEXT,
    business_model      TEXT NOT NULL DEFAULT 'Unknown'
                        CHECK (business_model IN ('B2B','B2C','B2B2C','Marketplace','Unknown')),
    signals             JSONB NOT NULL DEFAULT '[]'::jsonb,
    role_seniority      TEXT NOT NULL DEFAULT 'unknown'
                        CHECK (role_seniority IN ('ic','senior_ic','manager','director','vp','c_level','founder','unknown')),
    role_function       TEXT NOT NULL DEFAULT 'unknown'
                        CHECK (role_function IN ('engineering','product','marketing','sales','ops','finance','hr','exec','other','unknown')),
    outreach_hook       TEXT,
    outreach_confidence TEXT NOT NULL DEFAULT 'low'
                        CHECK (outreach_confidence IN ('low','medium','high')),
    confidence_notes    TEXT,

    -- ICP match result
    icp_id              BIGINT REFERENCES public.icp_profiles(id) ON DELETE SET NULL,
    icp_name            TEXT NOT NULL DEFAULT 'no-icp-match',
    icp_score           INTEGER NOT NULL DEFAULT 0
                        CHECK (icp_score BETWEEN 0 AND 100),
    band                TEXT NOT NULL DEFAULT 'cold'
                        CHECK (band IN ('hot','warm','cold')),

    enriched_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS contacts_enriched_band_score_idx
    ON public.contacts_enriched (band, icp_score DESC);

CREATE INDEX IF NOT EXISTS contacts_enriched_industry_size_idx
    ON public.contacts_enriched (industry, size_band);

CREATE INDEX IF NOT EXISTS contacts_enriched_enriched_at_idx
    ON public.contacts_enriched (enriched_at DESC);

-- ---------------------------------------------------------------------------
-- Seed ICP profiles — three illustrative ICPs covering the band thresholds.
-- These are deliberately demo-shaped; swap them out for your real ICPs.
--
-- Scoring with 4 axes worth 25 points each:
--   4-axis hit + weight 1.00 = 100 → hot
--   3-axis hit + weight 1.00 =  75 → hot (borderline)
--   2-axis hit + weight 1.00 =  50 → warm
--   1-axis hit + weight 1.00 =  25 → cold
--   0-axis hit                 =   0 → cold
--
-- Band thresholds are hardcoded in the Score Against ICPs node:
--   hot  >= 75
--   warm 40-74
--   cold < 40
-- ---------------------------------------------------------------------------
INSERT INTO public.icp_profiles
    (name, description, target_industries, target_size_bands, target_role_seniorities, target_business_models, weight, is_active)
VALUES
    (
        'AU SMB SaaS founders',
        'Australian SaaS companies under 50 staff, founder or C-level decision maker, B2B model.',
        ARRAY['SaaS'],
        ARRAY['solo','2-10','11-50'],
        ARRAY['founder','c_level'],
        ARRAY['B2B','B2B2C'],
        1.20,
        true
    ),
    (
        'Mid-market marketing ops',
        'Marketing or ops leaders at 51-200-person companies across SaaS / Ecommerce / Marketing verticals.',
        ARRAY['SaaS','Ecommerce','Marketing'],
        ARRAY['51-200','201-1000'],
        ARRAY['manager','director','vp'],
        ARRAY['B2B','B2C','B2B2C'],
        1.00,
        true
    ),
    (
        'Trade services digitisation',
        'Construction / hospitality / logistics businesses (any size, any role). Broad-axis cold-outreach ICP.',
        ARRAY['Construction','Hospitality','Logistics'],
        ARRAY[]::TEXT[],
        ARRAY[]::TEXT[],
        ARRAY['B2B','B2C'],
        0.85,
        true
    )
ON CONFLICT (name) DO NOTHING;

-- ---------------------------------------------------------------------------
-- updated_at maintenance — keep icp_profiles.updated_at fresh on edit.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS icp_profiles_touch_updated_at ON public.icp_profiles;
CREATE TRIGGER icp_profiles_touch_updated_at
    BEFORE UPDATE ON public.icp_profiles
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
