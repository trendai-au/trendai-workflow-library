# Contributing

This repo is a snapshot of production workflows, not an active
framework. PRs are welcome but specific:

## What we'll merge

- **Variants** of an existing workflow that fix a real production
  issue (with a one-paragraph rationale in the PR description).
- **Improvements to case studies** — better metrics, more honest
  failure-mode write-ups, additional gotchas observed in production.
- **Compatibility fixes** for newer n8n versions (we test on 2.10.x).
- **Better READMEs** — clearer setup steps, missing prerequisites,
  typos.

## What we won't merge

- **New, untested workflows.** The bar for inclusion is "ran in
  production for ≥2 weeks with metrics to show for it." Toy examples
  belong in your own repo.
- **Sanitisation regressions.** If your PR adds a credential ID,
  internal URL, or any of the patterns listed in
  [SANITISATION-CHECKLIST.md](SANITISATION-CHECKLIST.md), it won't
  merge until that's scrubbed.
- **Architecture-level PRs** ("rewrite all workflows to use the
  resumable-pipeline doctrine"). The workflows are intentionally
  small. Doctrine work lives in the consumer's own codebase, not
  in shared templates.

## PR checklist

- [ ] Re-import test: `workflow.json` imports cleanly into a fresh
      n8n instance (we verify this against our sandbox before merge).
- [ ] Sanitisation pass: no credential IDs, no internal URLs, no
      personal-name identifiers, no personal-domain or corporate
      email addresses in the JSON.
- [ ] README updated if behaviour changed.
- [ ] Case study updated if you observed something new.

## Issues

Bug reports for these workflows are welcome — include n8n version,
the failing node, and the workflow execution log.
