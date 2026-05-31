-- Customer Support Chatbot — required schema
--
-- Four tables: conversations, messages, tickets, orders.
-- Run against any Postgres ≥ 13. The workflow expects these in the
-- search_path of the credential it uses (default schema = public).
--
-- Re-runnable: every CREATE uses IF NOT EXISTS. Seed-data INSERTs at
-- the bottom use ON CONFLICT DO NOTHING so re-running is safe.

-- ---------------------------------------------------------------------------
-- 1. conversations — one row per chat session
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.conversations (
    id              UUID PRIMARY KEY,
    customer_email  TEXT,
    status          TEXT NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active', 'pending_human', 'closed')),
    metadata        JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS conversations_status_idx
    ON public.conversations (status)
    WHERE status = 'pending_human';

CREATE INDEX IF NOT EXISTS conversations_customer_email_idx
    ON public.conversations (customer_email);

-- ---------------------------------------------------------------------------
-- 2. messages — every user/assistant/system turn
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.messages (
    id               BIGSERIAL PRIMARY KEY,
    conversation_id  UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    role             TEXT NOT NULL
                     CHECK (role IN ('user', 'assistant', 'system')),
    content          TEXT NOT NULL,
    intent_label     TEXT,   -- populated for assistant turns: qa | order_lookup | ticket_create | handoff
    metadata         JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS messages_conversation_id_created_at_idx
    ON public.messages (conversation_id, created_at);

-- ---------------------------------------------------------------------------
-- 3. tickets — created by the ticket_create branch
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.tickets (
    id                BIGSERIAL PRIMARY KEY,
    conversation_id   UUID REFERENCES public.conversations(id) ON DELETE SET NULL,
    customer_email    TEXT,
    subject           TEXT NOT NULL,
    description       TEXT,
    priority          TEXT NOT NULL DEFAULT 'normal'
                      CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    status            TEXT NOT NULL DEFAULT 'open'
                      CHECK (status IN ('open', 'in_progress', 'resolved', 'closed')),
    assigned_to       TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS tickets_status_idx
    ON public.tickets (status)
    WHERE status IN ('open', 'in_progress');

CREATE INDEX IF NOT EXISTS tickets_customer_email_idx
    ON public.tickets (customer_email);

-- ---------------------------------------------------------------------------
-- 4. orders — read by the order_lookup branch
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.orders (
    id              BIGSERIAL PRIMARY KEY,
    order_number    TEXT UNIQUE NOT NULL,
    customer_email  TEXT NOT NULL,
    status          TEXT NOT NULL
                    CHECK (status IN ('pending', 'confirmed', 'shipped', 'delivered', 'cancelled', 'refunded')),
    total_cents     INTEGER NOT NULL,
    currency        TEXT NOT NULL DEFAULT 'AUD',
    items           JSONB NOT NULL DEFAULT '[]'::jsonb,
    tracking_url    TEXT,
    placed_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS orders_customer_email_idx
    ON public.orders (customer_email);

-- ---------------------------------------------------------------------------
-- Seed data — enough to demo the order_lookup branch
-- ---------------------------------------------------------------------------
INSERT INTO public.orders (order_number, customer_email, status, total_cents, currency, items, tracking_url, placed_at)
VALUES
    ('ORD-1001', 'jamie@example.com', 'shipped',   12900, 'AUD',
     '[{"sku":"WIDGET-A","qty":2,"price_cents":4900},{"sku":"WIDGET-B","qty":1,"price_cents":3100}]'::jsonb,
     'https://tracking.example.com/ORD-1001', now() - interval '3 days'),
    ('ORD-1002', 'jamie@example.com', 'delivered', 4900,  'AUD',
     '[{"sku":"WIDGET-A","qty":1,"price_cents":4900}]'::jsonb,
     'https://tracking.example.com/ORD-1002', now() - interval '14 days'),
    ('ORD-1003', 'priya@example.com', 'pending',   8900,  'AUD',
     '[{"sku":"WIDGET-C","qty":1,"price_cents":8900}]'::jsonb,
     NULL, now() - interval '2 hours'),
    ('ORD-1004', 'priya@example.com', 'cancelled', 4900,  'AUD',
     '[{"sku":"WIDGET-A","qty":1,"price_cents":4900}]'::jsonb,
     NULL, now() - interval '7 days')
ON CONFLICT (order_number) DO NOTHING;

-- ---------------------------------------------------------------------------
-- updated_at maintenance — keep conversations.updated_at fresh on touch.
-- The workflow does this explicitly in the upsert too, but the trigger
-- keeps it honest for any external writer (admin tools, manual fixes).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS conversations_touch_updated_at ON public.conversations;
CREATE TRIGGER conversations_touch_updated_at
    BEFORE UPDATE ON public.conversations
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

DROP TRIGGER IF EXISTS tickets_touch_updated_at ON public.tickets;
CREATE TRIGGER tickets_touch_updated_at
    BEFORE UPDATE ON public.tickets
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
