#!/usr/bin/env bash
# routing.sh — routing evals: does every skill description still win its own prompts?
#
# A runtime picks a skill by reading the skill descriptions. Nothing else says
# whether two descriptions now claim the same requests, or whether one became
# too vague to be picked at all. This script scores prompt cases against the
# descriptions and fails when a skill loses a prompt it must win, or wins one
# it must not.
#
# Cases live in tests/routing/<skill>.cases, one per line:
#
#   + <prompt>   the skill must win it: it scores highest, alone, above zero
#   - <prompt>   the skill must not win it: it neither scores highest nor ties
#                for highest with a score above zero
#   # comment    and blank lines are ignored
#
# Every skill needs a case file with at least one `+` and one `-` line, and
# every case file needs a skill.
#
# Scoring is lexical and deterministic (ADR-0001, ADR-0002: no model, no
# network, awk only). Text is lowercased, split on anything but letters and
# digits, stripped of stop words and crudely stemmed. A prompt scores against a
# description the weight of each distinct word the two share; a word's weight
# is N/df — the number of skills over the number of descriptions that use it —
# so a word every description uses decides nothing and a word only one uses
# decides most. Each phrase the description quotes ("review", "is this
# ready") that appears in the prompt adds its words' weight once more:
# a trigger phrase is the strongest signal a description gives. Weights are
# integers (N*1000/df, truncated), so equal sums are exactly equal on every
# awk.
#
# Only the description is scored, never the skill's name: a description the
# runtime would pass over must fail here even when its name says what it does.
#
# Prints one line per case — `ok` or `FAIL`, the skill, the sign, the prompt
# and the scores that decided it — then a summary line.
#
# Exit: 0 every case holds; 1 a case or the coverage failed; 2 bad input
# (usage, a malformed case line, a skill without a description).
#
# Usage: tests/routing.sh [--skills <dir>] [--cases <dir>]
set -eu
set -o pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)

_routing_die() {
  printf 'routing: %s\n' "$*" >&2
  exit 2
}

# _routing_description <SKILL.md> — the frontmatter's description, one line.
_routing_description() {
  awk '
    { sub(/\r$/, "") }
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    NR > 1 && /^description:/ {
      sub(/^description:[ \t]*/, "")
      q = substr($0, 1, 1)
      if (length($0) > 1 && (q == "\"" || q == "'\''") && substr($0, length($0), 1) == q)
        $0 = substr($0, 2, length($0) - 2)
      print
      exit
    }
  ' "$1"
}

# Referenced from the EXIT trap, so global (convention-shell).
_ROUTING_TMP=""

