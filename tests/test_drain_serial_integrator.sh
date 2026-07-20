#!/usr/bin/env bash
# roadmap:2062 — one-writer-to-main SERIAL integrator for the drain driver (id:ebbe child,
# meeting 2026-07-19-2035 D5 + D4 merge-time re-enforcement). Executors produce code in
# their OWN worktree branches only; the single driver merges each branch --no-ff SERIALLY
# into main. At merge time the disjoint-path rule is RE-ENFORCED: the next branch's touched
# paths vs everything already merged this round — a non-empty intersection is a HANDBACK
# (no merge attempted, branch left intact), never an auto-resolve. A textual merge conflict
# likewise aborts cleanly (git merge --abort) and hands back. No force flags anywhere.
#
# Interface under test (the spec): relay/scripts/drain-integrate.sh
#   drain-integrate.sh --repo <main-checkout> --branch <br> --merged-so-far <file>
#     exit 0: merged --no-ff; the branch's touched paths were APPENDED to <file>.
#     exit 4: overlap handback — branch touches a path already in <file>; NO merge attempted;
#             overlapping path(s) on stdout.
#     exit 5: conflict handback — merge attempted, conflicted, cleanly aborted; tree clean.
# Hermetic: throwaway git repos under mktemp; no network; no force/reset flags.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INTEG="$SRC_DIR/relay/scripts/drain-integrate.sh"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }

[[ -f "$INTEG" ]] || { echo "FAIL: relay/scripts/drain-integrate.sh does not exist yet (RED spec)"; exit 1; }
[[ -x "$INTEG" ]] || { echo "FAIL: drain-integrate.sh not executable"; exit 1; }

# The integrator must never reach for a force flag (ABSOLUTE relay rule).
if grep -nE -- '--force|reset --hard|checkout --force|branch -D|clean -f' "$INTEG"; then
  bad "drain-integrate.sh contains a forbidden force/destructive git flag (lines above)"
else
  ok "no force/destructive git flags in the integrator"
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"
git -c init.defaultBranch=main init -q "$R"
git -C "$R" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
printf 'alpha v1\n' > "$R/a.txt"
printf 'beta v1\n'  > "$R/b.txt"
git -C "$R" add a.txt b.txt
git -C "$R" -c user.email=t@t -c user.name=t commit -q -m "seed a+b"

# Executor branches (worktree stand-ins): wt1 edits a.txt, wt2 edits b.txt (disjoint),
# wt3 edits a.txt (overlaps wt1), wt4 edits b.txt divergently (textual conflict vs wt2).
git -C "$R" branch wt1
git -C "$R" branch wt2
git -C "$R" branch wt3
git -C "$R" branch wt4
git -C "$R" checkout -q wt1 && printf 'alpha v2\n' > "$R/a.txt" \
  && git -C "$R" -c user.email=t@t -c user.name=t commit -qam "wt1: a"
git -C "$R" checkout -q wt2 && printf 'beta v2\n' > "$R/b.txt" \
  && git -C "$R" -c user.email=t@t -c user.name=t commit -qam "wt2: b"
git -C "$R" checkout -q wt3 && printf 'alpha CONFLICTING\n' > "$R/a.txt" \
  && git -C "$R" -c user.email=t@t -c user.name=t commit -qam "wt3: a again"
git -C "$R" checkout -q wt4 && printf 'beta DIVERGENT\n' > "$R/b.txt" \
  && git -C "$R" -c user.email=t@t -c user.name=t commit -qam "wt4: b divergent"
git -C "$R" checkout -q main
MERGED="$TMP/merged-so-far"; : > "$MERGED"

# --- (a) first disjoint branch merges --no-ff ---------------------------------
if "$INTEG" --repo "$R" --branch wt1 --merged-so-far "$MERGED" >"$TMP/o1" 2>&1; then
  ok "wt1 integrated (exit 0)"
else
  bad "wt1 should integrate cleanly (out: $(cat "$TMP/o1"))"
fi
[[ "$(git -C "$R" rev-list --merges --count HEAD)" == "1" ]] \
  && ok "wt1 landed as a --no-ff merge commit" \
  || bad "expected exactly 1 merge commit after wt1 (got $(git -C "$R" rev-list --merges --count HEAD))"
grep -qx 'a.txt' "$MERGED" \
  && ok "wt1 touched paths appended to merged-so-far" \
  || bad "merged-so-far missing a.txt after wt1 (content: $(cat "$MERGED"))"

# --- (b) second disjoint branch also merges; both changes present -------------
"$INTEG" --repo "$R" --branch wt2 --merged-so-far "$MERGED" >"$TMP/o2" 2>&1 \
  && ok "wt2 integrated serially after wt1" \
  || bad "wt2 (disjoint) should integrate (out: $(cat "$TMP/o2"))"
[[ "$(cat "$R/a.txt")" == "alpha v2" && "$(cat "$R/b.txt")" == "beta v2" ]] \
  && ok "main carries BOTH executors' changes" \
  || bad "main lost a change (a=$(cat "$R/a.txt"), b=$(cat "$R/b.txt"))"

# --- (c) overlap → handback exit 4, NO merge, branch intact -------------------
head_before="$(git -C "$R" rev-parse HEAD)"
if "$INTEG" --repo "$R" --branch wt3 --merged-so-far "$MERGED" >"$TMP/o3" 2>&1; then
  bad "wt3 overlaps a.txt — the merge-time re-enforcement must hand back, not merge"
else
  rc=$?
  [[ $rc -eq 4 ]] && ok "wt3 overlap → exit 4 (handback)" || bad "wt3: expected exit 4, got $rc"
  grep -qF 'a.txt' "$TMP/o3" \
    && ok "overlapping path named in the handback output" \
    || bad "handback output does not name a.txt (out: $(cat "$TMP/o3"))"
fi
[[ "$(git -C "$R" rev-parse HEAD)" == "$head_before" ]] \
  && ok "main unmoved by the overlap handback (no auto-resolve)" \
  || bad "main moved on an overlap handback"
git -C "$R" rev-parse -q --verify wt3 >/dev/null \
  && ok "wt3 branch left intact for the handback" \
  || bad "wt3 branch vanished"

# --- (d) textual conflict → clean abort, exit 5, tree clean -------------------
: > "$MERGED"   # fresh round: overlap pre-check passes, the CONFLICT path is exercised
head_before="$(git -C "$R" rev-parse HEAD)"
if "$INTEG" --repo "$R" --branch wt4 --merged-so-far "$MERGED" >"$TMP/o4" 2>&1; then
  bad "wt4 conflicts with merged wt2 — must hand back, not land"
else
  rc=$?
  [[ $rc -eq 5 ]] && ok "wt4 conflict → exit 5 (handback)" || bad "wt4: expected exit 5, got $rc"
fi
[[ -z "$(git -C "$R" status --porcelain)" ]] \
  && ok "tree clean after conflict abort (git merge --abort ran)" \
  || bad "dirty tree left behind after the conflict handback"
[[ "$(git -C "$R" rev-parse HEAD)" == "$head_before" ]] \
  && ok "main unmoved by the conflict handback" \
  || bad "main moved on a conflict handback"

echo "summary: $pass ok, $fail bad"
[[ "$fail" -eq 0 ]] || exit 1
exit 0
