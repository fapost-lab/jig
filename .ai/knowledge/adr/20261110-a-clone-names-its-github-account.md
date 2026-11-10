---
id: adr-20261110-a-clone-names-its-github-account
type: adr
status: accepted
date: 2026-11-10
domains: []
paths:
  - scripts/lib/gh.sh
  - tests/gh.t.sh
  - scripts/lib/common.sh
  - scripts/lib/owntree.sh
summary: "Why every gh call about the project's repository goes through jig_gh with the clone's own account token: github.account, else the one account that may push; gh auth switch is never run."
reviewed_at: 2026-11-10
---
# A clone names its GitHub account, and gh is run with that account's token

## Context

`gh` holds several accounts per host and answers as the active one, which is a setting of the whole
machine. A person who works in several projects under different accounts met it at the end of every
task: `jig task ship` committed and pushed (the remote was SSH, so the key decided), then
`gh pr create` failed as the other account, and the agent stopped to ask for `gh auth switch`. It
was right not to switch: other sessions on the machine were working under the active account. The
quieter failures were worse — housekeeping and `jig upgrade --land` read pull requests as an account
that sees none, and reported nothing merged.

`jig pr` already solved the same problem for one command
(adr-20261109-a-review-is-posted-as-it-was-shown): the account's own token, for one call.

## Decision

- **One seam.** `jig_gh` (common.sh) is the only way a script runs `gh` about the project's
  repository; `tests/gh.t.sh` holds a guard against a bare call. `jig pr` keeps its own choice of
  account, made per pull request, and shares the helpers (`jig_gh_accounts`,
  `jig_gh_stored_token`, `jig_gh_dotcom_kind`, `jig_gh_token_env`).
- **The token is for one call.** In a subshell every token variable is unset and the host's own
  (`GH_TOKEN` for github.com and `*.ghe.com`, `GH_ENTERPRISE_TOKEN` for a GitHub Enterprise Server)
  is set to the account's stored token (`gh auth token --user`, gh 2.40 and later). Never an
  argument, never on disk, never printed: the token is read from gh's store directly, not through
  `jig_net`, which keeps a call's output in a file while it waits. Under `jig_net`, gh replaces
  the background job (`exec`), so the kill that cuts a silent call off reaches gh itself.
  `gh auth switch` is never run and gh's configuration is
  never written — by a script or by an agent (`templates/AGENTS.md`).
- **The account is the first of these that answers** (`jig_gh_resolve`):
  1. a token in the environment — gh is run as it is, so CI and a person's own shell stay in charge;
  2. `github.account`, a local-only key: a login is one person's. When gh gives no token for it,
     the command refuses and names the key and the accounts gh holds; it never falls back to the
     active account, which is the failure the key exists to end;
  3. the account remembered for this origin in the main checkout's `.ai/runtime/gh-account`
     (`<origin url><TAB><login><TAB><how>`, never a token; one per clone, so a task worktree
     finds it known), while gh still gives its token;
  4. the one account gh holds;
  5. of several, the only one that may push to the origin repository (`permissions.push`,
     `maintain` or `admin` of `repos/<owner>/<repo>`, read with each account's own token), or the
     active one when several may. Several that may, with the active one not among them, is a
     refusal that names `jig config set --local github.account <login>`. None that may — a fork's
     upstream, a public repository — leaves gh to its own choice and remembers nothing.
- **A write refuses, a read warns.** `jig task ship`, `jig spec ship`, `jig upgrade` and a write
  shipped from Jig's own tree (`owntree.sh`) at `pr` or
  `merge` name the account before their push (`jig_ship_account`), so a refusal leaves nothing
  sent (adr-20260925-a-ship-refuses-before-it-sends) — after the commit, because a ship that
  refuses for a reason of its own (an index that leaves work out, an empty branch) must not have
  asked the forge anything; a merge,
  `jig upgrade --land` and `jig gh` die on one too (`jig_gh_require`). Housekeeping and a pull
  request's state warn and ask as gh's active account (`jig_gh_prepare`), because a cleanup must
  not stop for it.
- **`jig gh <args>...`** is gh under the same account, with gh's output and exit status, for the
  calls an agent makes itself (`gh pr checks`, `gh pr view`). The "Jig first" table names it.
- **`jig status`** prints `github.account: <login> (found: …)` only when Jig chose among several
  accounts and no key is set, read from the remembered answer and never by asking gh. A named
  account is on the `config.local:` line already, and the one account gh holds needs no line.

## Alternatives

- **`gh auth switch` before each call.** Changes the machine: two sessions in two projects switch
  the account under each other mid-command.
- **Export the token into Jig's whole process.** One line instead of a seam, but every child
  inherits it — the project's own checks under `jig verify` included — and `jig pr` would take it
  for a token the person put in the environment and stop proposing an account.
- **`jig env` printing `export GH_TOKEN=…`** for the agent to `eval`. The token lands in a command's
  output and in the transcript.
- **The key alone, no detection.** One state file fewer, but every person with two accounts must
  fill something in before anything works, against the rule that Jig asks for no setting it can find.
- **A project `.envrc`.** Works where direnv is installed and the agent's shell loads it; not on
  Windows, not in a shell without the hook. It still works: a token in the environment wins.
- **Check the remembered account against gh's account list on every run.** `gh auth status` asks
  the network; the memo exists so that a run costs one keyring read.

## Consequences

- A person with two accounts sets nothing when one of them may push; the agent no longer stops at
  the pull request.
- The remembered answer is not re-examined while gh still gives that account's token: a clone
  whose rightful account changes — a second account signed in later, where the first was the only
  one — keeps the old one until `github.account` is set or `.ai/runtime/gh-account` is removed.
  `jig status` shows a choice made among several so that it can be seen.
- A refusal, and "no account may push", are not remembered: a command that asks GitHub from
  several subshells without naming the account first repeats the lookup. The ship, land and
  housekeeping entry points name it once, in their own shell.
- "May push" is the test of membership, so a clone of a fork picks the account that owns the fork;
  a pull request into an upstream that account cannot push to is still opened as it.
- `git` over HTTPS through gh's credential helper still answers as the active account: fetch and
  push are not covered here. SSH remotes are decided by the key and are not Jig's to choose.
- GitLab (`glab`) is unchanged; the key's name leaves room for a `gitlab.account`.
- A gh older than 2.40 gives no token per account: with the key set that is a refusal that says
  so; without it, gh runs as it did before.
- Every new `gh` call in `scripts/` goes through `jig_gh`, or the guard test fails.
