#!/usr/bin/env bash
# roadmap:9ef7 — old-vocab lane-tag ratchet pre-commit hook.
#
# Spec (TODO id:9ef7, owner chose HARD-DENY): hooks/pre-commit-lane-vocab.sh is a git
# pre-commit hook that BLOCKS a commit whose `git diff --cached` ADDED lines introduce an
# old-vocab lane tag (`[HARD — pool|meeting|hands|decision gate]`) — exit nonzero naming the
# new-vocab replacement. Existing old-vocab tags (context / unchanged lines) WARN only
# (grandfathered). New-vocab tags never fire. `git commit --no-verify` is the escape hatch.
#
# Requirements pinned here:
#   - ADDED-lines-only filter (a pre-existing old-vocab tag not in this diff never blocks).
#   - New-vocab replacement is named on stderr (lane-convert.sh mapping: pool→[HARD]).
#   - Tag-vs-prose classification reuses the id:4da4-anchored parser (NOT a fresh grep):
#     a backtick-quoted lane mention in an added PROSE line must NOT block (id:0d58 class).
#   - Self-gated to relay-onboarded repos via lib-own-repos.sh (honors `# path:`); a repo
#     ABSENT from the relay own-set is a no-op (so the global core.hooksPath install does not
#     fire in every throwaway repo). Env: LANE_VOCAB_RELAY_TOML / LANE_VOCAB_ALL_REPOS.
#   - `make install-lane-ratchet` target exists (global install, like the privacy gate).
#
# Hermetic: throwaway git repo under mktemp, fixture relay.toml, no ~/.claude, no network.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$SRC_DIR/hooks/pre-commit-lane-vocab.sh"

pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }

[[ -f "$HOOK" ]] || { echo "FAIL: pre-commit-lane-vocab.sh not found at $HOOK"; exit 1; }
[[ -x "$HOOK" ]] || bad "9ef7: hook is not executable (chmod +x)"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@example.com
git -C "$REPO" config user.name tester
printf 'clean base line\n' > "$REPO/ROADMAP.md"
git -C "$REPO" add ROADMAP.md
git -C "$REPO" commit -q -m base

# fixture relay.toml marking $REPO as an own (relay-onboarded) repo, so the hook fires.
RELAYTOML="$TMP/relay.toml"
printf '[repos.testfix]\nclassification = "own"\npath = "%s"\n' "$REPO" > "$RELAYTOML"
export LANE_VOCAB_RELAY_TOML="$RELAYTOML"

# stage <content> into ROADMAP.md, run the hook from inside the repo, echo rc; capture out.
stage_and_run() { # <content>
  printf '%s' "$1" > "$REPO/ROADMAP.md"
  git -C "$REPO" add ROADMAP.md
  ( cd "$REPO" && bash "$HOOK" ) 2>&1
}
run_rc() { # <content>
  printf '%s' "$1" > "$REPO/ROADMAP.md"
  git -C "$REPO" add ROADMAP.md
  ( cd "$REPO" && bash "$HOOK" >/dev/null 2>&1; echo $? )
}

# ── (1) ADDED line with a real old-vocab head tag → BLOCK (nonzero) + name replacement ──
BODY_OLD=$'clean base line\n- [ ] [HARD — pool] do the thing <!-- id:aaaa -->\n'
out="$(stage_and_run "$BODY_OLD")"
rc="$(run_rc "$BODY_OLD")"
[[ "$rc" -ne 0 ]] && ok "9ef7: added old-vocab [HARD — pool] blocks the commit (rc=$rc)" \
                  || bad "9ef7: added old-vocab tag did NOT block (rc=$rc)"
grep -qF '[HARD]' <<<"$out" \
  && ok "9ef7: refusal names the new-vocab replacement ([HARD — pool]→[HARD])" \
  || bad "9ef7: refusal did not name the replacement. Output: $out"

# ── (2) ADDED line with new-vocab [HARD] → allow (exit 0) ──
BODY_NEW=$'clean base line\n- [ ] [HARD] do the thing <!-- id:bbbb -->\n'
rc="$(run_rc "$BODY_NEW")"
[[ "$rc" -eq 0 ]] && ok "9ef7: added new-vocab [HARD] is allowed (exit 0)" \
                  || bad "9ef7: new-vocab [HARD] was blocked (rc=$rc)"

# ── (3) old-vocab present only in a CONTEXT (pre-existing, unchanged) line → allow ──
# commit an item carrying old-vocab, then stage an UNRELATED clean addition. The old-vocab
# tag is not in the diff's ADDED lines, so it must be grandfathered (warn-only, exit 0).
printf 'clean base line\n- [ ] [HARD — meeting] legacy item <!-- id:cccc -->\n' > "$REPO/ROADMAP.md"
git -C "$REPO" add ROADMAP.md
git -C "$REPO" commit -q -m legacy
BODY_CTX=$'clean base line\n- [ ] [HARD — meeting] legacy item <!-- id:cccc -->\n- [ ] [ROUTINE] fresh clean item <!-- id:dddd -->\n'
rc="$(run_rc "$BODY_CTX")"
[[ "$rc" -eq 0 ]] && ok "9ef7: pre-existing old-vocab in a context line is grandfathered (exit 0)" \
                  || bad "9ef7: context-line old-vocab blocked — added-lines-only filter missing (rc=$rc)"

# ── (4) ADDED backtick-quoted PROSE mention of an old-vocab tag → allow (id:0d58 class) ──
# reset to a clean base so only the prose line is added.
printf 'clean base line\n' > "$REPO/ROADMAP.md"
git -C "$REPO" add ROADMAP.md
git -C "$REPO" commit -q -m reset
BODY_PROSE=$'clean base line\n- [ ] [ROUTINE] re-laned `[HARD — pool]`→`[ROUTINE]` note <!-- id:eeee -->\n'
rc="$(run_rc "$BODY_PROSE")"
[[ "$rc" -eq 0 ]] && ok "9ef7: backtick-quoted old-vocab in added PROSE does not block (anchored tag-vs-prose)" \
                  || bad "9ef7: backtick-prose mention false-blocked — must reuse anchored parser, not a raw grep (rc=$rc)"

# ── (5) repo ABSENT from the relay own-set → no-op, even with an added old-vocab tag ──
EMPTYTOML="$TMP/relay-empty.toml"; printf '# no own repos\n' > "$EMPTYTOML"
printf 'clean base line\n- [ ] [HARD — decision gate] gated thing <!-- id:ffff -->\n' > "$REPO/ROADMAP.md"
git -C "$REPO" add ROADMAP.md
rc="$( ( cd "$REPO" && LANE_VOCAB_RELAY_TOML="$EMPTYTOML" bash "$HOOK" >/dev/null 2>&1; echo $? ) )"
[[ "$rc" -eq 0 ]] && ok "9ef7: repo absent from relay own-set is a no-op (relay-scoping)" \
                  || bad "9ef7: non-relay repo was not skipped (rc=$rc)"

# ── (6) make install-lane-ratchet target exists (global core.hooksPath install) ──
grep -qE '^install-lane-ratchet:' "$SRC_DIR/Makefile" \
  && ok "9ef7: make install-lane-ratchet target exists" \
  || bad "9ef7: no install-lane-ratchet target in Makefile"

echo "---- $pass ok, $fail bad ----"
[[ "$fail" -eq 0 ]] || exit 1
echo "ALL PASS: old-vocab lane-tag ratchet pre-commit hook (roadmap:9ef7)"
