---
id: adr-20261030-a-review-reads-behaviour-and-standards-apart
type: adr
status: accepted
date: 2026-10-30
domains:
  - skills
  - task
paths:
  - "skills/jig-review/**"
  - skills/jig-task/references/delegation.md
  - skills/jig-autopilot/SKILL.md
  - skills/jig-architecture-review/SKILL.md
summary: Why the review stage is read on two axes, Behaviour and Standards, by two fresh readers in turn; why every project gets a baseline of code smells capped at P2; where a reviewer finds the rules; and why the readers do not run in parallel.
reviewed_at: 2026-10-30
---
# A review reads behaviour and standards apart, one reader each, and every project has a baseline of code smells

## Context

`jig-review` asked one reader to check requirements, correctness, rules, contract drift, evidence
and scope in a single pass, against the rules `jig context` resolves. A blind comparison on one
real task (two pull requests, the same brief) with the `code-review` skill of the
mattpocock-skills plugin, which splits a review into a spec pass and a standards pass, found:

- every new P1/P2 the change introduced came from Jig's correctness check, which the other review
  has no counterpart for;
- the other review found real violations of written rules that Jig's reviewer had read and still
  missed — it compared the diff with each rule in turn; and a rule in a file git does not track
  (`CLAUDE.local.md`), which a reviewer in a task worktree never saw;
- duplicated code, repeated eager loads and copy-paste in a template — all real, all nits — that
  no written rule names, so "style opinions with no rule behind them are noise" left them out;
- a P2 that bypassed a guarantee of the feature through code outside the diff;
- and three false spec findings out of four, raised without a concrete scenario.

Calling that plugin was not an option: it runs only in Claude Code, asks the person questions and
so breaks an unattended run, reports outside the findings ledger, and changes without us.

## Decision

- **Two axes, one reader each.** The `review` stage (T2's review and T4's independent review) is
  read on two axes by two fresh readers. **Behaviour**: requirements, correctness, how a guarantee
  of the feature is bypassed — every path to the guarded state, code outside the diff included,
  and whether the server trusts what the client sent as proof — contract drift, evidence gaps,
  scope creep. **Standards**: every written rule that applies to the changed files, checked one by
  one, and the baseline of code smells. The architecture review stays one reader.
- **A finding needs a scenario on both axes.** A requirement deviation without the case where the
  behaviour differs from what was written is not a finding; an ambiguous requirement is a
  question for the author, reported and not recorded.
- **Severity keeps its meaning.** A violated ADR, invariant or boundary MUST NOT stays P0 on the
  Standards axis. A code smell is an assessment, never a violation: P3, P2 at most when the reader
  names the change in the task's own code that the smell makes harder; it never blocks.
- **The baseline of smells** (`skills/jig-review/references/code-smells.md`, after Fowler,
  *Refactoring*, chapter 3, in our own words) is checked in every project, in the code the task
  added or changed. A written project rule that allows what a smell would flag suppresses the
  finding, and what a configured linter or formatter checks is skipped.
- **Where the rules are.** Besides `jig context`: `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`,
  `.ai/guidelines/`, linter and formatter configuration. Files git does not track are read from
  the main checkout (`git worktree list --porcelain`), because a task worktree does not have them.
  A personal file (`*.local.md`) may be judged against, but a finding against it goes in the
  report, never in the ledger, which travels to the pull request and the triage task.
- **One after the other.** Behaviour reads first and records its findings; Standards reads second,
  without the first reader's report, records its own and signs the one receipt of the stage. The
  ledger is read, copied and renamed on every `task finding add`, so two readers writing at once
  could lose a finding. External readers (`executor: review`) may run side by side: the coordinator
  enters their findings and writes the receipt already.
- **How many readers.** Two for a first review and for a `full` re-review, at either depth; one,
  both axes in turn, for a `narrow` re-review, whose interdiff is small. `depth: lean` keeps both
  readers: adr-20261002-route-depth-is-a-personal-choice trims a review round, never a reader, and
  this decision does not amend it. `delegate:` lines and T4's other model apply to both readers.
- **No script, gate, receipt or setting changes.** One receipt per stage, as before, so
  `--since-review` is unchanged.

This refines adr-20261015-every-review-is-a-fresh-reader, whose rejected alternative "two
reviewers for T4" was two readers of the same thing; here they read different things, and the
comparison found what one pass did not. Every review is still a fresh reader.

## Alternatives

- **Call the plugin's skill when it is installed.** Rejected for the reasons in Context.
- **Spec and Standards as the plugin splits them.** Rejected: the bypassed guarantee sat between
  requirements and correctness, and all new P1/P2 came from correctness; cutting spec from
  correctness separates what works together.
- **Correctness as a third reader.** Rejected: a third reader per round for findings the Behaviour
  reader already makes together with the requirements.
- **Two readers in parallel, the coordinator entering their findings.** Rejected: the ledger works
  because a finding is entered by somebody other than the author (convention-required-records); in
  an attended run the coordinator is the author.
- **Two readers in parallel, a lock on the ledger.** Deferred: a script change with its own
  Windows semantics and tests, larger than this task. When the ledger takes concurrent writes, the
  order can go.
- **Cap the whole Standards axis at P2/P3.** Rejected: an accepted ADR contradicted silently is a
  blocking finding (adr-20260921-review-findings-block-completion).

## Consequences

- A first review costs a second reader and takes about twice as long by the clock;
  a narrow re-review costs what it did.
- More P3 findings reach the pull request and the triage task `task ship` files.
- Nothing checks which axis a reader took or that two ran; like the fresh reader itself, this is a
  norm of the skills.
- Undoing it: restore the skill and docs text, remove the smells reference and mark this ADR
  superseded; no state or data is involved.
