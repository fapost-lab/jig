# Carrying into a task worktree the state git does not track (adr-20260924-a-worktree-carries-what-git-does-not).
#
# A task worktree is a git checkout, so it holds exactly what git tracks.
# Every project with an install step keeps the rest outside git — vendor/,
# node_modules/, .env — and a worktree without them is a tree whose checks
# cannot run. What is carried is declared, never guessed: a profile declares
# its stack's derived state (`carry` in profile.yaml), a project declares its
# own layout (`worktree.carry`, `worktree.share` in .ai/config.yaml).
#
# Two actions, told apart by the nature of the state and not by the kind of
# file:
#   copy  — derived state, each tree's own: vendor, node_modules, .env
#   share — one source of truth under edit, shared by link: packages
# A copy of a shared package would be a second clone of its repository, and
# edits made through one would diverge from the other in silence.
#
# Sourced by scripts/lib/task.sh, which sources scripts/lib/profiles.sh first.
# Depends on common.sh (jig_info, jig_warn, jig_copy_dir, jig_link_dir) and
# config.sh (cfg_list_lines), both already sourced by the dispatcher.
# bash 3.2 compatible.
# shellcheck shell=bash

# _bootstrap_first_segment <path> — the first component of a relative path.
_bootstrap_first_segment() {
  case "$1" in
    */*) printf '%s\n' "${1%%/*}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# _bootstrap_trim_slash <path> — <path> without trailing slashes. A person
# writing `packages/` is copying .gitignore's own convention for a directory —
# the very convention this design depends on — so the slash is normalised
# away rather than refused.
_bootstrap_trim_slash() {
  local p="$1"
  while :; do
    case "$p" in
      ?*/) p=${p%/} ;;
      *) break ;;
    esac
  done
  printf '%s\n' "$p"
}

