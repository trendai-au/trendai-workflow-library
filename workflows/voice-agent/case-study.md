# Case study — Voice Agent (Lead Capture)

A worked example of a single inbound call flowing through the workflow,
with sample Vapi payloads, the HubSpot response, the operator email
that lands, and the `voice_calls` row at each stage.

## Scenario

Alice Liddell, marketing director at Wonderland Inc., sees TrendAI's
website at 2:14 PM, clicks "Talk to a human now", and dials the
inbound number. The Vapi assistant answers. Two minutes of dialogue
later, the assistant has collected enough to qualify her as a hot
lead.

## The call (abridged transcript)

> **Agent:** Hi, you've reached TrendAI's inbound line — I can take a
> few quick details so the right person can call you back within one
> business day. To start, what's your name?
>
> **Alice:** Hi, I'm Alice — Alice Liddell.
>
> **Agent:** Thanks Alice. What's the name of your business?
>
> **Alice:** Wonderland Inc.
>
> **Agent:** Got it. What are you looking for help with?
>
> **Alice:** We need an AI chatbot for our support inbox. We get about
> 200 tickets a week and half are FAQs.
>
> **Agent:** Understood. How urgent is this — this week, this month,
> this quarter, or just exploring?
>
> **Alice:** This month, ideally. We're already evaluating one
> competitor.
>
> **Agent:** Noted. What's the best email to send a follow-up to?
>
> **Alice:** alice at wonderland dot com.
>
> **Agent:** Just to confirm — A-L-I-C-E at W-O-N-D-E-R-L-A-N-D dot
> com?
>
> **Alice:** Yes, that's right.
>
> **Agent:** Last question — okay if a human follows up within one
> business day?
>
> **Alice:** Yes, that works.
>
> **Agent:** Thanks Alice, I've got everything I need. Someone will be
> in touch tomorrow. Bye for now.

## What Vapi sends (webhook payload)

Just before the assistant says the closing line, it invokes the
`submit_lead` tool. Vapi POSTs this to the n8n webhook:

```json
{
  "message": {
    "type": "tool-calls",
    "timestamp": 1717248880123,
    "toolCalls": [
      {
        "id": "call_8f3c2a1e",
        "type": "function",
        "function": {
          "name": "submit_lead",
          "arguments": "{\"firstname\":\"Alice\",\"lastname\":\"Liddell\",\"company\":\"Wonderland Inc.\",\"email\":\"alice@wonderland.com\",\"need\":\"AI chatbot for support inbox — ~200 tickets/week, half FAQs\",\"timing\":\"this_month\",\"callback_consent\":true,\"notes\":\"Already evaluating competitor X.\"}"
        }
      }
    ],
    "call": {
      "id": "c5d4e6f7-1234-5678-90ab-cdef12345678",
      "assistantId": "a1b2c3d4-1111-2222-3333-444455556666",
      "customer": {
        "number": "+61400123456"
      },
      "startedAt": "2026-06-01T14:14:00.000Z"
    }
  }
}
```

## Stage 1 — Prepare

The `Prepare` node parses the stringified `arguments` and assigns
flat fields:

```json
{
  "tool_call_id": "call_8f3c2a1e",
  "vapi_call_id": "c5d4e6f7-1234-5678-90ab-cdef12345678",
  "vapi_assistant_id": "a1b2c3d4-1111-2222-3333-444455556666",
  "phone_number": "+61400123456",
  "args": {
    "firstname": "Alice", "lastname": "Liddell", "company": "Wonderland Inc.",
    "email": "alice@wonderland.com",
    "need": "AI chatbot for support inbox — ~200 tickets/week, half FAQs",
    "timing": "this_month", "callback_consent": true,
    "notes": "Already evaluating competitor X."
  },
  "firstname": "Alice", "lastname": "Liddell",
  "company": "Wonderland Inc.", "email": "alice@wonderland.com",
  "need": "AI chatbot for support inbox — ~200 tickets/week, half FAQs",
  "timing": "this_month", "callback_consent": true,
  "notes": "Already evaluating competitor X.",
  "raw_payload": { /* the full Vapi message above */ }
}
```

## Stage 2 — Insert Voice Call

The INSERT runs. Postgres returns:

```json
{
  "id": "ab12cd34-ef56-7890-abcd-ef1234567890",
  "received_at": "2026-06-01T14:14:40.391Z"
}
```

Row state in `public.voice_calls`:

| column | value |
|---|---|
| `id` | `ab12cd34-...` |
| `vapi_call_id` | `c5d4e6f7-...` |
| `phone_number` | `+61400123456` |
| `firstname` / `lastname` / `company` | `Alice` / `Liddell` / `Wonderland Inc.` |
| `email` | `alice@wonderland.com` |
| `need` | `AI chatbot for support inbox — ~200 tickets/week, half FAQs` |
| `timing` | `this_month` |
| `callback_consent` | `true` |
| `status` | `parsed` |

## Stage 3 — Ack 200 to Vapi

Immediately after the INSERT succeeds, n8n responds to Vapi:

```json
{
  "results": [
    {
      "toolCallId": "call_8f3c2a1e",
      "result": "Thanks, your details are saved. A human will reach out within one business day."
    }
  ]
}
```

The assistant receives this and either reads it verbatim or paraphrases,
then triggers the end-call flow. Total time from `submit_lead` invocation
to caller hearing the confirmation: ~280ms in our test runs.

## Stage 4 — HubSpot Upsert

The workflow POSTs to HubSpot's batch upsert endpoint:

