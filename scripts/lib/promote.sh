# shellcheck shell=bash
# "Prepare for prod": a task tested on the staging branch reaches a pull
# request into the base branch (adr-20261111-prepare-for-prod-opens-the-promotion-from-git-alone;
# .ai/specs/staging-branch/). Sourced by task.sh for `jig task promote` alone,
# so that every other task command pays for none of it.
#
# It runs from git and the forge alone: a CI runner has the repository and a
# forge token, never a workspace, a queue or `agent.git`. What a workspace
# adds where there is one — the link in `promote_url`, the dependency warning,
# the person's `agent.git` — is never required.
#
# Every refusal comes before the first step that leaves the machine
# (adr-20260925-a-ship-refuses-before-it-sends): the only things sent are a
# push of merges of the base the person or agent already made on the task
# branch, and the pull request.

# _promote_refuse <code> <message> — refuse this task's promotion: nothing was
# pushed and no pull request opened. One seam for every refusal, so that
# promoting several tasks ("Promote from CI") can turn a refusal of one task
# into that task's result rather than the end of the run.
_promote_refuse() {
  jig_fail "$@"
}

# _promote_needs_person <message> — a promotion only a person (or their
# agent) can finish: said on stderr, exit 3 from the command, as `task ship`
# hands over at `agent.git: none`.
_promote_needs_person() {
  printf '%s\n' "$1" >&2
  return 3
}

# _promote_fetch <who> <name>... — refresh origin/<name> for each branch, and
# refuse when one cannot be fetched: unlike jig_fetch_branches, which only
# warns, a promotion judged on a stale origin/<task-branch> would open its
# pull request on the real branch, which may hold a fix nobody tested.
# GIT_TERMINAL_PROMPT=0 and GIT_SSH_COMMAND as every network git call
# (conventions/shell.md).
_promote_fetch() {
  local who="$1" name out
  shift
  git -C "$JIG_PROJECT" remote get-url origin >/dev/null 2>&1 \
    || _promote_refuse failed "$who: this clone has no origin, so nothing can be judged against what was tested"
  for name in "$@"; do
    if ! out=$(GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="$(jig_git_batch_ssh)" \
         jig_net git -C "$JIG_PROJECT" fetch --quiet origin \
         "+refs/heads/$name:refs/remotes/origin/$name" 2>&1); then
      # Origin answered, and has no such branch: nothing there was tested.
      case "$out" in
        *"couldn't find remote ref"*)
          _promote_refuse not-found "$who: origin has no branch $name; what was not pushed was not tested" ;;
      esac
      _promote_refuse failed "$who: could not fetch $name from origin, so it cannot be judged as origin has it now. Nothing was pushed and no pull request opened; fix the fetch and run again.
$out"
    fi
  done
  return 0
}

# _promote_branch_of <id> — the task's branch: `branch` from its state where
# this checkout has one, else the name git.branch_template gives the id —
# what a CI runner, which has no workspace, has to go by.
_promote_branch_of() {
  local id="$1" branch template
  task_state_var branch "$id" branch
  if [ -z "$branch" ]; then
    template=$(cfg git.branch_template "task/{id}")
    case "$template" in
      *'{id}'*) branch=${template%%'{id}'*}$id${template#*'{id}'} ;;
      *) branch="task/$id" ;;
    esac
  fi
  printf '%s\n' "$branch"
}

# _promote_pr_rows <head> <base> <state> — "<url><TAB><title>" of the pull
# requests from <head> into <base> the forge reports in <state> (`open` or
# `all`), newest first; nothing without a forge or when it cannot answer.
_promote_pr_rows() {
  local head="$1" base="$2" state="$3" kind out
  kind=$(jig_forge_kind 2>/dev/null) || return 0
  case "$kind" in
    github)
      jig_net gh pr list --head "$head" --base "$base" --state "$state" --json url,title \
        --jq '.[] | .url + "\t" + .title' 2>/dev/null || true ;;
    gitlab)
      if [ "$state" = all ]; then
        out=$(jig_net glab mr list --source-branch "$head" --target-branch "$base" --all --output json 2>/dev/null) || out=""
      else
        out=$(jig_net glab mr list --source-branch "$head" --target-branch "$base" --output json 2>/dev/null) || out=""
      fi
      printf '%s' "$out" | jig_glab_fields web_url title || true ;;
  esac
  return 0
}

