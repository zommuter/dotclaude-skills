#!/usr/bin/env bash
# (Deliberately NO `# roadmap:` header — id:da87 is a TODO defect item, not a
# promoted ROADMAP item, so per tests/README conventions this test's failures
# always count. Do not add an EXPECTED-RED escape hatch to it.)
#
# id:da87 — a per-repo collector must NEVER let one emitter's failure silently
# truncate the emitters after it.
#
# Background (2026-07-31): `/relay human .` on dotclaude-skills reported ZERO
# `review_me` rows while REVIEW_ME.md held 6 open boxes. The ROOT CAUSE was a
# CALLER that piped the collector through `head -80` (the repo emits 89 rows and
# `review_me` is emitted LAST), not the script — the script emitted all 6 rows,
# exit 0, empty stderr. But the investigation exposed a REAL latent instance of
# the same failure shape INSIDE `scan_repo`: several emitters ran unguarded under
# `set -e`, and the ROADMAP hard-lane emitter did a bare `return "$rc"` on any
# non-3 nonzero — either of which drops the mechanical / REVIEW_ME / @manual rows
# for that repo with NO message at all, leaving a short TSV that reads as a clean
# "nothing to do".
#
# Acceptance (three properties):
#   (1) da87's specified fixture — a repo whose TODO.md trips the untagged /
#       bad-lane path MUST still emit every open REVIEW_ME.md box.
#   (2) an emitter that FAILS must not suppress the emitters after it: with the
#       ROADMAP hard-lane emitter forced to fail, the repo's REVIEW_ME boxes are
#       still emitted.
#   (3) that failure is LOUD — a stderr ERROR line NAMES the failing emitter, and
#       the run exits nonzero, so an incomplete TSV can never read as clean.
#
# Hermetic: temp RELAY_TOML + temp own repos under a temp SRC_DIR.
# fails-against: rev 4a6b4bccf700 -- the tree as it stood immediately before the commit that
#   added this test, i.e. the pre-fix relay/SKILL.md, relay/references/human.md, relay/scripts/gather-human-backlog.sh. Derived + verified by tests/verify-negative-cases.py.
# fails-against-rev: 4a6b4bccf700 -- relay/SKILL.md relay/references/human.md relay/scripts/gather-human-backlog.sh
# fails-against-assertion: a FAILING ROADMAP hard-lane emitter suppressed the REVIEW_ME emitter that runs after it

set -euo pipefail

SRC_DIR_REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SRC_DIR_REPO/relay/scripts/gather-human-backlog.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SCRIPT" ]] || fail "gather-human-backlog.sh not found/executable at $SCRIPT"

