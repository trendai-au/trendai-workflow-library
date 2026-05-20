# Case study — Lead Capture

How the production deployment used this workflow during sprint-16 /
sprint-17. Numbers reflect a 4-week window on the TrendAI portal.

## Inputs received

- ~30 form submissions/week from the `/contact` form on the TrendAI
  marketing site
- 5 health-check `probe: true` calls per hour (from an external
  monitor)

## Sample successful run

**Inbound webhook body:**

```json
{
  "email": "founder@startup.com.au",
  "firstname": "Jamie",
  "lastname": "Founder",
  "company": "StartupCo",
  "message": "Looking for help automating our customer onboarding.",
  "probe": false
}
```

**Workflow path:**

1. `Insert Submission` writes row in `form_intake.submissions`
   with `submission_id = 5e7a...`, `status='received'`
2. `HubSpot Upsert` POSTs to `/crm/v3/objects/contacts` —
   200 OK, contact id `12345`
3. `Update HubSpot OK` stamps `hubspot_status='ok'`,
   `hubspot_contact_id='12345'`
4. `Client Confirm Email` POSTs to Brevo `/v3/smtp/email` —
   201 OK, message id `<...@smtp-relay.sendinblue.com>`
5. `Update Email OK` stamps `email_status='ok'`
6. `Mark Completed` stamps `status='completed'`

**Webhook response:**

```json
{ "ok": true, "submission_id": "5e7a..." }
```

**Wall-clock:** ~1.8s typical, 4s p95 (mostly the HubSpot upsert).

## Sample partial-failure run

**Inbound:** valid email, but HubSpot is rate-limiting (429).

**Workflow path:**

1. `Insert Submission` OK
2. `HubSpot Upsert` returns 429
3. `Update HubSpot Error` stamps `hubspot_status='error'`,
   `hubspot_error_body='{...429 json...}'`
4. `Client Confirm Email` STILL fires — the workflow doesn't
   short-circuit on HubSpot failure, because the user-visible
   email is more important than the CRM sync
5. `Update Email OK` stamps `email_status='ok'`
6. `Mark Completed` stamps `status='completed'`

The submission is durable in postgres with both status columns
recorded. A nightly job can sweep `hubspot_status='error'` rows
and retry.

## What broke during production use

- **Brevo "double-send" during n8n restart.** When the n8n container
  was restarted mid-flight on a high-traffic minute, two submissions
  triggered both their email and a replay of an earlier email. Root
  cause: in-flight webhook execution wasn't drained before the
  container terminated. Fix: graceful-shutdown hook on the n8n
  systemd unit (see thin-host doctrine).
- **HubSpot property required-but-missing.** Adding a required
  property to a HubSpot portal broke every workflow that wrote to
  contacts without that property. The `Update HubSpot Error` row
  surfaced the problem within minutes — the alert dashboard noticed
  the climb in `hubspot_status='error'` rates.

## Metrics over the window

- **Throughput:** ~3,400 submissions
- **HubSpot success rate:** 99.4% (rest sweep-retried successfully)
- **Brevo success rate:** 99.9%
- **End-to-end success (status='completed'):** 99.3%
- **p95 wall-clock:** 4s
- **Failures requiring human review:** 4

## Notes for re-users

If you're adapting this for your own form, the two most-likely-to-need-
editing nodes are:

1. **`HubSpot Upsert`** — change the property names in the body to
   match your portal's schema
2. **`Client Confirm Email`** — replace the Brevo template ID and the
   `params` object with your own template's variable names

Everything else (the postgres durability layer, the OK/Error
isolation IFs, the status walk) should work unchanged.
