# Testing standard: test like a real user

Applies to every change that reaches a user, a caller, or another team. Read
with `PROTOCOL.md` (how we work together).

> **Root rule: it is not done until it has run the way a user runs it.**
> Green unit tests are necessary. They are not sufficient.

---

## 1. Why unit tests are not enough

The bugs that cost the most hours look fine from the inside:

- every request returns `200 OK`, and the screen shows "0 results";
- the unit test mocks the dependency that is actually misconfigured;
- the build that was tested is not the build that was deployed;
- a fallback swallows an error, so "no data" and "failed to read" look the same.

None of these fail a unit test. All of them fail a user. Keep a short list of
real incidents like these at the top of this file in your project; it is the
best argument for the rules below.

---

## 2. Sizes, not names

Classify tests by the resources they use, because that decides how fast,
stable and honest they are:

| Size | Constraint | Typical form |
|---|---|---|
| **Small** | one process, no I/O, no network, no sleep | pure functions, reducers, parsers |
| **Medium** | several processes on **one machine**, localhost only | service + real database in a container |
| **Large** | the real system, real data shapes, driven **like a user** | browser E2E, API flows across services, staging runs |

**Volume** follows the pyramid: roughly 80% small, 15% medium, 5% large. Edge
cases, bad inputs and combinatorics belong in small tests: fast, and they point
at the broken line.

**The "done" gate** is different: any change that touches a user flow needs
**at least one large test run for real** before it is reported done. The
pyramid sets how many tests of each size you write. It never lets you skip the
top.

---

## 3. Definition of done

The `DONE:` line of a task (the `TaskCreated` gate requires one) must **name the
E2E case** that will be run, not "tests pass".

A change that touches a user flow is done only when all six hold:

1. **Small and medium tests green**: the test suite and type checks of every
   module touched.
2. **A large test ran on a real stack** (local full stack or staging) against
   **the exact build** being shipped. State the commit or version.
3. **Evidence attached**: the command, its real output, a screenshot or
   accessibility snapshot, log lines. "It works" alone counts for nothing.
4. **At least one failure path ran** (see §6) and the user saw a meaningful
   error.
5. **The verifier is not the author**: `qa`, or a fresh-context reviewer.
6. **The E2E case can be re-run**: as a script or test file, or as steps
   written precisely enough to follow.

Cannot build an environment to run the large test? Then it is **not done**.
Send a `HELP-NEEDED` block (PROTOCOL.md §4.4) that says where you are stuck.

---

## 4. Writing an E2E case

Every large test follows the same four steps: **set up the system, seed data,
act, verify**.

```
### E2E CASE: <short name>
- USER: <who> — trying to <goal>
- SYSTEM: <what runs for real, what is faked; commit / version / environment>
- DATA: <seed: accounts, records, fixtures; all prefixed so they can be cleaned up>
- STEPS: 1. ... 2. ... (exactly what the user clicks, types, or sends)
- EXPECTED: <what the user SEES: text, numbers, buttons, messages>
- CROSS-CHECK: <read the result back through another path: DB, log, API>
- EVIDENCE: <screenshot, snapshot, output>
```

Two rules for the verify step:

- **Assert at the layer the user sees.** "HTTP 200" is not a pass. Check the
  text, the numbers, the buttons.
- **Read back through a different path.** Write through the UI, read through the
  database or the API (or the other way round). One path can lie; two rarely
  lie the same way.

When an E2E run finds a bug, **push it down**: write the smallest small test
that reproduces it, then fix. Next time it fails in seconds, not minutes.

---

## 5. Which E2E cases are mandatory

Keep a table in your project mapping areas of the code to the E2E cases that
must run when they change, for example:

| If you change | You must run |
|---|---|
| authentication, sessions | sign-up, sign-in, sign-out, expired session |
| checkout or payments | happy path, declined card, retry after timeout |
| data import | small file, large file, malformed file |

