# Form Intake — Lead Capture (postgres → HubSpot → Brevo)

Production form-intake chain following the **resumable-pipeline
doctrine**: persist the raw submission first, propagate to downstream
systems, mark per-step state so retries are idempotent.

## Pattern

```
Webhook (POST /lead-capture)
   ↓
Insert Submission (postgres → form_intake.submissions)
   ↓
[probe?] → Mark Probe Completed       ← end early if just a probe
   ↓
HubSpot Upsert (contact create-or-update)
   ↓ ↓
   OK            Error
   ↓            ↓
Update HubSpot OK / Error (postgres status)
   ↓
Brevo Client Confirm Email
   ↓ ↓
   OK            Error
   ↓            ↓
Update Email OK / Error → Mark Completed
```

15 nodes. Two failure-isolation IFs so HubSpot failure doesn't block
the confirmation email and vice versa.

## Required credentials

| Placeholder | n8n credential type | What it needs |
|---|---|---|
| `REPLACE_ME_postgres-form-intake-writer` | Postgres | Host + DB + role with `INSERT/UPDATE` on `form_intake.submissions` |
| `REPLACE_ME_hubspot-trendai-token` | HTTP Header Auth | HubSpot private app PAT in `Authorization: Bearer <token>` |
| `REPLACE_ME_brevo-trendai-api` | HTTP Header Auth | Brevo API key in `api-key: <key>` |

The "trendai" / "form-intake" in the placeholder names is just a hint
about what each credential is for — rename to whatever fits your
instance.

## Required schema

A `submissions` table in your postgres database. Minimum columns the
workflow reads/writes:

```sql
CREATE TABLE form_intake.submissions (
  submission_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source         TEXT NOT NULL,            -- 'lead-capture' here
  payload        JSONB NOT NULL,           -- the raw webhook body
  hubspot_status TEXT,                     -- 'ok' | 'error' | NULL
  email_status   TEXT,                     -- 'ok' | 'error' | NULL
  status         TEXT NOT NULL DEFAULT 'received',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

## Setup

1. Import `workflow.json` into your n8n instance.
2. Open each node with a credential dropdown and bind it to your own
   credential. **The placeholder IDs do not resolve at runtime** —
   the workflow won't execute until every cred is re-bound. (This is
   intentional; see the n8n credential binding gotcha in
   [SANITISATION-CHECKLIST](../../SANITISATION-CHECKLIST.md#known-n8n-quirks).)
3. Edit `HubSpot Upsert` node body — replace any tenant-specific
   property names with your own portal's. By default the workflow
   writes `email`, `firstname`, `lastname`, `company` — adjust to your
   schema.
4. Edit `Client Confirm Email` node body — Brevo template ID, sender
   address, and subject are stubs and need to match a real template
   in your Brevo account.
5. Activate the workflow. The webhook URL appears in the `Webhook`
   node after save.

## Inputs (POST body to the webhook)

```json
{
  "email": "alice@example.com",
  "firstname": "Alice",
  "lastname": "Liddell",
  "company": "Wonderland Inc.",
  "message": "Interested in a consult.",
  "probe": false
}
```

`probe: true` is a health-check call — the workflow inserts the row
with `source='probe'` and exits without calling HubSpot/Brevo.
Useful for monitoring the webhook surface without polluting CRM.

## Outputs

**Synchronous webhook response (200 OK):**

```json
{ "ok": true, "submission_id": "..." }
```

**Side effects:**

1. One row in `form_intake.submissions` (status walks through
   `received` → `hubspot_ok` → `email_ok` → `completed`).
2. One contact upserted in HubSpot.
3. One confirmation email sent via Brevo.

Each side effect is recorded in its own status column — a partial
failure leaves the row recoverable. The `submission_id` returned to
the caller is the postgres row's UUID.

## Known limitations

- **Brevo template stub.** `Client Confirm Email` references a
  template by ID; the import won't fail but the email won't render
  until you replace the ID with a real one from your Brevo account.
- **HubSpot property mapping.** The `HubSpot Upsert` body writes a
  small fixed set of properties. If your portal uses different
  property names (e.g. `phone` instead of `mobile`), edit the node.
- **No queue / retry.** Failures are recorded in postgres but not
  retried automatically. If HubSpot is down, the workflow stamps
  `hubspot_status='error'` and moves on. Pair with a scheduled
  re-process job for retry semantics.
- **Webhook URL is public** by default. Add an API key gate (HTTP
  Header Auth on the webhook node, or a Cloudflare WAF rule)
  before exposing to real traffic.

## See also

- [`case-study.md`](case-study.md) — worked example with sample
  HubSpot response + email rendering
- Sibling workflow [`case-study-followup`](../case-study-followup/) —
  uses the same `submissions` table as input
