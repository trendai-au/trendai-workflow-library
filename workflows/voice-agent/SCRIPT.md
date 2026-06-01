# Screencast script — Voice Agent (Lead Capture)

**Target length:** 2:30–3:00
**Audience:** technical founders / ops engineers evaluating "how do I
put a 24/7 voice agent on my inbound number that qualifies callers into
my CRM, without it sounding like a 2010-era IVR?"
**Recording surface:** OBS / Loom; screen-share a phone (or softphone)
dialling the Vapi number + n8n editor + pgAdmin or psql + HubSpot +
operator inbox.

---

## Scene 1 — Hook (0:00–0:25)

**Visual:** softphone (or real phone) dialling the Vapi number. Speaker
audio captured by OBS. The assistant answers, runs a ~60-second
qualification dialogue with the operator (playing the caller), then
ends the call. Cut to HubSpot — contact appears with `lead_need`,
`lead_timing`, `lead_source: voice-agent/trendai-inbound`. Cut to
operator inbox — notification email arrives.

**Voice (script):**
> Someone dials your number, a voice agent answers, asks four
> qualification questions, and hangs up. By the time the caller has
> put their phone down, the lead is in HubSpot with the right
> properties set, and the operator has an email with the full
> transcript-derived summary. No IVR menus, no "press 1 for sales", and
> nothing for the caller to learn. Here's how the pipeline works.

## Scene 2 — The two halves: Vapi + n8n (0:25–1:00)

**Visual:** split the screen — left side shows `vapi-assistant.json` in
an editor (zoom on the system prompt + `submit_lead` tool definition);
right side shows the n8n workflow canvas with all 15 nodes laid out.

**Voice:**
> Two pieces. On the left, Vapi runs the conversation — it's the voice
> + transcription + LLM stack that handles the audio and the dialogue.
> The assistant config is one JSON file: system prompt, the qualification
> questions, voice choice, and a tool definition. The assistant calls
> that tool when it's gathered enough. On the right, n8n handles
> everything *after* the qualification — persist the call, push to
> HubSpot, notify the operator. The handoff is one webhook with a
> structured JSON payload.

## Scene 3 — The persist-first move (1:00–1:30)

**Visual:** click into the `Insert Voice Call` node. Show that it runs
*before* HubSpot, *before* the operator email. Then open pgAdmin / psql
and run `SELECT id, vapi_call_id, firstname, company, need, timing,
status FROM voice_calls ORDER BY received_at DESC LIMIT 5;`. Show the
status walking through `parsed → hubspot_ok → email_ok → completed`.

**Voice:**
> Same doctrine as the form-intake workflow — the very first action is
> the postgres insert. If HubSpot is down, the row exists, the audit
> trail is complete, and a sweep job can replay HubSpot later. The row
> is the source of truth, not the CRM. Same applies to the operator
> email — if Brevo bounces, the call isn't lost, we have it in
> postgres and can re-fire the notification.

## Scene 4 — The 280-millisecond Ack (1:30–2:00)

**Visual:** zoom on the `Ack 200` node, show its response body
returning `{ results: [{ toolCallId, result: "Thanks, your details are
saved..." }] }`. Then jump back to the workflow canvas and trace the
arrow from `Insert Voice Call` to `Ack 200` — highlight that this
fires *before* HubSpot or Brevo even start.

**Voice:**
> Critical detail: we respond to Vapi as soon as the postgres insert
> succeeds — under 300 milliseconds in production. The assistant gets
> a clean "result" string to read back to the caller, and the call
> wraps up immediately. HubSpot and the operator email happen after
> the caller has already hung up. Anything that takes longer than a
> beat to run lives outside the caller's perception.

## Scene 5 — Failure isolation (2:00–2:30)

**Visual:** n8n editor on the workflow canvas. Zoom on the two failure
branches — `HubSpot Upsert` splits to `Update HubSpot OK` and
`Update HubSpot Error`, both lead into `Operator Notify`. Same for
`Operator Notify` splitting into `Update Notify OK` and `Update Notify
Error`.

**Voice:**
> Two failure-isolation IFs. If HubSpot 503s during a maintenance
> window, the operator still gets the email — the lead row stamps
> `hubspot_error` and `next_retry_at`, and a sweep job replays it
> later. If Brevo is down, the HubSpot contact still gets created.
> Each side effect's verdict lands in its own status column. Partial
> failures are recoverable, not lost.

## Scene 6 — Wrap (2:30–2:55)

**Visual:** back to HubSpot showing the contact, then to postgres
showing `status=completed`, then to the operator inbox. Final card: the
repo URL + workflow folder path.

**Voice:**
> Fork the workflow, import the Vapi assistant config, re-bind the
> credentials, point HubSpot and Brevo at your accounts, and you've
> got a 24/7 voice-qualification chain on your inbound number that
> never loses a call. Costs about 14 cents per call to run. Link to
> the workflow + Vapi assistant config + schema in the description.

---

## Shot list

- [ ] Softphone or real phone dialling the Vapi number (audio captured)
- [ ] Vapi assistant config JSON in an editor
- [ ] n8n editor on the workflow canvas (all 15 nodes visible)
- [ ] pgAdmin / psql showing the `voice_calls` rows
- [ ] HubSpot showing the new contact with custom properties set
- [ ] Operator inbox showing the notification email
- [ ] Close-up on the failure-isolation IF branches
- [ ] End card: repo URL + workflow folder path

## Recording notes

- Use a Vapi free-tier US test number for the demo — don't expose your
  production number on camera.
- Use a HubSpot sandbox portal or a free HubSpot Starter account — don't
  use a real client's portal. Pre-create the custom contact properties
  (`lead_need`, `lead_timing`, `lead_source`, `lead_status`).
- Brevo template / sender domain should be a throwaway. The recording
  will burn the sender email into search engines.
- Show the failure-isolation by *deliberately* breaking HubSpot
  (revoke the token temporarily) and showing that the operator email
  still arrives + the row records `hubspot_error`. This is the most
  compelling part of the demo (same as form-intake's SCRIPT).
- Cap the call audio carefully — the assistant speaks the result string
  back; the cut should let the viewer hear "Thanks, your details are
  saved" before transitioning to the n8n side.
- Caller-side voice (the operator playing Alice) should be the same
  person across all takes for consistency, but doesn't need to be the
  narrator.

## Throwaway credentials checklist (revoke after recording)

- [ ] Vapi API key (revoke in Vapi dashboard)
- [ ] OpenAI API key shown in Vapi config (rotate)
- [ ] ElevenLabs voice id (no key on screen, but revoke if shown)
- [ ] Deepgram key (rotate)
- [ ] HubSpot private app PAT (delete the app)
- [ ] Brevo API key (revoke)
- [ ] Postgres credentials shown in pgAdmin (rotate role password)
