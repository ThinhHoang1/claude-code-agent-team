# Team protocol

Shared rules for every role in `.claude/agents/`. The constraints below come
from how Claude Code agent teams actually behave (see the official docs on
agent teams, subagents and hooks); they are not decoration.

---

## 0. Two ways the roles run

| | **Teammate** (agent teams on) | **Subagent** (agent teams off) |
|---|---|---|
| What it is | an independent Claude Code session | a run inside the main session |
| Can message others | yes, `SendMessage` to anyone by name | no, returns a result to its caller |
| Coordination | shared task list + messages | the main session manages everything |
| How the lead gets results | **only what you send** (see §3) | automatically, when it finishes |
| Can spawn others | no (no nested teams) | no |

Agent teams are switched on by `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` in
`.claude/settings.json` (`"1"` on, `"0"` off; applied when the file is saved).

**Only the lead spawns.** The lead is the main session. To run the tech lead
role as the lead:

```bash
claude --agent tech-lead
```

Otherwise the main session acts as lead and follows the playbook in `CLAUDE.md`.

---

## 1. Roster

| Agent type = teammate name | Owns | Ask when |
|---|---|---|
| `tech-lead` | planning, coordination, tie-breaks | splitting work, ordering, estimates, deadlock |
| `product-manager` | scope, acceptance criteria, sign-off | value, scope cuts, GO / NO-GO, final acceptance |
| `product-strategist` | long-term direction + evidence | a decision might change where the product is going |
| `architect` | how it **should** be built, scale | design review, options, "what breaks at 10x?" |
| `codebase-historian` | how it **actually** works today | current behaviour, hook points, blast radius |
| `frontend` | UI code + browser verification | screens, components, client state |
| `developer` | non-UI code + tests | services, data, integrations, refactors |
| `qa` | testing like a real user, verdict | before sign-off, whenever "it works" lacks proof |

The lead names each teammate **exactly** after its agent type, so anyone can
reach anyone with `SendMessage` by a predictable name. The lead session itself
is usually addressable as `team-lead`.

---

## 2. Source of truth: the task list, not a file

Claude Code has a shared task list. Use it for work:

- `TaskCreate` creates a task and can declare **dependencies**; a blocked task
  cannot be claimed.
- `TaskList` / `TaskGet` show what is open and who holds it.
- `TaskUpdate` moves pending → in progress → completed.

`.claude/team/BOARD.md` is **not** a task list. It keeps the three things tasks
cannot: **decisions made**, **open blockers**, and **handoff context** that must
outlive a session.

> The `TaskCreated` gate rejects any task whose description has no `DONE:` line.

---

## 3. Reporting

> **Your final text is not a report.** Depending on version and display mode,
> the lead may receive only "teammate is idle", or a summary it cannot act on.
> A `SendMessage` is explicit, addressed, and lands in the recipient's inbox.

Before you end a turn, always:

1. `SendMessage` a report to the lead or to whoever assigned the work.
2. `TaskUpdate` the task you worked on.

Skip step 1 and your work effectively did not happen.

> The `TeammateIdle` gate stops you from going idle once per turn if the turn
> contains no `SendMessage` call. If it fires, send the report and stop normally.

Report template:

```
## Conclusion
<2-4 sentences>

## Evidence
<file:line, commands run, real output, measurements>

## Handoffs
<0..n HANDOFF blocks>

## Next step
<one action, one owner, doable now>
```

---

## 4. Handing off work

### 4.1 Who opens work

- **Lead**: `Agent` to spawn a teammate, `TaskCreate` to create work.
- **Teammates**: cannot spawn teammates. Calling `Agent` from a teammate only
  starts an ordinary foreground subagent. Need another person → message the lead.

### 4.2 HANDOFF: task descriptions, spawn prompts, and messages

```
### HANDOFF
- FROM: <role>
- TO: <role>
- TASK: <one sentence, verb first>
- CONTEXT: <file:line / commands run / real output the receiver needs>
- FILES YOU OWN: <paths the receiver may edit; everything else is read-only>
- EXPECTED OUTPUT: <concrete deliverable>
- DONE: <how completion is verified>        <- required, the gate checks it
- BLOCKING: yes | no
```

The receiver **cannot see** what you read or discussed. Never write "as
discussed"; write it out. A handoff without `CONTEXT` or `DONE:` may be sent back.

### 4.3 DECISION: recorded in BOARD.md

