# Customer Support Chatbot — web widget + intent routing


<!-- E09.4-2-video-start -->
## Video

[![Watch the 2-minute walk-through](https://img.youtube.com/vi/scT3g1vnuU0/maxresdefault.jpg)](https://www.youtube.com/watch?v=scT3g1vnuU0)

**[Watch on YouTube → https://www.youtube.com/watch?v=scT3g1vnuU0](https://www.youtube.com/watch?v=scT3g1vnuU0)**

A 2-minute walk-through of the workflow: what it does, how the nodes wire up, and what you change to fork it for your stack. Part of the [TrendAI Workflow Library "Workflows" playlist](https://www.youtube.com/playlist?list=PLnl2DWExbS90Bw74p_gL9o8Ut9F88C8PX).
<!-- E09.4-2-video-end -->

A production-shaped n8n workflow that powers an embeddable customer
support chatbot. One Gemini 2.5 Flash call classifies the customer's
intent and drafts a response; the workflow then routes to one of four
specialised branches and finalises the reply.

The accompanying `web-widget.html` is a drop-in floating chat bubble
that posts to the workflow's webhook — no build step, no framework,
no third-party JS deps.

## Pattern

```
Webhook (POST /chatbot/customer-support)
   ↓
Upsert Conversation + Insert User Msg (postgres)
   ↓
Load History (postgres — last 20 turns)
   ↓
Build Gemini Prompt (code — system + transcript + user turn)
   ↓
Call Gemini 2.5 Flash (HTTP — JSON response mode)
   ↓
Parse Gemini Output (code — extract intent + drafted reply + structured fields)
   ↓
Route on Intent (switch v3.2 — 4 outputs)
   ├─ qa            ───────────────────────────────────────┐
   ├─ order_lookup  → Lookup Order (postgres) ─────────────┤
   ├─ ticket_create → Create Ticket (postgres) ────────────┤
   └─ handoff       → Set Handoff Status (postgres)        │
                      → Notify Discord (HTTP) ─────────────┤
                                                           ↓
                                                Merge Branches (4-input)
                                                           ↓
                                          Compose Final Reply (code —
                                          fills {{ORDER_DETAILS}} /
                                          {{TICKET_ID}} placeholders)
                                                           ↓
                                          Insert Assistant Message (postgres)
                                                           ↓
                                          Respond to Widget (JSON 200,
                                          CORS headers set)
```

15 nodes. The intent classification, response drafting, and structured
field extraction all happen in **one** Gemini call — the four branches
only run the side-effects (DB lookup, ticket row, status change,
notification) and substitute their data into placeholders the model
already wrote into the draft reply.

## Required credentials

| Placeholder | n8n credential type | What it needs |
|---|---|---|
| `REPLACE_ME_gemini-2-5-flash` | Google PaLM API (covers Gemini) | Gemini API key with access to `gemini-2.5-flash` |
| `REPLACE_ME_postgres-chatbot-rw` | Postgres | A user that can read/write the four tables (see `schema.sql`) |
| `REPLACE_ME_discord_webhook_url` | (no credential — plain URL) | A Discord channel webhook URL, hard-coded in the `Notify Discord` node |

Discord is used unauthenticated via channel webhook URL (the URL is the
secret). If you'd rather use a Discord bot credential, swap the
`Notify Discord` HTTP node for a Discord node bound to a bot credential —
both work.

> **No knowledge node?** Right. This template treats the system prompt
> + Gemini's general knowledge as the answering surface. For grounded
> Q&A against your own policy/product corpus, see the
> [knowledge-engine-summarise-save](../knowledge-engine-summarise-save/)
> sub-workflow and call it before the Gemini step — or swap the Gemini
> call for an Embedding + Supabase RAG chain.

## Required schema

The workflow expects four Postgres tables: `conversations`, `messages`,
`tickets`, `orders`. Full DDL with constraints, indexes, the
`updated_at` trigger, and seed data for the order-lookup demo is in
[`schema.sql`](./schema.sql).

Tables overview:

- **`conversations`** — one row per chat session (UUID PK, `status ∈
  {active, pending_human, closed}`, `metadata JSONB`).
- **`messages`** — every turn (user / assistant / system) with optional
  `intent_label` on assistant turns.
- **`tickets`** — created by the `ticket_create` branch. Keyed by FK
  back to the conversation.
- **`orders`** — read-only here. Seed-data file ships four sample
  orders so prospects can drive the `order_lookup` branch out of the
  box.

Apply with:

```bash
psql "$POSTGRES_URL" -f schema.sql
```

## Setup

1. **Import the workflow.** In n8n: *Workflows → Import from File →*
   pick `workflow.json`.
2. **Re-bind credentials** on every node with `REPLACE_ME_…` — open the
   node, pick (or create) a credential of the matching type, Save.
3. **Set the Discord webhook URL** on the `Notify Discord` node:
   open the node, replace `REPLACE_ME_discord_webhook_url` with your
   channel webhook URL, Save. Or rewire to a Discord bot node if you
   prefer authenticated posts.
4. **Apply the schema** (`schema.sql`) against the Postgres database
   bound to the credential.
5. **Activate the workflow.** The webhook URL will show in the
   `Webhook` node — copy it.
6. **Drop the widget into a page.** Open `web-widget.html` and set
   `window.CHATBOT_WEBHOOK_URL` to the URL from step 5. Optionally
   override `window.CHATBOT_BRAND`. Open the file in a browser to
   test, or copy the `BEGIN-WIDGET` → `END-WIDGET` CSS+HTML+JS blocks
   into your own page template.

## Inputs

The widget posts JSON to the webhook:

```json
{
  "conversation_id": "8a3f1c2d-4b5e-6f7a-8b9c-0d1e2f3a4b5c",
  "customer_email": "jamie@example.com",
  "message": "Where is order ORD-1001?"
}
```

- `conversation_id` — **client-generated UUID v4**, persisted in
  `sessionStorage` by the widget. Used to stitch turns + upsert the
  `conversations` row.
- `customer_email` — optional. Helps the `order_lookup` branch when
  the customer doesn't quote an order number.
- `message` — the customer's text.

## Outputs

The webhook responds with JSON:

```json
{
  "ok": true,
  "conversation_id": "8a3f1c2d-4b5e-6f7a-8b9c-0d1e2f3a4b5c",
  "intent": "order_lookup",
  "response": "Let me check that for you. Here's what I found:\n• Order ORD-1001 — shipped — AUD 129.00\n  Tracking: https://tracking.example.com/ORD-1001",
  "ticket_id": null,
  "order_count": 1
}
```

- `intent` — one of `qa | order_lookup | ticket_create | handoff`.
- `response` — final reply text (placeholders substituted).
- `ticket_id` — populated only for `ticket_create`.
- `order_count` — populated only for `order_lookup`.

The workflow also writes a row to `messages` with `role='assistant'`
and `intent_label` set, so the next turn's history reload sees it.

## Customisation guide (for consulting prospects)

The point of this template is to be **easy to fork for a specific
client**. The lift points are:

1. **The system prompt** in `Build Gemini Prompt` — change the company
   name, voice, and intent rules. Add domain knowledge if you want
   grounded Q&A (or wire in RAG — see the note above).
2. **The branches** — add or remove. Each new intent needs (a) a rule
   in `Route on Intent`, (b) one or more action nodes, (c) a Merge
   input, (d) substitution logic in `Compose Final Reply`. Examples
   worth adding for B2B clients: appointment-booking (Cal.com), known-
   issue lookup, account-info retrieval.
3. **The handoff target** — Discord is the default. Slack works the
   same (different webhook URL + payload shape). Email via Brevo
   follows the form-intake template's pattern. PagerDuty for high-
   priority. The point is the `pending_human` status — pick whichever
   matches the client's ops surface.
4. **The web widget styling** — single CSS block in `web-widget.html`
   between `BEGIN-WIDGET` and `END-WIDGET`. Brand colours, position,
   sizing — all variables you'd typically expose to the client.
5. **The order lookup query** — adapt to the client's actual orders
   schema. The seed `orders` table is a placeholder; in production
   you'd join against the client's order-management system (or call
   their order API via HTTP instead of a local Postgres SELECT).

## Anti-patterns this template demonstrates avoiding

- **Multi-call intent classification.** Some tutorials wire a
  classifier model, then a separate generator model. One call is
  cheaper, lower-latency, and gives you the *drafted reply* and the
  *structured fields* in one shot — by asking Gemini for JSON output.
- **Branch-specific response composition.** Each branch could write
  its own reply from scratch. Instead the *model* drafts the reply
  with placeholders (`{{ORDER_DETAILS}}`, `{{TICKET_ID}}`) and each
  branch only fills in its data. Tone stays consistent without
  per-branch prompt engineering.
- **Stateless chat.** History is loaded fresh from Postgres on every
  turn, so the workflow stays stateless and concurrent-safe. No
  per-conversation in-memory cache to leak or corrupt.
- **Tight coupling to one vendor.** The Gemini call is a plain HTTP
  request, not the native Google node. Swap to OpenAI, Anthropic,
  Mistral, or a self-hosted model by changing one node's URL + auth
  and the response-parse path.

## Known limitations

- **No streaming.** The widget waits for the full response before
  rendering. For chatty UX, you'd swap the Respond node for SSE +
  server-side streaming — not on the n8n happy path.
- **No file uploads.** Customers can't attach screenshots or files.
  Add a separate `/upload` webhook + S3/Supabase storage if needed.
- **No rate limiting.** Production deployments should put a WAF or
  CF rate-limit rule in front of the webhook URL.
- **Order-lookup is local-table-only.** Swap the `Lookup Order` node
  for an HTTP call into your real order system for production use.
- **CORS is permissive** (`Access-Control-Allow-Origin: *`). Lock to
  your widget's host in production.
