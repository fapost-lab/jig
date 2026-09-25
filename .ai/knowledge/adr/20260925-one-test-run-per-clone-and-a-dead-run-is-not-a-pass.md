---
id: adr-20260925-one-test-run-per-clone-and-a-dead-run-is-not-a-pass
type: adr
status: accepted
date: 2026-09-25
domains:
  - verify
paths:
  - scripts/lib/verify.sh
  - scripts/lib/profile.sh
  - "profiles/**"
  - tests/run.sh
  - scripts/lib/config.sh
summary: Why jig verify holds a record the whole clone can see and waits for another run, and why a run killed rather than failed is a third outcome with exit code 3.
---
# ADR: One test run per clone, and a run that dies is not a pass

## Context

On the night of 2026-09-24/25 eight full test sets ran at once on one machine, started by
eight different agents at 23:41, 23:42, 23:43, 23:46, 23:47, 00:07, 00:16 and 00:18 — 126
test processes, load average 364. A set that takes 5-6 minutes alone took forty. Two reviews
stalled at 40 and 50 minutes, and a third task queued behind them for the same CPU.

**Nobody broke the rule.** `conventions/shell.md` already said "avoid simultaneous duplicate
full runs", and every agent obeyed it: each had exactly one run, and none was a duplicate.
The rule is written for one actor and says nothing about a population, so eight law-abiding
agents produce eight sets. This is the class `conventions/required-records.md` names — an
instruction that has to be remembered, and that fails precisely when each reader keeps it.
A fact the machine can see is the only fix; more prose is not.

The same night produced a second, quieter cost. Four times a run was killed by the sandbox
rather than failing — `Killed: 9`, `Terminated: 15` — and four times that was read as a
defect in the code. The author of `worktree-bootstrap` spent three attempts and two hours on
it; the reviewer of #95 chased 24 "failures" in `verify::` that were an artefact of a
parallel run. Not once was the cause in the repository. The sentence that closes it was
written in the body of PR #111:

> A run that dies without a failure is not a pass, so it is not claimed as one.

It is the sister of a rule this domain already holds — "a narrowing that selects nothing is
not a pass". Same shape: the absence of red is not green. Today `jig verify` has one non-zero
exit code, so "the tests failed" and "the run never finished" arrive as the same answer, and
a human has to tell them apart by reading a log. Three times in one night the human told them
apart wrongly.

## Decision

### A run takes a record the whole clone can see, and waits while another holds it

`jig verify` claims a record before it runs any profile and gives it back on exit. While
another run holds it, this one **waits**.

**Waiting, not refusing or warning.** Run serially, the eight sets finish at 6, 12, 18 … 48
minutes. Seven of the eight answers arrive sooner than they do under contention, the average
at 27 minutes against forty; only the last is later, by about the length of one set. That
trade alone would be arguable — what settles it is everything *else* on the machine. At load
average 364 the CPU is mostly not running tests, and the two reviews that stalled at 40 and 50
minutes were not running a suite at all; they were queued behind eight of them. Serialising
gives that time back to work that was never competing.

A refusal would break CI and honest parallel work and would need the same expiry anyway; a
warning is the same prose that already failed.

**The record lives in the clone's main checkout**, at `<clone root>/.ai/runtime/verify/`,
found with `jig_config_clone_root` — which already answers from git's own files, with no
`git` process, and gives one answer from every worktree. ADR-0038 made *reading* there a
named exception to ADR-0008's "no cross-worktree lookup"; this extends that exception to
*writing*, for a reason ADR-0024 does not cover: what is being protected belongs to no
checkout. The CPU is one per clone, and the eight runs were in eight different worktrees.
The checkout record was rightly kept per checkout because it is *about* a checkout; this one
is about the machine.