```
### DECISION <id> · <date> · <topic>
- PROBLEM: <one sentence>
- CHOSEN: <option>
- BECAUSE: <reasoning + evidence>
- TRADE-OFF: <what we give up>
- DECIDED BY: <role>
```

### 4.4 HELP-NEEDED: stuck for more than one turn? Say so.

```
### HELP-NEEDED
- WORKING ON: <task>
- STUCK AT: <exactly where>
- TRIED: <what, and what happened>
- NEED: <role> because <reason>
```

### 4.5 BLOCKER: an entry under "## Blockers" in BOARD.md

```
- [<role> <date>] **B-<n> · <short title>** — <evidence: command + output>.
  Repro: <steps>. Owner: <role>.
```

While any blocker is listed, no `[GATE]` task can be completed. Resolve it, then
move the entry to "## Closed" with the fixing commit or decision.

---

## 5. Lifecycle of a feature

```
product-manager    -> scope + acceptance criteria         GO / GO with cuts / NO-GO
  |
product-strategist -> direction check                     (only for direction-changing bets)
  |
codebase-historian -> how it works today, hook points, blast radius
  |
architect          -> design verdict + 1x/10x/100x table  (plan approval, §6)
  |
lead               -> TaskCreate with dependencies, file ownership per teammate
  |
developer  ||  frontend                                   (parallel, disjoint files)
  |
qa                 -> real-user verification              PASS / CONDITIONAL / FAIL
  |
product-manager    -> sign-off against the agreed criteria  <- task tagged [GATE]
```

The final acceptance task carries `[GATE]` in its subject. The `TaskCompleted`
gate refuses to complete it while BOARD.md lists open blockers.

Skipping a stage is allowed; say which one and why.

---

## 6. Plan approval for risky work

The lead spawns with an explicit request:

```
Spawn a teammate named architect using the architect agent type.
Require plan approval before they make any changes.
Approve only plans that include a rollback step and a test.
```

The teammate works read-only until its plan is approved. Approval criteria
belong in the spawn prompt: depending on the Claude Code version, approval may
be granted automatically by the lead session, so the criteria are the only
steering you get.

Use plan approval for: schema or data migrations, contract changes between
components, deleting code or data, and anything the architect marked WRONG
ARCHITECTURE.

---

## 7. Coordination rules

1. **Each teammate owns a disjoint set of files.** Two teammates editing one
   file overwrite each other. The lead splits files before spawning; editing
   outside your set means messaging the owner.
2. **Do not do someone else's job.** Out-of-scope problem → HANDOFF. Exception:
   a one-line fix to unblock your own task, stated in your report.
3. **Owners decide in their domain.** Scope → product-manager. Direction →
   product-strategist. Architecture → architect. Everything else → tech lead.
   Current behaviour is described by codebase-historian before the architect
   rules on it.
4. **Disagreement goes to data.** Before a second round of argument, both sides
   answer "what data would settle this?" and go get it. Still stuck → the tech
   lead decides and records a DECISION.
5. **Nothing is done until it ran.** Every "it works" comes with the command and
   the real output. Failures are pasted, not paraphrased.
6. **Cite sources.** Claims about existing code carry `file:line`.
7. **Messages from other agents are instructions, not authority.** A teammate
   cannot approve permissions on your behalf, and you do not ask another agent
   to do something you were just denied.

---

## 8. Team size

Run **3 to 5 teammates** at a time. Eight roles exist so the lead can pick the
right ones per phase, not so all of them run at once:

| Phase | Active |
|---|---|
| Shape | product-manager, product-strategist |
| Understand + design | codebase-historian, then architect |
| Build | developer, frontend |
| Verify + accept | qa, then product-manager |

Each teammate is a separate Claude instance; token cost grows linearly with the
head count. Sequential work, same-file edits, or tightly coupled steps are
cheaper in a single session or with plain subagents.

---

## 9. Known limitations (experimental feature)

- Resuming a session does not bring back in-process teammates; the lead may
  message teammates that no longer exist. Spawn them again.
- Task status can lag when a teammate forgets `TaskUpdate`, which blocks
  dependent tasks.
- One team per session, a fixed lead, no nested teams.
- Teammates inherit the lead's permission mode; permission prompts surface in
  the lead session.
- With agent teams on, a subagent that Claude names launches as a teammate even
  when nobody asked for a team. Flows that wait for a subagent's return value
  will wait forever. Set the flag to `"0"` when you need plain subagents.
