# Sanitisation Checklist

Every workflow JSON in this repo has been processed through the
sanitiser. This document is the authoritative description of what
gets scrubbed and why.

If you fork these workflows and re-publish your own variants,
**run the same checklist**. The risks below are real — credential
IDs published publicly become probe targets within hours.

## What gets stripped from the workflow JSON

### Top-level ephemeral fields

n8n exports a lot of instance-specific metadata at the top level.
All of this is dropped:

- `id`, `versionId`, `activeVersionId`, `versionCounter`,
  `triggerCount` — n8n regenerates on import
- `updatedAt`, `createdAt` — irrelevant to a re-importer
- `isArchived`, `shared`, `activeVersion` — instance-specific state
- `meta.instanceId`, `meta.templateCredsSetupCompleted` — leak
  instance identity

The workflow's `active` flag is forced to `false` so the importer
chooses when to activate.

### Run-time data

- `staticData` — usually empty but can carry cached state. Cleared.
- `pinData` — pinned execution data used for testing. Cleared.

### Per-node sensitive fields

- **`node.webhookId`** — n8n's per-instance webhook identifier.
  Dropped (n8n regenerates on import).
- **`node.credentials.<type>.id`** — the credential's database ID.
  Replaced with `REPLACE_ME_<label-slug>` placeholder. n8n accepts
  the placeholder at import time but the workflow won't execute
  until the credential is re-bound via the UI.
- **`node.credentials.<type>.name`** — the human label. Personal
  identifiers (operator's name) stripped from the label string.

### String-value substitutions

These patterns are replaced in **any** string value inside the JSON,
not just specific fields — caught by a recursive walk:

| Pattern | Replaced with |
|---|---|
| Operator-internal tenant domains (configured in the sanitiser) | `example-tenant.com` |
| Operator-personal email addresses | `operator@example-tenant.com` |
| Tenant-corporate email addresses | `noreply@example-tenant.com` |
| Tailscale `100.x.x.x` IPs | `100.0.0.0` |
| Personal-name patterns (operator handles, full names) | stripped |

The actual list of tenant domains / operator handles to scrub is
**configured inside `tools/sanitise.py`**. Edit that file to match
the identifiers your own stack uses before running the sanitiser
on your own workflows.

### Verification pass

After sanitisation, every file is grep-scanned for **any** remaining
match against:

- Specific internal domains (the list configured in the sanitiser)
- Personal-name patterns
- Bearer-format tokens (`sbp_*`, `sb_secret_*`, `gh[ps]_*`, JWT
  shape, Gemini `AIza*` keys)
- Tailnet IP ranges

The verification is automated as part of `_pending/sanitise.py` — see
the post-pass scan output. **Zero matches** is required before any
workflow is moved from `_pending/` to `workflows/`.

## Known n8n quirks

### Placeholder credential IDs do import (but don't run)

n8n's `POST /workflows` endpoint accepts arbitrary strings as
credential IDs — the placeholder `REPLACE_ME_<label-slug>`
imports cleanly. The workflow's nodes appear in the UI with their
credential field pre-populated with the placeholder. The user
then opens each node, swaps the dropdown to a real credential
from their own store, and saves.

This is by design (we don't want a published workflow to
accidentally run with someone else's credentials), but worth
calling out because the "no error at import time" can mislead a
user into activating before re-binding.

### Webhook IDs are regenerated

When you import a workflow with a Webhook node, n8n generates a
fresh `webhookId`. The new webhook URL appears in the node after
the first save. **Don't expose the URL until you've added
authentication** (HTTP Header Auth node-level, or a CF WAF rule
upstream).

### Public-API credential binding gotcha

Specifically: `POST /credentials` via the n8n public API persists
the credential but doesn't bind it for runtime resolution by any
node. A workflow that references the credential by ID will fail
at execution time with "credential not found" until you open the
node in the UI and re-save it. This bites automated provisioning
pipelines especially hard.

The workaround documented in the TrendAI memory:
`inline secret via placeholder + deploy-time substitution` —
write the credential value directly into the workflow JSON's
node expressions as `{{ $env.MY_API_KEY }}` and inject the env
var at deploy time. Trade-off: the secret lives in n8n's env
rather than its credential store. Fine for automated-only
credentials; not fine for human-edited ones.

## Reviewer checklist before publishing a new workflow

If you add a workflow to this repo, do the full pass:

- [ ] Export raw JSON from n8n
- [ ] Run `_pending/sanitise.py` (or its equivalent) — produces
      `<slug>.sanitised.json` + `<slug>.audit.txt`
- [ ] Review the audit.txt — confirm every reported substitution
      makes sense
- [ ] Run the verification grep pass — confirm zero matches
- [ ] Import the sanitised JSON into a fresh n8n instance — confirm
      it imports cleanly + every credential dropdown shows the
      placeholder
- [ ] Write the README + case-study + observed metrics
- [ ] Move the sanitised JSON from `_pending/` to `workflows/<slug>/workflow.json`
- [ ] Open the PR; the merger does an independent grep pass before
      hitting merge