# _promote_open_url <head> <base> — the open pull request from <head> into
# <base>, or nothing.
_promote_open_url() {
  local rows url
  rows=$(_promote_pr_rows "$1" "$2" open)
  url=${rows%%$'\t'*}
  url=${url%%$'\n'*}
  case "$url" in https://*) printf '%s\n' "$url" ;; esac
  return 0
}

# _promote_one <id> <commit> <title> <body-file> — promote one task: the steps
# of design §2 in order. Returns 0 (the pull request is open, or the task is
# in the base already) or 3 (a person is needed); a refusal exits 1 through
# _promote_refuse.
_promote_one() {
  local id="$1" commit_arg="$2" title="$3" body_file="$4"
  local who="task promote" t=$'\t' problems flow base staging dir have_ws=0 branch tbase run level
  _task_valid_id "$id" || _promote_refuse usage "invalid task id: $id"

  # 1. The flow.
  problems=$(jig_git_flow_problems)
  [ -z "$problems" ] || _promote_refuse failed "$who: the project's git flow cannot be read:
$problems
Fix it in .ai/config.yaml (jig doctor names the same) and run again."
  flow=$(jig_git_flow) || flow=""
  base=$(cfg git.base_branch main)
  [ "$flow" = staging ] \
    || _promote_refuse failed "$who: the git flow is ${flow:-direct}, not staging; a task reaches $base by jig task ship"
  staging=$(jig_staging_branch)

  # 2. The task: its branch, and its base where a workspace records one.
  task_dir_v dir "$id"
  [ ! -f "$dir/state" ] || have_ws=1
  branch=$(_promote_branch_of "$id")
  if [ "$have_ws" = 1 ]; then
    tbase=$(jig_task_base "$id")
    [ "$tbase" = "$base" ] \
      || _promote_refuse failed "$who: $id is cut from $tbase, not $base; the staging flow does not apply to it"
  fi

  # 3. Rights: a runner's pipeline is the team's decision; a checkout's is
  # its person's agent.git.
  # Autopilot never promotes, on a runner as in a checkout (decided by the
  # person, 2026-11-11): wherever a workspace says a run is on.
  if [ "$have_ws" = 1 ]; then
    task_state_var run "$id" autopilot
    [ "$run" != on ] \
      || _promote_refuse failed "$who: $id runs on autopilot, which never promotes; stop it, or let the person say prepare for prod"
  fi
  if ! jig_on_ci_runner; then
    level=$(jig_agent_git) || _promote_refuse failed "$who: invalid agent.git: $level (expected none|commit|push|pr|merge)"
    case "$level" in
      pr | merge) ;;
      *)
        _promote_needs_person "$who: agent.git is $level in this clone; opening the pull request into $base is the person's. Nothing was pushed."
        return 3 ;;
    esac
  fi

  # 4. History deep enough to tell what a commit contains.
  if [ "$(git -C "$JIG_PROJECT" rev-parse --is-shallow-repository 2>/dev/null)" = true ]; then
    _promote_refuse shallow-clone "$who: this clone is shallow, so what the tested commit contains cannot be told. Fetch the full history (actions/checkout fetch-depth: 0; GitLab GIT_DEPTH: 0) and run again."
  fi

  # 5. Fresh refs, refused when one cannot be had, and the flow the base
  # branch names.
  _promote_fetch "$who" "$base" "$staging" "$branch"
  _task_ship_flow_agrees "$base" "$flow" "$staging" "$who"

  # 6. The tested commit.
  local stip csha base_ref base_sha
  stip=$(git -C "$JIG_PROJECT" rev-parse --verify --quiet "refs/remotes/origin/$staging^{commit}" 2>/dev/null) || stip=""
  [ -n "$stip" ] || _promote_refuse failed "$who: origin has no $staging branch, so nothing was tested on it"
  if [ -n "$commit_arg" ]; then
    csha=$(git -C "$JIG_PROJECT" rev-parse --verify --quiet "$commit_arg^{commit}" 2>/dev/null) || csha=""
    [ -n "$csha" ] || _promote_refuse not-found "$who: --commit $commit_arg names no commit here; fetch it and run again"
    git -C "$JIG_PROJECT" merge-base --is-ancestor "$csha" "$stip" 2>/dev/null \
      || _promote_refuse failed "$who: $commit_arg is not a commit of origin/$staging; the tested commit is one the staging branch has"
  else
    csha=$stip
  fi
  base_ref=$(jig_base_ref "$base")
  [ -n "$base_ref" ] || _promote_refuse failed "$who: no branch $base here or on origin; fetch it and run again"
  base_sha=$(git -C "$JIG_PROJECT" rev-parse "$base_ref^{commit}")
  printf '%s: tested commit %s of %s\n' "$who" "$(git -C "$JIG_PROJECT" rev-parse --short "$csha")" "$staging"

  # 7. The tip: what the pull request will carry once pushed.
  local lsha osha tip push=0
  lsha=$(git -C "$JIG_PROJECT" rev-parse --verify --quiet "refs/heads/$branch^{commit}" 2>/dev/null) || lsha=""
  osha=$(git -C "$JIG_PROJECT" rev-parse --verify --quiet "refs/remotes/origin/$branch^{commit}" 2>/dev/null) || osha=""
  if [ -z "$lsha" ] && [ -z "$osha" ]; then
    _promote_refuse not-found "$who: no branch $branch here or on origin"
  elif [ -z "$lsha" ] || [ "$lsha" = "$osha" ]; then
    tip=$osha
  elif [ -z "$osha" ]; then
    tip=$lsha
    push=1
  elif git -C "$JIG_PROJECT" merge-base --is-ancestor "$lsha" "$osha" 2>/dev/null; then
    tip=$osha
  elif git -C "$JIG_PROJECT" merge-base --is-ancestor "$osha" "$lsha" 2>/dev/null; then
    tip=$lsha
    push=1
  else
    _promote_refuse branch-diverged "$who: $branch here and on origin have diverged; nothing is forced. Bring them together and run again."
  fi
  if git -C "$JIG_PROJECT" merge-base --is-ancestor "$tip" "$base_sha" 2>/dev/null; then
    printf '%s: %s is already in %s; nothing to promote\n' "$who" "$branch" "$base"
    return 0
  fi

  # 8. Against the tested commit: on it, nothing of its own after it, and no
  # staging merged in (_jig_staging_walk, the walk `jig status` reads).
  local walk state="" own="" line kind sha short url open_url=""
  walk=$(_jig_staging_walk "$csha" "$id$t$branch$t$base$t$tip")
  while IFS="$t" read -r kind _ sha; do
    case "$kind" in
      state) state=$sha ;;
      own) own="$own$sha"$'\n' ;;
    esac
  done <<EOF
