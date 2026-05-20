# Case study — Knowledge Engine Summarise & Save

Built sprint-15 (TrendAI E23.1-3). 4-week window covers the bulk of
the article-engine + inbox-ingest traffic.

## Sample input

Called from the article-ingest parent workflow:

```json
{
  "source_type": "article",
  "source_url": "https://www.anthropic.com/news/agent-sdk-credit",
  "external_id": "anthropic-agent-sdk-credit-2026-05",
  "raw_content": "Today we're introducing a new monthly $100 credit ..."
}
```

## Sample output (the row that lands in `knowledge_items`)

```json
{
  "id": 92,
  "source_type": "article",
  "source_url": "https://www.anthropic.com/news/agent-sdk-credit",
  "title": "A new monthly Agent SDK credit for your plan",
  "ai_summary": "Anthropic is introducing a $100 monthly credit for Max 5x plan subscribers for Agent SDK and non-interactive Claude usage, effective June 15...",
  "tags": ["anthropic", "agent-sdk", "billing", "claude"],
  "content_md": "...",
  "created_at": "2026-05-19T22:31:14Z"
}
```

## Discord notification rendered

```
📥 New article: A new monthly Agent SDK credit for your plan
> Anthropic is introducing a $100 monthly credit for Max 5x plan
> subscribers for Agent SDK and non-interactive Claude usage...
🔗 https://www.anthropic.com/news/agent-sdk-credit
🏷 #anthropic #agent-sdk #billing #claude
```

## Metrics over the window

- **Throughput:** ~80 items/week across the three parent ingestors
- **Mean latency (Gemini call dominates):** 1.7s
- **Token usage per call:** ~8,900 in / ~150 out (average)
- **Cost per item:** ~$0.0007
- **Supabase write success rate:** 100% in window
- **Discord-reply success rate:** ~99% (rate-limit drops in spiky hours)

## Observed issues

- **Long input truncation.** Articles over ~15KB occasionally produced
  truncated summaries — Gemini Flash's effective context for this
  prompt is fine for typical web articles but breaks down on
  long-form PDFs. Workaround: pre-chunk the input or upgrade to
  Pro for long content.
- **Tag inflation.** Early prompts had no tag-count constraint; some
  items came back with 12+ tags. Constrained the prompt to "3-5
  tags, no duplicates, no synonyms."
- **Key-quote drift.** Initial prompts asked for "the most impactful
  quote." Model started inventing quotes. Tightened to "an exact
  string from the article body" — eliminated hallucinations.

## Notes for re-users

The prompt is the load-bearing part of this workflow. Treat it as
production-tuned for short-to-medium-form web content. For:

- **Long-form** (PDFs, papers): swap to Gemini 2.5 Pro and remove
  `thinkingBudget=0`
- **Code-heavy content**: rewrite the prompt to request
  language-tagged code blocks
- **Non-English**: add a `language` parameter and pass it to the
  prompt explicitly — Flash respects the language hint
