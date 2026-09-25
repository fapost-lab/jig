---
id: convention-detectors
type: convention
status: active
domains: []
paths:
  - ".github/scripts/**"
  - "tests/ci-*.t.sh"
  - "tests/*-check.t.sh"
  - tests/dispatcher.t.sh
summary: A detector's green is indistinguishable from its blind, so a planted sample it must report ships in the same change as the detector.
---
# Detectors

A detector is a check that reads this repository's own artifacts and is expected to pass:
the pipe guard in `tests/dispatcher.t.sh`, the scope and gate scripts under
`.github/scripts/`, and the tests that drive them.

## Practice

| Rule | Rationale |
|---|---|
| A detector ships with a planted sample it must report, written in the same change. | A detector's green is indistinguishable from its blind. It passes when the repository is clean, and it passes when it can see nothing at all, and no number of runs tells those apart — the full suite answers the same either way. Only a second answer, on input deliberately made dirty, separates them. |
| Widening a detector is shipping one: the case that motivated the widening goes in as a sample too, never as a follow-up task. | In #101 the pipe guard's writer list and its directory list were widened for a pipeline in `.github/scripts/ci-windows-scope.sh`, and the widened guard did not report that pipeline — the scan read one physical line at a time and the pipeline was written across four. It merged green *and it passed review*, because the reader of the diff had nothing to check the claim against either. This hole walks past CI and past the person looking at the change, so the proof cannot wait for a later task. |
| The sample carries what the detector must stay silent about, beside what it must report. | A detector that reports everything is as useless as one that reports nothing, and the exemptions are where the cost sits: eleven places in `scripts/lib/` rely on the pipe guard passing `sed … \| head -n 1`. One fixture holding both shapes makes an over-wide rule fail on the spot. |

## Example

`tests/dispatcher.t.sh` keeps the pipe guard and its samples side by side.
`test_no_script_pipes_into_an_early_quitting_reader` scans the real directories and must
find nothing; `test_pipe_guard_reads_a_pipeline_written_across_lines` plants a pipeline
spread over continuation lines next to a blessed `sed … | head -n 1` and asserts exactly
one hit. The first proves the repository is clean. Only the second proves the guard can
see.

## Rationale

Three defects in the guard were found this way and none of them by a test run: the widened
guard missing its own case (the pre-fix file put back into the tree), a buffered pipeline
dropped at a file boundary (one file against two in a single `awk` call), and a
continuation invented where bash sees none. A run of the full suite would have reported
success for all three.
