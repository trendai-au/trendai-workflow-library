# Content Idea Enqueue

A minimal webhook → postgres-queue producer. Drops a new task row into
a queue table so a separate processor workflow can pick it up later.
This is the **queue-producer** half of the queue-claim + processor
pattern (the **consumer** is on the scheduler instance).

## Pattern

```
Webhook (POST /content-idea)
   ↓
Code (validate + shape into queue row)
   ↓
Insert Task Queue (postgres → tos_runtime.task_queue)
   ↓
respondToWebhook ({ ok, task_id })
```

4 nodes. Decouples submission (cheap, sync) from processing (expensive,
async).

## Required credentials

| Placeholder | n8n credential type | What it needs |
|---|---|---|
| `REPLACE_ME_postgres-tos-runtime-writer` | Postgres | Host + DB + role with `INSERT` on `tos_runtime.task_queue` |

One credential. That's it.

## Required schema

```sql
CREATE TABLE tos_runtime.task_queue (
  task_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  task_type    TEXT NOT NULL,         -- 'content-idea' here
  payload      JSONB NOT NULL,        -- the webhook body
  status       TEXT NOT NULL DEFAULT 'pending',  -- 'pending' | 'claimed' | 'done' | 'error'
  claimed_at   TIMESTAMPTZ,
  claimed_by   TEXT,                  -- consumer ID for debugging
  completed_at TIMESTAMPTZ,
  error        TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_task_queue_pending ON tos_runtime.task_queue (created_at)
  WHERE status = 'pending';
```

## Setup

1. Import `workflow.json` into your n8n instance.
2. Re-bind the postgres credential.
3. Activate. The webhook URL appears in the `Webhook` node.

## Inputs

```json
{
  "idea": "Article about the n8n credential binding gotcha",
  "venture": "trendai",
  "priority": "normal"
}
```

The `Code` node is the schema gate — adjust it to enforce whatever
shape your downstream consumer needs.

## Outputs

**Synchronous webhook response (200):**

```json
{ "ok": true, "task_id": "..." }
```

**Side effect:** one row in `tos_runtime.task_queue` with
`status='pending'`. The processor workflow (a separate workflow on
your scheduler instance) is responsible for claiming + executing it.

## Known limitations

- **No deduplication.** Identical payloads create duplicate queue
  rows. If you need idempotency, hash the payload and either CHECK
  or upsert in the `Code` node.
- **No backpressure.** A flood of webhook calls will flood the queue;
  the consumer needs its own rate-limit/concurrency control.
- **Schema is illustrative.** The `task_type='content-idea'` is
  specific to this workflow. To enqueue different work, fork and
  change the constant in the `Code` node (or pass it in via the
  body).

## See also

- [`case-study.md`](case-study.md) — observed throughput + consumer
  pairing
- This is the producer half. The **consumer pattern** (claim a row
  with `UPDATE ... WHERE status='pending' RETURNING *` + execute +
  mark `done`/`error`) is a separate workflow not included in this
  library snapshot — see [SANITISATION-CHECKLIST](../../SANITISATION-CHECKLIST.md)
  for the wiring sketch.
