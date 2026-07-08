#!/usr/bin/env bash
# id:354f — /relay inject front-door command (SKILL.md wiring over inject.sh add|peek).
# No `# roadmap:` header: id:354f is a TODO item, not a ROADMAP unit, so these
# failures always count (per tests/README testing conventions).
#
# The front door is a prose skill (SKILL.md drives the turn), so — like
# tests/test_relay_front_door.sh — this is a static contract check on the spec.
# The inject.sh add/peek/take mechanics themselves are covered by
# tests/test_relay_inject.sh; this asserts the ergonomic front door exists,
# resolves repos safely, defaults verdict, mints nothing, and surfaces pending.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$SRC_DIR/relay/SKILL.md"
INJECT="$SRC_DIR/relay/scripts/inject.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$SKILL" ]]  || fail "SKILL.md not found at $SKILL"
[[ -f "$INJECT" ]] || fail "inject.sh not found at $INJECT"
pass "SKILL.md and inject.sh exist"

# (1) The invocation block documents /relay inject with the specified arg shape.
grep -qE '^/relay inject' "$SKILL" \
  || fail "SKILL.md invocation block has no /relay inject line"
pass "SKILL.md documents /relay inject invocation"

for opt in -- '--item' '--verdict' '--prompt'; do
  grep -q -- "$opt" "$SKILL" || fail "SKILL.md /relay inject missing $opt option"
done
pass "SKILL.md documents --item/--verdict/--prompt options"

# (2) A dedicated `inject` arg section exists, tagged with the id.
grep -qE '^## `inject` arg' "$SKILL" || fail "SKILL.md has no '## \`inject\` arg' section"
grep -q 'id:354f' "$SKILL" || fail "SKILL.md inject section not tagged id:354f"
pass "SKILL.md has the inject section tagged id:354f"

# (3) It delegates to inject.sh add — mints nothing itself.
grep -q 'inject.sh add' "$SKILL" || fail "SKILL.md inject section does not call inject.sh add"
grep -qiE 'mint nothing|never mint|mint[[:space:]]nothing' "$SKILL" \
  || fail "SKILL.md inject section does not state it mints nothing (token is the script's)"
pass "SKILL.md delegates to inject.sh add and mints nothing"

# (4) Repo resolves against relay.toml; unknown/unconfirmed = LOUD reject.
#     Assert the LOUD-reject language appears in the inject section specifically.
inject_section="$(awk '/^## `inject` arg/{f=1} f; /^## Default mode/{if(f)exit}' "$SKILL")"
grep -q 'relay.toml' <<<"$inject_section" \
  || fail "inject section does not resolve <repo> against relay.toml"
grep -qiE 'LOUD reject' <<<"$inject_section" \
  || fail "inject section does not LOUD-reject an unknown/unconfirmed repo"
pass "inject section resolves against relay.toml with a LOUD reject"

# (5) Default verdict is execute.
grep -qiE 'default .*verdict .*execute|--verdict execute.* when omitted|default `--verdict execute`' <<<"$inject_section" \
  || fail "inject section does not default --verdict to execute"
pass "inject section defaults --verdict to execute"

# (6) Pending injections are surfaced via inject.sh peek (non-consuming).
grep -q 'inject.sh peek' "$SKILL" \
  || fail "SKILL.md does not surface pending injections via inject.sh peek"
grep -qiE 'non-consuming|not-yet-taken|pending injection' "$SKILL" \
  || fail "SKILL.md does not describe peek as non-consuming / pending surfacing"
pass "SKILL.md surfaces pending injections via inject.sh peek (non-consuming)"

# (7) The front door must NOT consume the inbox — take stays the pool's job.
grep -qiE 'take is the pool|`take` is the pool|never the front door' <<<"$inject_section" \
  || fail "inject section does not reserve inject.sh take for the pool (front door must not consume)"
pass "inject section reserves inject.sh take for the pool"

echo "ALL PASS"
