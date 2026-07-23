# Changelog

<!-- DERIVED at relay integrate from existing relay state (report.summary + worked ids) by
     relay/scripts/changelog-append.sh (id:b8fa). Newest bucket first; never hand-edit or
     reorder past buckets. This repo is DATE-bucketed and carries NO version (git = version
     SSOT — id:8ef3/D3, meeting docs/meeting-notes/2026-07-17-1541-semver-trigger-and-fleet-changelog.md).
     Semver repos across the fleet are release-bucketed instead, gated on the id:e647 bump.
     Started from now — history is NOT backfilled (per-close tags are unrecoverable). -->

## 2026-07-23

- review: suite 293/0 green; verified 6176/7681/f9cd genuine (no gaming); minted id:ce50 for routed:bdee; routine_open=0 (id:6176,7681,f9cd,ce50)
- handoff: promoted id:ce50 (per-repo filtered inbox scan) + RED spec test_inbox_scan_repo.sh; suite 293/0/1-expected-red (id:ce50)

## 2026-07-20

- relay behaviour: distinct-key meeting↔executor lease (claim.sh WARN-not-refuse, id:0ee1); classifier not-executor-ready 3-class hybrid — @owner-verify exclusion + typed gated-on: via shared id:46f6 engine (blocks only OPEN targets) + SURFACED→handoff, extracted shared lib-typed-edges.sh (id:65f5); user-visible-close bump gate — review.md §5c fail-closed @owner-accepted marker + executor-contract v10 provenance + CLAUDE.md pointer (id:8089); one-unit-per-repo-per-round C2 invariant via round-plan.mjs (id:dc5b, worktree part); inbox-done twin-check anchored on lib-anchored-id.sh (id:3743) (id:0ee1,65f5,8089,dc5b,3743)

## 2026-07-19

- hard: closed ac7f (af48 KEYSTONE) — @wire grammar in hard-lanes.md, classify-repo @wire→actionable_routine_open count, new render-verdict.sh drained render-alias; suite 263/0 (id:ac7f)
- C5 66d4: shipped review-gate.sh tier-coverage checkpoint gate (mechanizes review.md §3), suite 264/0 green (id:66d4)
- C5 78df: shipped consumer-enum.sh spec-completeness listing aid (grep-based artifact-reader enumeration), suite green (id:78df)
- C2-C4: promoted id:798d (unpromoted-scan gated-twin fix) with verified RED spec; triaged 6 phantom/mis-classified promote items to REVIEW_ME (id:798d)
- Fixed unpromoted-scan.sh twin-check end-of-line anchor so auto-GATED ROADMAP items (marker + trailing gate note) are recognized as twins instead of phantom-re-dispatching; id:798d closed, full suite 266/0. (id:798d)
- Verified id:798d (unpromoted-scan gated-twin fix) genuinely green — real red→green, RED spec untouched, suite 266/0; reconciled 5 cross-ledger drift twins (e875/b9b5/ab5c/66d4/78df) (id:798d,e875,b9b5,ab5c,66d4,78df)
- a17a: authored the /relay + /meeting state-machine diagram set (3 Mermaid diagrams) + drift guard-test green; full suite 267/0 (id:a17a)
- handoff (claude-opus-4-8): re-laned id:4a46 [INPUT — decision]→[ROUTINE] (owner-resolved handback-log-completeness gate) + RED spec test_handback_invariant_equality.sh; suite 267/0/1-red (id:4a46)

## 2026-07-18

- Relay integrate now derives a `CHANGELOG.md` entry per close — `changelog-append.sh` folds the integrator's own `report.summary` + worked ids into a date bucket (this repo) or a `## vX.Y.Z` release bucket (semver repos, via `--version`); opt-in per repo, so it never fires where no `CHANGELOG.md` exists (id:b8fa)
- review: 20-commit window since relay-ckpt-20260717-1820 verified green (gaming-scan clean, suite 260/0); ticked shipped id:bbb2; verified e647/b8fa/7d20/fc0f/af5a; routine_open=0 (id:bbb2,e647,b8fa,7d20,fc0f,af5a)
- handoff: promoted 4 ROUTINE items (e875/b9b5/ab5c/eb46) into ROADMAP (8→12 open), 2 red specs, suite 260/0 (id:e875,b9b5,ab5c,eb46)
- Closed id:b9b5 — model-probe.sh grade arm swapped echo for printf so a literal -n/-e/-E/-ne output no longer mismatches; RED spec confirmed red then green; full suite 261/0/1-expected-red. (id:b9b5)
- memory-index.py resolves title:/hook:/description from metadata.* nesting + loud stderr warning (id:e875), full suite 262/0/0 (id:e875)
- Fixed flaky test_resource_claim_pid.sh (id:ab5c) — claim.sh's pid_alive() now retries the jq read 3x before concluding a PID-anchored claim is dead, eliminating the ~50%-flaky false-dead verdict under full-suite process load; full suite green 262/0/0. (id:ab5c)
