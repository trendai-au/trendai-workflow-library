# Case study — Content Idea Enqueue

Production-deployed sprint-17 as part of the No-Sheets doctrine
cutover (All.7-17.1b — migrating queue/trigger/log patterns off
Google Sheets to postgres-tos).

## Why this exists

Previous version was a Google Sheet with a row-append on form submit
and a separate sheet-polling consumer. The new postgres version:

- Sub-second insert latency (vs ~1s Sheets append)
- No 5M-cell hard limit (was ~6 months from hitting it)
- Native `UPDATE ... WHERE status='pending' RETURNING *` for claim
  semantics (vs Sheets's "find empty row" race condition)

## Sample input

```json
{
  "idea": "Write up the n8n credential binding gotcha — POST /credentials persists but doesn't bind at execution time",
  "venture": "trendai",
  "priority": "normal"
}
```

## Sample queue row produced

```json
{
  "task_id": "f0e7...",
  "task_type": "content-idea",
  "payload": {
    "idea": "Write up the n8n credential binding gotcha...",
    "venture": "trendai",
    "priority": "normal"
  },
  "status": "pending",
  "created_at": "2026-05-19T03:14:22Z"
}
```

## Webhook response

```json
{ "ok": true, "task_id": "f0e7..." }
```

## Consumer wiring (separate workflow)

On the n8n-scheduler instance, a cron-triggered workflow claims
pending rows:

```sql
UPDATE tos_runtime.task_queue
   SET status = 'claimed',
       claimed_at = now(),
       claimed_by = 'consumer-content-draft-v1'
 WHERE task_id = (
   SELECT task_id FROM tos_runtime.task_queue
    WHERE status = 'pending'
    ORDER BY created_at
    FOR UPDATE SKIP LOCKED
    LIMIT 1
 )
 RETURNING *;
```

The `FOR UPDATE SKIP LOCKED` makes the claim concurrent-safe — two
consumers can run in parallel without claiming the same row twice.

The consumer then processes (e.g. Gemini draft + Supabase persist)
and marks the row `done` or `error`.

## Metrics

Roughly two weeks of production traffic:

- **Throughput:** ~15 enqueues/day
- **Webhook p95 latency:** 220ms
- **Consumer turnaround p95:** ~90s (Gemini-bound)
- **Failed enqueues:** 0
- **Stuck `claimed` rows (consumer crashed):** 2 — recovered by a
  daily sweep that resets claims older than 1 hour

## Notes for re-users

This pattern is generic — `task_type='content-idea'` is the only
work-specific bit. For a different work queue:

1. Fork this workflow, rename the webhook path
2. Change the `task_type` constant in the `Code` node
3. Build a matching consumer workflow with the claim SQL above
4. Add a "stuck-claim sweep" workflow (cron-triggered, hourly)
   to reset `claimed_at < now() - interval '1 hour'` rows back
   to `pending`