# _bootstrap_path_problem <path> — print why <path> may not be carried and
# exit 0; print nothing and exit 1 when it is acceptable. A declaration is
# read from .ai/config.yaml or a profile.yaml, both of which a person edits,
# so every path is checked before anything is created (RULES.md: no
# filesystem path is built from a name that has not been validated first).
# Expects a path already run through _bootstrap_trim_slash.
_bootstrap_path_problem() {
  local p="$1" lower ai
  case "$p" in
    '') printf 'it is empty\n'; return 0 ;;
    /*) printf 'it is absolute\n'; return 0 ;;
  esac
  case "$p" in
    *"$(printf '\t')"* | *' '* | *'
'*) printf 'it holds a space, a tab or a newline\n'; return 0 ;;
  esac
  # The /…/ wrapping makes one pattern catch a leading `../`, a trailing
  # `/..` and a bare `..` alike (jig_check_review_path's idiom).
  case "/$p/" in
    */../* | */./* | *//*) printf 'it is not a plain repository-relative path\n'; return 0 ;;
  esac
  # Compared lowercased, and on every segment rather than only the first: a
  # case-insensitive filesystem — macOS by default, and NTFS — opens
  # `.AI/state` as `.ai/state`, so a case-sensitive test refuses nothing
  # there. km_source_problem lowercases `.git` for the same reason. This is a
  # lexical guard; _bootstrap_dest_ok makes the physical one, because a path
  # can also reach .ai/ through a link rather than through its spelling.
  lower=$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')
  ai=$(printf '%s' "$JIG_AI_DIR" | tr '[:upper:]' '[:lower:]')
  case "/$lower/" in
    */"$ai"/*)
      printf 'it is inside %s/, which a worktree borrows by link and must never copy\n' "$JIG_AI_DIR"
      return 0
      ;;
    */.git/*) printf 'it is inside .git/\n'; return 0 ;;
  esac
  return 1
}

# _bootstrap_dest_ok <tree-root> <dst> — exit 0 when <dst> is a safe place to
# create something: its deepest existing ancestor resolves physically inside
# the worktree, and not inside the worktree's own .ai/.
#
# Checked *before* anything is made, because `mkdir -p` and `cp` follow a
# symlink that is already there: a link at an intermediate component of a
# declared path would otherwise let the carry write outside the worktree
# entirely. The owning checkout's side is checked by _bootstrap_inside; this
# is the same guarantee for the destination.
_bootstrap_dest_ok() {
  local root="$1" probe="$2" dir ai
  while [ ! -e "$probe" ] && [ "$probe" != "/" ] && [ "$probe" != "$root" ]; do
    probe=$(dirname "$probe")
  done
  [ -e "$probe" ] || return 1
  [ -d "$probe" ] || probe=$(dirname "$probe")
  dir=$(cd -P "$probe" 2>/dev/null && pwd -P) || return 1
  case "$dir/" in
    "$root"/* | "$root"/) ;;
    *) return 1 ;;
  esac
  ai=$(cd -P "$root/$JIG_AI_DIR" 2>/dev/null && pwd -P) || return 0
  case "$dir/" in
    "$ai"/* | "$ai"/) return 1 ;;
  esac
  return 0
}

# _bootstrap_discard <tree-root> <dst> — remove what this run just created at
# <dst> after a carry failed partway.
#
# The one deletion this library makes, and RULES.md names it. It is bounded
# four ways: <dst> did not exist when this run reached it — a path already
# present is skipped long before — it was created by this run and by nothing
# else, _bootstrap_dest_ok has already placed it physically inside the task
# worktree, and it is never the worktree root itself.
#
# Leaving the remains instead was considered and rejected: the outer loop
# treats an existing <dst> as already carried, so a half-copied vendor or a
# half-linked mirror would be taken for finished by every later run —
# `jig task bootstrap` included, which is the repair this design relies on.
_bootstrap_discard() {
  local root="$1" dst="$2"
  [ -n "$dst" ] || return 0
  [ "$dst" != "$root" ] || return 0
  _bootstrap_dest_ok "$root" "$dst" || return 0
  rm -rf "$dst" 2>/dev/null || true
  return 0
}

# _bootstrap_join <words> — space-separated words, comma separated for a
# report line. Paths never hold a space (_bootstrap_path_problem refuses one),
# so splitting on whitespace is safe here.
_bootstrap_join() {
  local w out=""
  for w in $1; do
    if [ -z "$out" ]; then out="$w"; else out="$out, $w"; fi
  done
  printf '%s\n' "$out"
}

# _bootstrap_inside <root-physical> <path> — exit 0 when <path>'s own physical
# location lies inside <root-physical>. A lexical check is not enough: a
# symlinked parent directory leads out of the checkout without a single `..`
# in the path (jig_knowledge_read_path's reasoning).
_bootstrap_inside() {
  local root="$1" dir
  dir=$(cd -P "$(dirname "$2")" 2>/dev/null && pwd -P) || return 1
  case "$dir/" in
    "$root"/*) return 0 ;;
    "$root"/) return 0 ;;
  esac
  return 1
}

# _bootstrap_declared — `<source><TAB><action><TAB><path>` for everything this
# project declares, profiles first, then the project's own lists. <source> is
# a profile name or `project`, and is what an install hint is looked up from.
_bootstrap_declared() {
  local name item
  while IFS="$(printf '\t')" read -r name item; do
    [ -n "$item" ] || continue
    printf '%s\tcopy\t%s\n' "$name" "$item"
  done < <(profiles_carry)
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    printf 'project\tcopy\t%s\n' "$item"
  done < <(cfg_list_lines worktree.carry)
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    printf 'project\tshare\t%s\n' "$item"
  done < <(cfg_list_lines worktree.share)
  return 0
}

# _bootstrap_stale <owner> <tree> <verb> — warn for each declared lock file
# that differs between the owning checkout and the worktree. The carried tree
# matches the owner's lock; the worktree's lock came from the task's base. A
# difference means the carried state is of the wrong vintage, not that it is
# broken, so this is a warning and never a refusal.
_bootstrap_stale() {
  local owner="$1" tree="$2" verb="$3" name item
  while IFS="$(printf '\t')" read -r name item; do
    [ -n "$item" ] || continue
    item=$(_bootstrap_trim_slash "$item")
    _bootstrap_path_problem "$item" >/dev/null && continue
    [ -f "$owner/$item" ] || continue
    [ -f "$tree/$item" ] || continue
    cmp -s "$owner/$item" "$tree/$item" && continue
    jig_warn "$verb: $item differs from this checkout's; what was carried may be stale"
  done < <(profiles_lock)
  return 0
}

# _bootstrap_share <src-abs> <dst-abs> — share one declared path into the
# worktree, by link rather than by copy.
#
# A file is linked directly. A directory is *mirrored* — the directory is
# created and each of its entries linked — instead of being linked whole, and
# the reason is git, not taste. A project keeps such a directory out of git
# with a trailing-slash pattern (`packages/`), and git does not apply that
# pattern to a symlink: a linked directory reads as an untracked path, and
# `git worktree remove` without --force then refuses the worktree for the rest
# of its life. Housekeeping would keep the task under `worktree-kept` forever
# and the tree would have to go by hand, which is the cleanup by manual
# discipline ADR-0029 exists to avoid. A real directory matches the pattern
# the project already has, so nothing is asked of the person.
#
# What a mirror costs: a package added to the owning checkout afterwards does
# not appear here by itself. That is close to free — a worktree exists for one
# task, and what the directory held when it was made is what that task needs;
# a package installed later belongs to another task and arrives through the
# base. `jig task bootstrap` brings one in when it is genuinely wanted.
_bootstrap_share() {
  local src="$1" dst="$2" entry base
  if [ ! -d "$src" ]; then
    jig_link_dir "$src" "$dst"
    return $?
  fi
  mkdir -p "$dst" 2>/dev/null || return 1
  for entry in "$src"/* "$src"/.[!.]*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    base=${entry##*/}
    [ -e "$dst/$base" ] || [ -L "$dst/$base" ] || jig_link_dir "$entry" "$dst/$base" || return 1
  done
  return 0
}

