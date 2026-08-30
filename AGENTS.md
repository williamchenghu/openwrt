# Project knowledge

This file gives Freebuff context about your project: goals, commands, conventions, and gotchas.

## Quickstart
- Setup:
- Dev:
- Test:

## Architecture
- Key directories:
- Data flow:

## Ways of working (hard requirements)

These rules govern every change in this repository. They are non-negotiable and
apply to every agent session and human edit.

### Language rule — English or Chinese only

- Every reply to the user must be written in **English or Chinese** — never in
  any other language. German (or any third language) is strictly forbidden in
  conversation replies.
- This rule also applies to commit messages, PR titles/bodies, and issue
  comments that are addressed to the user.

### Always feature branch + PR — never commit/push to `main`

- Every change goes on a dedicated **feature branch** and lands via a **pull
  request**. No commits, no pushes, and no merges are ever made to `main`
  directly.
- Branch off `origin/main` (fetch it first), push your branch, and open a PR.
- A PR targets `main` as its base.

### A ticket is only "closed" when its linking PR goes in

- An issue is **not** closed by its findings doc, its comments, or a local
  resolution. It is only closed when the **pull request that captures the
  change is merged**.
- Treat "closed" as equivalent to "merged": if the linking PR is still open,
  the ticket is **not closed**, it is *pending merge*.
- Never narrate a ticket as closed, completed, or resolved while its PR is
  open.
- **Close it automatically, never by hand.** In the PR that captures a
  ticket's change, write the closing keyword `Closes #<n>` (GitHub also
  accepts `Fixes`/`Resolves`) in the PR **body** so that GitHub auto-closes
  the issue the moment the PR merges. Do not also run `gh issue close` —
  that's the manual step this convention forbids; the merge's auto-close is
  the only close.
- To make the pending state visible while the PR is open, tag the ticket
  `wayfinder:pending-merge`. It stops being pending (label removed) only after
  the PR merges and auto-closes it.

### Commit-and-push every completed request

- Whenever requested work or a revision is completed, **commit it and push it
  to the current feature branch** immediately.
- The most recent requested change must be captured in its PR. If work is left
  only in the working tree, that request is not done.

### Wayfinder: every closed ticket gets an overview comment on the map

- When a wayfinder ticket (a child of the `wayfinder:map` issue) is resolved
  and closed, post a **"✅ Ticket closed: <title> (#N)"** overview comment
  **on the map issue itself** — answer, downstream effect, fog graduated, and
  asset links — in the style already used there. This is in addition to the
  ticket's own resolution comment and the map body's Decisions-so-far entry.
- The map's overview comments are the effort's running changelog; a closed
  ticket without one is incomplete. Before closing a wayfinder ticket, check
  the map's comment history and **backfill any earlier closed ticket that is
  missing its overview comment** in the same pass.

## Conventions
- Formatting/linting:
- Patterns to follow:
- Things to avoid:

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues using the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Domain docs

This repository uses a single-context layout with a root `CONTEXT.md` and `docs/adr/`. See `docs/agents/domain.md`.
