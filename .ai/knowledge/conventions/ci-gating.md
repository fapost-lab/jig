---
id: convention-ci-gating
type: convention
status: active
domains: []
paths:
  - ".github/workflows/**"
summary: Why the branch rules require only the ci-ok job, and why a matrix job's name can never be a required check.
reviewed_at: 2026-09-24
---
# CI gating

How this repository's branch rules and its workflow stay compatible. The practice is one
rule, and the rationale is the pull request it cost.

## Practice

| Rule | Rationale |
|---|---|
| The branch rules require exactly one status check, `ci-ok`: a job that needs every other job, runs with `always()`, and fails unless each ended as `success` or `skipped`. A new job joins its `needs` list rather than the branch rule. | A rule listing jobs by hand drifts from the workflow, and the drift is only visible as a merge button that is wrong in one direction or the other. |
| A matrix job's name is never a required check. | `test` is named `${{ matrix.os }}` and `test-windows` `${{ matrix.shard }}/3`. When `scope` skips such a job, GitHub never expands the expression: it reports one skipped check called `matrix.os`, and the contexts `ubuntu-latest` and `macos-latest` are never sent. A rule naming them leaves the pull request at "Expected — waiting for status to be reported" with a green suite behind it and no way to merge — which is what happened to #86, hours after the rule was changed to name them. |
| A skipped job counts as a pass. | Skipping is how `scope` answers that the change needed no run, and how a job says it does not apply to this event. GitHub already reads a skipped required check as successful, so the aggregate must agree with it or the two disagree about the same run. |

## Example

The check that decides it, in `.github/workflows/ci.yml`:

```yaml
  ci-ok:
    needs: [scope, knowledge, test, test-windows, smoke-windows, changelog, epic-pr]
    if: always()
```

Its step reads `${{ join(needs.*.result, ' ') }}` and fails on anything that is neither
`success` nor `skipped`, an empty list included.

## Probing the workflow itself

A change to the workflow's own routing — a new output, a new `if:`, a job that must skip —
cannot be answered locally: nothing on a developer's machine evaluates a GitHub expression.
Waiting for the real suite to answer costs what the suite costs, and on Windows that is
about 25 minutes for a question worth seconds.

The practice is a throwaway branch carrying a trimmed `ci.yml`: the job being changed, plus
stand-in jobs on `ubuntu-latest` that carry the real `if:` expression and do nothing but
`echo`. A decision script is copied to `$RUNNER_TEMP` first, so the job can
`git checkout --detach` a historical commit and ask the script what it would have said about
a change that already happened. Run it with `gh workflow run ci.yml --ref <branch>`, read
which stand-in ran and which skipped, and delete the branch.

Two runs used it: `probe/section-crlf-windows`, which answered a Windows question in 29
seconds instead of 25 minutes, and `probe/windows-scope`, which proved that
`adr-20260924-windows-runs-on-a-pull-request-that-touches-platform-behaviour` routes #93 to
the Windows shards and an ordinary change past them — a minute for the answer, and the same
answer the runner gives for real.

## Rationale

A branch rule lives in GitHub's settings, not in the repository, so nothing tests it and no
review sees it change. Keeping the rule down to one name moves the whole decision into the
workflow, where a change to it is reviewed with the code — and where the reason a merge is
blocked can be read in a log rather than guessed from the settings page.
