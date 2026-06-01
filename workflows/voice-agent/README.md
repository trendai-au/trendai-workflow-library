# Voice Agent — Lead Capture (Vapi → n8n → HubSpot + Brevo)

Inbound voice agent that qualifies a caller into a CRM lead row. A
[Vapi](https://vapi.ai) assistant answers the phone, asks the
qualification questions, then calls an n8n webhook with the structured
result. n8n follows the **resumable-pipeline doctrine** — persist the
call first, propagate to HubSpot + operator email, record per-step
status so partial failures are recoverable.

**This is the voice-first sibling of
[`form-intake-lead-capture`](../form-intake-lead-capture/).** Same
downstream plumbing (postgres → HubSpot → Brevo), same failure-isolation
IFs, different input surface — instead of an HTML form, the caller talks.

## Pattern

```
Vapi call (caller dials your number)
   ↓
Vapi assistant runs qualification dialogue
   ↓
Vapi calls submit_lead tool → POST /voice-agent/trendai-lead-submit
   ↓
Webhook → Prepare (extract args)
   ↓
Insert Voice Call (postgres → voice_calls)
   ↓ ↓
   OK            Error
   ↓            ↓
Ack 200 (tool result)    Brevo Alert → Reject 500
   ↓
[probe?] → Mark Probe Completed     ← end early if probe
   ↓
HubSpot Upsert (contact create-or-update)
   ↓ ↓
   OK            Error
   ↓            ↓
Update HubSpot OK / Error (postgres status)
   ↓
Operator Notify (Brevo email with full lead row)
   ↓ ↓
   OK            Error
   ↓            ↓
Update Notify OK / Error → Mark Completed
```

15 nodes. Two failure-isolation IFs so HubSpot failure doesn't block
the operator notification and vice versa.

## What's in this folder

| File | Purpose |
|---|---|
| `workflow.json` | n8n workflow export — import this into your n8n. |
| `vapi-assistant.json` | Vapi assistant config — import this into your Vapi account. Contains the system prompt, `submit_lead` tool definition, voice + transcriber + LLM choices. |
| `schema.sql` | Postgres DDL for the `voice_calls` table the workflow writes to. |
| `case-study.md` | Worked example with sample Vapi payloads + HubSpot upsert result + the operator email that lands. |
| `SCRIPT.md` | 2-3 min screencast script for the workflow demo. |

## Required credentials

| Placeholder | n8n credential type | What it needs |
|---|---|---|
| `REPLACE_ME_postgres-voice-agent-writer` | Postgres | Host + DB + role with `INSERT/UPDATE` on `public.voice_calls` |
| `REPLACE_ME_hubspot-trendai-token` | HTTP Header Auth | HubSpot private app PAT in `Authorization: Bearer <token>` |
| `REPLACE_ME_brevo-trendai-api` | HTTP Header Auth | Brevo API key in `api-key: <key>` |

The "trendai" / "voice-agent" hints in the placeholder names are just
naming — rename to whatever fits your instance.

You'll also need (outside n8n):

- A **Vapi account** + an assistant created from `vapi-assistant.json`.
- A **phone number provisioned in Vapi** (or BYO Twilio number routed to
  Vapi). Vapi's free tier includes a US test number, enough to validate
  the round-trip.
- **ElevenLabs voice** + **Deepgram transcription** keys (Vapi-managed —
  link them in Vapi's provider settings, not in n8n).
- **OpenAI API key** for the assistant LLM (also Vapi-managed).

## Required schema

The workflow expects a `voice_calls` table in your postgres database
(default `public` schema). Full DDL with indexes, an `updated_at`
trigger, and the per-step status enum is in [`schema.sql`](./schema.sql).

- **`public.voice_calls`** — one row per Vapi inbound call, keyed by
  `vapi_call_id` (UNIQUE). Walks through `status` values
  `received → parsed → hubspot_ok → email_ok → completed` (or
  `probe_completed` for health-check calls). `hubspot_error` and
  `operator_notify_error` columns record per-step failures so a
  partial failure leaves the row recoverable.

Apply with:

```bash
psql "$POSTGRES_URL" -f schema.sql
```

## Setup

### 1. n8n side

1. Import `workflow.json` into your n8n instance.
2. Open each node with a credential dropdown and bind it to your own
   credential. **The placeholder IDs do not resolve at runtime** — the
   workflow won't execute until every cred is re-bound. (See the n8n
   credential binding gotcha in
   [SANITISATION-CHECKLIST](../../SANITISATION-CHECKLIST.md#known-n8n-quirks).)
3. Open `HubSpot Upsert` — adjust `lead_need`, `lead_timing`,
   `lead_source` to property names that exist in your portal. The
   default set assumes you've added these as custom contact properties.
4. Open `Operator Notify` — replace `info@example-tenant.com` (sender)
   and `ops@example-tenant.com` (recipient) with your real addresses.
5. Open `Brevo Alert (INSERT fail)` — same sender/recipient swap.
6. Activate the workflow. The webhook URL appears in the `Webhook` node
   after save — copy it for the next step.

### 2. Vapi side

1. Edit `vapi-assistant.json`:
   - Replace `REPLACE_ME_n8n_webhook_host` with your n8n host (e.g.
     `n8n.example.com`) in both `tools[0].function.server.url` and
     `serverUrl`.
   - Replace `REPLACE_ME_shared_webhook_secret` with a random string —
     this gets sent as the `x-vapi-secret` header on every webhook call;
     verify it in n8n with a check at the top of `Prepare` if you want
     auth on the webhook.
   - Replace `REPLACE_ME_elevenlabs_voice_id` with your chosen voice id
     from the ElevenLabs library (or pick a different voice provider).
2. Create the assistant in Vapi — either via dashboard "Import JSON" or
   via the Vapi API:
   ```bash
   curl -X POST https://api.vapi.ai/assistant \
     -H "Authorization: Bearer $VAPI_API_KEY" \
     -H "Content-Type: application/json" \
     -d @vapi-assistant.json
   ```
3. Assign your Vapi phone number to the assistant.
4. Test by dialling the number. The assistant should greet you, run the
   qualification dialogue, and end the call. Check `voice_calls` for the
   row and your operator inbox for the notification.

## Inputs (POST body the workflow receives from Vapi)

Vapi sends `tool-calls` events to the `submit_lead` server URL. The
workflow's `Prepare` node expects this shape:

```json
{
  "message": {
    "type": "tool-calls",
    "toolCalls": [
      {
        "id": "call_abc123",
        "function": {
          "name": "submit_lead",
          "arguments": "{\"firstname\":\"Alice\",\"lastname\":\"Liddell\",\"company\":\"Wonderland Inc.\",\"email\":\"alice@example.com\",\"need\":\"AI chatbot for support\",\"timing\":\"this_month\",\"callback_consent\":true,\"notes\":\"Mentioned competitor X\"}"
        }
      }
    ],
    "call": {
      "id": "vapi-call-uuid",
      "assistantId": "vapi-asst-uuid",
      "customer": { "number": "+61400000000" }
    }
  }
}
```

`arguments` arrives as a JSON string — `Prepare` parses it. If parsing
fails (Vapi schema change, malformed args), `args` falls back to `{}`
and the row is inserted with whatever fields the assistant managed to
collect — never lose the call.

For probe testing (no real call), POST manually with
`args.__probe__: true`:

```bash
curl -X POST "$WEBHOOK_URL" -H "Content-Type: application/json" -d '{
  "message": {
    "type": "tool-calls",
    "toolCalls": [{
      "id": "probe-1",
      "function": {
        "name": "submit_lead",
        "arguments": "{\"__probe__\":true,\"firstname\":\"Probe\",\"company\":\"Monitoring\",\"need\":\"health check\",\"callback_consent\":false}"
      }
    }],
    "call": { "id": "probe-call-1" }
  }
}'
```

## Outputs

**Synchronous webhook response (200 OK, Vapi tool-call format):**

```json
{
  "results": [
    {
      "toolCallId": "call_abc123",
      "result": "Thanks, your details are saved. A human will reach out within one business day."
    }
  ]
}
```

Vapi reads `result` and the assistant speaks it (or paraphrases) before
ending the call.

**Side effects:**

1. One row in `public.voice_calls` (status walks
   `received → parsed → hubspot_ok → email_ok → completed`).
2. One contact upserted in HubSpot (keyed by email, falling back to a
   synthetic `vapi-<callid>@no-email.trendai.au` if the caller didn't
   give one — so phone-only leads still land in CRM and can be merged
   later).
3. One operator notification email via Brevo with the full lead row.

Each side effect is recorded in its own status column — a partial
failure leaves the row recoverable. The `id` returned to Vapi is the
postgres row's UUID.

## Customisation guide (for consulting prospects)

The point of this template is to be **easy to fork for a specific
client**. The lift points are:

1. **The voice agent persona.** The system prompt in
   `vapi-assistant.json` is tuned for TrendAI inbound. Rewrite the
   prompt + opening line + closing line for your brand and qualification
   funnel. Keep the tool-call structure — the n8n side reads
   `firstname`, `company`, `need`, `email`, `timing`, etc.
2. **The qualification fields.** Add/remove fields by editing the
   `submit_lead` tool's `parameters.properties` in
   `vapi-assistant.json`, then mirror the change in the n8n `Prepare`
   node, the `Insert Voice Call` SQL, and the `schema.sql`. JSONB
   `structured_data` column always captures the raw args, so you can add
   fields without DDL changes — only the typed columns need updates.
3. **The CRM.** HubSpot is the default. Swap `HubSpot Upsert` for a
   Pipedrive *Person — Update*, a Salesforce *Lead — Upsert*, or any
   CRM with an upsert-by-email endpoint. The Insert / IF / Update
   plumbing around it stays unchanged.
4. **The operator notification.** Brevo + email is the default. Swap
   `Operator Notify` for a Slack `chat.postMessage`, a Discord webhook,
   a Twilio SMS to the on-call phone, or a PagerDuty incident if
   callback consent is `true` and timing is `this_week`. The IF +
   status-update plumbing stays untouched.
5. **The probe semantic.** The `__probe__: true` short-circuit is a
   monitoring hook — `Mark Probe Completed` writes a `probe_completed`
   row and exits. Wire your uptime monitor (Kuma, BetterStack, Pingdom)
   to POST the probe payload once per minute; query
   `WHERE status='probe_completed'` to confirm the full chain is live
   without polluting CRM with synthetic contacts.
6. **The voice + transcriber stack.** ElevenLabs + Deepgram + GPT-4o-
   mini is the default. Vapi supports OpenAI Realtime, Cartesia,
   Rime.ai, PlayHT, Whisper, Gladia, and others — swap in
   `vapi-assistant.json` `voice`/`transcriber`/`model` blocks. The n8n
   side is provider-agnostic, only the assistant config changes.

## Anti-patterns this template demonstrates avoiding

- **Inline tool-result blocking.** The naïve pattern is to make Vapi
  wait while n8n calls HubSpot + sends email, *then* respond. That ties
  the caller's experience to HubSpot's latency — a 5-second CRM lag is
  5 seconds of awkward silence on the line. Here we Ack 200 immediately
  after the postgres insert; HubSpot and Brevo happen after the caller
  has already heard "Thanks, your details are saved."
- **Single try / catch around HubSpot + email.** Same anti-pattern as
  form-intake. A HubSpot 500 swallows the operator notification — and
  worse, you don't even know a lead came in. Per-step IFs decouple
  them; operator always gets notified even if CRM is down.
- **Propagate-then-persist.** If HubSpot 500s before the row exists,
  the call is gone with no audit trail and no way to replay. Persist
  first, propagate second — the `voice_calls` row is the source of
  truth, not the CRM.
- **Requiring an email.** Voice callers often won't give a clean email
  ("alice at gmail dot com" → "alice@gmail.com" — sometimes the
  assistant gets it, sometimes not). HubSpot upsert keys on email, so
  we fall back to a synthetic `vapi-<callid>@no-email.trendai.au` to
  keep the contact landable. Operator merges manually after the
  callback if a real email is captured later.
- **No callback-consent capture.** If you don't ask, you can't legally
  call back in many jurisdictions. The `callback_consent` field is in
  the tool schema and required — the assistant won't submit without
  asking.
- **Vapi webhook URL exposed without auth.** The default has no auth
  beyond the shared secret in the request body — fine for templating,
  dangerous in production. Add HTTP Header Auth on the Webhook node
  (verify `x-vapi-secret`) or a Cloudflare WAF rule before exposing
  to real traffic.

## Known limitations

- **End-of-call transcript not persisted in this workflow.** Vapi sends
  a separate `end-of-call-report` event with the full transcript +
  summary + recording URL. This template handles only the `submit_lead`
  tool call (the lead capture). To persist transcripts, add a second
  workflow on the `serverUrl` from `vapi-assistant.json` that UPSERTs
  `transcript`, `summary`, `duration_seconds`, `recording_url`,
  `ended_reason` onto the same `voice_calls` row by `vapi_call_id`.
  Stub schema columns are already in `schema.sql`.
- **Email parsing is hit-or-miss.** Voice transcription of email
  addresses fails ~20% of the time even with Deepgram nova-2. The
  assistant prompt instructs it to spell back letter-by-letter, but
  the user's confirmation isn't validated against any pattern.
  Consider adding an LLM post-processing step (regex + DNS MX check)
  or accepting that email will be empty for ~1 in 5 calls and falling
  back to phone-only callback.
- **No queue / retry.** Failures are recorded in postgres but not
  retried automatically. If HubSpot is down, the workflow stamps
  `hubspot_error` and moves on. Pair with a scheduled re-process job
  for retry semantics (reads `WHERE next_retry_at < now() AND status
  IN ('parsed', 'hubspot_ok')`).
- **HubSpot custom properties.** The upsert writes `lead_need`,
  `lead_timing`, `lead_source`, `hs_lead_status`. The first three are
  custom properties you must create in your HubSpot portal first — the
  import won't fail without them, but the values won't land.
- **Vapi free tier limits.** Free tier includes ~$10 of test calling
  credits. Sufficient to validate the workflow end-to-end, not for
  production traffic. Production needs a paid Vapi plan + your own
  ElevenLabs / Deepgram / OpenAI billing.

## See also

- [`case-study.md`](case-study.md) — worked example with sample Vapi
  payload + HubSpot response + operator email
- Sibling workflow [`form-intake-lead-capture`](../form-intake-lead-capture/)
  — same downstream plumbing, web form input surface instead of voice
- Sibling workflow [`customer-support-chatbot`](../customer-support-chatbot/)
  — text-chat input surface, also one Gemini classification step + side
  effects fan-out
