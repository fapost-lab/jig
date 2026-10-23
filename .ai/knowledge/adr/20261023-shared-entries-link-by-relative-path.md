---
id: adr-20261023-shared-entries-link-by-relative-path
type: adr
status: accepted
date: 2026-10-23
domains:
  - task
  - install
paths:
  - scripts/lib/bootstrap.sh
summary: Why a shared directory's mirror links each entry by a relative symlink target counted on physical paths from the mirror's final place, so it resolves in a container mounting the common parent; junctions stay absolute.
---
# A shared entry's symlink holds a relative target

## Context

`worktree.share` (adr-20261002-a-worktree-shares-a-directory-by-mirroring-it) gives a task
worktree a mirror of a directory: a real directory whose every entry links to the owning
checkout's entry of the same name. That decision said "Link targets are absolute".

An absolute target holds the host's spelling of the path. Projects whose checks run in a container
see the same files under another one: devilbox mounts `~/Projects/php` as `/shared/httpd`, Sail and
docker compose mount the project directory under `/var/www/html` or `/app`. In the container
`/Users/...` does not exist, so every link of the mirror leads nowhere and the tests there cannot
find the packages, while the same tests pass on the host. Jig itself points checks into such
containers (`run.exec`), so this is the setting `share` meets, not an edge of it. Found on
fapost-core on 2026-10-23, where agents had linked `packages` by hand instead, and miscounted.

## Decision

**Where the mirror's link is a symlink, its target is relative: the path from the mirror's final
place in the worktree to the owner's entry.** It resolves wherever the two checkouts are seen under
a common parent — on the host, and in a container that mounts that parent.

- **Counted from where the link will be read, on physical paths.** The mirror is built in staging
  and renamed into place; the rename keeps a link's text, so the target is counted from the
  destination, never from staging. Both sides are resolved with `cd -P`/`pwd -P` first: the roots
  come from git and are physical, but the shared path may pass through a link the project tracks
  (`lib -> src/lib`, sharing `lib/packages`), and counting through its spelling miscounts the `../`.
- **A junction keeps an absolute target, and so does a symlink under Git Bash.** An NTFS junction
  has no relative form (ADR-0037). MSYS makes a native symlink only to a target that exists, and the
  relative target, counted from the destination, dangles while the link sits in staging at another
  depth. Containers on Windows are not what this decision serves, so Windows keeps the mirror as it
  was rather than changing how it is built.
- **The top-up links new entries the same way.** Nothing already in a mirror is replaced, as
  before, so a mirror made earlier keeps its absolute links until its worktree is made anew.
- The path arithmetic is `jig_relpath_from` in `common.sh`, moved there from `init.sh`, whose link
  mode already places relative symlinks with it.

## Alternatives

- **Absolute targets rewritten for the container**, from `run.exec` or the mounts. Jig would have to
  know every runtime's mount points, and the links would then be broken on the host instead.
- **Relative only when a container is detected.** Two kinds of mirror for one setting, and the one a
  machine got would depend on whether Docker was running when the worktree was made.
- **Rewriting existing absolute links at the top-up.** It replaces an entry already in the mirror,
  which the mirror's contract never does; worktrees live days, and a new one gets the new links.

## Consequences

- A container that mounts the common parent of the checkout and its worktree root sees working
  links; one that mounts only the checkout never saw the worktree at all, so nothing is lost there.
- Moving the common parent keeps the links working, where absolute ones broke. Moving one
  worktree alone (`git worktree move`) now breaks them, where absolute ones survived; Jig never moves
  a worktree, and `git.worktree_root` applies to new ones only.
- Removing a link never touches its target, whatever the target's form: the guarantees of
  adr-20261002-a-worktree-shares-a-directory-by-mirroring-it about removal are unchanged.
- Tests: a mirror's links are relative and survive moving the common parent; a worktree root
  reached through a link and a shared path through a tracked link both resolve.
