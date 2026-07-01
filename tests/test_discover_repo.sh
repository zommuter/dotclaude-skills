#!/usr/bin/env bash
# roadmap:64b4
# Spec for relay/scripts/discover-repo.sh (id:64b4) — the per-repo COMPOSITION that lets the
# mechanical runner (a0b6) replace the LLM discovery shard. Composes reconcile-repo.sh (side
# effects, id:5987) + classify-repo.sh --emit unit (full unit, id:3d61) and applies the
# discovery ROUTING, emitting {units,surfaced,skipped} for ONE repo.
#
# Contract under test (authored by /relay handoff 2026-07-01):
#   discover-repo.sh --repo <name> --path <abs> [--runid <id>] [--live-claims <csv>]
#                    [--main-branch <name>]  → ONE JSON: {"units":[…≤1…],"surfaced":[…],"skipped":[…]}
#   ROUTING (worked out in scratchpad a0b6-runner-design.md):
#     1. rec = reconcile-repo.sh … ; surfaced += rec.surfaced
#     2. IF rec.surfaced non-empty → return {units:[], surfaced:rec.surfaced, skipped:[]}
#        (reconcile surfaces EXACTLY the don't-work cases: diverged/parked/in-flight — do NOT
#         classify, and NEVER double-surface.)
#     3. ELSE unit = classify-repo.sh --emit unit … ; route by unit.verdict:
#        - "blocked"   → surfaced += {repo, reason}; no unit          (dirty non-lock)
#        - "AMBIGUOUS" → surfaced += {repo, reason: loud}; no unit     (dormant loud hook; NO LLM prompt)
#        - "idle"      → units += unit; skipped += {repo, reason}
#        - else        → units += unit                                (execute/review/hard/handoff/human)
#   SIDE-EFFECT hygiene: only reconcile-repo.sh's bounded git ops mutate; classify is read-only.
#
# reconcile-repo.sh + classify-repo.sh already exist, so this test goes GREEN once
# discover-repo.sh lands. roadmap:64b4 box unticked ⇒ EXPECTED-RED until then.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DR="$ROOT/relay/scripts/discover-repo.sh"
[[ -x "$DR" ]] || { echo "discover-repo.sh not found (RED): $DR"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export RELAY_WORKTREE_BASE="$tmp/wt"
export RELAY_TOML="$tmp/relay.toml"; : > "$RELAY_TOML"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

mkrepo() { local d="$1"; mkdir -p "$d"; git -C "$d" init -q; git -C "$d" config user.email t@e; git -C "$d" config user.name t; git -C "$d" config commit.gpgsign false; }
ncount() { python3 -c 'import sys,json; d=json.load(sys.stdin); print(len(d.get(sys.argv[1],[])))' "$1"; }
uverdict() { python3 -c 'import sys,json; u=json.load(sys.stdin).get("units",[]); print(u[0]["verdict"] if u else "<none>")'; }
surf_reasons() { python3 -c 'import sys,json; print("|".join(s.get("reason","") for s in json.load(sys.stdin).get("surfaced",[])))'; }

# === (1) clean + open [ROUTINE] → exactly 1 execute unit, 0 surfaced, 0 skipped ===========
R1="$tmp/r_exec"; mkrepo "$R1"
printf '# Roadmap\n## Items\n- [ ] [ROUTINE] do it <!-- id:1111 -->\n' > "$R1/ROADMAP.md"
printf '# TODO\n## Current\n' > "$R1/TODO.md"
git -C "$R1" add -A; git -C "$R1" commit -qm init
o1="$("$DR" --repo r_exec --path "$R1" --runid thisrun --live-claims "" --main-branch main)"
[[ "$(printf '%s' "$o1" | ncount units)"    == "1" ]] || fail "(1) expected 1 unit, got $(printf '%s' "$o1" | ncount units): $o1"
[[ "$(printf '%s' "$o1" | uverdict)"        == "execute" ]] || fail "(1) unit verdict != execute: $o1"
[[ "$(printf '%s' "$o1" | ncount surfaced)" == "0" ]] || fail "(1) clean repo must not surface: $o1"
[[ "$(printf '%s' "$o1" | ncount skipped)"  == "0" ]] || fail "(1) execute repo must not be skipped: $o1"
pass "(1) clean + open [ROUTINE] → 1 execute unit, nothing surfaced/skipped"

# === (2) diverged → reconcile surfaces; NO classify, NO double-surface, 0 units ============
origin="$(mktemp -d)"; git -C "$origin" init -q --bare
R2="$tmp/r_div"; mkrepo "$R2"
printf '# Roadmap\n## Items\n- [ ] [ROUTINE] do it <!-- id:2222 -->\n' > "$R2/ROADMAP.md"
printf '# TODO\n## Current\n' > "$R2/TODO.md"
git -C "$R2" add -A; git -C "$R2" commit -qm init
git -C "$R2" remote add origin "$origin"; git -C "$R2" push -q -u origin HEAD:refs/heads/main
c2="$(mktemp -d)"; git clone -q "$origin" "$c2"; git -C "$c2" config user.email t@e; git -C "$c2" config user.name t
echo o > "$c2/fo"; git -C "$c2" add fo; git -C "$c2" commit -qm oside; git -C "$c2" push -q origin HEAD:refs/heads/main
echo l > "$R2/fl"; git -C "$R2" add fl; git -C "$R2" commit -qm lside; git -C "$R2" fetch -q origin
o2="$("$DR" --repo r_div --path "$R2" --runid thisrun --live-claims "" --main-branch main)"
[[ "$(printf '%s' "$o2" | ncount units)"    == "0" ]] || fail "(2) diverged must yield 0 units: $o2"
[[ "$(printf '%s' "$o2" | ncount surfaced)" == "1" ]] || fail "(2) diverged must surface EXACTLY once (no reconcile+classify double): $o2"
printf '%s' "$o2" | surf_reasons | grep -qi diverged || fail "(2) surfaced reason is not the diverged one: $o2"
pass "(2) diverged surfaces exactly once, classify skipped, 0 units"

# === (3) finished/idle → 1 idle unit + 1 skipped ==========================================
R3="$tmp/r_idle"; mkrepo "$R3"
printf '# Roadmap\n## Items\n- [x] [ROUTINE] done <!-- id:3333 -->\n' > "$R3/ROADMAP.md"
printf '# TODO\n## Current\n- [x] done <!-- id:3334 -->\n' > "$R3/TODO.md"
git -C "$R3" add -A; git -C "$R3" commit -qm init; git -C "$R3" tag -a relay-ckpt-20260101-0000 -m ckpt
o3="$("$DR" --repo r_idle --path "$R3" --runid thisrun --live-claims "" --main-branch main)"
[[ "$(printf '%s' "$o3" | ncount units)"   == "1" ]] || fail "(3) idle repo still emits a unit (schema: idle=unit+skipped): $o3"
[[ "$(printf '%s' "$o3" | uverdict)"       == "idle" ]] || fail "(3) unit verdict != idle: $o3"
[[ "$(printf '%s' "$o3" | ncount skipped)" == "1" ]] || fail "(3) idle repo must also appear in skipped: $o3"
pass "(3) finished/idle → 1 idle unit + 1 skipped rollup"

# === (4) dirty non-lock → reconcile silent, classify blocked → surfaced, 0 units ==========
R4="$tmp/r_dirty"; mkrepo "$R4"
printf '# Roadmap\n## Items\n- [ ] [ROUTINE] do it <!-- id:4444 -->\n' > "$R4/ROADMAP.md"
printf '# TODO\n## Current\n' > "$R4/TODO.md"
git -C "$R4" add -A; git -C "$R4" commit -qm init
echo change >> "$R4/ROADMAP.md"   # dirty non-lock
o4="$("$DR" --repo r_dirty --path "$R4" --runid thisrun --live-claims "" --main-branch main)"
[[ "$(printf '%s' "$o4" | ncount units)"    == "0" ]] || fail "(4) dirty non-lock must not dispatch (blocked): $o4"
[[ "$(printf '%s' "$o4" | ncount surfaced)" == "1" ]] || fail "(4) dirty non-lock must surface (blocked): $o4"
pass "(4) dirty non-lock → classify blocked → surfaced, 0 units"

# === (5) uv.lock-only dirty + open routine → reconcile commits lock, classify → 1 unit =====
R5="$tmp/r_lock"; mkrepo "$R5"
printf '# Roadmap\n## Items\n- [ ] [ROUTINE] do it <!-- id:5555 -->\n' > "$R5/ROADMAP.md"
printf '# TODO\n## Current\n' > "$R5/TODO.md"
echo "lock v1" > "$R5/uv.lock"
git -C "$R5" add -A; git -C "$R5" commit -qm init
echo "lock v2" > "$R5/uv.lock"   # dirty: uv.lock only
o5="$("$DR" --repo r_lock --path "$R5" --runid thisrun --live-claims "" --main-branch main)"
[[ -z "$(git -C "$R5" status --porcelain)" ]] || fail "(5) uv.lock-only: tree still dirty (reconcile did not commit): $(git -C "$R5" status --porcelain)"
[[ "$(printf '%s' "$o5" | ncount units)" == "1" ]] || fail "(5) uv.lock-only+routine must classify to 1 unit after relock: $o5"
[[ "$(printf '%s' "$o5" | uverdict)"     == "execute" ]] || fail "(5) unit verdict != execute after lock-commit: $o5"
pass "(5) uv.lock-only dirty → reconcile commits, classify → 1 execute unit"

echo "ALL PASS: discover-repo.sh per-repo composition + routing (id:64b4)"
