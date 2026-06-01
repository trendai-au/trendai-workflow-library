# Screencast script — Customer Support Chatbot

**Target length:** 2:30–3:00
**Audience:** consulting prospects evaluating "can n8n + Gemini replace a
chatbot vendor for my SMB?"
**Recording surface:** OBS / Loom; screen-share n8n editor + a browser
tab open on `web-widget.html`.

---

## Scene 1 — Hook (0:00–0:15)

**Visual:** the `web-widget.html` floating bubble open in a browser,
typing "where is my order ORD-1001?" and hitting Send. Reply renders
within 2s with the order details.

**Voice (script):**
> Here's a customer-support chatbot that classifies intent, routes to
> the right backend, and replies — all in one n8n workflow, one Gemini
> call, and 15 nodes. No vendor SDK, no monthly seat fee. Let me show
> you what's inside.

## Scene 2 — The pattern (0:15–0:45)

**Visual:** switch to the n8n editor showing the workflow canvas.
Zoom on the Pattern diagram from the README (overlay or scroll).

**Voice:**
> The webhook receives a customer message, upserts the conversation
> row, loads the last 20 turns from Postgres, and builds a prompt.
> Then *one* Gemini 2.5 Flash call does three things at once: classify
> the intent, draft the reply with placeholders, and emit structured
> fields. The four downstream branches only run the side effects —
> order lookup, ticket creation, status change, or human handoff.

## Scene 3 — The intent router (0:45–1:30)

**Visual:** click into `Route on Intent` (Switch v3.2), show the four
output rules. Then click into `Compose Final Reply`, show how it fills
`{{ORDER_DETAILS}}` and `{{TICKET_ID}}` placeholders.

**Voice:**
> The Switch routes on `intent`, which Gemini returned as a structured
> field — not parsed from prose. Each branch runs its side effect, then
> all four merge back. The final reply isn't re-written per branch —
> Gemini drafted it with placeholders, and each branch just substitutes
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

- Use the sanitised `REPLACE_ME_…` placeholders on-screen — never show
  a real Gemini key, real Discord webhook URL, or a real DB connection
  string.
- The end-to-end demo runs against the seeded `orders` table; no live
  CRM connection needed.
- Keep cursor highlight on (Loom: enabled by default; OBS: install a
  cursor highlight plugin).
