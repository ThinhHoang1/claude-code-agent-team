# claude-code-agent-team

A small, opinionated kit that turns a repository into a workspace for an
**AI dev team** in [Claude Code](https://code.claude.com/docs/en/agent-teams):
eight role agents, a message protocol they share, and three hooks that act as
deterministic quality gates.

## The idea

Claude Code's *agent teams* let one session (the lead) spawn teammates that
are independent Claude sessions, message each other by name, and share a task
list. That is a lot of power and very little structure. This kit adds the
structure that a human team would have:

- **Roles with boundaries.** Each role knows what it owns, what it must not
  touch, and who to ask. "How it works today" (codebase-historian) is separated
  from "how it should be" (architect), and the person who builds is never the
  person who verifies (qa).
- **A protocol.** Work is handed off in a fixed `HANDOFF` block that carries all
  the context, because teammates cannot see each other's conversations.
  Decisions and blockers go in one file, `BOARD.md`.
- **Gates that always run.** `CLAUDE.md` is advice the model may forget. Hooks
  are executed by Claude Code every time. Three of them enforce the rules that
  matter most when nobody is watching.

## What's in the box

```
CLAUDE.md                         lead playbook + project map template
.claude/settings.json             enables agent teams, wires the hooks
.claude/agents/                   eight role definitions
.claude/team/PROTOCOL.md          how teammates work and talk
.claude/team/BOARD.md             decisions + blockers (template)
.claude/team/TESTING.md           test-like-a-real-user standard
.claude/hooks/task-created-gate.sh
.claude/hooks/task-completed-gate.sh
.claude/hooks/teammate-idle-gate.sh
install.sh                        copy the kit into another repo
tests/                            hook tests, fixtures, regression test
```

## Roles

| Agent (= teammate name) | Owns | Edits files? | Notable tools |
|---|---|---|---|
| `tech-lead` | plan, task split, file ownership, tie-breaks | board and plans only | `Agent(...)` limited to the other seven roles |
| `product-manager` | scope, acceptance criteria, final sign-off | board and specs | |
| `product-strategist` | long-term direction and the evidence for it | no | WebSearch, read-only Bash for measuring |
| `architect` | how it **should** be built; 1x / 10x / 100x scale table | no | read-only Bash for benchmarks |
| `codebase-historian` | how it **actually** works today; blast radius | no | read-only Bash for `git log`, tests |
| `frontend` | UI code, verified in a real browser | yes | |
| `developer` | non-UI code and its tests | yes | |
| `qa` | testing like a real user; PASS / CONDITIONAL / FAIL | test files and blockers only | |

Every role can `SendMessage` and use the task tools. Only the lead spawns.
The lead runs 3 to 5 teammates at a time, chosen by phase: shape
(product-manager, product-strategist), understand and design
(codebase-historian, then architect), build (developer, frontend), verify and
accept (qa, then product-manager).

## Message protocol

Teammates do not share context, so every unit of work travels as a
self-contained block (full formats in [PROTOCOL.md](.claude/team/PROTOCOL.md)):

```
### HANDOFF
- FROM: tech-lead
- TO: developer
- TASK: add a bounded retry to the payment client
- CONTEXT: client.ts:88 calls the API once; timeouts surface as 500s (log excerpt ...)
- FILES YOU OWN: src/payments/client.ts, src/payments/client.test.ts
- EXPECTED OUTPUT: retry with backoff, max 3 attempts, idempotency key reused
- DONE: unit tests green and the "checkout survives one timeout" E2E case passes
- BLOCKING: yes
```

Plus `DECISION` (recorded in BOARD.md), `HELP-NEEDED` (stuck for more than one
turn) and `BLOCKER` (an entry under "## Blockers" in BOARD.md). Every turn ends
with a `SendMessage` report: conclusion, evidence, handoffs, next step.

## The three gates

| Hook | Blocks (exit 2) when | Why it exists |
|---|---|---|
| `TaskCreated` | the task description has no `DONE:` line | A task without a verifiable finish line gets "finished" by whoever is most confident. Forcing a `DONE:` line at creation time makes "how will we know?" part of the plan, not an afterthought. |
| `TaskCompleted` | a task tagged `[GATE]` is completed while BOARD.md lists open blockers | Sign-off is the moment pressure to ship is highest. The gate makes "known blocking bug" and "accepted" mutually exclusive unless someone explicitly closes the blocker. |
| `TeammateIdle` | a teammate goes idle after a turn with no `SendMessage` call | A teammate's final text is not a reliable report: depending on version and display mode, the lead may only learn that the teammate stopped. An explicit, addressed message is what turns work into something the team can use. The gate asks once per turn, then lets go. |

All three fail open on malformed input, and each can be switched off with an
environment variable (see Configuration).

## Postmortem: the idle gate that never let go

The first version of the `TeammateIdle` gate trapped teammates in a loop. In
the incident that exposed it, a QA teammate was blocked four times in a row on
a single task and sent a fresh report every time; the gate kept insisting it
had not reported.

**Root causes**, found by replaying the gate against the real transcripts:

1. **Wrong file.** For in-process teammates, the hook payload's
   `transcript_path` is the *lead's* session transcript. A teammate's own tool
   calls live in `<session>/subagents/agent-<id>.jsonl`. The gate was counting
   the lead's `SendMessage` calls and never saw the teammate's.
2. **The window was anchored at the end, not the start.** The gate stored the
   transcript's line count when it last ran and only counted lines after it
   (`tail -n +$((prev+1))`). Anything before that point, including a report
   already sent, was outside the window: 0 `SendMessage` calls in the window,
   22 in the whole file, all of them the lead's.
3. **The escape hatch could not open.** To avoid loops, the gate released a
   teammate when the line count was unchanged since the last block
   (`blocked == total`). But every block appends feedback to the transcript and
   every reply appends more, so the count always grew. The release condition
   could never become true.

An earlier revision had a fourth defect: it keyed its state on `agent_id`,
which the payload did not carry, so every teammate shared one counter.

**The fix** (`.claude/hooks/teammate-idle-gate.sh`):

- **Read the teammate's own transcript**: `agent_transcript_path` if present,
  else `subagents/agent-<agent_id>.jsonl`, else the newest
  `subagents/*.meta.json` whose name matches `teammate_name`, else
  `transcript_path` only when no `subagents/` folder exists (split-pane
  teammates are their own session). If none resolves, do not judge.
- **Anchor the turn by content, at its start**: the turn begins at the last
  message the teammate *received*. Tool results and hook feedback do not count
  as received messages, so the continuation after a block is judged together
  with the blocked turn, and a report sent in it releases the gate.
- **Bounded by construction**: at most one nudge per turn, counted from the
  gate's own feedback in the transcript, with a small state file keyed by the
  anchor message's id as a backstop. State can only release, never block.

**The regression test** (`tests/test_regression_idle_loop.sh`) drives a
re-implementation of the old logic and the new hook through the same
scenarios:

```
scenario A  legacy exit codes per idle: 0 2 2 2 2 2   <- reports every turn, blocked every turn
scenario A  fixed  exit codes per idle: 0 0 0 0 0 0
scenario B  legacy exit codes per idle: 2 2 2 2 2 2   <- silent once, then compliant: still blocked
scenario B  fixed  exit codes per idle: 2 0           <- one nudge, released after the report
scenario C  legacy exit codes per idle: 0 2 2 2 2     <- right file, but the window starts after the report
scenario C  fixed  exit codes per idle: 0 0
```

**Lessons**

- A gate that can block must have a release condition that provably becomes
  true. Test the release, not just the block.
- Never use as a cursor a size that the gate itself makes grow.
- Read a real payload and the real files before trusting a field's name.
  `transcript_path` did not point where we assumed. (The same audit found the
  task gates reading `task_title`, while the documented field is
  `task_subject`; the kit reads both.)
- When unsure what you are looking at, fail open and say why in the debug log.

## Install

Requirements: Claude Code with agent teams available, `bash` (3.2 or newer),
`jq`.

```bash
git clone <this repository> claude-code-agent-team
./claude-code-agent-team/install.sh --dry-run /path/to/your/repo   # preview
./claude-code-agent-team/install.sh /path/to/your/repo
```

The installer never clobbers: a file that already exists with different
content is skipped and listed, with a merge hint for `settings.json` and
`CLAUDE.md`. `--force` overwrites those files, except `BOARD.md`, which is your
project's decision log and is only ever seeded. Then open the repo in Claude
Code and fill in the "Project map" section of `CLAUDE.md`.

This repository is itself set up with the kit, so you can try it here first.

## Usage

Talk to the lead in plain language and name the roles you want:

```
Build CSV export for the reports page. Use the team: product-manager writes
acceptance criteria, codebase-historian maps the current export code, architect
reviews the design, developer and frontend build it on separate files, qa
verifies it like a user. Name each teammate after its role. Require plan
approval for anything that changes the database schema.
```

Or start the tech-lead role as the lead session:

```bash
claude --agent tech-lead
```

Useful habits for the lead: give every spawn a full HANDOFF; split files before
spawning; when a teammate goes idle without a report, ask for one; tag the final
acceptance task `[GATE]`.

## Configuration

| Variable | Default | Effect |
|---|---|---|
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | `"1"` in settings.json | `"0"` turns teams off; named subagents run as plain subagents again |
| `AGENT_TEAM_TASK_GATE` | `on` | `off` disables both task gates |
| `AGENT_TEAM_DONE_MARKER` | `DONE` | keyword the TaskCreated gate requires (e.g. a translation) |
| `AGENT_TEAM_BOARD` | `.claude/team/BOARD.md` | board read by the TaskCompleted gate |
| `AGENT_TEAM_IDLE_GATE` | `on` | `off` disables the TeammateIdle gate |
| `AGENT_TEAM_IDLE_MAX_NUDGES` | `1` | nudges per turn before the idle gate releases; `0` never blocks |
| `AGENT_TEAM_STATE_DIR` | `.claude/hooks/.state` | idle gate backstop state (git-ignored automatically) |

Set them in the `env` block of `.claude/settings.json` or
`.claude/settings.local.json`.

## Testing the kit

```bash
tests/run.sh             # with your default bash
tests/run.sh /bin/bash   # on macOS: also check the system bash 3.2
```

Plain bash + jq, no other dependencies. The tests feed fixture hook payloads
and fixture transcripts to each hook and assert exit codes and messages, check
the installer against a scratch repo, and run the regression scenarios above.

## Limitations

- **Agent teams are experimental.** Hook payloads, the transcript format and the
  `subagents/` layout are not a stable API. The idle gate depends on them; when
  it cannot make sense of what it reads, it fails open (and says so in the
  debug log) rather than trapping a teammate.
- **Newer builds may include the final answer in idle notifications.** The idle
  gate still asks for an explicit, addressed report. If you do not want that,
  set `AGENT_TEAM_IDLE_GATE=off`.
- **A message delivered mid-turn as a user entry starts a new judged turn.**
  Worst case: one extra nudge.
- **Split-pane teammates that spawn their own subagents** have a `subagents/`
  folder next to their transcript, so the idle gate cannot tell their file from
  a lead's and does not judge them.
- **Tool lists are guardrails, not a sandbox.** Read-only roles keep `Bash` for
  measuring, and could still write with it. Their prompts forbid it.
- **Plan approval** may be granted automatically by the lead session in some
  versions; put your approval criteria in the spawn prompt.
- **Cost.** Every teammate is a separate Claude session; tokens scale with head
  count. For sequential or same-file work, one session or plain subagents are
  cheaper.
- **Platforms.** Tested locally on macOS with bash 3.2 and 5.x; the included CI
  workflow runs the suite on Linux and macOS. Windows needs WSL or Git Bash
  (untested).

## License

[MIT](LICENSE) © 2026 ThinhHoang
