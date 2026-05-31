# Input sheet — `contacts-input` template

The workflow's `Google Sheets Trigger - New Contact` node polls a
single tab in a Google Sheet for `rowAdded` events. This file
defines the canonical header row + sample data so you can spin up
a fresh sheet that the workflow will trigger on out of the box.

## Header row (row 1)

```
email | name | company | role | source
```

Column order doesn't matter — the workflow reads by header name —
but **the header row is required** (n8n's Google Sheets Trigger
treats row 1 as the header by default).

| Column | Type | Required | Notes |
|---|---|---|---|
| `email` | text | yes | Lowercased + trimmed in the Validate node. Rows with no `@` are still processed (downstream lands in `cold` band with `_validation: missing_or_invalid_email`). |
| `name` | text | no | Free text. Passed to Gemini as-is. |
| `company` | text | no | Free text. If blank, the Validate node infers from email domain (skip on free webmail). |
| `role` | text | no | Free text. Drives `role_seniority` + `role_function` inference. |
| `source` | text | no | Where the lead came from. Not used in scoring; persisted for audit. |

## Sample data (rows 2-9)

Drop these in to drive a first-pass enrichment + observe each band.
Expected band shown in parens — actual band depends on Gemini's
inference + the seeded ICPs from `schema.sql`.

```
email                       | name           | company       | role               | source
priya@acmelabs.io           | Priya Patel    | Acme Labs     | Head of Growth     | LinkedIn       (hot — AU SMB SaaS, VP role + B2B)
jamie@nimble.co             | Jamie Liu      | Nimble        | Founder            | Cold email     (hot — AU SMB SaaS founder)
sam@buildco.com.au          | Sam Reilly     | BuildCo       | Operations Manager | Referral       (hot — Trade services broad ICP)
alex@bigshop.com.au         | Alex Tran      | Bigshop       | Marketing Manager  | Conference     (hot/warm — Mid-market marketing ops)
morgan@quietfund.com        | Morgan Doyle   | QuietFund     | Analyst            | LinkedIn       (warm/cold — Finance, IC, no ICP match)
casey@offgridtea.com        | Casey Nguyen   | OffGridTea    | Founder            | Newsletter     (warm — Ecommerce founder, no SaaS match)
                            | (no email)     | TestRow       | (none)             | manual         (rejected — invalid email, drops to cold)
test@gmail.com              |                |               |                    |                (cold — free webmail + no company anchor)
```

Notes:

- Two rows are deliberate-failure cases (invalid email + free-
  webmail-no-company). The workflow handles both gracefully — no
  exceptions, just low scores.
- Expected bands are **directional** — Gemini's exact inference
  varies, and your ICP edits will shift the scoring. Use this set
  as a smoke test, then replace with real contacts.

## Output sheet — `contacts-enriched-output`

The workflow writes to a **separate** sheet (the `Write to Output
Sheet` node). Create a second sheet (or another tab on the same
document) with this header row before activating the workflow — or
let n8n create the columns on first append.

```
email | name | company_name | industry | size_band | hq_country | business_model | role_seniority | role_function | outreach_hook | outreach_confidence | icp_name | icp_score | band | enriched_at
```

The `appendOrUpdate` operation matches on `email` — re-enriching
an existing contact updates the existing row in place.

## Webhook alternative (for typeform / Pipedrive / HubSpot)

If you want real-time enrichment instead of polling, swap the
trigger node for a `Webhook` node. Required payload shape:

```json
POST /webhook/contacts/enrich
Content-Type: application/json

{
  "email": "priya@acmelabs.io",
  "name": "Priya Patel",
  "company": "Acme Labs",
  "role": "Head of Growth",
  "source": "LinkedIn"
}
```

The Validate node already reads `$input.first().json`, so a
Webhook node with `responseMode: "responseNode"` slots straight in.
Add a `Respond to Webhook` node at the end (parallel branch off
`Score Against ICPs`) if the caller needs the enriched record back
synchronously.
