#!/usr/bin/env bash
# roadmap:f54d
# The archiver must stay WIRED. `relay/scripts/roadmap-archive.sh` shipped built,
# tested and Makefile-targeted under id:6b67 — and `grep -c roadmap-archive
# relay/scripts/relay-loop.js` was 0 for 13 days, until an executor died with
# `Prompt is too long` against a 523,926-byte ROADMAP.md (2026-08-01, run
# relay-20260801-213927-29875). Built-green-but-unreferenced.
#
# This is a STATIC contract check over the integrator prompt (the live loop is far
# too expensive to run in a unit test — same approach as
# test_relay_integrator_scoped_add.sh / test_relay_loop_structure.sh), plus one
# behavioural check that the archiver really is the safe-on-every-repo no-op the
# integrator step claims it is.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
ARCHIVER="$SRC_DIR/relay/scripts/roadmap-archive.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$JS" ]]       || fail "relay-loop.js not found at $JS"
[[ -x "$ARCHIVER" ]] || fail "roadmap-archive.sh not found/executable at $ARCHIVER"
pass "relay-loop.js and roadmap-archive.sh both exist"

# (1) The integrator actually names the script. This is the exact done-check the
#     item specifies: grep -c 'roadmap-archive' relay-loop.js >= 1.
hits=$(grep -c 'roadmap-archive' "$JS" || true)
[[ "$hits" -ge 1 ]] \
  || fail "id:f54d: relay-loop.js never mentions roadmap-archive (count=$hits) — the archiver is un-wired again"
pass "id:f54d: relay-loop.js references roadmap-archive ($hits occurrence(s))"

# (2) It is invoked as a COMMAND from the relay scripts dir, not merely discussed
#     in prose. A mention inside a comment/explanation would satisfy (1) alone.
grep -qF -- 'relay/scripts/roadmap-archive.sh ${unit.path}' "$JS" \
  || fail "id:f54d: no 'roadmap-archive.sh \${unit.path}' invocation — the reference is prose, not a call"
pass "id:f54d: archiver is invoked on the unit's repo path (\${unit.path})"

# (3) The invocation lives in the INTEGRATOR prompt — the serialized, once-per-unit
#     path that already runs changelog-append.sh and ckpt-tag.sh — not in some other
#     phase where it would race a live child.
integ_start=$(grep -n 'You are the serialized integrator of the relay pool' "$JS" | head -1 | cut -d: -f1)
[[ -n "$integ_start" ]] || fail "id:f54d: could not locate the integrator prompt in relay-loop.js"
ckpt_line=$(awk -v s="$integ_start" 'NR>s && /ckpt-tag\.sh \$\{unit\.path\}/ {print NR; exit}' "$JS")
arch_line=$(awk -v s="$integ_start" 'NR>s && /roadmap-archive\.sh \$\{unit\.path\}/ {print NR; exit}' "$JS")
[[ -n "$ckpt_line" ]] || fail "id:f54d: integrator prompt has no ckpt-tag.sh step to anchor against"
[[ -n "$arch_line" ]] || fail "id:f54d: the roadmap-archive invocation is NOT inside the integrator prompt"
pass "id:f54d: archiver call sits inside the integrator prompt (line $arch_line), beside ckpt-tag (line $ckpt_line)"

# (4) It runs BEFORE the checkpoint tag, so the archived ROADMAP is part of the
#     checkpointed state rather than dangling uncommitted into worktree-retire.
[[ "$arch_line" -lt "$ckpt_line" ]] \
  || fail "id:f54d: archiver runs AFTER ckpt-tag (archive=$arch_line, ckpt=$ckpt_line) — it must precede the checkpoint"
pass "id:f54d: archiver runs before ckpt-tag.sh"

# (5) The step commits its own result with SCOPED staging, so the integrator does
#     not hand a dirty ROADMAP.md to worktree-retire (id:debf / id:373e).
step=$(awk -v a="$arch_line" -v c="$ckpt_line" 'NR>=a-6 && NR<c' "$JS")
grep -qF -- 'add -- ROADMAP.md ROADMAP.archive.md' <<<"$step" \
  || fail "id:f54d: the archive step does not scope-stage ROADMAP.md + ROADMAP.archive.md"
grep -qF -- 'status --porcelain -- ROADMAP.md ROADMAP.archive.md' <<<"$step" \
  || fail "id:f54d: the archive step does not gate its commit on an actual change (porcelain check)"
pass "id:f54d: archive step gates on a real change and stages ONLY the two ledger paths"

# (6) BEHAVIOUR: the integrator step calls the archiver unconditionally on every
#     repo, so the "safe no-op" claim must hold. Hermetic fixture in mktemp -d.
TMP=$(mktemp -d)
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# 6a. a repo with NO ROADMAP.md at all
git init -q "$TMP/norm"
git -C "$TMP/norm" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init
out=$(HOME="$TMP/home" "$ARCHIVER" "$TMP/norm" 2>&1) || fail "id:f54d: archiver exited non-zero on a repo with no ROADMAP.md: $out"
[[ -z "$(git -C "$TMP/norm" status --porcelain)" ]] \
  || fail "id:f54d: archiver dirtied a repo that has no ROADMAP.md"
pass "id:f54d: no-ROADMAP repo — clean exit 0, tree untouched"

# 6b. a repo whose ROADMAP has only OPEN items (nothing archivable)
git init -q "$TMP/open"
printf '# ROADMAP\n\n- [ ] open thing [ROUTINE] <!-- id:aaaa -->\n  - **Acceptance**: x\n' > "$TMP/open/ROADMAP.md"
git -C "$TMP/open" add -A
git -C "$TMP/open" -c user.email=t@e -c user.name=t commit -q -m init
out=$(HOME="$TMP/home" "$ARCHIVER" "$TMP/open" 2>&1) || fail "id:f54d: archiver exited non-zero with nothing to archive: $out"
grep -q 'nothing to archive' <<<"$out" \
  || fail "id:f54d: archiver did not report the nothing-to-archive no-op (got: $out)"
[[ -z "$(git -C "$TMP/open" status --porcelain)" ]] \
  || fail "id:f54d: archiver dirtied a repo with nothing to archive"
pass "id:f54d: nothing-to-archive — clean no-op, tree untouched"

echo "ALL PASS: roadmap-archive.sh is wired into the relay integrator (id:f54d)"
