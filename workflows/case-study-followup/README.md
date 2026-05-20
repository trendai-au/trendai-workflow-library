# Case Study Followup Sequence

Minimal "schedule a followup task" webhook. Inserts a row into a
postgres queue with a `scheduled_for` timestamp; a consumer workflow
fires the actual followup when its time arrives. Useful for nurture
sequences, scheduled reminders, and any "do X at time T" need.

## Pattern

```
Webhook (POST /schedule-followup)
   ↓
Code (compute scheduled_for from delay_days + shape the row)
   ↓
Insert Task Queue (postgres → tos_runtime.task_queue)
```

3 nodes. Distinct from the immediate-execute Enqueue pattern in that
the row carries a `scheduled_for` timestamp the consumer respects.

## Required credentials

| Placeholder | n8n credential type | What it needs |
|---|---|---|
| `REPLACE_ME_postgres-tos-runtime-writer` | Postgres | Host + DB + role with `INSERT` on `tos_runtime.task_queue` |

## Required schema

Same `task_queue` shape as [content-idea-enqueue](../content-idea-enqueue/),
plus one extra column:

```sql
ALTER TABLE tos_runtime.task_queue
  ADD COLUMN IF NOT EXISTS scheduled_for TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS ix_task_queue_due
  ON tos_runtime.task_queue (scheduled_for)
  WHERE status = 'pending';
```

Consumer claim query becomes:

```sql
UPDATE tos_runtime.task_queue
   SET status='claimed', claimed_at=now()
 WHERE task_id = (
   SELECT task_id FROM tos_runtime.task_queue
    WHERE status='pending'
      AND (scheduled_for IS NULL OR scheduled_for <= now())
    ORDER BY scheduled_for NULLS LAST, created_at
    FOR UPDATE SKIP LOCKED
    LIMIT 1
 )
 RETURNING *;
```

## Setup

1. Import + re-bind the postgres credential
2. Activate

## Inputs

```json
{
  "case_study_url": "https://your-site.com/case-studies/acme",
  "recipient_email": "lead@example.com",
  "delay_days": 7,
  "template_id": "case-study-followup-v1"
}
```

The `Code` node uses `delay_days` to compute `scheduled_for = now() + interval '<delay_days> days'`.

## Outputs

**Synchronous webhook response:**

```json
{ "ok": true, "task_id": "...", "scheduled_for": "2026-05-27T03:14:22Z" }
```

**Side effect:** one row in `tos_runtime.task_queue` with `status='pending'`,
`task_type='case-study-followup'`, `scheduled_for=<now + delay_days>`.

## Known limitations

- **Trusts the caller's `delay_days`.** Caps the value at 365 days in
  the `Code` node; adjust if you need longer.
- **Cancellation:** to cancel a scheduled task, the consumer or a
  separate admin workflow needs to flip `status` to `cancelled`
  before `scheduled_for` arrives. No cancellation surface in this
  workflow.

## See also

- [`case-study.md`](case-study.md) — observed nurture-sequence usage
- Sibling: [`content-idea-enqueue`](../content-idea-enqueue/) — same
  queue table, immediate-execution shape