main() {
  local skills_dir="$ROOT/skills" cases_dir="$ROOT/tests/routing"
  local dir name desc file line n plus minus base t cr coverage=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --skills) [ $# -ge 2 ] || _routing_die "--skills requires a value"; skills_dir="$2"; shift 2 ;;
      --cases) [ $# -ge 2 ] || _routing_die "--cases requires a value"; cases_dir="$2"; shift 2 ;;
      *) _routing_die "unknown argument: $1 (usage: tests/routing.sh [--skills <dir>] [--cases <dir>])" ;;
    esac
  done
  [ -d "$skills_dir" ] || _routing_die "no skills directory: $skills_dir"
  [ -d "$cases_dir" ] || _routing_die "no cases directory: $cases_dir"

  _ROUTING_TMP=$(mktemp -d "${TMPDIR:-/tmp}/jig-routing.XXXXXX")
  trap '[ -n "$_ROUTING_TMP" ] && rm -rf "$_ROUTING_TMP"' EXIT
  : > "$_ROUTING_TMP/skills"
  : > "$_ROUTING_TMP/cases"
  : > "$_ROUTING_TMP/coverage"
  t=$(printf '\t')
  cr=$(printf '\r')

  for dir in "$skills_dir"/*/; do
    [ -f "$dir/SKILL.md" ] || continue
    name=$(basename "$dir")
    desc=$(_routing_description "$dir/SKILL.md")
    [ -n "$desc" ] || _routing_die "$dir""SKILL.md: no description in the frontmatter"
    # A tab is the field separator of the file handed to awk.
    desc=${desc//"$t"/ }
    printf '%s\t%s\n' "$name" "$desc" >> "$_ROUTING_TMP/skills"

    file="$cases_dir/$name.cases"
    if [ ! -f "$file" ]; then
      printf 'FAIL %s: no cases (%s)\n' "$name" "$file" >> "$_ROUTING_TMP/coverage"
      continue
    fi
    n=0 plus=0 minus=0
    while IFS= read -r line || [ -n "$line" ]; do
      n=$((n + 1))
      # A tab is the field separator of the file handed to awk.
      line=${line%"$cr"}
      line=${line//"$t"/ }
      case "$line" in
        '#'*) ;;
        "+ "*[![:space:]]*) plus=$((plus + 1)); printf '%s\t+\t%s\n' "$name" "${line#+ }" >> "$_ROUTING_TMP/cases" ;;
        "- "*[![:space:]]*) minus=$((minus + 1)); printf '%s\t-\t%s\n' "$name" "${line#- }" >> "$_ROUTING_TMP/cases" ;;
        *[![:space:]]*)
          _routing_die "$file:$n: expected \"+ <prompt>\", \"- <prompt>\" or \"# comment\": $line"
          ;;
      esac
    done < "$file"
    [ "$plus" -gt 0 ] || printf 'FAIL %s: no "+" case, a prompt it must win (%s)\n' "$name" "$file" >> "$_ROUTING_TMP/coverage"
    [ "$minus" -gt 0 ] || printf 'FAIL %s: no "-" case, a prompt it must not win (%s)\n' "$name" "$file" >> "$_ROUTING_TMP/coverage"
  done
  [ -s "$_ROUTING_TMP/skills" ] || _routing_die "no skills with a SKILL.md in $skills_dir"

  for file in "$cases_dir"/*.cases; do
    [ -f "$file" ] || continue
    base=$(basename "$file" .cases)
    if [ ! -f "$skills_dir/$base/SKILL.md" ]; then
      printf 'FAIL %s: cases for a skill that does not exist (%s)\n' "$base" "$file" >> "$_ROUTING_TMP/coverage"
    fi
  done

  if [ -s "$_ROUTING_TMP/coverage" ]; then
    cat "$_ROUTING_TMP/coverage"
    coverage=1
  fi

  # The cases may contain a tab only as the field separator written above.
  if ! awk -F "$t" -v coverage="$coverage" "$(_routing_awk)" \
    "$_ROUTING_TMP/skills" "$_ROUTING_TMP/cases"; then
    return 1
  fi
}

# The scorer. Reads the skills file (name, description) and then the cases
# file (skill, sign, prompt), both tab-separated.
_routing_awk() {
  cat <<'AWK'
BEGIN {
  split("a an and are as at be been but by can could did do does don for from " \
        "had has have he her his how i if in into is it its just let lets me " \
        "my no not now of on or our please she should so some such than that " \
        "the their them then there these they this those to too up us was we " \
        "were what when where which who will with would you your use user say " \
        "says before after", w, " ")
  for (i in w) STOP[w[i]] = 1
  S = 0; C = 0
}

function stem(x) {
  if (length(x) > 5 && x ~ /ing$/) x = substr(x, 1, length(x) - 3)
  else if (length(x) > 4 && x ~ /ed$/) x = substr(x, 1, length(x) - 2)
  else if (length(x) > 4 && x ~ /es$/) x = substr(x, 1, length(x) - 2)
  else if (length(x) > 3 && x ~ /s$/ && x !~ /ss$/) x = substr(x, 1, length(x) - 1)
  if (length(x) > 3 && x ~ /(bb|dd|gg|ll|mm|nn|pp|rr|tt)$/) x = substr(x, 1, length(x) - 1)
  if (length(x) > 4 && x ~ /e$/) x = substr(x, 1, length(x) - 1)
  return x
}

# words(text, out) — the text's words in order, stemmed, stop words dropped;
# returns how many.
function words(text, out,    parts, n, i, k, x) {
  text = tolower(text)
  gsub(/[^a-z0-9]+/, " ", text)
  n = split(text, parts, " ")
  k = 0
  for (i = 1; i <= n; i++) {
    x = parts[i]
    if (length(x) < 2 || (x in STOP)) continue
    out[++k] = stem(x)
  }
  return k
}

function joined(arr, n,    s, i) {
  s = " "
  for (i = 1; i <= n; i++) s = s arr[i] " "
  return s
}

# Skills: vocabulary and quoted phrases per skill.
FNR == NR {
  S++
  NAME[S] = $1
  n = words($2, ws)
  for (i = 1; i <= n; i++) {
    if (!((S, ws[i]) in HAS)) { HAS[S, ws[i]] = 1; DF[ws[i]]++ }
  }
  rest = $2
  P[S] = 0
  while ((a = index(rest, "\"")) > 0) {
    rest = substr(rest, a + 1)
    b = index(rest, "\"")
    if (b == 0) break
    split("", pw)
    m = words(substr(rest, 1, b - 1), pw)
    rest = substr(rest, b + 1)
    if (m == 0) continue
    P[S]++
    PHRASE[S, P[S]] = joined(pw, m)
    PLEN[S, P[S]] = m
    for (i = 1; i <= m; i++) PWORD[S, P[S], i] = pw[i]
  }
  next
}

# The weight of a word: N*1000/df, an integer.
function weight(x) {
  return (x in DF) ? int(S * 1000 / DF[x]) : 0
}

# Cases: score the prompt against every skill.
{
  C++
  skill = $1; sign = $2; prompt = $3
  split("", pw); split("", seen)
  n = words(prompt, pw)
  line = joined(pw, n)
  best = -1; nbest = 0; own = 0; wi = 0; second = -1; si = 0
  for (s = 1; s <= S; s++) {
    sc = 0
    for (i = 1; i <= n; i++) {
      if ((s, pw[i]) in HAS && !((s, pw[i]) in seen)) { seen[s, pw[i]] = 1; sc += weight(pw[i]) }
    }
    for (p = 1; p <= P[s]; p++) {
      if (index(line, PHRASE[s, p]) > 0) {
        split("", pseen)
        for (i = 1; i <= PLEN[s, p]; i++) {
          x = PWORD[s, p, i]
          if (!(x in pseen)) { pseen[x] = 1; sc += weight(x) }
        }
      }
    }
    SC[s] = sc
    if (NAME[s] == skill) { own = sc; oi = s }
    if (sc > best) { second = best; si = wi; best = sc; wi = s; nbest = 1 }
    else if (sc == best) { nbest++; if (second < sc) { second = sc; si = s } }
    else if (sc > second) { second = sc; si = s }
  }
  if (sign == "+") {
    pass = (own == best && nbest == 1 && best > 0)
    if (best == 0) why = "no skill scores"
    else if (pass && second == 0) why = sprintf("%s %.1f, no other skill scores", skill, own / 1000)
    else if (pass) why = sprintf("%s %.1f over %s %.1f", skill, own / 1000, NAME[si], second / 1000)
    else if (own == best) why = sprintf("%s %.1f ties %s %.1f", skill, own / 1000, NAME[(wi == oi) ? si : wi], best / 1000)
    else why = sprintf("%s %.1f beats %s %.1f", NAME[wi], best / 1000, skill, own / 1000)
  } else {
    pass = !(own > 0 && own == best)
    if (best == 0) why = "no skill scores"
    else if (pass) why = sprintf("%s %.1f, %s %.1f", NAME[wi], best / 1000, skill, own / 1000)
    else if (nbest > 1) why = sprintf("%s %.1f ties for the lead", skill, own / 1000)
    else why = sprintf("%s %.1f wins", skill, own / 1000)
  }
  if (!pass) failed++
  printf "%s %s %s \"%s\"  (%s)\n", (pass ? "ok  " : "FAIL"), skill, sign, prompt, why
}

END {
  printf "\nrouting: %d case(s) over %d skill(s), %d failed%s\n", C, S, failed, \
    (coverage ? "; coverage incomplete (see FAIL lines above)" : "")
  exit (failed > 0 || coverage) ? 1 : 0
}
AWK
}

main "$@"
