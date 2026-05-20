# Case study — Case Study Followup

Used in the TrendAI sales nurture flow: after a prospect requests a
case study, a 7-day followup task is scheduled. When the day arrives,
the consumer workflow sends a templated email asking if they had
follow-up questions.

## Sample input

```json
{
  "case_study_url": "https://example-tenant.com/case-studies/sportcorp-automations",
  "recipient_email": "founder@sportcorp.example.com",
  "delay_days": 7,
  "template_id": "case-study-7day-checkin"
}
```

## Sample queue row produced

```json
{
  "task_id": "9a4f...",
  "task_type": "case-study-followup",
  "scheduled_for": "2026-05-27T03:14:22Z",
  "payload": {
    "case_study_url": "https://example-tenant.com/case-studies/sportcorp-automations",
    "recipient_email": "founder@sportcorp.example.com",
    "template_id": "case-study-7day-checkin"
  },
  "status": "pending",
  "created_at": "2026-05-20T03:14:22Z"
}
```

## Webhook response

```json
{
  "ok": true,
  "task_id": "9a4f...",
  "scheduled_for": "2026-05-27T03:14:22Z"
}
```

## Consumer-side rendering

7 days later, the consumer claims the row and renders the templated
email:

> Hi Jamie — just checking in on the SportCorp case study you
> requested last week. Any questions about the migration approach
> we walked through, or topics you'd like a deeper dive on?

## Metrics

Around 12 nurture sequences scheduled over a ~4-week window:

- **Open rate** (followup email): 64%
- **Reply rate** to the followup: 25%
- **Cancellations** (prospect bounced before T+7): 1
- **Stuck `claimed` rows** (consumer error): 0

## Notes for re-users

The "case study followup" is one shape; the same workflow trivially
becomes a "7-day onboarding reminder" or "30-day churn signal probe"
by changing the `template_id` constant and the consumer's email body.

For a multi-step nurture (T+1, T+7, T+30), call this workflow three
times with different `delay_days` and `template_id` values rather
than chaining them — keeps the consumer logic simple.
