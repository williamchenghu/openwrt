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

### Commit-and-push every completed request

- Whenever requested work or a revision is completed, **commit it and push it
  to the current feature branch** immediately.
- The most recent requested change must be captured in its PR. If work is left
  only in the working tree, that request is not done.

## Conventions
- Formatting/linting:
- Patterns to follow:
- Things to avoid:

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues using the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Domain docs

This repository uses a single-context layout with a root `CONTEXT.md` and `docs/adr/`. See `docs/agents/domain.md`.
