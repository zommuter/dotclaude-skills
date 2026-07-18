# Changelog

<!-- DERIVED at relay integrate from existing relay state (report.summary + worked ids) by
     relay/scripts/changelog-append.sh (id:b8fa). Newest bucket first; never hand-edit or
     reorder past buckets. This repo is DATE-bucketed and carries NO version (git = version
     SSOT — id:8ef3/D3, meeting docs/meeting-notes/2026-07-17-1541-semver-trigger-and-fleet-changelog.md).
     Semver repos across the fleet are release-bucketed instead, gated on the id:e647 bump.
     Started from now — history is NOT backfilled (per-close tags are unrecoverable). -->

## 2026-07-18

- Relay integrate now derives a `CHANGELOG.md` entry per close — `changelog-append.sh` folds the integrator's own `report.summary` + worked ids into a date bucket (this repo) or a `## vX.Y.Z` release bucket (semver repos, via `--version`); opt-in per repo, so it never fires where no `CHANGELOG.md` exists (id:b8fa)
- review: 20-commit window since relay-ckpt-20260717-1820 verified green (gaming-scan clean, suite 260/0); ticked shipped id:bbb2; verified e647/b8fa/7d20/fc0f/af5a; routine_open=0 (id:bbb2,e647,b8fa,7d20,fc0f,af5a)
- handoff: promoted 4 ROUTINE items (e875/b9b5/ab5c/eb46) into ROADMAP (8→12 open), 2 red specs, suite 260/0 (id:e875,b9b5,ab5c,eb46)
- Closed id:b9b5 — model-probe.sh grade arm swapped echo for printf so a literal -n/-e/-E/-ne output no longer mismatches; RED spec confirmed red then green; full suite 261/0/1-expected-red. (id:b9b5)
