# Adopting a project's existing knowledge

Depth: deep — it changes what `jig context` resolves and who owns a project's rules; a mistake
here is a rule that agents silently stop seeing.

## Idea

- 2026-09-10 (only a paraphrase was kept): existing project documents and rules should coexist
  with Jig's structure; `jig-map` is the place to extend; an inventory should distribute the
  existing rules into that structure.
- 2026-09-15: "For teams with documentation, but let's not forget the vibe coders. Ideally we
  would ask whether to move the documentation or link to it. Though we probably don't need to
  ask: if the docs are in the repository, we link to them; if they are the user's local files,
  we move them, and those can be deleted later."
- "We never touch CLAUDE.local.md."
- "We create a new document in Jig's knowledge and put a link to the existing document in the
  frontmatter, or in the body — I don't know which is better — so that the agent reads it."
- "The agent should ignore READMEs, changelogs, API descriptions and guides for people. It cares
  about conventions, ADRs and everything useful for maintaining the code."
- "Ideally there should be a mechanism for a full migration. Even if the user drops Jig later,
  the documentation stays in the project in a structured form."

## Goal and problem

- Who is worse off without this, and how: a team that already keeps its rules in `docs/`, ADRs
  or `CONTRIBUTING.md` and adopts Jig. `jig-map` proposes new documents under `.ai/knowledge/`
  and knows nothing about the existing ones, so the rules either exist twice and drift apart,
  or never reach an agent through `jig context`. A vibe coder's untracked rule files are
  invisible in the same way.
- What is true when the work is done: adopting Jig loses and duplicates no project rule; an
  agent receives each rule through `jig context` wherever it lives; contradictions are shown to
  a human, never settled silently.

## Stress test

The failure modes come from an independent hunt in a clean context (2026-09-15), ranked by
likelihood times cost.

- Hidden assumptions:
  - A linked document is something an agent should read in full — holds only for rule-like
    documents. Hence `jig-map` selects them and a human accepts each link.
  - The source stays where it is — holds only until someone moves or deletes it; a broken link
    must fail loudly, not resolve to nothing.
  - A runtime loads its own instruction file — holds per runtime, not per project: Codex never
    reads `CLAUDE.md`, and Claude Code never reads `.cursorrules`.
  - Accepting a stub approves what agents will read — holds only on the day of acceptance: the
    text lives in the source, and anyone can change it afterwards.
- The main trade-off: two files per linked document — a stub in `.ai/knowledge/` and the source —
  in exchange for never copying a body and never keeping two copies of one rule.
- The weakest point: approval and review are attached to the stub, while everything an agent is
  bound by lives in the source.
- Failure modes — cause, what breaks, the signal that shows it:
  1. **A source edited after acceptance reaches every agent unapproved.** A docs PR, a tech
     writer or consolidation itself changes the source; the ledger only makes it pending, which
     the agent clears itself. ADR-0016's gate is bypassed, and an open-source repository gains a
     prompt-injection path. Signal: none — `proposals: none` stays true.
  2. **Staleness drowns in noise.** People edit sources without stamping stubs they do not know
     exist; convention stubs claim `**`; a squash merge lands days after `reviewed_at`. The report
     stops meaning anything and hides real rot. Signal: the stale count grows with every merge.
  3. **A moved or deleted source stops every task.** `docs/` gets reorganised by people and tools
     that do not know Jig; if the missing source is fatal like `requires`, `jig context` fails for
     tasks the stub would never match, and agents are tempted to reject the stub to proceed.
     Signal: `jig context` failing on a colleague's machine; CI does not run `knowledge check`.
  4. **Whole files blow the context budget.** A long CONTRIBUTING, dozens of ADRs, a style guide
     that is honestly `load: always`: agents acknowledge without reading, and accepting sixty
     stubs becomes "all". Signal: required reading outside `.ai/`; proposals accepted in one batch.
  5. **Consolidation writes into files the team governs.** Accepted ADRs get edited in place;
     new decisions take Jig's numbering beside the team's; `jig knowledge changed` sees only
     `.ai/knowledge/`, so the report omits the real edit. Signal: two ADR-0012s; docs owners asked
     to review agent PRs; `knowledge changed: 0` for a task that edited a source.
  6. **Rules inside READMEs are lost or pulled in whole.** Conventions often sit in a
     `## Development` section of `README.md`. Signal: zero stubs, or a stub whose source is a
     README.
  7. **Vibe coders get almost nothing.** Their only file is a generated `CLAUDE.md`, excluded as
     runtime-loaded, though Codex never loads it; `.cursor/rules/*.mdc` carry frontmatter that
     fails `knowledge check` once moved; reconciliation is handed to a non-developer. Signal: no
     stubs; Codex sessions ignoring rules written in `CLAUDE.md`.
  8. **A move is a copy, and it can commit secrets.** Ignored files are often ignored for a
     reason; a pasted token is missed by a human skimming the file; the original keeps being
     edited because another tool still loads it. Signal: secret-scanning alerts; two similar files.
  9. **A path valid on one machine is missing on another.** Case-insensitive filesystems accept
     `Docs/ADR/…`; non-ASCII names come out of `git ls-files` quoted. Signal: "missing source" on
     one OS only; a stub that is never stale.
  10. **Ids and numbers stop matching the team's.** A team's ADR-3 linked as `type: adr` becomes
      `adr-0041`, and agents cite the wrong decision. Signal: mismatched numbers in agent output.
