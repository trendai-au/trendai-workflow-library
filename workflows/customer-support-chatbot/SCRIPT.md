# Screencast script — Customer Support Chatbot

**Target length:** 2:30–3:00
**Audience:** consulting prospects evaluating "can n8n + an LLM replace a
chatbot vendor for my SMB?"
**Recording surface:** region screen capture; n8n editor + a browser
tab open on `web-widget.html`.

> **REVISED 2026-09-08 (TOS-06-03) so the words match what is on screen.**
> The repo ships this workflow wired to **Gemini 2.5 Flash**, and that has not
> changed. The recording runs it against **our own LLM** — `qwen2.5:7b` on the
> s07 runtime — at the operator's instruction, so every voice line that named
> Gemini as *the* model now names the LLM step instead. The point of the
> pattern is that this is ONE HTTP node, and the video says so out loud rather
> than hiding the difference.
>
> **The round trip is 8–16 SECONDS, not two.** Measured through the widget on
> 2026-09-08: 16.0s warm end-to-end (two Postgres round-trips, the LLM call,
> then two more writes), 8.4s for a short handoff reply. The old "within 2s"
> line was written before anything had been run and is not achievable on this
> stack. Leave the typing indicator visible and cut the wait — do NOT stage it
> to look instant.

---

## Scene 1 — Hook (0:00–0:15)

**Visual:** the `web-widget.html` floating bubble open in a browser,
typing "where is my order ORD-1001?" and hitting Send. The typing
indicator runs for roughly ten seconds, then the reply renders with the
live order details pulled from Postgres. Cut the wait, keep the
indicator — the delay is real and staging it away would be a lie about
what this stack does.

**Voice (script):**
> Here's a customer-support chatbot that classifies intent, routes to
> the right backend, and replies — all in one n8n workflow, one LLM
> call, and 15 nodes. No vendor SDK, no monthly seat fee. Let me show
> you what's inside.

## Scene 2 — The pattern (0:15–0:45)

**Visual:** switch to the n8n editor showing the workflow canvas.
Zoom on the Pattern diagram from the README (overlay or scroll).

**Voice:**
> The webhook receives a customer message, upserts the conversation
> row, loads the last 20 turns from Postgres, and builds a prompt.
> Then *one* LLM call does three things at once: classify the intent,
> draft the reply with placeholders, and emit structured fields. The
> four downstream branches only run the side effects — order lookup,
> ticket creation, status change, or human handoff.
>
> And that call is a single HTTP node. The repo ships it pointed at
> Gemini 2.5 Flash; I'm running it here against a model on our own
> box. Swapping the provider is one node, not a rewrite — which is the
> whole reason the intelligence sits in one place instead of being
> smeared across four branches.

## Scene 3 — The intent router (0:45–1:30)

**Visual:** click into `Route on Intent` (Switch v3.2), show the four
output rules. Then click into `Compose Final Reply`, show how it fills
`{{ORDER_DETAILS}}` and `{{TICKET_ID}}` placeholders.

**Voice:**
> The Switch routes on `intent`, which the model returned as a structured
> field — not parsed from prose. Each branch runs its side effect, then
> all four merge back. The final reply isn't re-written per branch —
> the model drafted it with placeholders, and each branch just substitutes
> its data. Tone stays consistent without per-branch prompt engineering.

## Scene 4 — The schema (1:30–2:00)

**Visual:** open `schema.sql` in the editor. Highlight the four tables
(`conversations`, `messages`, `tickets`, `orders`), then the seeded
sample orders.

**Voice:**
> Four tables: conversations, messages, tickets, orders. The schema
> file ships seed data for four sample orders so a prospect can drive
> the order-lookup branch out of the box — no real CRM needed for the
> demo. In production you'd swap that seeded table for a join against
> the client's real order system or an HTTP call to their order API.

## Scene 5 — The widget drop-in (2:00–2:30)

**Visual:** `web-widget.html` open in a code editor. Highlight the
`window.CHATBOT_WEBHOOK_URL` and `window.CHATBOT_BRAND` config block,
then the `BEGIN-WIDGET` → `END-WIDGET` CSS+HTML+JS block.

**Voice:**
> The widget is a single HTML file — no build step, no framework, no
> third-party JS. Set the webhook URL and brand name at the top, copy
> the `BEGIN-WIDGET` to `END-WIDGET` block into the client's page
> template, and it works. The brand colours are CSS variables — that's
> the one customisation point you'd expose to the client.

## Scene 6 — Wrap (2:30–2:45)

**Visual:** back to the floating bubble, run a `handoff` intent
("I want to talk to a human"). Reply acknowledges + Discord shows the
handoff notification in real time.

**Voice:**
> Fork the workflow, re-bind the credentials, edit the system prompt
> for your client's voice, and you've got a custom-branded support bot
> ready to ship. Link to the workflow + setup guide in the description.

---

## Shot list

- [ ] Browser with `web-widget.html` floating bubble (light theme)
- [ ] n8n editor on the workflow canvas (zoom out to fit, then zoom on
      Switch + Compose Final Reply)
- [ ] `schema.sql` open in code editor
- [ ] `web-widget.html` open in code editor (collapsed CSS)
- [ ] Discord channel showing the handoff notification
- [ ] End card: `github.com/trendai-au/trendai-workflow-library` + the
      workflow folder path

## Recording notes

- Never show a real API key, Discord webhook URL, or DB connection
  string. In the TOS-06-03 recording setup every one of those is behind
  an n8n **credential**, which the editor masks — the LLM, Discord and
  Postgres nodes carry no plaintext secret to expose. Do not open the
  credential manager on camera.
- The end-to-end demo runs against the seeded `orders` table; no live
  CRM connection needed.
- Keep cursor highlight on (Loom: enabled by default; OBS: install a
  cursor highlight plugin).