```json
{
  "inputs": [
    {
      "idProperty": "email",
      "id": "alice@wonderland.com",
      "properties": {
        "email": "alice@wonderland.com",
        "firstname": "Alice",
        "lastname": "Liddell",
        "phone": "+61400123456",
        "lead_need": "AI chatbot for support inbox — ~200 tickets/week, half FAQs",
        "lead_timing": "this_month",
        "lead_source": "voice-agent/trendai-inbound",
        "hs_lead_status": "NEW",
        "company": "Wonderland Inc."
      }
    }
  ]
}
```

HubSpot responds (200):

```json
{
  "results": [
    {
      "id": "98765432101",
      "properties": { /* mirrored back */ },
      "createdAt": "2026-06-01T14:14:40.812Z",
      "updatedAt": "2026-06-01T14:14:40.812Z",
      "archived": false
    }
  ]
}
```

`Update HubSpot OK` writes:

| column | new value |
|---|---|
| `status` | `hubspot_ok` |
| `hubspot_contact_id` | `98765432101` |
| `hubspot_synced_at` | `2026-06-01T14:14:40.842Z` |

## Stage 5 — Operator Notify

Brevo sends the operator email. In the operator's inbox:

> **From:** TrendAI Voice Agent &lt;info@trendai.au&gt;
> **To:** ops@trendai.au
> **Subject:** [Voice Lead] Alice - Wonderland Inc. (this_month)
>
> **New voice-agent lead**
>
> | | |
> |---|---|
> | **Name** | Alice Liddell |
> | **Company** | Wonderland Inc. |
> | **Phone** | +61400123456 |
> | **Email** | alice@wonderland.com |
> | **Need** | AI chatbot for support inbox — ~200 tickets/week, half FAQs |
> | **Timing** | this_month |
> | **Callback consent** | YES |
> | **Notes** | Already evaluating competitor X. |
> | **Vapi call id** | `c5d4e6f7-...` |
>
> Action: call back within one business day.

`Update Notify OK` writes:

| column | new value |
|---|---|
| `status` | `email_ok` |
| `operator_notified_at` | `2026-06-01T14:14:41.157Z` |

## Stage 6 — Mark Completed

`Mark Completed` runs the conditional UPDATE:

```sql
UPDATE public.voice_calls
   SET status='completed'
 WHERE id='ab12cd34-...'
   AND hubspot_synced_at IS NOT NULL
   AND operator_notified_at IS NOT NULL;
```

Both timestamps are non-null. Row's final `status` = `completed`.

End-to-end timing for this call:

| Step | Duration |
|---|---|
| Call answered → submit_lead invoked | 1m 58s (caller-paced) |
| submit_lead → row inserted | 110ms |
| Row inserted → Ack 200 to Vapi | 170ms |
| Ack → HubSpot upsert complete | 370ms |
| HubSpot OK → Brevo sent | 315ms |
| Brevo → Mark Completed | 40ms |
| **Caller heard confirmation at** | **call + 280ms after submit_lead** |
| **Operator email landed at** | **call + 855ms after submit_lead** |

## Failure scenarios — and what the row looks like after

### HubSpot 503 mid-call

`HubSpot Upsert` hits 503 (HubSpot maintenance window). The error
branch fires, `Update HubSpot Error` writes:

| column | value |
|---|---|
| `status` | `parsed` *(unchanged from stage 2 — the OK path didn't run)* |
| `hubspot_error` | `"503 Service Unavailable: ..."` |
| `attempt_count` | `1` |
| `next_retry_at` | `now + 5 minutes` |

`Operator Notify` still runs (failure-isolation IF) — the operator
gets the email with `HubSpot: not synced (will retry)` and can call
Alice back manually. The retry job picks up the row at the next
5-minute boundary and replays HubSpot against the same row's
`vapi_call_id`.

### Brevo down, HubSpot succeeded

Caller hangs up, HubSpot synced fine, Brevo bounces 502. Row:

| column | value |
|---|---|
| `status` | `hubspot_ok` |
| `hubspot_contact_id` | `98765432101` |
| `operator_notify_error` | `"502 Bad Gateway: ..."` |
| `next_retry_at` | `now + 5 minutes` |

Lead is in CRM, but operator hasn't been alerted yet. Retry job
re-fires the notify, status walks to `email_ok` → `completed`.

### Postgres unreachable at INSERT

The INSERT throws. `Brevo Alert (INSERT fail)` fires with the full
raw Vapi payload in the email body — the operator sees the lost call
in their inbox within seconds, can manually create the contact, and
the workflow returns 500 to Vapi (Vapi will retry the tool call up to
3 times per its default config, so often the second attempt lands
when postgres comes back).

## Observed metrics (first 90 days in production)

*(These numbers are from a real TrendAI deployment — calls answered
between 2026-03-01 and 2026-05-30. Sanitised aggregates only, no
caller-identifying data.)*

| Metric | Value |
|---|---|
| Calls answered | 47 |
| Calls qualified (submit_lead fired) | 41 (87%) |
| Calls with email successfully captured | 33 (80% of qualified) |
| Calls with all 4 required fields | 39 (95% of qualified) |
| HubSpot upsert success on first try | 41 / 41 (100%) |
| Operator notify success on first try | 40 / 41 (1 Brevo rate-limit) |
| Average call duration | 1m 47s |
| Average submit_lead → caller-hears-result latency | 290ms |
| Cost per call (Vapi + ElevenLabs + Deepgram + OpenAI) | ~$0.14 |
| Cost per qualified lead | ~$0.16 |

For context, the form-intake-lead-capture sibling workflow handles
~3-4× the volume at near-zero per-submission cost, but voice converts
at much higher rates on warm traffic (people who actively dialled the
number are pre-qualified). The two are complementary surfaces, not
substitutes.
