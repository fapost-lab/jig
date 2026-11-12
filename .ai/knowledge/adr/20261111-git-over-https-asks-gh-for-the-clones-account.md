---
id: adr-20261111-git-over-https-asks-gh-for-the-clones-account
type: adr
status: accepted
date: 2026-11-11
domains: []
paths:
  - scripts/lib/common.sh
  - tests/gh.t.sh
  - scripts/lib/housekeeping.sh
  - scripts/lib/owntree.sh
summary: Why every network git call on the project's origin goes through jig_git_origin, which over HTTPS to GitHub swaps git's credential helpers for one call for a helper reading the clone's account token from gh's store.
reviewed_at: 2026-11-11
---
# git over HTTPS asks gh for the clone's account, for that call only

## Context

adr-20261110-a-clone-names-its-github-account gave every `gh` call the clone's own account, and
left `git` out: over HTTPS git asks its credential helper, and a helper holds one credential per
host. On a machine with two GitHub accounts the push before the pull request, and every fetch,
went as whichever account the helper held. The helper is not always gh's: on the machine where this
was reproduced it was `osxkeychain`, which answered as the active account just as
`gh auth git-credential` did. `git ls-remote` of a private repository of the second account failed
with "Repository not found" as is, and succeeded with the account named.

## Decision

- **One seam.** `jig_git_origin <git-args>...` (common.sh) is the only way a script runs a network
  `git` call on the project's origin (fetch, push, ls-remote); `tests/gh.t.sh` holds a guard
  against a bare one. It also sets `GIT_TERMINAL_PROMPT=0` and `GIT_SSH_COMMAND`
  (`jig_git_batch_ssh`) itself. Under `jig_net` it replaces itself with git (`exec`), as `jig_gh`
  does with gh, so a cut-off reaches git.
- **When.** Only when the URL git uses for the call (the push URL for a push, with `insteadOf`
  applied) is HTTPS — never plain http, which would carry the token unencrypted — names GitHub
  (`forge: github`, or `auto` and a GitHub name), gh is installed, its host is the one
  `jig_gh_resolve` read, and an account is named: by `github.account` (`config`), among several
  (`detected`), or as the one gh holds (`only`). `only` is remembered, and a second account signed
  in later and made active must not take the push while the pull request still goes as the first.
  With a token in the environment, or no account named, git's own helper answers, as before. SSH
  is decided by the key; nothing is asked of gh for it.
- **How.** Two `-c` options for the call: `credential.<scheme>://<host>.helper=` empties the helper
  list for that host, and a second one adds an inline helper that on `get` runs
  `gh auth token --hostname <host> --user <login>` with every token variable unset and answers
  `username=<login>`, `password=<token>`. It ignores `store` and `erase`, so the person's helper
  neither keeps the other account's token nor loses its own entry after a refusal. Only the host
  and the login are in the helper's text, and only after a check of their characters: the token is
  never an argument, never in git's environment (where a `pre-push` hook would see it), never on
  disk. The helper's `gh auth token` is the one gh call outside `jig_gh` besides the account
  helpers it stands on: it runs in git's process, not in a script.
- **A write refuses, a read warns.** `jig_git_origin_account <who> write|read` names the account in
  the command's own shell before the first call. A refusal of `jig_gh_resolve` stops
  `jig_ship_push` with nothing pushed — at every `agent.git` level, `push` included, which
  `jig_ship_account` does not cover. Fetch, ls-remote and housekeeping's branch deletions warn
  once and go on with git's own helper.
- **Not this seam:** `self-update.sh` and `jig_ls_remote_tags` reach Jig's own repository, and
  `jig pr` chooses its account per pull request (lib/pr.sh).

## Alternatives

- **The token in git's environment, read by the helper.** Simpler, but every child of git sees it —
  hooks and whatever they start.
- **`GH_TOKEN` in git's environment, for gh's helper.** Works only where the helper is gh's.
- **`GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_n` instead of `-c`.** Keeps `git` the program under
  `jig_net` without a wrapper, but needs git 2.31; `-c` works with any git, and neither carries a
  secret.
- **The login in the remote URL.** Writes the repository's configuration and still depends on what
  the helper holds for that login.
- **Leave the one account gh holds to git's helper.** Changes less for one-account people, but the
  remembered `only` outlives a second login: the push would go as the new active account and the
  pull request as the first.
- **Plain http too.** Hands a token to an unencrypted URL.
- **`gh auth switch`.** Changes the machine under other sessions.

## Consequences

- A push or fetch over HTTPS goes as the account the pull request is opened as, whatever the
  helper holds and whichever account gh has active.
- Each such call costs one read of gh's store when git asks for a credential.
- A person with one gh account whose own helper held another GitHub user's credentials now pushes
  as the gh account, the one the pull request is opened as; a token in the environment or an SSH
  origin leaves git as it was.
- `-c` options reach git's hooks through `GIT_CONFIG_PARAMETERS`: a hook's own git call to the same
  host authenticates as the clone's account too. Only the login and host travel, never the token.
- A ship at `agent.git: push`, which asked GitHub nothing before, now names the account over HTTPS
  and stops before its push when it cannot.
- `jig pr fetch` over HTTPS still goes as git's helper answers; its account is chosen per pull
  request (lib/pr.sh) and is not this seam's.
- gh's token must carry the scopes the push needs: `workflow` for a change under
  `.github/workflows` (gh's default login asks for it).
- A GitHub Enterprise host under `forge: auto` is not recognised by name, as for `jig_forge_kind`;
  `forge: github` covers it.
- Every new network `git` call on origin goes through `jig_git_origin`, or the guard test fails.
