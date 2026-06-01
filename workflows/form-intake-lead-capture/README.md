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

The workflow expects a `submissions` table in your postgres database,
inside a `form_intake` schema. Full DDL with indexes and the
`updated_at` trigger is in [`schema.sql`](./schema.sql).

- **`form_intake.submissions`** — one row per webhook submission.
  Walks through `status` values `received → hubspot_ok → email_ok →
  completed` (or `probe_completed` for health-check submissions). The
  `hubspot_status` and `email_status` columns record per-step verdicts
  so a partial failure leaves the row recoverable.

Apply with:

```bash
psql "$POSTGRES_URL" -f schema.sql
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

## Customisation guide (for consulting prospects)

The point of this template is to be **easy to fork for a specific
client**. The lift points are:

1. **The CRM.** HubSpot is the default. Swap `HubSpot Upsert` for a
   Pipedrive *Person — Update*, a Salesforce *Lead — Upsert*, or any
   CRM with an upsert-by-email endpoint. The Insert / IF / Update
   plumbing around it stays unchanged — failure isolation is the
   value, not the specific CRM.
2. **The transactional mailer.** Brevo is the default. Mailgun,
   SendGrid, Postmark, Resend, and Amazon SES all follow the same
   pattern: template ID + recipient + dynamic data. Replace the
   `Client Confirm Email` HTTP node's URL + auth header + body shape,
   leave the IF + status-update plumbing untouched.
3. **The form fields.** The default payload is `email`, `firstname`,
   `lastname`, `company`, `message`. Add fields by extending the
   webhook payload, the `Insert Submission` JSONB column (no DDL
   change needed — payload is JSONB), and the CRM upsert body. The
   IF / Update / status-walk plumbing stays as-is.
4. **The probe semantic.** The `probe: true` short-circuit is a
   monitoring hook — `Mark Probe Completed` writes a `probe_completed`
   row and exits. Wire your uptime monitor (Kuma, BetterStack, Pingdom)
   to POST `{"probe": true}` once per minute; query `WHERE
   status='probe_completed'` to confirm the full chain is live without
   polluting CRM / mailer with synthetic contacts.
5. **Failure-isolation in your own pipeline.** The IF-after-each-side-
   effect pattern (HubSpot OK / Error → Update; Email OK / Error →
   Update) is the reusable shape. Apply it any time you chain N
   independent side effects where partial success is still partial
   delivery — the row records what happened, a sweep job retries the
   errored steps.

## Anti-patterns this template demonstrates avoiding

- **Single try / catch around the whole chain.** Wrapping HubSpot +
  email in one error handler means a HubSpot 500 swallows the email
  attempt — the customer gets nothing even though Brevo was up. Per-
  step IFs decouple the failures.
- **Propagate-then-persist.** The naïve shape is *call HubSpot, call
  Brevo, then write a row*. If HubSpot 500s before the row exists,
  the submission is gone with no audit trail. Persist first, propagate
  second — the `submissions` row is the source of truth, not the CRM.
- **In-flight retries.** The workflow records `hubspot_status='error'`
  and moves on; it does not retry inline. A separate sweep job
  (cron-driven `SELECT WHERE hubspot_status='error'` + replay) handles
  retries idempotently against the same row's `submission_id`. Mixing
  retry into the inline path multiplies side effects on flaky CRMs.
- **Webhook URL exposed without an auth gate.** The default has no
  auth — fine for templating, dangerous in production. Add HTTP
  Header Auth on the Webhook node (operator-supplied bearer) or a
  Cloudflare WAF rate-limit rule before exposing to real traffic.

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