- Other shapes considered, and why this one:
  - Migrate first (move every rule document into `.ai/knowledge/`, leave a pointer) — the team's
    tools and habits keep writing to the old place, and the move PR breaks docs builds and links.
    Kept as the later "full migration", chosen by the team, never by default.
  - Extra knowledge roots with frontmatter written into the team's files — clashes with
    Docusaurus, MkDocs and Cursor frontmatter that Jig's flat parser cannot read, edits files the
    team owns, and lets a directory decide applicability (ADR-0014).
  - A read-only inventory report alone — nobody acts on a snapshot, and nothing re-runs it.

## Scope and non-goals

- In scope: an inventory of the existing documentation; stub knowledge documents whose
  frontmatter points at a tracked source, proposed by `jig-map` and accepted through
  `jig-accept`; resolving, acknowledging and checking the source through its stub;
  consolidation editing the source; copying untracked rule files into `.ai/knowledge/` after
  a secret check and showing each one whole; reading runtime instruction files for duplicates and
  contradictions and proposing how to reconcile them.
- Not doing now: references to sections of a file; deleting any original; linking an
  instruction file every configured runtime already loads; READMEs, changelogs, API references
  and guides for people; files outside the repository.
- Never: touching `CLAUDE.local.md`.
- Later: a full migration of adopted documents into Jig's structure, which stays useful to the
  project even if it drops Jig — started only by the user, never by adoption itself.

## Decisions

- The shape is stubs linking tracked sources in place, and the first slice is the inventory:
  which documents look like rules, where they duplicate and contradict each other — decided by
  the maintainer on 2026-09-15. The inventory is the first step of `jig-map` when Jig is adopted
  and ends in proposals a human accepts, not in a report nobody acts on. A full migration into
  Jig's structure is recorded for the future and runs only when the user starts it — rejected as
  the default: moving a team's documents without its decision. Rejected: frontmatter written into
  the team's own files.
- A tracked document is linked in place; an untracked or ignored file inside the repository is
  copied into `.ai/knowledge/`. The user is not asked which — rejected: asking for every document.
- The link is a frontmatter field of the stub (for example `source:`), so scripts can resolve
  the source and hash it for acknowledgements — rejected: a link in the body, which no script
  reads and an agent may not follow.
- "The user's local files" are untracked or ignored files inside the repository — rejected:
  files outside it, such as `~/.claude/CLAUDE.md`, which serve every project at once.
  `CLAUDE.local.md` is never touched: it holds one person's preferences, not project rules.
- Only rule-like documents are linked — conventions, ADRs, anything that helps maintain the
  code. `jig-map` selects them and creates the stubs `proposed`; a human accepts them through
  `jig-accept` — rejected: linking every document found.
