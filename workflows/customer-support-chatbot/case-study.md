# Case study — Customer Support Chatbot

This template is shipped as a **design reference**, not as the
artefact of a 4-week production deployment. The numbers below are
design assumptions and per-branch latency budgets — useful for
sizing your own pilot. Adjust them once you've ran the workflow
against real traffic for a couple of weeks.

## Sample run — `qa` intent

**Inbound webhook body** (from the widget):

```json
{
  "conversation_id": "8a3f1c2d-4b5e-6f7a-8b9c-0d1e2f3a4b5c",
  "customer_email": "jamie@example.com",
  "message": "What's your return policy?"
}
```

**Workflow path:**

1. `Upsert Conversation + Insert User Msg` — creates the conversation
   row (if new) and inserts the user message. Returns the new message
   row's `id`.
2. `Load History` — returns `[{ role: 'user', content: '...', created_at: ... }]`
   (just the message we wrote, since this is the first turn).
3. `Build Gemini Prompt` — assembles the system + transcript + user
   prompt and stashes it in `_gemini_prompt`.
4. `Call Gemini 2.5 Flash` — Gemini returns:

   ```json
   {
     "intent": "qa",
     "response_text": "Our return policy gives you 30 days from delivery to send any item back for a full refund, as long as it's in original condition. You can start a return at acme.example/returns — you'll get a prepaid label by email.",
     "order_query": null,
     "ticket": null,
     "handoff_reason": null
   }
   ```

5. `Route on Intent` — output 0 (qa) → straight to `Merge Branches`
   input 0.
6. `Compose Final Reply` — no substitution needed; passes through.
7. `Insert Assistant Message` — writes the assistant turn with
   `intent_label='qa'`.
8. `Respond to Widget`:

   ```json
   {
     "ok": true,
     "conversation_id": "8a3f1c2d-4b5e-6f7a-8b9c-0d1e2f3a4b5c",
     "intent": "qa",
     "response": "Our return policy gives you 30 days from delivery...",
     "ticket_id": null,
     "order_count": null
   }
   ```

## Sample run — `order_lookup` intent

**Inbound:**

```json
{
  "conversation_id": "1d2e3f4a-5b6c-7d8e-9f0a-1b2c3d4e5f6a",
  "customer_email": "jamie@example.com",
  "message": "Where is order ORD-1001?"
}
```

**Gemini response:**

```json
{
  "intent": "order_lookup",
  "response_text": "Let me check that for you. Here's what I found:\n{{ORDER_DETAILS}}",
  "order_query": { "order_number": "ORD-1001", "customer_email": "" },
  "ticket": null,
  "handoff_reason": null
}
```

**Lookup Order** SELECT returns one row (from seed data):

```
order_number | status   | total_cents | currency | tracking_url
ORD-1001     | shipped  | 12900       | AUD      | https://tracking.example.com/ORD-1001
```

**Compose Final Reply** substitutes `{{ORDER_DETAILS}}`:

```
Let me check that for you. Here's what I found:
• Order ORD-1001 — shipped — AUD 129.00
  Tracking: https://tracking.example.com/ORD-1001
```

## Sample run — `ticket_create` intent

**Inbound:**

```json
{
  "conversation_id": "...",
  "customer_email": "priya@example.com",
  "message": "My order arrived damaged. I'd like a refund please."
}
```

**Gemini response:**

```json
{
  "intent": "ticket_create",
  "response_text": "I'm sorry to hear that. I've logged this for our team to handle — they'll be in touch within one business day. Your ticket reference is #{{TICKET_ID}}.",
  "order_query": null,
  "ticket": {
    "subject": "Damaged order — refund request",
    "description": "Customer reports their order arrived damaged and is requesting a refund.",
    "priority": "high"
  },
  "handoff_reason": null
}
```

**Create Ticket** returns `{ id: 42, subject: '...', priority: 'high', status: 'open' }`.

**Final reply** sent to widget:

```
I'm sorry to hear that. I've logged this for our team to handle —
they'll be in touch within one business day. Your ticket reference
is #42.
```

## Sample run — `handoff` intent

**Inbound:**

```json
{
  "conversation_id": "...",
  "customer_email": "alex@example.com",
  "message": "Can I please speak to a real human?"
}
```

**Gemini response:**

```json
{
  "intent": "handoff",
  "response_text": "Of course — I'm connecting you to a teammate now. They'll be with you shortly.",
  "order_query": null,
  "ticket": null,
  "handoff_reason": "Customer explicitly requested human contact."
}
```

**Set Handoff Status** sets `conversations.status = 'pending_human'`
and merges `{ handoff_reason, handoff_at }` into the metadata JSONB.

**Notify Discord** posts to the configured channel:

```
**Handoff requested** — conversation a1b2c3d4-...
Customer: alex@example.com
Reason: Customer explicitly requested human contact.
Last message: Can I please speak to a real human?
```

## Per-branch latency budget (design assumption)

| Branch | DB queries | Model calls | Notification | Target p50 | Target p95 |
|---|---:|---:|---:|---:|---:|
| qa            | 3 | 1 (Gemini) | 0 | ~1.6s | ~2.8s |
| order_lookup  | 4 | 1 (Gemini) | 0 | ~1.9s | ~3.2s |
| ticket_create | 4 | 1 (Gemini) | 0 | ~2.0s | ~3.3s |
| handoff       | 4 | 1 (Gemini) | 1 (Discord) | ~2.2s | ~3.6s |

Gemini 2.5 Flash with `thinkingBudget: 0` + `responseMimeType:
'application/json'` typically returns in 800-1500ms for prompts of
this size. Postgres queries on indexed columns are <50ms each. The
Discord webhook is fire-and-forget (`onError: continueRegularOutput`)
so a failed notification doesn't break the customer reply.

## What to measure once it's running

Add these to your observability stack (a `chatbot_runs` table mirroring
the knowledge-engine template's `knowledge_runs` is a reasonable
starting point):

- **Intent distribution.** If 80% of traffic routes to `qa`, the
  template is doing what it should. If 30%+ goes to `handoff`, the
  system prompt or the intent rules need tightening.
- **Containment rate.** % of conversations that ended without a
  `pending_human` status. This is the headline KPI for a support
  chatbot.
- **Ticket conversion.** % of `ticket_create` runs that result in an
  actual resolved ticket (vs. spam / mis-routed). Tells you whether
  the model is over- or under-creating tickets.
- **Order lookup success rate.** % of `order_lookup` runs where
  `order_count > 0`. Low rate means customers are asking for orders
  the system can't find — log the queries to tune extraction.
- **Average turns per conversation.** A healthy contained chatbot
  averages 2-4 turns; >6 usually means it's struggling and should
  have handed off.

## Anti-pattern callouts

- **Don't add a "confirm before write" step.** The temptation is to
  have the model re-confirm with the user before creating a ticket
  or marking handoff. Don't — it doubles the turn count and customers
  hate it. Trust the classifier; if it's wrong, the ticket can be
  closed cheaply, and `pending_human` is easy to undo.
- **Don't let the model write the ticket ID itself.** Gemini will
  cheerfully hallucinate ticket numbers. The template uses a
  `{{TICKET_ID}}` placeholder substituted by `Compose Final Reply`
  from the *actual* Postgres `RETURNING id`.
- **Don't classify on every turn if you don't have to.** For long
  conversations already in `pending_human` status, you could short-
  circuit the Gemini call entirely. That optimisation isn't in this
  template — add it once you see the traffic pattern.
