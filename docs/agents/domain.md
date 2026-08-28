# Domain documentation

This repository uses a single-context layout:

- `CONTEXT.md` at the repository root contains the project's domain model and shared vocabulary.
- `docs/adr/` contains architecture decision records.

## Consumer rules

- Read `CONTEXT.md` when a task depends on domain terminology, business rules, or system concepts.
- Read relevant records in `docs/adr/` before changing an area governed by an architectural decision.
- Keep domain terms consistent with `CONTEXT.md`; update it when the domain model changes.
- Record durable architectural decisions in `docs/adr/` rather than relying on code comments or chat history.