$walk
EOF
  short=$(git -C "$JIG_PROJECT" rev-parse --short "$csha")
  # The branch is a clean task branch first (jig_staging_branch_problems):
  # cut from the base, with no staging and no other branch merged in but the
  # clean branch of another task, which goes to the base with this one and is
  # said so (decided by the person, 2026-11-11). Asked before the tested
  # commit is, so staging merged in, newer than that commit, is named for
  # what it is rather than listed as the task's own commits.
  local problems_line bad="" carry_warn="" dkind dval dsha
  problems_line=$(jig_staging_branch_problems "$branch" "$tip" "$base" "$staging")
  while IFS="$t" read -r dkind dval dsha; do
    case "$dkind" in
      bad) bad="$bad
  $dval" ;;
      dep) carry_warn="$carry_warn$id carries $dval (merged at $(git -C "$JIG_PROJECT" rev-parse --short "$dsha")); it reaches $base with this task"$'\n' ;;
    esac
  done <<EOF
$problems_line
EOF
  if [ -n "$bad" ]; then
    _promote_refuse carries-staging "$who: $branch is not a clean task branch: it carries work that $base does not have and that is not its own:$bad
its pull request would take it to $base. Rebuild the branch from $base with its own commits only (a clean branch of another task may be merged in), ship it to $staging again, and run again after the test."
  fi
  if [ -z "$state" ]; then
    _promote_refuse not-on-staging "$who: $branch is not in the tested commit $short of $staging: none of its own commits is there.
