---
id: adr-20261112-a-promotion-merges-itself-only-where-ci-gates-it
type: adr
status: accepted
date: 2026-11-12
domains:
  - task
paths:
  - scripts/lib/promote.sh
summary: Why git.promote_merge auto switches the forge's auto-merge on only in a checkout at agent.git merge or on a CI runner, only where the base requires a check and with a merge commit, never for a release (a major one a draft), and why a behind-staging refusal switches it off.
---
# A promotion merges itself only where CI gates the base, with a merge commit, and never as a release

## Context

In the staging flow `jig task promote` opens the pull request from a tested task branch into the
base (adr-20261111-prepare-for-prod-opens-the-promotion-from-git-alone). `git.promote_merge` says
who merges it: `human` stops at the link; the spec (`.ai/specs/staging-branch/`, "`promote_merge:
auto` is a merge, deferred") decided `auto` switches on the forge's auto-merge instead of Jig
merging, since the command runs from a CI job or a UI that should not wait for the promotion's CI.

adr-20260922-unattended-runs-ask-nothing-and-merge-on-green-ci rejected `gh pr merge --auto`: with
no required checks the forge merges at once and CI gates nothing. That is true (`gh pr merge
--help`: auto-merge is enabled only "if required checks have not yet passed"), so `auto` needs an
answer to it. A promotion that raises the declared version is a release
(adr-20261026-a-task-that-raises-the-version-is-a-release), and `release.merge`, which guards a
release in a ship, is local-only: a runner never has it.

## Decision

- **`git.promote_merge: auto` switches the forge's auto-merge on; Jig never waits or merges.**
  GitHub: `gh pr merge <url> --auto --merge --match-head-commit <tip>`; GitLab: `glab mr merge
  <iid> --auto-merge --sha <tip> --yes`. The step is `_promote_merge` in `scripts/lib/promote.sh`,
  the last step of one task's promotion, so a run over several tasks switches each one's on its
  own.
- **Who may.** In a checkout, `agent.git: merge`, the same right as any merge; below it the pull
  request opens and auto-merge is not switched on. On a CI runner (`jig_on_ci_runner`) the flow
  alone decides: the team put the token in its pipeline and chose `auto`.
- **Only where CI gates the base.** GitHub: a ruleset or classic branch protection requires a
  status check on the base, the repository allows auto-merge and merge commits. GitLab: the project
  requires a successful pipeline to merge (`only_allow_merge_if_pipeline_succeeds`), merges with a
  merge commit, does not squash by default, and does not count a skipped pipeline as a success
  (`allow_merge_on_skipped_pipeline: false`). What cannot be read is a no. This answers the
  objection of adr-20260922 for this one merge; every other merge stays as that ADR says.
- **Only with a merge commit**: the ancestry by which a task reads as in the base, on staging or
  staging drift is judged survives no squash or rebase.
- **Never for a release.** A promotion that raises the declared version switches nothing on, and an
  auto-merge already on (a configuration changed, a pull request opened before) is switched off.
  Where Jig would otherwise have switched it on, a `major` release opens as a draft whose body
  starts with `Needs a human: major release?`, and an open one found not a draft is made one, as
  `task ship` does at `merge`. Under `human`, or below `merge`, a major release opens as it is: a
  person merges every promotion there anyway.
- **Untested work on the branch switches it off.** Every refusal that means origin's task branch
  is not the commit that was tested — `branch-diverged`, `carries-staging`, `not-on-staging`,
  `behind-staging` — first switches auto-merge off on the open promotion, if it is on, and the
  refusal says so: that pull request carries the untested work and would merge it on green CI
  (`_promote_refuse_untested`). So does a run that finds the open pull request at another head than
  the promoted one. It is the one step a promotion's refusal sends, an exception to
  adr-20260925-a-ship-refuses-before-it-sends that only removes a merge.
- **The outcome is a line, never an exit code.** Every outcome of the step exits 0, since the pull
  request is open: `auto-merge on <url>: …`, `auto-merge on <url> (already on)`, `merged <url>`
  (its checks had already passed), `auto-merge not switched on: <why>; the merge is the person's`,
  `auto-merge switched off on <url>: <why>`; under `human` the line is as before.
- **Nothing is written.** Whether auto-merge is on is asked of the forge on every run (ADR-0005).

## Alternatives

- **Jig waits for CI and merges (`jig_ship_merge`).** A CI job or a person's session would hold for
  up to `agent.ci_timeout`; the spec chose a deferred merge.
- **`--auto` with no check of required checks.** The forge merges at once, and CI gates nothing.
- **GraphQL `enablePullRequestAutoMerge` instead of gh**, which fails on a pull request that could
  merge now instead of merging it. Merging at once when the required checks already passed is a
  merge on green CI; a second code path buys nothing.
- **Any merge method, as a ship into the base.** A squashed promotion reads as not in the base.
- **`release.merge` for a promotion.** Local-only: a runner never has it, and a guard that exists in
  one place only is none.
- **A non-zero exit when auto-merge is not switched on.** A pipeline that opened its pull request
  would go red for a setting.
- **Only saying, in the `behind-staging` refusal, that auto-merge is on.** The untested fix would
  merge on green CI while the person reads.

## Consequences

- A team on `auto` gets each tested task into the base on green CI with no person, as long as the
  base requires a check; without one Jig says so and the person merges.
- On GitHub Actions the token must not be `GITHUB_TOKEN`: a pull request it opens starts no
  workflow, so required checks never report, and a merge it makes starts no push workflow on the
  base. The documentation says to use a personal or GitHub App token.
- A push to the task branch by hand after auto-merge is on still reaches the base on green CI; Jig
  sees it only at the next `jig task promote`, which refuses and switches it off.
- Right after the push the forge may still report the old head, or not yet confirm auto-merge: the
  command then says it was not switched on, and running it again settles it.
- GitLab's auto-merge is built from glab's documented flags and not tried on a real project.
