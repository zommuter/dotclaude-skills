# 2026-06-01 — Makefile allowlist generator for skill scripts

**Started:** 2026-06-01 12:21
**Session:** 96bcbe4c-486f-488c-a5d8-a79323432b51
**Mode:** Class 2 planning record (no meeting was held — plan-mode output)
**Topic:** Fix recurring permission prompts for `find-todos.sh` and `orphan-scan.sh` by making the Makefile the single source for both symlinks and Bash allowlist entries.

## Context

`/meeting` setup runs `find-todos.sh` and `orphan-scan.sh` at every invocation. Despite a 2026-05-27 fix that added some absolute-path entries, permission prompts recurred on 2026-05-29 during a zkm session. The TODO item captured the symptom ("diagnose missing entries") but two root causes were found:

1. **Incomplete, hand-maintained allowlist matrix.** The path-form × args cross-product (4 path forms × bare + `*`) was filled in ad-hoc. `find-todos.sh` had only 4 of 8 expected entries; `orphan-scan.sh` was missing the absolute symlink forms. A new cwd or invocation shape re-prompted.

2. **Scripts not Makefile-managed.** `meeting_FILES` only listed `SKILL.md format.md personas.md append.sh cost-of.sh`. `find-todos.sh`, `orphan-scan.sh`, `broker-curl.sh`, and `broker.py` were symlinked by hand outside `make install` — no single source owned them.

The user also requested that the Makefile cover *all* Claude-invoked exec scripts across all skills (systemic fix, not just the two scripts) and use auto-merge into `settings.json`.

## Plan

**Design:**
- New `_ALLOW` var per skill listing Claude-directly-invoked scripts (distinct from `_EXEC` which is for chmod).
- New `tools/allowlist.py`: for each `skill/script.sh`, generates 8 entries (4 path forms × bare + `*`); `--mode print` previews, `--mode merge` idempotently merges into `settings.json`.
- Path forms: tilde-dest, abs-dest, tilde-src, abs-src — all derived from `--home`/`--src-dir`/`--dest-dir`; no `/home/tobias` hardcoding.
- `make print-allowlist` (read-only preview) and `make install-allowlist` (auto-merge with `.bak` backup) wired into `make install`.
- `meeting_FILES`/`meeting_EXEC` extended to include the 4 previously-unmanaged scripts.

**Explicit out-of-scope:** no removal of existing hand entries (additive only); `broker.py` gets a symlink but no allowlist entry (not Claude-invoked); no SKILL.md changes.

## Implementation findings

- `make print-allowlist` emitted 64 entries across 8 scripts: 37 new, 27 already present. The `+`/`=` markers confirmed the exact gaps were as diagnosed.
- `make install-allowlist` added 37 entries, created `settings.json.bak`. Second run: "nothing to add" — idempotent confirmed.
- `make install-meeting && make status-meeting`: all 9 files (SKILL.md through broker.py) now show `ok` with correct symlink targets.
- Root cause (b) — symlink drift — is now structurally eliminated: any future script added to `meeting_ALLOW` automatically gets both a Makefile-managed symlink and the full 8-form allowlist entries.

## Decisions

- `_ALLOW` is a separate Makefile var from `_EXEC`; the distinction is "what Claude runs at runtime" vs "what needs executable bit on install." `broker.py` is in `_EXEC` (needs `+x`) but not `_ALLOW` (not Claude-invoked via Bash).
- Generator lives in `tools/allowlist.py` (single source); Makefile passes the paths as positional args — no per-skill logic in the script itself.
- Merge is additive-only (set-union, never removes) to avoid a coverage-regression if a hand-authored specific-arg form (e.g. `append.sh -t * -e *`) is semantically narrower than the new `*` wildcard.
- `make install` now depends on `install-allowlist`; a fresh install on a new machine is self-contained.

## Action items

- [x] Close "Permission prompts on `find-todos.sh` and `orphan-scan.sh` recurring" in `TODO.md` — done in this session.