It reaches $base only after it was tested on $staging: land it there (jig task ship) and run again after the test."
  fi
  # On the task's first-parent line every commit but a merge of the base is
  # its own work and must be in the tested commit, a merge of a clean
  # dependency included: content made in that merge was never tested
  # otherwise (third architecture review, F11). _jig_staging_walk does not
  # count such a merge, since its other parent is on the tested commit.
  local fpline fc fpp fbase notin
  notin=$(git -C "$JIG_PROJECT" rev-list "$tip" "^$base_sha" "^$csha" 2>/dev/null) || notin=""
  if [ -n "$notin" ]; then
    while IFS= read -r fpline; do
      [ -n "$fpline" ] || continue
      set -f
      # shellcheck disable=SC2086 # the commit and its parents, hexadecimal
      set -- $fpline
      set +f
      fc=$1
      jig_has_line "$fc" "$notin" || continue
      jig_has_line "$fc" "$own" && continue
      if [ $# -gt 2 ]; then
        fbase=1
        shift 2
        for fpp in "$@"; do
          git -C "$JIG_PROJECT" merge-base --is-ancestor "$fpp" "$base_sha" 2>/dev/null || fbase=0
        done
        [ "$fbase" = 0 ] || continue
      fi
      own="$own$fc"$'\n'
      state=behind
    done < <(git -C "$JIG_PROJECT" rev-list --first-parent --parents "$tip" "^$base_sha" 2>/dev/null)
  fi
  if [ "$state" = behind ]; then
    local list="" note=""
    while IFS= read -r sha; do
      [ -n "$sha" ] || continue
      note=""
      if [ "$push" = 1 ] && { [ -z "$osha" ] || ! git -C "$JIG_PROJECT" merge-base --is-ancestor "$sha" "$osha" 2>/dev/null; }; then
        note=" (not pushed)"
      fi
      list="$list
  $(git -C "$JIG_PROJECT" log -1 --format='%h %s' "$sha")$note"
    done <<EOF
$own
EOF
    open_url=$(_promote_open_url "$branch" "$base")
    _promote_refuse behind-staging "$who: $branch has commit(s) of its own that the tested commit $short does not have:$list
A fix made after the test must be tested before it reaches $base: ship it to $staging and run again after the test.${open_url:+
The open pull request $open_url already carries them: it must not be merged before they are tested.
Close it first: it comes from this same branch, so jig task ship refuses while it is open, and every push reaches it. Then ship the fix to $staging, and run jig task promote again after the test.}"
  fi

  # 9. A conflict with the base is found here and resolved by whoever merges
  # the base into the task branch: a script resolves no conflict (ADR-0001).
  local conflicts
  jig_merge_conflicts "$base_sha" "$tip" \
    || _promote_refuse failed "$who: could not try the merge of $branch into $base here"
  conflicts=$JIG_MERGE_CONFLICTS
  if [ -n "$conflicts" ]; then
    open_url=$(_promote_open_url "$branch" "$base")
    [ -z "$open_url" ] || printf 'pr %s (already open)\n' "$open_url"
    _promote_needs_person "$who: $branch conflicts with $base in:
$(printf '%s\n' "$conflicts" | sed 's/^/  /')
Nothing was pushed. Merge $base into the task branch and resolve it in the task's checkout
(git switch $branch && git merge origin/$base), commit, and run jig task promote $id again: it pushes the merge and opens the pull request."
    return 3
  fi

  # 10. Dependencies on the staging branch but not in the base, where this
  # checkout has a queue: a warning, never a refusal.
  local warnings="$carry_warn" dep reason dep_id dep_branch rows="" dline dkind did
  if jig_queue_place "$id"; then
    while IFS="$t" read -r dep reason; do
      case "$dep" in task:*) ;; *) continue ;; esac
      dep_id=${dep#task:}
      _task_valid_id "$dep_id" || continue
      dep_branch=$(_promote_branch_of "$dep_id")
      rows="$rows$dep_id$t$dep_branch$t$base$t${reason:-}"$'\n'
    done <<EOF
$_JIG_QUEUE_DEPS
EOF
  fi
  if [ -n "$rows" ]; then
    local states
    states=$(_jig_staging_walk "$csha" "$(printf '%s' "$rows" | awk -F '\t' '{ print $1 "\t" $2 "\t" $3 }')" \
      | awk -F '\t' '$1 == "state" { print $2 }')
    while IFS="$t" read -r did dep_branch _ reason; do
      [ -n "$did" ] || continue
      jig_has_line "$did" "$states" || continue
      dline=$(jig_base_ref "$dep_branch")
      [ -n "$dline" ] || continue
      if ! git -C "$JIG_PROJECT" merge-base --is-ancestor "$dline" "$base_sha" 2>/dev/null; then
        warnings="$warnings$id depends on $did (queue${reason:+: $reason}), which is on $staging but not in $base; promote $did with this task or before it"$'\n'
      fi
    done <<EOF
$rows
EOF
  fi
  if [ -n "$warnings" ]; then
    while IFS= read -r dline; do
      [ -n "$dline" ] || continue
      printf '%s: warning: %s\n' "$who" "$dline"
    done <<EOF
$warnings
EOF
  fi

  # 11. A raised version makes the promotion a release; its merge is a
  # person's (adr-20261026-a-task-that-raises-the-version-is-a-release).
  local raise r_file r_old r_new r_level release_line=""
  raise=$(jig_release_raise "$base" "$tip")
  if [ -n "$raise" ]; then
    # shellcheck disable=SC2034 # the level is part of the row, not shown here
    IFS="$t" read -r r_file r_old r_new r_level <<EOF
$raise
EOF
    printf "%s: this promotion raises the version in %s: %s -> %s; it is a release, and its merge is a person's\n" \
      "$who" "$r_file" "$r_old" "$r_new"
    release_line="Release: this promotion raises the version in $r_file: $r_old -> $r_new"
  fi

  # 12. Send: the base merges already made on the task branch, then the pull
  # request into the base branch, found by head and base together.
  jig_ship_sends_no_commit "a promotion commits nothing; it pushes only merges of the base already on the branch"
  if [ "$push" = 1 ]; then
    jig_ship_push "$who" "$branch"
  fi
  local staging_rows staging_url="" staging_title="" body
  staging_rows=$(_promote_pr_rows "$branch" "$staging" all)
  if [ -n "$staging_rows" ]; then
    line=${staging_rows%%$'\n'*}
    staging_url=${line%%"$t"*}
    staging_title=${line#*"$t"}
    [ "$staging_title" != "$line" ] || staging_title=""
  fi
  if [ -z "$title" ]; then
    title=$staging_title
    [ -n "$title" ] || title=$(git -C "$JIG_PROJECT" log -1 --no-merges --format=%s "$tip" "^$base_sha" 2>/dev/null)
    [ -n "$title" ] || title="Promote $branch to $base"
  fi
  body=$(mktemp "${TMPDIR:-/tmp}/jig-promote-body.XXXXXX")
  jig_cleanup_add "$body"
  {
    if [ -n "$body_file" ]; then
      cat "$body_file"
    else
      printf 'Promotes %s to %s, tested on %s at %s.\n' "$branch" "$base" "$staging" "$short"
      case "$staging_url" in https://*) printf 'Staging pull request: %s\n' "$staging_url" ;; esac
    fi
    if [ -n "$warnings" ]; then
      printf '\nDepends on\n\n'
      printf '%s' "$warnings" | sed 's/^/- /'
    fi
    if [ -n "$release_line" ] && [ -z "$body_file" ]; then
      printf '\n%s\n' "$release_line"
    fi
  } > "$body"
  jig_ship_pr "$who" "$branch" "$base" "$body" "$title" "$body" 0 1
  url=$JIG_SHIP_URL
  case "$url" in
    https://*) ;;
    *)
      _promote_needs_person "$who: no forge available; open the pull request from $branch into $base by hand"
      return 3 ;;
  esac
  if [ "$have_ws" = 1 ]; then
    _task_rewrite_state "$dir" promote_url "$url"
  fi

  # The merge: who does it is git.promote_merge, a later step
  # (.ai/specs/staging-branch/, "Merge the promotion by the flow").
  local pm
  pm=$(jig_promote_merge) || pm=human
  if [ "$pm" = auto ]; then
    printf "%s: git.promote_merge is auto, which is not built yet; the merge is the person's\n" "$who"
  else
    printf "%s: the merge is the person's (git.promote_merge: %s)\n" "$who" "$pm"
  fi
  return 0
}