tmp="$(mktemp -d)"
cleanup() { chmod -R u+rwX "$tmp" 2>/dev/null || true; rm -rf "$tmp"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# (1) TODO.md trips the untagged/bad-lane path — REVIEW_ME boxes must survive.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/src/repoTODO"
cat >"$tmp/src/repoTODO/ROADMAP.md" <<'MD'
# Roadmap

## Items

- [ ] [HARD] A perfectly well-formed pool item <!-- id:1111 -->
MD

# Untagged / bad-lane items in TODO.md: a bare `[HARD` with no recognized lane,
# and an INBOUND-style routed line carrying no lane tag at all (the exact shape
# of the six `[INBOUND routed:…]` items that were in flight on 2026-07-31).
cat >"$tmp/src/repoTODO/TODO.md" <<'MD'
# TODO

- [ ] [HARD - strong model REPOTODO] no such lane exists <!-- id:2222 -->
- [ ] [INPUT - no-such-lane] also unrecognized <!-- id:3333 -->
- [ ] [INBOUND routed:9999] an ingested cross-repo item with no lane tag <!-- id:4444 -->
- [ ] [INPUT - meeting] a genuine human-lane TODO item <!-- id:5555 -->
MD

cat >"$tmp/src/repoTODO/REVIEW_ME.md" <<'MD'
# Review me

- [ ] REVIEWBOX-ONE must survive an untagged TODO.md <!-- id:aaaa -->
- [ ] REVIEWBOX-TWO must survive an untagged TODO.md <!-- id:bbbb -->
- [x] REVIEWBOX-CLOSED must never be emitted <!-- id:cccc -->
MD

cat >"$tmp/relay-todo.toml" <<'TOML'
[repos.repoTODO]
classification = "own"
confirmed = "2026-01-01"
TOML

set +e
out="$(RELAY_TOML="$tmp/relay-todo.toml" SRC_DIR="$tmp/src" bash "$SCRIPT" 2>"$tmp/err1")"
rc=$?
set -e

grep -q "REVIEWBOX-ONE" <<<"$out" \
  || fail "an untagged/bad-lane TODO.md suppressed REVIEW_ME box 1 (rc=$rc, out: $out, err: $(cat "$tmp/err1"))"
grep -q "REVIEWBOX-TWO" <<<"$out" \
  || fail "an untagged/bad-lane TODO.md suppressed REVIEW_ME box 2 (rc=$rc, out: $out, err: $(cat "$tmp/err1"))"
grep -q "REVIEWBOX-CLOSED" <<<"$out" \
  && fail "a CLOSED '- [x]' REVIEW_ME box was emitted (out: $out)"
n_review="$(awk -F'\t' '$3 == "review_me"' <<<"$out" | wc -l)"
[[ "$n_review" -eq 2 ]] \
  || fail "expected exactly 2 review_me rows, got $n_review (out: $out)"
pass "da87 (1): an untagged/bad-lane TODO.md never suppresses the repo's open REVIEW_ME boxes"

# ---------------------------------------------------------------------------
# (2)+(3) A FAILING emitter must not suppress later emitters, and must be LOUD.
#
# Fault injection: make ROADMAP.md unreadable so the ROADMAP hard-lane emitter's
# awk fails with a non-3 status. `[[ -f ]]` still passes, so the emitter really
# runs and really fails — the exact condition that used to hit the bare
# `return "$rc"` and drop everything after it.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/src/repoFAIL"
cat >"$tmp/src/repoFAIL/ROADMAP.md" <<'MD'
# Roadmap

- [ ] [HARD] some item <!-- id:6666 -->
MD
cat >"$tmp/src/repoFAIL/REVIEW_ME.md" <<'MD'
# Review me

- [ ] REVIEWBOX-AFTER-FAILURE must still be emitted <!-- id:dddd -->
MD

cat >"$tmp/relay-fail.toml" <<'TOML'
[repos.repoFAIL]
classification = "own"
confirmed = "2026-01-01"
TOML

chmod 000 "$tmp/src/repoFAIL/ROADMAP.md"
if [[ -r "$tmp/src/repoFAIL/ROADMAP.md" ]]; then
  # Running as root (or on a filesystem ignoring the mode) — the fault cannot be
  # injected this way. Say so LOUDLY rather than silently reporting a pass.
  echo "SKIP: cannot make a file unreadable in this environment (running as root?) — emitter-failure isolation not exercised"
else
  set +e
  out2="$(RELAY_TOML="$tmp/relay-fail.toml" SRC_DIR="$tmp/src" bash "$SCRIPT" 2>"$tmp/err2")"
  rc2=$?
  set -e

  grep -q "REVIEWBOX-AFTER-FAILURE" <<<"$out2" \
    || fail "a FAILING ROADMAP hard-lane emitter suppressed the REVIEW_ME emitter that runs after it (rc=$rc2, out: $out2, err: $(cat "$tmp/err2"))"
  pass "da87 (2): a failing emitter does not truncate the emitters after it"

  grep -qi "ERROR" "$tmp/err2" \
    || fail "an emitter failed with NO stderr ERROR line — silent truncation (err: $(cat "$tmp/err2"))"
  grep -qi "ROADMAP hard-lane" "$tmp/err2" \
    || fail "the stderr ERROR does not NAME the failing emitter (err: $(cat "$tmp/err2"))"
  [[ $rc2 -ne 0 ]] \
    || fail "the run exited 0 despite an emitter failure — an incomplete TSV must never read as clean (err: $(cat "$tmp/err2"))"
  pass "da87 (3): the failing emitter is named LOUDLY on stderr and forces a nonzero exit"
fi

chmod 644 "$tmp/src/repoFAIL/ROADMAP.md"

# ---------------------------------------------------------------------------
# (4) The CALLER CONTRACT that was the ACTUAL 2026-07-31 root cause is documented
#     in the script header: never truncate the collector's stdout with `head`.
#     `review_me` is emitted LAST, so a truncating reader loses it first and
#     SILENTLY. This is a doc assertion on purpose — the script cannot detect a
#     reader that throws its output away.
# ---------------------------------------------------------------------------
grep -qi "NEVER TRUNCATE" "$SCRIPT" \
  || fail "the collector no longer documents the never-truncate caller contract (id:da87)"
grep -q "head" "$SCRIPT" \
  || fail "the never-truncate contract no longer names \`head\` as the hazard (id:da87)"
pass "da87 (4): the never-truncate caller contract is documented in the collector header"

echo "OK: gather-human-backlog emitter isolation + never-truncate contract (da87)"
