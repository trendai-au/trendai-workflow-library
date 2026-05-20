# OpenClaw Crash Alert (minimal webhook → email)

The simplest possible alerting workflow: a webhook receives a crash
event, the workflow sends a templated email via Gmail. Two nodes. Use
this as the "hello world" of n8n-based alerting before adding
deduplication, digesting, or routing.

## Pattern

```
Receive Crash Event (webhook)
   ↓
Send Crash Alert (Gmail OAuth2)
```

2 nodes. No persistence, no dedup. Each call → one email.

## Required credentials

| Placeholder | n8n credential type | What it needs |
|---|---|---|
| `REPLACE_ME_gmail-account` | Gmail OAuth2 | A Gmail OAuth credential you've authorised in n8n |

For non-Gmail providers (SES, Postmark, Brevo), replace the second
node with the corresponding sender node and bind a credential of
that type.

## Setup

1. Import + re-bind the Gmail credential
2. Edit the email body in `Send Crash Alert` — replace placeholder
   `to:`, `subject:`, and the body template with your own
3. Activate

## Inputs

```json
{
  "host": "s05",
  "service": "openclaw-agent",
  "error_type": "segfault",
  "stack_summary": "Thread 0 ... main.py:142",
  "timestamp": "2026-05-20T03:14:22Z"
}
```

Any JSON the body interpolation expects. Edit the email template
expression to match your incoming shape.

## Outputs

**Side effect:** one email sent to the configured recipient.

**No response body** by default — n8n returns 200 with the input
echoed. Add a `respondToWebhook` node if a caller needs a structured
response.

## Known limitations — and why this is template-worthy anyway

- **No deduplication.** A crash loop will flood your inbox. The
  proper fix is to pair with a per-source alert-state table (write
  the event, only email on transition from `ok` → `degraded` or
  `degraded` → `down`). That pattern lives in a separate Python
  service in the TrendAI stack, not n8n — but this workflow can
  serve as the bottom-of-funnel email-sender once the dedup logic
  is in front of it.
- **No digesting.** Pair with a daily cron workflow that pulls
  `WHERE created_at > now() - interval '24h'` and emails a
  digest.
- **Hard-coded recipient.** For multi-recipient or
  on-call rotation, replace the `to:` field with a lookup against
  a recipients table.

This template is intentionally bare — it's the building block, not
the finished alerting system. Compose it with a state-machine
or queue in front for production use.

## See also

- [`case-study.md`](case-study.md) — what we used this for and what
  broke
- For the production-grade dedup pattern this template feeds into:
  see the `reference_alert_dedupe_pattern` notes in the TrendAI
  internal memory (not part of this library — that's an
  application-level architecture concern, not a single workflow).
