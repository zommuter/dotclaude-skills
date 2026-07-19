# Changelog

<!-- DERIVED at relay integrate from existing relay state (report.summary + worked ids) by
     relay/scripts/changelog-append.sh (id:b8fa). Newest bucket first; never hand-edit or
     reorder past buckets. This repo is DATE-bucketed and carries NO version (git = version
     SSOT — id:8ef3/D3, meeting docs/meeting-notes/2026-07-17-1541-semver-trigger-and-fleet-changelog.md).
     Semver repos across the fleet are release-bucketed instead, gated on the id:e647 bump.
     Started from now — history is NOT backfilled (per-close tags are unrecoverable). -->

## 2026-07-19

- hard: closed ac7f (af48 KEYSTONE) — @wire grammar in hard-lanes.md, classify-repo @wire→actionable_routine_open count, new render-verdict.sh drained render-alias; suite 263/0 (id:ac7f)
- C5 66d4: shipped review-gate.sh tier-coverage checkpoint gate (mechanizes review.md §3), suite 264/0 green (id:66d4)
- C5 78df: shipped consumer-enum.sh spec-completeness listing aid (grep-based artifact-reader enumeration), suite green (id:78df)
- C2-C4: promoted id:798d (unpromoted-scan gated-twin fix) with verified RED spec; triaged 6 phantom/mis-classified promote items to REVIEW_ME (id:798d)

## 2026-07-18

- Relay integrate now derives a `CHANGELOG.md` entry per close — `changelog-append.sh` folds the integrator's own `report.summary` + worked ids into a date bucket (this repo) or a `## vX.Y.Z` release bucket (semver repos, via `--version`); opt-in per repo, so it never fires where no `CHANGELOG.md` exists (id:b8fa)
- review: 20-commit window since relay-ckpt-20260717-1820 verified green (gaming-scan clean, suite 260/0); ticked shipped id:bbb2; verified e647/b8fa/7d20/fc0f/af5a; routine_open=0 (id:bbb2,e647,b8fa,7d20,fc0f,af5a)
- handoff: promoted 4 ROUTINE items (e875/b9b5/ab5c/eb46) into ROADMAP (8→12 open), 2 red specs, suite 260/0 (id:e875,b9b5,ab5c,eb46)
- Closed id:b9b5 — model-probe.sh grade arm swapped echo for printf so a literal -n/-e/-E/-ne output no longer mismatches; RED spec confirmed red then green; full suite 261/0/1-expected-red. (id:b9b5)
- memory-index.py resolves title:/hook:/description from metadata.* nesting + loud stderr warning (id:e875), full suite 262/0/0 (id:e875)
- Fixed flaky test_resource_claim_pid.sh (id:ab5c) — claim.sh's pid_alive() now retries the jq read 3x before concluding a PID-anchored claim is dead, eliminating the ~50%-flaky false-dead verdict under full-suite process load; full suite green 262/0/0. (id:ab5c)
