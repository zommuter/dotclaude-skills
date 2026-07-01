#!/usr/bin/env bash
# roadmap:8e3e — ckpt-tag.sh -c <commit>: the mechanical substrate for the zero-commit-review
# checkpoint. The integrator must be able to anchor the checkpoint tag on the tip the review
# child actually AUDITED, never on a main HEAD that advanced after dispatch (2026-07-01
# incident: review dispatched at HEAD 33169ee, main advanced to 65ce4ea mid-run; tagging
# current HEAD would have falsely marked the unseen commits audited). The RELAY_LOG entry
# still lands on the current branch; only the TAG target moves.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CT="$ROOT/relay/scripts/ckpt-tag.sh"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }
[[ -x "$CT" ]] || fail "ckpt-tag.sh not found/executable at $CT"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export FABLES_CONFIG="$TMP/cfg"   # hermetic: no relay.toml → watermark sync is a logged no-op

R="$TMP/repo"; mkdir -p "$R"
git -C "$R" init -q
git -C "$R" config user.email t@e.st
git -C "$R" config user.name t
echo one > "$R/f"; git -C "$R" add -A; git -C "$R" commit -qm c1
reviewed_tip="$(git -C "$R" rev-parse HEAD)"
echo two > "$R/f"; git -C "$R" add -A; git -C "$R" commit -qm c2   # main advanced after dispatch

# (1) -c anchors the tag on the reviewed tip, not HEAD.
tag="$("$CT" "$R" -m "zero-commit review checkpoint" -l "reviewer (claude-opus-4-8, integrate)" -c "$reviewed_tip" 2>/dev/null)" \
  || fail "(1) ckpt-tag.sh -c failed"
[[ -n "$tag" ]] || fail "(1) no tag name printed"
tag_target="$(git -C "$R" rev-parse "$tag^{commit}")"
[[ "$tag_target" == "$reviewed_tip" ]] \
  || fail "(1) tag points at $tag_target, expected the reviewed tip $reviewed_tip (would falsely audit unseen commits)"
pass "(1) -c <commit>: tag anchored on the reviewed tip, not the advanced HEAD"

# (2) the RELAY_LOG entry still lands on the current branch (documentation is not lost).
git -C "$R" show HEAD --name-only --pretty=format: | grep -qx 'RELAY_LOG.md' \
  || fail "(2) RELAY_LOG.md commit missing from the current branch"
pass "(2) RELAY_LOG entry still committed on the current branch"

# (3) a bogus -c target is a LOUD reject before anything is written.
before_log="$(git -C "$R" rev-parse HEAD)"
if "$CT" "$R" -m "bogus" -l "reviewer (test)" -c deadbeefdeadbeef 2>/dev/null; then
  fail "(3) bogus -c target accepted"
fi
[[ "$(git -C "$R" rev-parse HEAD)" == "$before_log" ]] \
  || fail "(3) bogus -c still wrote a RELAY_LOG commit (must reject before writing)"
pass "(3) unresolvable -c target rejected loudly, nothing written"

# (4) without -c, behavior unchanged: tag points at the RELAY_LOG commit on HEAD.
tag2="$("$CT" "$R" -m "normal checkpoint" -l "reviewer (test)" 2>/dev/null)" || fail "(4) plain ckpt-tag failed"
[[ "$(git -C "$R" rev-parse "$tag2^{commit}")" == "$(git -C "$R" rev-parse HEAD)" ]] \
  || fail "(4) default tag target is no longer HEAD (regression)"
pass "(4) default (no -c) behavior unchanged"

echo "ALL PASS: roadmap:8e3e ckpt-tag.sh -c commit target"
