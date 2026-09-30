# tests/manifest.t.sh — the .ai/manifest reader/writer (scripts/lib/manifest.sh,
# domains/install, ADR-0003).
#
# A CRLF `.ai/manifest` is not a corner case: it is what a clone made by Git
# for Windows with core.autocrlf=true produces whenever nothing pins the
# manifest to LF (adr-20260930-an-upgrade-is-a-unit-of-work,
# task manifest-survives-a-windows-clone). Every reader here must still find
# the `---` separator and split each body line, the way section.sh already
# tolerates the CR of a CRLF AGENTS.md (ADR-0037) — otherwise the manifest
# reads as empty and every framework file looks either kept or conflicting to
# the command that follows.

_manifest_lib() {
  # shellcheck disable=SC2034 # read by manifest.sh's manifest_file
  JIG_PROJECT="$PWD"
  # shellcheck disable=SC2034 # read by manifest.sh's manifest_file
  JIG_AI_DIR=".ai"
  # shellcheck source=../scripts/lib/manifest.sh
  . "$JIG_HOME/scripts/lib/manifest.sh"
}

# A well-formed manifest, written with the given line ending ('\n' or
# '\r\n') for every line, header and body alike — matching what a checkout
# actually produces: the whole file gets one conversion, not a mix.
_manifest_fixture() {
  local eol="$1" nl=$'\n'
  [ "$eol" = crlf ] && nl=$'\r\n'
  mkdir -p .ai
  {
    printf '# jig manifest. Do not edit by hand.%s' "$nl"
    printf 'jig.version: 1.2.3%s' "$nl"
    printf 'jig.source: /src%s' "$nl"
    printf 'jig.mode: copy%s' "$nl"
    printf 'adapters: [claude]%s' "$nl"
    printf 'instructions.section: sha1 AGENTS.md%s' "$nl"
    printf -- '---%s' "$nl"
    printf 'hash1 .ai/scripts/jig%s' "$nl"
    printf 'hash2 .ai/profiles/generic/profile.yaml%s' "$nl"
  } > .ai/manifest
}

# --- manifest_paths ----------------------------------------------------------

test_manifest_paths_reads_an_lf_manifest() {
  _manifest_lib
  _manifest_fixture lf
  assert_eq "$(printf '.ai/scripts/jig\n.ai/profiles/generic/profile.yaml')" \
    "$(manifest_paths)"
}

test_manifest_paths_reads_a_crlf_manifest() {
  _manifest_lib
  _manifest_fixture crlf
  assert_eq "$(printf '.ai/scripts/jig\n.ai/profiles/generic/profile.yaml')" \
    "$(manifest_paths)"
}

test_manifest_paths_empty_when_the_file_is_missing() {
  _manifest_lib
  assert_eq "" "$(manifest_paths)"
}

# --- manifest_entries --------------------------------------------------------

test_manifest_entries_reads_a_crlf_manifest() {
  _manifest_lib
  _manifest_fixture crlf
  assert_eq "$(printf 'hash1 .ai/scripts/jig\nhash2 .ai/profiles/generic/profile.yaml')" \
    "$(manifest_entries)"
}

# --- manifest_hash_of --------------------------------------------------------

test_manifest_hash_of_reads_a_crlf_manifest() {
  _manifest_lib
  _manifest_fixture crlf
  assert_eq "hash2" "$(manifest_hash_of .ai/profiles/generic/profile.yaml)"
}

test_manifest_hash_of_unknown_path_prints_nothing_on_a_crlf_manifest() {
  _manifest_lib
  _manifest_fixture crlf
  assert_eq "" "$(manifest_hash_of .ai/does/not/exist)"
}

# --- manifest_header_get ------------------------------------------------------

test_manifest_header_get_reads_a_crlf_manifest() {
  _manifest_lib
  _manifest_fixture crlf
  assert_eq "1.2.3" "$(manifest_header_get jig.version)"
  assert_eq "sha1 AGENTS.md" "$(manifest_header_get instructions.section)"
}

test_manifest_header_get_stops_at_the_separator_on_a_crlf_manifest() {
  _manifest_lib
  _manifest_fixture crlf
  # A key that only appears in the body, never above `---`, must not match.
  assert_eq "" "$(manifest_header_get hash1)"
}