# jig_bootstrap_worktree <owner-abs> <tree-abs> <verb> — carry the declared
# state from the owning checkout into the worktree.
#
# Never fatal, and never a rollback. By the time it runs the task is started,
# its branch exists and its workspace is linked; a tree that is missing a
# dependency is not a broken task, and the tree and the branch are exactly
# what is needed to try the carry again (`jig task bootstrap`). Every refusal
# and every skip is reported. Always returns 0.
jig_bootstrap_worktree() {
  local owner="$1" tree="$2" verb="$3"
  local src dst source action path problem started elapsed
  local carried="" shared="" missing="" seen=""
  local owner_root tree_root

  owner_root=$(cd -P "$owner" 2>/dev/null && pwd -P) || return 0
  tree_root=$(cd -P "$tree" 2>/dev/null && pwd -P) || return 0
  [ "$owner_root" != "$tree_root" ] || return 0

  started=$(date +%s 2>/dev/null || printf '0')

  while IFS="$(printf '\t')" read -r source action path; do
    [ -n "$path" ] || continue
    path=$(_bootstrap_trim_slash "$path")

    problem=$(_bootstrap_path_problem "$path") && {
      jig_warn "$verb: refusing to carry $path: $problem"
      continue
    }

    # A path declared twice, or declared both ways, is a configuration
    # mistake worth naming rather than resolving silently.
    case "$seen" in
      *"<$path>"*)
        jig_warn "$verb: $path is declared more than once; carried once"
        continue
        ;;
    esac
    seen="$seen<$path>"

    src="$owner_root/$path"
    dst="$tree_root/$path"

    # git brought it: the worktree's own copy is the right one, always.
    if [ -e "$dst" ] || [ -L "$dst" ]; then
      continue
    fi
    if [ ! -e "$src" ] && [ ! -L "$src" ]; then
      missing="$missing $source:$path"
      continue
    fi
    if [ -L "$src" ]; then
      jig_warn "$verb: refusing to carry $path: it is a link in this checkout"
      continue
    fi
    if ! _bootstrap_inside "$owner_root" "$src"; then
      jig_warn "$verb: refusing to carry $path: it resolves outside this checkout"
      continue
    fi
    if ! _bootstrap_dest_ok "$tree_root" "$dst"; then
      jig_warn "$verb: refusing to carry $path: in the worktree it resolves outside the tree, or into $JIG_AI_DIR/"
      continue
    fi
    if ! mkdir -p "$(dirname "$dst")" 2>/dev/null; then
      jig_warn "$verb: could not make room for $path in the worktree"
      continue
    fi

    # Both branches discard what they made when they fail, and for the same
    # reason: the loop above takes an existing <dst> for already carried, so
    # remains left behind would be mistaken for a finished carry by every
    # later run, `jig task bootstrap` included.
    case "$action" in
      share)
        if _bootstrap_share "$src" "$dst"; then
          shared="$shared $path"
        else
          _bootstrap_discard "$tree_root" "$dst"
          jig_warn "$verb: could not share $path into the worktree"
        fi
        ;;
      *)
        if jig_copy_dir "$src" "$dst"; then
          carried="$carried $path"
        else
          _bootstrap_discard "$tree_root" "$dst"
          jig_warn "$verb: could not carry $path into the worktree"
        fi
        ;;
    esac
  done < <(_bootstrap_declared)

  elapsed=$(( $(date +%s 2>/dev/null || printf '0') - started ))
  [ "$elapsed" -ge 0 ] 2>/dev/null || elapsed=0

  if [ -n "$carried" ]; then
    jig_info "$verb: carried $(_bootstrap_join "$carried") ($_JIG_COPY_KIND, ${elapsed}s)"
  fi
  if [ -n "$shared" ]; then
    jig_info "$verb: shared $(_bootstrap_join "$shared")"
  fi
  _bootstrap_missing_report "$missing" "$verb"
  _bootstrap_stale "$owner_root" "$tree_root" "$verb"
  return 0
}

# _bootstrap_missing_report <list> <verb> — one line per declared path that
# the owning checkout does not have either, naming the profile's install
# command where there is one. Nothing is run: if there is nothing to carry,
# the owning checkout is not installed either, and installing inside the
# worktree is a thing only a human with a toolchain can decide to do.
_bootstrap_missing_report() {
  local entry source path install
  for entry in $1; do
    source="${entry%%:*}"
    path="${entry#*:}"
    install=""
    [ "$source" = project ] || install=$(profiles_install "$source" 2>/dev/null || printf '')
    if [ -n "$install" ]; then
      jig_info "$2: $path is absent in this checkout too, so nothing was carried; run \`$install\` in the worktree"
    elif [ "$source" = project ]; then
      jig_info "$2: $path is absent in this checkout too, so nothing was carried"
    else
      jig_info "$2: $path is absent in this checkout too, so nothing was carried; install this stack's dependencies in the worktree"
    fi
  done
  return 0
}