- A stub lives in `.ai/knowledge/sources/<slug>.md`, typed by its source's content (`adr`,
  `convention`, `feature`), with an id without Jig's ADR number and no `date`; the ADR file-name and
  number checks stay with Jig's own `adr/`. A stub cannot be accepted until phase 2, when
  `jig context` resolves it to its source — decided 2026-09-15 — rejected: a `source` type, which
  loses "this is an ADR"; stubs under `adr/` with Jig's numbers; accepting in phase 1, when an agent
  would get the stub's body instead of the rule.
- A link covers a whole file — rejected for now: sections addressed by heading, which break
  silently when a heading is renamed.
- After adoption the source owns its rules: consolidation edits the source, and the stub keeps
  only metadata — rejected: editing the stub, which would split one rule into two copies.
- A runtime instruction file is not linked when every runtime configured for the project loads
  it, so it is not read twice. `CLAUDE.md` in a project that also runs Codex is linked, unless
  it only points at `AGENTS.md`. Every instruction file is still read for duplicates and
  contradictions with other rules, and the reconciliation is proposed to the user — rejected:
  "its runtime loads it", which is true of one runtime and false of the other.
- An untracked rule file is copied, and called a copy. Before copying, a script looks for
  obvious secrets (token and key patterns) and refuses until the human confirms; the file is
  shown whole; frontmatter of another tool (Cursor `.mdc`) is replaced by Jig's. Afterwards Jig
  says that the original remains and that another tool may keep loading it. Jig never deletes
  the original; that decision is the user's.
- An acknowledgement of a stub records the hash of its source, so a changed source is owed a new
  reading. Acknowledged paths widen from `.ai/knowledge/` to sources declared in `source:`, not to
  any file in the repository — an amendment to ADR-0015. Accepted cost: editing only a stub's
  metadata does not make the document pending again.
- A source that is missing always fails `jig knowledge check`, naming the stub. `jig context`
  fails only when that stub is selected for the task; otherwise the catalog lists it as
  "missing source" — rejected: failing every resolution, which lets someone else's reorganisation
  of `docs/` stop unrelated tasks; skipping it silently; proposing a new link by guessing where
  the file went.
- A stub records the hash of its source when it is accepted and when it is reviewed
  (`source_hash`). A source whose hash differs is changed: `jig status` counts such stubs,
  `jig-accept` shows the diff for re-approval, and `jig knowledge stale` reports them. Agents keep
  reading the current text: a tracked document changes only through a commit the team reviews,
  and ADR-0016's gate exists for an agent's inferences, not for text people wrote and merged.
  Staleness against code under `paths` stays date-based — rejected: stopping resolution until
  re-approval, which would halt agents on every docs pull request; and dates for the source, which
  a squash merge or an unstamped human edit turns into noise.
- A linked team ADR keeps the team's id and number, taken from its file name, not Jig's `NNNN`.
  Consolidation never edits an accepted decision record in place; a new decision follows the
  project's own convention — its ADR directory and numbering — when it has one. `jig knowledge
  changed` reports edits to sources too — rejected: renumbering team ADRs, and a consolidation
  report blind to the file it actually edited.
- Reading stays bounded: a linked team ADR is catalog-only by default and pulled in with `--ids`;
  `load: always` is proposed for a stub only with the source's size shown; `jig-accept` shows the
  size of every source.
- Source paths come from git (`git ls-files -z`) and are checked against the index with exact
  case, so a stub valid on a case-insensitive filesystem is not missing on another, and a
  non-ASCII name is not recorded quoted.

## Open questions

- A full migration into Jig's structure: what it produces, how it splits a mixed document, and
  whether the project keeps it after dropping Jig — the maintainer wants it, later.
- Section references — what makes a reference survive a renamed heading.
- Which untracked files count as rule files, and how private notes are told apart from them.
- Rules that live in sections of READMEs — lost today, pulled in whole by a file link.
- The paused `knowledge-adoption` task: the first item of the roadmap, or abandoned in favour of
  new tasks.

## Assumptions left untested

- An agent can tell rule-like documents from guides for people reliably enough that the human
  review stays short — taken at deep; tested by running the inventory on real repositories.
