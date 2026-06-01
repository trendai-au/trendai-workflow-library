# Screencast script — Form Intake (Lead Capture)

**Target length:** 2:30–3:00
**Audience:** technical founders / ops engineers evaluating "how do I
get web-form submissions into my CRM *and* fire a confirmation email,
without losing anything when one of them is down?"
**Recording surface:** OBS / Loom; screen-share a browser tab with the
form + n8n editor + pgAdmin or psql + HubSpot.

---

## Scene 1 — Hook (0:00–0:20)

**Visual:** a simple HTML form in a browser. Fill in name + email +
company + message, click Submit. Cut to HubSpot — contact appears.
Cut to the operator's inbox — confirmation email arrives.

**Voice (script):**
> Web form submits, HubSpot creates the contact, customer gets a
> confirmation email. Standard. But here's what's different: if
> HubSpot is down, the email still goes out. If the email fails, the
> HubSpot contact still gets created. And every submission is
> persisted in Postgres before either side effect runs — so a partial
> failure leaves a recoverable row, not a lost lead.

## Scene 2 — The failure-isolation pattern (0:20–1:00)

**Visual:** n8n editor on the workflow canvas. Zoom on the Pattern
diagram showing the two IF branches (HubSpot OK/Error → Update,
Email OK/Error → Update).

**Voice:**
> Three side effects: insert to Postgres, upsert to HubSpot, send via
> Brevo. The naïve pattern wraps all three in one try / catch — so a
> HubSpot 500 swallows the email attempt and the customer gets
> nothing. Per-step IFs decouple them. Each side effect writes its own
> status column. A sweep job retries the errored steps later.

## Scene 3 — The persist-first move (1:00–1:30)

**Visual:** click into `Insert Submission`. Show that it runs *first*
— before HubSpot, before Brevo. Then open pgAdmin / psql and run
`SELECT submission_id, status, hubspot_status, email_status FROM
form_intake.submissions ORDER BY created_at DESC LIMIT 5;`. Show
status walking through `received → hubspot_ok → email_ok → completed`.

**Voice:**
> The very first action is the Postgres insert. If HubSpot 500s
> before we ever call it, the row exists, the audit trail is
> complete, and a sweep job can replay HubSpot against
> `submission_id` later. The row is the source of truth — not the CRM.

## Scene 4 — The probe (1:30–2:00)

**Visual:** `curl -X POST <webhook> -d '{"probe": true}'`. Show the
`probe_completed` row in Postgres. Highlight that no HubSpot contact
or email was generated.

**Voice:**
> Built-in monitoring hook. POST `{"probe": true}` and the workflow
> writes a `probe_completed` row and exits — no CRM contact, no
> email. Wire your uptime monitor to ping this once per minute and
> you can confirm the *full chain* is live without polluting CRM
> with synthetic contacts. The end-to-end test runs in production,
> on the live workflow.

## Scene 5 — The reusable shape (2:00–2:30)

**Visual:** flip to the Pattern diagram again. Frame it abstractly —
"Insert → Side Effect 1 → IF → Update Status → Side Effect 2 → IF →
Update Status".

**Voice:**
> The shape is reusable. Any time you chain N side effects where
> partial success is still partial delivery, this pattern works:
> persist first, propagate per-side-effect, IF after each, record the
> verdict, sweep the errored rows later. Form intake is the canonical
> instance — but order processing, webhook fan-out, scheduled
> emails all fit the same mold.

## Scene 6 — Wrap (2:30–2:50)

**Visual:** back to HubSpot showing the contact, then to Postgres
showing `status=completed`.

**Voice:**
> Fork the workflow, re-bind the credentials, point Brevo and HubSpot
> at your accounts, and you've got a resilient lead-capture chain that
> never loses a submission. Link to the workflow + schema + setup in
> the description.

---

## Shot list

- [ ] Browser with a simple HTML form
- [ ] HubSpot showing the new contact
- [ ] Inbox showing the confirmation email
- [ ] n8n editor on the workflow canvas
- [ ] pgAdmin / psql showing the `submissions` rows
- [ ] Terminal running the `probe: true` curl
- [ ] End card: repo URL + workflow folder path

## Recording notes

- Use a HubSpot sandbox portal or a free HubSpot Starter account for
  the demo — don't use a real client's portal.
- Brevo confirmation email needs a real template (the shipped node
  references `REPLACE_ME_template_id`); set one up in advance.
- Show the failure-isolation by *deliberately* breaking HubSpot
  (revoke the token temporarily) and showing that the email still
  goes out + the row records `hubspot_status='error'`. This is the
  most compelling part of the demo.
