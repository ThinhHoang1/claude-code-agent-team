# Team board

> **This is not a task list.** Work lives in the shared task list (`TaskCreate`,
> `TaskList`, `TaskUpdate`). This file keeps the three things tasks cannot hold:
> **open blockers**, **decisions made**, and **handoff context** that must
> outlive a session.
>
> Rules: append to the end of a section, never delete someone else's entry,
> start every entry with `[<role> <date>]`. Formats are in
> `.claude/team/PROTOCOL.md` §4.

## Blockers

<!--
  The TaskCompleted gate reads THIS section. While it contains any top-level
  list item, no task tagged [GATE] can be completed. Placeholders in italics
  ("- _none_"), checked boxes ("- [x] ...") and anything inside comments or
  code fences are ignored.

  Format:
  - [qa 2026-01-31] **B-1 · Checkout fails on retry** — `npm run e2e -- checkout`
    returns 500 on the second attempt. Repro: ... Owner: developer.

  Resolved? Move the entry to "## Closed" with the fixing commit or decision.
-->

- _none_

## Decisions

<!-- One DECISION block per decision, newest last. -->

_none yet_

## Handoff context

<!-- Context that a future session needs: who holds what, what waits on whom,
     environment quirks, links to reports. Keep it short; prune when stale. -->

_none yet_

## Closed

<!-- Resolved blockers, moved here from "## Blockers" with the fix reference. -->

_none yet_
