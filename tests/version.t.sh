# tests/version.t.sh — scripts/lib/version.sh: jig_version_lt, the dotted-
# integer compare _upgrade_manual_steps uses to decide which of 0.16.0's
# manual steps still apply (upgrade-carries-its-own-checklist).
# shellcheck shell=bash

_version_lib() {
  # shellcheck source=../scripts/lib/version.sh
  . "$JIG_HOME/scripts/lib/version.sh"
}

test_version_lt_true_on_lower_minor() {
  _version_lib
  jig_version_lt 0.15.1 0.16.0 || fail "0.15.1 should be older than 0.16.0"
}

test_version_lt_false_on_equal() {
  _version_lib
  ! jig_version_lt 0.16.0 0.16.0 || fail "0.16.0 is not older than itself"
}

test_version_lt_false_on_higher() {
  _version_lib
  ! jig_version_lt 0.16.1 0.16.0 || fail "0.16.1 should not be older than 0.16.0"
}

test_version_lt_missing_component_reads_as_zero() {
  _version_lib
  ! jig_version_lt 0.16 0.16.0 || fail "0.16 should equal 0.16.0"
  jig_version_lt 0.15 0.16.0 || fail "0.15 should be older than 0.16.0"
}

test_version_lt_compares_the_higher_component_first() {
  _version_lib
  jig_version_lt 0.9.9 0.16.0 || fail "0.9.9 should be older than 0.16.0 (minor, not lexical, compare)"
  ! jig_version_lt 9.0.0 0.16.0 || fail "9.0.0 should not be older than 0.16.0"
}

test_version_lt_unknown_reads_as_older_than_anything() {
  _version_lib
  jig_version_lt unknown 0.16.0 || fail "an unrecognised value should read as older, not newer (ADR-0017)"
  jig_version_lt "" 0.16.0 || fail "an empty value should read as older"
}