Changes that touch several areas run the union.

---

## 6. Test the failure paths: errors must surface

The most expensive class of bug is **broken but looks normal**. Every main E2E
case needs at least one failing sibling:

- **Kill a dependency** (stop a service, wrong credentials, wrong environment
  variable). The UI must show a meaningful error. A blank page, an endless
  spinner, or "0 results" is a **FAIL**.
- **"No data" and "failed to read" must differ**, on screen and in logs. An
  `if (!x) return` with no log line is where bugs hide.
- **Truncated lists carry the real total**: the items you show and the count
  you report are different numbers.
- **Twice and halfway**: submit twice, retry a webhook, restart a worker mid-job.

---

## 7. Test doubles: real > fake > stub > mock

- Prefer the real implementation. Mocks make tests brittle and rarely catch bugs.
- **Mock an AI model only in small tests.** Every AI-backed feature needs at least
  one case that calls the real model with production settings.
- **Fakes are owned by the owner of the real thing**, and come with a test
  proving the fake still matches.
- **Check state, not calls.** Right: "after sending, the conversation shows
  message X". Wrong: "`send` was called once".

---

## 8. Against flakiness

- **No fixed sleeps.** Poll for the expected state with a timeout.
- **Test data has its own prefix** and is cleaned up afterwards. Never touch
  real user data.
- **Run A-A**: same build, twice. Different results mean the test is not
  deterministic; that is not yet a product bug.
- **AI output: never assert exact text.** Assert properties (answered, correct
  price, no invented links, right tool called). Run at least 3 times and report
  the pass rate.
- **A flaky test is a bug in the test.** Fix it or quarantine it now. Re-running
  until green is not a pass.
- **If you liked it, you should have put a test on it.** An important flow
  without an E2E case that someone breaks is on whoever skipped the test.

---

## 9. Working with agents on tests

| Practice | How the team applies it |
|---|---|
| Give the agent a check it can run | every HANDOFF to `developer` / `frontend` includes the command that proves done |
| Spec first, ending in an E2E step | `product-manager` writes acceptance criteria as E2E cases (§4) before building |
| Small steps, commit when green | one change + its test + a commit; commits are save points |
| Evidence over claims | reports follow §10; UI changes include a screenshot or snapshot |
| Give the agent eyes at runtime | browser automation (Playwright or a browser MCP) for `frontend` and `qa` |
| E2E cases live in files | cases become test files or scripts, not memories |
| Writer is not the reviewer | `qa` verifies; a fresh-context review before handing to `qa` |
| Deterministic gates use hooks | CLAUDE.md is advice; hooks always run |
| A human signs | agents write, people sign; nobody merges what they have not seen run |

### Prompt template for an implementation task

```
Implement <feature> in <files/area>.
1. Write small tests for <function/branch>, including missing-data and read-failure cases.
2. Run the module's tests and type checks; fix until green.
3. Start the stack (<how>), deploy the new build, clear caches that could serve the old one.
4. Run the E2E case "<name>" from .claude/team/TESTING.md §4, acting as <user>.
5. Run a failure case: stop <dependency>, confirm the UI shows <message>.
6. Report using §10 with real output. If a step cannot run, say where it is stuck.
   Do not report done without a large test.
```

---

## 10. Test report template

```
## Verdict
PASS | CONDITIONAL PASS — N minor issues | FAIL — blocking issues

## Results by size
| Size   | Command                 | Result |
|--------|-------------------------|--------|
| Small  | npm test                | 42/42  |
| Medium | npm run test:integration| PASS   |
| Large  | npm run e2e -- checkout | 12/12, order visible in history |

## E2E cases run
<each case in the §4 format, with evidence>

## Failure cases run
<which dependency was broken -> what the user saw>

## NOT VERIFIED
<what, and why. Be honest; an empty section means everything was verified>
```

The **NOT VERIFIED** section is mandatory. A report without it is hiding the
part nobody checked.
