#!/usr/bin/env bash
# relay/scripts/review-gate.sh — tier-coverage checkpoint gate (id:66d4)
#
# MECHANIZES review.md §3 (id:f032): the rule "a checkpoint must account for every declared
# test tier" was fully specified but per-turn-LLM-trusted, and a reviewer skipped an e2e tier
# with a judgment excuse while the toolchain was installed (chidiai
# `2026-07-18-during-relay-review-loderite-skipped-the`). A filed case does not bind subagents;
# a SCRIPT does — so this refuses the checkpoint mechanically.
#
# Usage:
#   review-gate.sh --repo <dir> --entry <file>
#
#   Enumerates the DECLARED test tiers from <dir>'s manifests, then checks that <file> (the
#   checkpoint-entry text) covers EACH declared tier with EITHER:
#     - a RESULT token line   `<tier>: <result>`   (e.g. `test: 12 passed`), OR
#     - a SKIP line           `SKIPPED-TIER: <tier> — <reason>`
#   Exit 0 = every declared tier accounted for. Nonzero + the offending tier on stderr = refuse.
#
#   TOOLCHAIN-PRESENCE PROBE (the crux, id:66d4 / review.md §3): a `SKIPPED-TIER` claim is
#   REJECTED (nonzero) if the tier's toolchain is in fact PRESENT — a judgment excuse
#   ("doc-only window") must NOT satisfy a skip when the tooling is installed. The probe is
#   scoped to a marker UNDER <dir> (a populated `<dir>/node_modules` for a node/package.json
#   tier) so it stays hermetic — global caches are deliberately NOT consulted.
#
# Manifest sources (a script/target name CONTAINING "test" is a declared tier; tier-name = the
# key/target name verbatim, so `test` and `test:e2e` are distinct tiers):
#   - package.json  `scripts`  keys   (the source the RED spec test_review_gate_tier_coverage.sh
#                                       exercises; toolchain marker = <dir>/node_modules populated)
#   - Makefile / makefile / GNUmakefile  targets  (honors the ROADMAP's multi-source wording;
#                                       shares the node_modules toolchain marker — extend
#                                       `toolchain_present()` for other markers as tiers appear)
#
# SIDE-EFFECT-FREE: reads <dir>'s manifests + <file>, writes only exit status + stderr. No git,
# no filesystem writes. Bound automatically by any subagent that runs it (unlike a filed case).
set -euo pipefail

repo=""
entry=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)  repo="${2:-}"; shift 2 ;;
    --entry) entry="${2:-}"; shift 2 ;;
    *) echo "review-gate.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$repo" ]]  || { echo "review-gate.sh: --repo <dir> required" >&2; exit 2; }
[[ -n "$entry" ]] || { echo "review-gate.sh: --entry <file> required" >&2; exit 2; }
[[ -d "$repo" ]]  || { echo "review-gate.sh: --repo not a directory: $repo" >&2; exit 2; }
[[ -f "$entry" ]] || { echo "review-gate.sh: --entry not a file: $entry" >&2; exit 2; }

REPO="$repo" ENTRY="$entry" python3 - <<'PY'
import json, os, re, sys

repo  = os.environ["REPO"]
entry = os.environ["ENTRY"]

# --- enumerate declared tiers ------------------------------------------------------------
tiers = []            # ordered, de-duplicated
seen  = set()
def add_tier(name):
    if name and name not in seen:
        seen.add(name); tiers.append(name)

# package.json scripts: any script key whose name contains "test"
pkg_path = os.path.join(repo, "package.json")
if os.path.isfile(pkg_path):
    try:
        with open(pkg_path, encoding="utf-8") as fh:
            pkg = json.load(fh)
        for key in (pkg.get("scripts") or {}):
            if "test" in key:
                add_tier(key)
    except (ValueError, OSError) as e:
        print(f"review-gate.sh: cannot parse {pkg_path}: {e}", file=sys.stderr)
        sys.exit(2)

# Makefile targets: any target whose name contains "test"
for mk in ("Makefile", "makefile", "GNUmakefile"):
    mk_path = os.path.join(repo, mk)
    if os.path.isfile(mk_path):
        with open(mk_path, encoding="utf-8") as fh:
            for line in fh:
                m = re.match(r'^([A-Za-z0-9_][A-Za-z0-9_.:%-]*)\s*:(?!=)', line)
                if m and "test" in m.group(1):
                    add_tier(m.group(1))
        break  # first make manifest wins

# --- toolchain-presence probe ------------------------------------------------------------
def toolchain_present(tier):
    """Is the tier's toolchain installed UNDER <repo>? Hermetic: markers live under <repo> only.
    Current marker: a populated node_modules (node/package.json tiers). Extend here for new
    tier toolchains (never consult a global/home cache — it would break hermeticity)."""
    nm = os.path.join(repo, "node_modules")
    if os.path.isdir(nm):
        try:
            if any(os.scandir(nm)):
                return True
        except OSError:
            pass
    return False

# --- read the checkpoint entry -----------------------------------------------------------
with open(entry, encoding="utf-8") as fh:
    lines = [ln.rstrip("\n") for ln in fh]

def has_result(tier):
    # a RESULT token line: "<tier>: ..." — tier followed by a colon then a space, so that a
    # `test:e2e: ...` line does NOT falsely satisfy the bare `test` tier.
    prefix = tier + ": "
    return any(ln.startswith(prefix) for ln in lines)

def has_skip(tier):
    # a SKIP line: "SKIPPED-TIER: <tier> ..." — tier followed by a space (before the em-dash),
    # again so `test:e2e` does not satisfy `test`.
    prefix = "SKIPPED-TIER: " + tier + " "
    return any(ln.startswith(prefix) for ln in lines)

# --- adjudicate --------------------------------------------------------------------------
for tier in tiers:
    if has_result(tier):
        continue                                  # tier reported a result → covered
    if has_skip(tier):
        if toolchain_present(tier):
            print(f"review-gate.sh: REFUSE — tier '{tier}' was SKIPPED-TIER but its toolchain "
                  f"is PRESENT under {repo} (node_modules populated); a skip excuse must not "
                  f"pass when the tooling is installed", file=sys.stderr)
            sys.exit(1)
        continue                                  # genuine skip (toolchain absent) → accepted
    print(f"review-gate.sh: REFUSE — declared tier '{tier}' is not accounted for in the "
          f"checkpoint entry (needs a `{tier}: <result>` line or a "
          f"`SKIPPED-TIER: {tier} — <reason>` line)", file=sys.stderr)
    sys.exit(1)

sys.exit(0)
PY
