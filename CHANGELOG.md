# Changelog

<!-- DERIVED at relay integrate from existing relay state (report.summary + worked ids) by
     relay/scripts/changelog-append.sh (id:b8fa). Newest bucket first; never hand-edit or
     reorder past buckets. This repo is DATE-bucketed and carries NO version (git = version
     SSOT — id:8ef3/D3, meeting docs/meeting-notes/2026-07-17-1541-semver-trigger-and-fleet-changelog.md).
     Semver repos across the fleet are release-bucketed instead, gated on the id:e647 bump.
     Started from now — history is NOT backfilled (per-close tags are unrecoverable). -->

## 2026-07-18

- Relay integrate now derives a `CHANGELOG.md` entry per close — `changelog-append.sh` folds the integrator's own `report.summary` + worked ids into a date bucket (this repo) or a `## vX.Y.Z` release bucket (semver repos, via `--version`); opt-in per repo, so it never fires where no `CHANGELOG.md` exists (id:b8fa)
