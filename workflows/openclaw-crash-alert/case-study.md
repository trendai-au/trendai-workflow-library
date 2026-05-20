# Case study — OpenClaw Crash Alert

Used in TrendAI's agent stack as the "agent died" notifier. When the
OpenClaw runtime process crashed, a wrapper script posted to this
webhook before exiting; the email landed in the operator's inbox
within seconds.

## Sample input

```json
{
  "host": "eb01",
  "service": "openclaw-agent",
  "error_type": "uncaught-exception",
  "stack_summary": "json.decoder.JSONDecodeError: Expecting value: line 1 column 1 (char 0) at adapter/claude_api.py:84",
  "timestamp": "2026-05-18T10:31:08Z"
}
```

## Sample email rendered

```
Subject: [ALERT] openclaw-agent crashed on eb01

The OpenClaw agent process on eb01 has crashed.

  Service: openclaw-agent
  Error:   uncaught-exception
  Where:   adapter/claude_api.py:84
  Stack:   json.decoder.JSONDecodeError: Expecting value: line 1 column 1 (char 0)
  Time:    2026-05-18T10:31:08Z

The process has exited. Restart with `systemctl restart openclaw-agent`.
```

## What we learned in production

Three lessons that pushed us off the bare template into the
production alert-dedupe pattern:

1. **A crash loop produces 200 emails before you can disable the
   alert.** Once an upstream service started returning HTML where
   we expected JSON, the agent re-crashed every 10s until we
   noticed. The dedup pattern (only email on state-transition)
   solved this — but the bare workflow is fine when you're sure
   the upstream is well-behaved.
2. **Without persistence, you can't answer "did this fire last
   night?"** Added a `Insert Alert` node in front of `Send Crash
   Alert` that writes to a Postgres table. Now we can grep
   history.
3. **Gmail OAuth tokens need refresh.** The first time the OAuth
   refresh expired (after several months idle), the alert
   silently stopped firing. Add a daily probe (`probe=true`
   webhook call from a cron) so you notice when the auth dies.

## Metrics from production use

Before the dedup pattern was added:

- **Total events received:** 643 over 6 weeks
- **Unique incidents:** 4
- **Email-to-incident ratio:** 161x — i.e. an average of 161
  duplicate emails per real incident

After dedup + dedup-aware digest:

- **Total events received:** ~similar
- **Emails sent:** 4 transition emails + 6 daily digests = 10
- **Email-to-incident ratio:** ~2.5x — manageable

## Notes for re-users

This is **template, not architecture**. Use it as your alerting
foundation and add the dedupe / digest layer separately. The
build-out order we used:

1. Bare template (this workflow) — to confirm the webhook + email
   plumbing works
2. Add an `Insert Alert` node before the email — persistence
3. Add a "did we recently send a similar alert?" lookup in front
   of the email send — naive dedupe
4. Replace step 3 with a state-machine pattern (per-source
   `alert_state` table, emit only on transitions) — production
   dedupe
5. Add a daily cron that summarises the `alert` log into a
   digest email — digesting

Steps 2 + 3 take an afternoon; step 4 is a doctrine-level decision
that's out of scope for a single workflow template.
