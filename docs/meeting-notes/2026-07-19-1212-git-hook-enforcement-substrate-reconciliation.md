# 2026-07-19 — Git-hook enforcement substrate reconciliation (7a05)

**Started:** 2026-07-19 12:12
**Session:** a44f59c6-4299-42c5-9b1c-44af75762b23
**Attendees:** 🏗️ Archie (architect), 😈 Riku (devil's advocate), ✂️ Petra (productivity), ⚙️ Sage (skill/hook mechanics), 🎛️ Orla (orchestration / provenance-gating)
**Topic:** Reconcile the git-hook enforcement substrate — 7a05 against existing ebd0 (install infra + privacy pre-push), 077d (role-boundary/provenance pre-commit), ce10 (PII), 0c86 (executor-no-own-RED).

## Context / grounding
- **7a05 was filed as a fresh "substrate," but the git-hook substrate is already carved across three existing items** — surfaced by reading the ledger in setup (the [[review-me-discipline-16e3-3684]] profile trait / chidiai `scoped-a-core-feature-out` lesson working):
  - **id:ebd0** (HIGH — security): git-hook **install infra** (`core.hooksPath` / wire into `git-lock-push.sh`) + a **pre-push** privacy/leak-diff scan.
  - **id:077d** (INBOUND `routed:d6be` from loderite, deeply designed): a **pre-commit role-boundary/provenance hook** — branch-name-encodes-verdict (`relay/<run>-execute-<id>`) + `RELAY_TIER`, per-role write rules, the line-scoped "may flip only its own id's checkbox" rule, a worked counterexample (id:a78b executor *correctly* deviated) + escape-hatch, and the separate-users tradeoff.
  - **id:ce10** (INBOUND `routed:bce3` from zelegator): a **pre-commit/pre-push PII hook** importing `scan_pii()`, warn→calibrate→block, `# pii-ok` allowlist.
- The `hooks/` dir today holds **only Claude Code hooks** (PostToolUse/Stop — `memory-index-sync.py`, `parallel-edit-detector.py`, `pathspec-drop-guard.py`), **no git hooks**, no tracked `.githooks/`, nothing in the Makefile installs one. The git-hook install infra is **greenfield**.

## Decisions
- **D1 — Reconcile, don't greenfield: 7a05 = the shared git-hook framework + ledger-invariant checks.** A 3-layer architecture: **L0 install infra** (`core.hooksPath` + tracked `hooks/git/` dir + `make install-githooks` + `--no-verify` policy + relay-pipeline-safety validation), **L1 dispatch shell** (`pre-commit`/`pre-merge-commit`/`pre-push` entrypoints calling N independent check scripts), **L2 per-concern checks** (each with an owner). 7a05 owns L0+L1 (the framework) + the ledger-invariant L2 checks that have no other home (formatting/shape/size/cross-ledger). **Out of scope:** re-designing 077d's provenance rules, the privacy/PII regexes (ebd0/ce10).
- **D2 — 7a05 owns the framework.** The re-scoped 7a05 builds L0+L1 and validates the relay-pipeline safety **once** (a false-positive on `md-merge.py --commit`/`ckpt-tag.sh`/integrator `--no-ff`/`git-lock-push.sh` wedges the pool — `git-lock-push.sh` is the natural home for a pool `--no-verify`); ebd0/077d/ce10 register their checks into it. Consolidating *reduces* risk vs four items each re-discovering the pipeline hazard.
- **D3 — Provenance is ONE engine: id:077d.** 7a05's "provenance-of-tick" and 0c86's "executor-no-own-RED provenance detector" are *rules that plug into 077d's branch/tier engine*, not separate mechanisms (two hooks reading the branch would disagree — Riku). Fold 7a05's provenance-of-tick into 077d; re-point 0c86's detector `gated-on:077d`. 077d plugs into the 7a05 framework.
- **D4 (amendment) — semver-bump enforcement = its own `[HARD — meeting]` item (id:d1b2).** Splits: (a) *justification half* — the handoff annotates each ROADMAP item with its loose-0.x bump level (bugfix→patch, else→minor at major 0); an **extension of id:e647** (which already owns reviewer-bumps-at-integrate, landed `6c5f84f`); (b) *enforcement half* — a 7a05-framework pre-commit check that "manifest version changed ⇒ tagged same commit" (bump-and-tag) AND actual-bump ≥ max-annotated-among-closed-items. **No-op on version-less repos (id:8ef3)** — dotclaude-skills has no version by design. Enforce "actual ≥ annotated", never *guess* the level (the level is the handoff's judgment, not a classifier — Riku). Cross-linked 7a05 (framework consumer) + e647.

## Action items
- [ ] Re-scope id:7a05 to the framework + ledger-invariant checks (done in this write-back) <!-- resolved in-session -->
- [ ] Consolidate provenance into id:077d; re-point id:0c86 `gated-on:077d` (done in this write-back) <!-- resolved in-session -->
- [ ] Cross-link id:ebd0 / id:ce10 as framework-consumers (done in this write-back) <!-- resolved in-session -->
- [ ] Semver-bump enforcement + handoff bump-level annotation — `[HARD — meeting]`, x-ref 7a05 + e647 <!-- id:d1b2 -->
