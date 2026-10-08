# Project instructions

<!--
  Template from claude-code-agent-team. Fill in the "Project map" section,
  adjust the roles if your team needs different ones, and delete this comment.
-->

## Project map

<!-- Keep this short and true. The codebase-historian role keeps it accurate. -->

| Area | Path | What it is | Owner role | Touching it means |
|---|---|---|---|---|
| _e.g. API_ | `server/` | _HTTP API, jobs_ | developer | _shared/ is used by every process_ |
| _e.g. Web app_ | `web/` | _browser client_ | frontend | _design tokens live in web/theme_ |

Terms that are easy to confuse (define each once, use it the same way everywhere):

| Term | Means | Do not say |
|---|---|---|
| _e.g. "account"_ | _the billing entity_ | _"user" (that is a login)_ |

## Team

Eight roles live in `.claude/agents/`. The rules for working together, and the
HANDOFF / DECISION / HELP-NEEDED / BLOCKER formats, are in
**`.claude/team/PROTOCOL.md`**. Decisions and open blockers live in
**`.claude/team/BOARD.md`**. The testing standard is
**`.claude/team/TESTING.md`**.

| Agent type = teammate name | Owns |
|---|---|
| `tech-lead` | planning, coordination, tie-breaks |
| `product-manager` | scope, acceptance criteria, sign-off |
| `product-strategist` | long-term direction and the evidence for it |
| `architect` | how it should be built; scale at 1x / 10x / 100x |
| `codebase-historian` | how it actually works today |
| `frontend` | UI code, verified in a real browser |
| `developer` | non-UI code and its tests |
| `qa` | testing like a real user; the release verdict |

## When you are the lead

The main session is the lead. To make the tech-lead role the lead, start with
`claude --agent tech-lead`. Otherwise the main session plays lead and follows
this playbook:

1. **Only the lead spawns teammates.** Nested teams are not allowed; a teammate
   that needs help asks you.
2. **Name every teammate exactly after its role** (`architect`, `qa`, ...), so
   everyone can `SendMessage` everyone else by a predictable name.
3. **Every spawn prompt is a full HANDOFF block** (PROTOCOL.md §4.2). Teammates
   do not see your conversation; whatever you do not write down, they do not know.
4. **3 to 5 teammates at a time**, chosen by phase: shape (product-manager,
   product-strategist) → understand + design (codebase-historian, then architect)
   → build (developer, frontend) → verify + accept (qa, then product-manager).
5. **Split file ownership before spawning.** Two teammates must never edit the
   same file. Put "FILES YOU OWN" in each HANDOFF.
6. **An idle teammate is not a report.** Idle notifications may carry no usable
   output. If you have not received a `SendMessage` with results, ask for it.
7. **Risky work needs plan approval**: spawn with *"require plan approval before
   they make any changes"* and state your approval criteria in the same prompt.
8. **The task list is the source of truth.** Every task has a `DONE:` line; the
   final acceptance task is tagged `[GATE]`.

## Quality gates (hooks)

`.claude/settings.json` turns on agent teams and wires three hooks in
`.claude/hooks/`:

| Hook | Blocks when |
|---|---|
| `TaskCreated` | the task description has no `DONE:` line |
| `TaskCompleted` | a task tagged `[GATE]` is completed while BOARD.md lists open blockers |
| `TeammateIdle` | a teammate goes idle after a turn with no `SendMessage` call (once per turn) |

## Agent teams are ON

`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is `"1"` in `.claude/settings.json`.
Consequence: **a subagent that Claude names launches as a teammate**, even when
nobody asked for a team, and a flow waiting for that subagent's return value
will stall. Set the variable to `"0"` to get plain subagents back; it applies
when the file is saved.
