# trendai-workflow-library

Production-tested **n8n workflow templates** from the TrendAI stack —
form intake, queue producers, summariser sub-workflows, alert
plumbing. Each workflow ships as a sanitised JSON export plus a
README explaining inputs / outputs / required credentials / setup,
and a case-study with sample input/output and observed metrics.

These aren't toy examples. They're the actual workflows running (or
that ran) in TrendAI production, scrubbed of credential IDs and
tenant-specific URLs so you can fork them as a starting point for
your own n8n instance.

## Workflows

| Workflow | Nodes | Purpose | Required credential types |
|---|---:|---|---|
| [form-intake-lead-capture](workflows/form-intake-lead-capture/) | 15 | Webhook → postgres → HubSpot → Brevo, with failure-isolation IFs | Postgres, HTTP Header Auth (×2) |
| [knowledge-engine-summarise-save](workflows/knowledge-engine-summarise-save/) | 9 | Reusable sub-workflow: Gemini summarise + Supabase persist + Discord notify | Google PaLM API (Gemini), Supabase, Discord Bot |
| [content-idea-enqueue](workflows/content-idea-enqueue/) | 4 | Minimal webhook → postgres queue producer (no-Sheets doctrine) | Postgres |
| [case-study-followup](workflows/case-study-followup/) | 3 | Scheduled-task enqueue: `webhook → queue row with scheduled_for` | Postgres |
| [openclaw-crash-alert](workflows/openclaw-crash-alert/) | 2 | Minimal alerting template — webhook → email (the bottom of an alert stack) | Gmail OAuth2 |
| [customer-support-chatbot](workflows/customer-support-chatbot/) | 15 | Web-widget chatbot: Gemini 2.5 Flash intent routing → Q&A / order-lookup / ticket-create / human-handoff branches | Google PaLM API (Gemini), Postgres |
| [crm-data-enrichment](workflows/crm-data-enrichment/) | 12 | Google Sheets row → Gemini 2.5 Flash company/role/ICP enrichment → ICP-banded UPSERT to Postgres + output sheet + Discord hot-lead ping | Google Sheets Trigger OAuth2, Google Sheets OAuth2, Google PaLM API (Gemini), Postgres |
| [social-media-scheduling](workflows/social-media-scheduling/) | 14 | Cron-polled Sheet queue → optional Gemini per-channel rewrite → FB Page / LinkedIn Company / Discord webhook → status + result_url written back to the row | Google Sheets OAuth2, Google PaLM API (Gemini), FB Page token (inline), LinkedIn access token (inline), Discord webhook URL (inline) |

## Importing into your n8n

1. Clone or download this repo.
2. Open n8n → **Workflows → Import from File** → pick the
   `workflows/<slug>/workflow.json` you want.
3. **Re-bind every credential.** Each node with a credential dropdown
   will show a placeholder ID like `REPLACE_ME_postgres-form-intake-writer`
   — open the node, pick (or create) a credential of the same type in
   your own credential store, and Save.
4. Read the workflow's `README.md` for inputs / outputs / known
   limitations and any schema it needs in your database.
5. Activate the workflow when ready.

### Why re-bind?

n8n's public API persists credential references in workflow JSON,
but doesn't bind them at runtime — that step only happens when a
human opens the node in the UI and clicks Save. See
[SANITISATION-CHECKLIST.md](SANITISATION-CHECKLIST.md#known-n8n-quirks)
for the full story.

## Anti-patterns these workflows demonstrate avoiding

The case studies are deliberately honest about what broke in
production. If you read them, you'll see why these patterns exist:

- **Failure isolation** (form-intake) — HubSpot down should not block
  the user's confirmation email.
- **Persistence before propagation** (form-intake, both queue
  producers) — never lose a submission to a downstream outage.
- **Sub-workflow re-use** (knowledge-engine) — three parent
  ingestors share one summariser; tune the prompt once.
- **Queue producer / consumer split** (content-idea-enqueue) — sync
  webhook is fast; async consumer handles the expensive work.
- **Templates are not architectures** (openclaw-crash-alert) — a
  bare webhook → email is the building block, not the finished
  alerting stack.

## Compatibility

Exported from n8n self-hosted v2.10.4 (May 2026). Workflows use only
nodes available in the open-source community edition. Tested by
re-importing into a fresh n8n-sandbox instance.

## Contributing

These workflows are from a single operator's stack. If you build a
significantly improved variant of any of them, PRs welcome — see
[CONTRIBUTING.md](CONTRIBUTING.md) for what we look for.

## License

MIT — see [LICENSE](LICENSE).