**This is not the first write there, and that matters.** The live status page has been
written to the main checkout's `.ai/runtime/` since 2026-09-22, found the same way
(adr-20260922-the-status-page-stays-current-without-a-server: "One page per clone, in the
main checkout"). What this decision adds is the second user and the rule that admits both,
now recorded as ADR-0008's third amendment: state that belongs to the **clone** — because
the reader and the CPU are one for all its worktrees — lives there; state about a
**checkout** does not.

That line is what keeps this from contradicting
adr-20260924-a-checkout-records-what-is-happening-in-it, which considered a shared per-clone
directory for *its* record and rejected it. That record answers "what is happening in this
checkout", so a shared home would have made it answer the wrong question. Its rejection is
about the record's subject, not about the location, and it stands untouched.

The git common directory (`git rev-parse --git-common-dir`) gives the same visibility and
was rejected on two counts: it needs a new `git` call where an existing helper already
answers, and it puts the path outside `.ai/`, where RULES.md's deletion invariant can no
longer hold.

**The claim is a `mkdir`.** Under ADR-0002 it is the one atomic primitive available on POSIX
and in Git Bash alike, and atomicity is the whole point: with a plain flag file the eight
waiters wake together the moment the holder leaves and produce the eight simultaneous sets
again. The kernel arbitrates, so two runs reclaiming an expired record at once is safe too.
The body — `checkout:` and `pid:` — is written straight into the claimed directory: only the
claimant can write there, a reader that catches a partial file falls back to the expiry, and
a leftover temporary would make `rmdir` refuse for good.

**A record is live only when two independent tests both pass**, and they answer different
failures:

1. `kill -0 <pid>` succeeds. A shell builtin, not `ps`, which ADR-0002 rules out and which
   behaves differently under Git Bash — the same argument that rejected option (e) in
   `checkout-is-occupied`. This is the normal path, and it is the one this task needs: a run
   killed by the sandbox gives the clone back at the very next poll.
2. The record's mtime is within `verify.busy_ttl`. The backstop for when (1) is wrong —
   another user's process reads as dead (EPERM), a recycled pid reads as alive. Both errors
   are bounded: "wrongly dead" is today's behaviour, and "wrongly alive" waits no longer
   than the expiry. A record with no readable `pid:` falls back to (2) alone.

The record is **not refreshed** while the run goes on. A heartbeat would need a background
process, and one orphaned by a `kill -9` on its parent would hold the clone for ever — worse
than the stale record it prevents. So a run longer than the expiry stops holding the clone;
the pid check is what makes that rare rather than normal.

**One key, `verify.busy_ttl`, default `30m`**, in the duration grammar the framework already
has, with a mistyped value leaving the default standing rather than taking the command down.
It belongs to the local layer (ADR-0038) as well as the project one: how long a machine's own
suite takes is a fact about the machine. `0` is a duration the grammar already spells and
switches the whole mechanism off — the escape for someone who genuinely wants parallel local
runs, with no new flag to learn. There is no key anyone must fill.

**`CI` switches it off entirely.** In CI parallelism is deliberate and each job has a machine
of its own; a record there is useless at best and queues jobs meant to run at once at worst.
`CI` is the signal `cmd_verify` already trusts for `verify.full_run` (ADR-0041), so this adds
no new way of telling CI apart.

**Waiting is said out loud, in two places.** The waiting itself goes to stderr — the first
line names the checkout and how long it has been running, and says how never to wait; a
progress line follows once a minute, so a run is visibly waiting rather than hung. When a
wait actually happened, one line goes to **stdout**, into the report: the evidence that this
run queued belongs where the run's other evidence is.

**Giving the record back is two bounded deletions**, the shape ADR-0035 allows `jig spec new`:
`rm -f` of one named file, then `rmdir`, which refuses a directory that is not empty. There is
no `rm -rf` on a computed path, and the path is checked to be the one this code builds before
anything is deleted. Taking over an expired record uses the same two.

**Nothing here may fail `jig verify`.** Every path that cannot answer gives up and lets the run
go ahead: a record that cannot be taken is a missed serialisation, which is today's behaviour,
while a refusal would be a new way to break.

### A run that died is a third outcome, and exit code 3 carries it

`Killed: 9` and `Terminated: 15` reach a waiting process as 128+N. That is visible in exactly
three places, and all three now report it:

- **`tests/run.sh`** already records each test's exit code. A code at or above 128 is a death
  by signal; a missing result file is a worker killed before it could write one — the case an
  overloaded machine produces most often. Both are counted apart from failures, the summary
  gained a fourth field (`N passed, M failed, K skipped, L not completed`), and the runner
  exits **3**.
- **`jp_run` in `scripts/lib/profile.sh`** — the one place every stack profile runs a check
  through, so one change answers for go, jvm, ruby, swift, php, laravel, rust and python at
  once. A check killed by a signal is printed as `incomplete`, and `jp_end` exits **3**.
  `jp_incomplete` is the new function for a profile that reads a runner's own answer instead.
  `profiles/shell/verify.sh`, which predates that library, does the same by hand.

  This edits a `jp_*` function, which adr-20260918 forbids — "never renamed, never given a
  new meaning" — because a user-modified profile meets whatever library the upgrade
  installed. The exception is argued and recorded as that ADR's amendment, and it rests on
  one property rather than on goodwill: **this adds a third state to a channel that already
  carried the answer, and every consumer that does not know the state reads it as the more
  cautious of the old two.** A profile that only asks whether the code is zero sees a
  non-zero and reads it as it read a failure; none becomes less careful than it was. A
  profile written without the library — the `if cmd; then pass; else fail; exit 1` shape —
  is untouched entirely, and a test proves that rather than asserting it.
- **`cmd_verify`** — a profile that exits 3, or that was itself killed (128+N, which no
  profile has to be taught), is `RESULT <p>: incomplete`. The tally gained an `incomplete`
  field and `jig verify` exits **3** with one sentence: the run did not finish, so it neither
  passed nor failed — run it again.

**Incomplete outranks fail** at every level. A run something was killed in is not evidence, so
the failures beside it cannot be trusted either — which is precisely what happened to the
reviewer of #95. Nothing is lost by this precedence: a real failure comes back on the next
run, while an artefact of an overloaded machine does not.

**Exit 3 was free.** Profiles exit only 0, 1 and 2 today; `jig verify`'s code is read by
nobody outside the tests — not `jig task ship`, not the skills, and CI cares only whether it
is zero. Jig already uses 3 for a distinct outcome in `jig task autopilot repair`, so the
vocabulary is not new either.

**The honest limit.** What is detected is death **by a signal**. A test that was starved
rather than killed, and failed in the ordinary way, still reads as a failure and cannot be
told apart from a real one. The first half of this decision removes the condition that
produces such artefacts; the second makes legible the part the machine can actually see.

## Alternatives

- **Do it in `tests/run.sh` rather than `jig verify`.** Rejected for the record: `tests/run.sh`
  is this repository's runner, while `jig verify` is installed into every project, and any
  project with more than one agent has this problem. The runner still learns the *killed test*
  half, because that is where a dead test is visible at all.
- **`git rev-parse --git-common-dir` as the record's home.** Rejected: a new `git` call where
  `jig_config_clone_root` already answers, and a path outside `.ai/` where the deletion
  invariant cannot hold.
- **A flag file instead of `mkdir`.** Rejected: not atomic, so the waiters would wake together
  and reproduce the incident this decision exists to prevent.
- **A heartbeat that refreshes the record.** Rejected: it needs a background process, and one
  orphaned by a `kill -9` on its parent holds the clone for ever.
- **Refusing, or warning, when another run is live.** Rejected on the arithmetic above: a
  refusal breaks CI and honest parallel work, and a warning is the prose that already failed.
- **Two keys, an expiry and a separate wait cap.** Rejected once the pid check was in: with a
  dead holder released at the next poll, the expiry is a backstop rather than the normal path,
  and one number does both jobs.
- **Detecting starvation as well as signals** (timeouts, wall-clock outliers). Rejected as a
  guess a green run cannot confirm. The limit is stated instead of hidden.
- **Teaching every shipped profile the third outcome by hand.** Unnecessary: `jp_run` is the
  shared choke point, and `cmd_verify` catches 128+N from any profile whatever it does.

## Consequences

- Two runs on one clone now take twice the wall time and finish sooner than two runs that
  fight. A run may sit waiting for minutes, visibly and with the reason named; `verify.busy_ttl: 0`
  opts out.
- A run longer than `verify.busy_ttl` stops holding the clone and can be run over. Projects
  whose suite is longer than half an hour raise the key.
- **The default and the incident's own worst case are uncomfortably close, and the reason
  they are not in conflict has to be said.** The incident measured a 5-6 minute set taking
  forty; the default expiry is thirty. Read naively, a run like that would lose its record
  to a waiter under exactly the load this feature exists for, and pile up again at smaller
  scale. What makes that reading wrong is that **forty minutes is a measurement of the world
  this decision abolishes**: it is the time of a set sharing a machine with seven others,
  and once the record holds, a set runs at roughly its solo time. The number the expiry must
  cover is a suite's *own* length, not its contended one, and thirty minutes is five times
  this repository's. A project whose suite genuinely takes longer alone raises the key —
  which is why it is a key and not a constant. The residual case is a run that is alive but
  stuck: the pid check keeps saying "alive", and only the expiry ends the wait. Thirty
  minutes bounds that; a much larger default would not.
- `jig verify` and `tests/run.sh` now have three answers, not two. Anything that reads their
  exit code must treat 3 as "run it again", not as a failure — today nothing outside the
  tests does.
- The profile contract gains an exit code and a verdict word. A profile a user edited and
  `upgrade` kept will simply never produce them, which reads as it does today.
- `.ai/runtime/verify/` is one more thing in the clone root's runtime directory. Nothing
  deletes an expired record in the background; the next run takes it over.
- **There is no queue and no order.** When a holder leaves, every waiter races on the same
  `mkdir` and one wins; the others go back to waiting. That is enough for the problem — what
  had to stop was eight sets running at once, not unfairness between eight waiters — and a
  real queue would need state that survives a killed waiter, which is the mechanism this
  decision was careful to avoid.
- The mechanism is scoped to one clone. Two clones of the same repository on one machine
  still compete; that is the boundary `jig_config_clone_root` can see, and naming it is
  better than pretending the record covers the machine.
