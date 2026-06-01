# Screencast script — Knowledge Engine (Summarise & Save)

**Target length:** 2:00–2:30
**Audience:** technical founders / RAG-curious builders evaluating
"how do I ingest content from multiple sources into one knowledge
store without writing the summariser N times?"
**Recording surface:** OBS / Loom; screen-share n8n editor (two
workflows visible) + Supabase + Discord.

---

## Scene 1 — Hook (0:00–0:20)

**Visual:** four parent workflows in the n8n sidebar — `yt-ingest`,
`article-ingest`, `inbox-ingest`, `manual-ingest`. All of them have an
"Execute Workflow" node pointing to the same target: `knowledge-engine-
summarise-save`.

**Voice (script):**
> Four ingest pipelines, one summariser. Article ingest, inbox ingest,
> YouTube ingest, manual ingest — they all do source-specific
> extraction, then call *this* sub-workflow to summarise, persist, and
> notify. One prompt to tune, one schema to maintain, four sources
> served.

## Scene 2 — The sub-workflow shape (0:20–0:50)

**Visual:** open the `knowledge-engine-summarise-save` workflow in
the editor. Zoom on the canvas: Execute Workflow Trigger → Gemini →
Supabase → knowledge_runs → Discord.

**Voice:**
> Five nodes that matter: the Execute Workflow trigger that defines
> the input shape, the Gemini call that does the summarisation, the
> Supabase insert that persists the content, the `knowledge_runs`
> insert that records the model call's cost and latency, and the
> Discord notification for operator visibility.

## Scene 3 — Two tables, separate jobs (0:50–1:20)

**Visual:** open `schema.sql`. Show both tables side by side —
`knowledge_items` (content) and `knowledge_runs` (observability).

**Voice:**
> Two tables, separated on purpose. `knowledge_items` is the content
> store — title, summary, tags, source URL. `knowledge_runs` is the
> observability log — model name, tokens in, tokens out, latency.
> When you need to debug a cost spike or a slow model day, the run
> log is right there. One INSERT per call. Pays back the first time
> you ask "why did yesterday's ingest take four times longer".

## Scene 4 — The prompt is the lift point (1:20–1:50)

**Visual:** click into the `Message a model` node. Show the system
prompt extracting `title`, `summary`, `tags`, `key_quote`,
`thumbnail_url` as JSON.

**Voice:**
> The prompt is the one place that needs client-specific tuning. For
> a legal-research client this becomes citation extraction. For a
> sales-intel client, named-entity recognition. For a content-
> curation client, the generic summary + tags shape works as-is.
> Tune *one* node, all four ingest parents benefit.

## Scene 5 — The Flash + thinking-budget tradeoff (1:50–2:10)

**Visual:** highlight `thinkingConfig.thinkingBudget: 0` in the HTTP
node body.

**Voice:**
> Flash with thinking disabled is correct for non-reasoning
> summarisation — cheap, fast, deterministic. If you swap in
> `gemini-2.5-pro` for higher-stakes content like legal review,
> remove that override — Pro is a reasoning model and benefits from
> a thinking budget. Per-model overrides should match the model.

## Scene 6 — Wrap (2:10–2:25)

**Visual:** trigger one of the parent workflows manually. Discord
notification fires in real time. Supabase row appears.

**Voice:**
> Fork it, point it at your Supabase, tune the prompt for your
> content, wire it up from whatever ingest parents you have. Link to
> the workflow + schema in the description.

---

## Shot list

- [ ] n8n sidebar showing the four parent workflows
- [ ] Workflow canvas (sub-workflow)
- [ ] `schema.sql` open with both tables
- [ ] `Message a model` node (zoomed prompt + thinking_budget)
- [ ] Discord channel with the notification
- [ ] Supabase table editor showing the new `knowledge_items` row
- [ ] End card: repo URL + workflow folder path

## Recording notes

- Use a throwaway Supabase project + a throwaway Gemini key for the
  live demo. Delete after recording.
- The four parent workflows in Scene 1 are *visual reference* — they
  don't ship with this template. Mention that on camera ("the four
  parents in TrendAI's pipeline aren't in this template — they're
  example consumers; you build the parents for your sources").
- Keep this one shorter than the others — it's a sub-workflow, the
  pattern story is sharper than the demo story.
