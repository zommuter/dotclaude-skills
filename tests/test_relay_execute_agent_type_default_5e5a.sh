#!/usr/bin/env bash
# No roadmap header -- defect-fix spec for id:5e5a. Failures always count.
#
# Owner decision 2026-09-12: `EXECUTE_AGENT_TYPE` defaults to `relay-implementer` instead of OFF.
# This AMENDS the in-code "Do not flip the default" instruction, which was written when the only
# evidence was the quality-regression risk. What changed: THREE recorded silent non-adoptions
# (code.lawless adopted the flag at 15:55 on 2026-09-09 and had dropped it by 20:18; the
# 2026-09-11 close pool carried it; the 2026-09-12 pool did not), plus pooled arms of 2/9 execute
# children dying WITH the trim against 14/22 WITHOUT (n/N, never percentages -- id:3846's rule).
#
# THE DEFECT THIS PINS is not "the default is wrong" -- it is that flipping a default silently
# COLLAPSES TWO INPUTS THAT USED TO BE THE SAME. While the default was OFF, `undefined` and `''`
# both meant "no custom agent", so every call site could test falsiness and be right by accident.
# They now mean OPPOSITE things, and a falsiness test (`A.EXECUTE_AGENT_TYPE || DEFAULT`) silently
# destroys the opt-out: an operator who explicitly passes '' to get the old behaviour back would
# be handed `relay-implementer` instead, with nothing logged. That is the whole clause.
#
# Clause, three parts:
#   (A) UNSET (absent/null) resolves to `relay-implementer` -- the new default actually applies.
#   (B) EXPLICIT BLANK ('' or whitespace) resolves to '' -- the opt-out SURVIVES, and this is the
#       assertion a falsiness-based implementation fails.
#   (C) An explicit name is passed through verbatim and still wins over the default.
#
# fails-against: the flip and this spec land in the same commit, so the negative case is the
# falsiness mutation described above -- the single most likely way to write this wrong.
# fails-against-mutation: perl -0pi -e 's{const EXECUTE_AGENT_TYPE = A\.EXECUTE_AGENT_TYPE == null\n  \? EXECUTE_AGENT_TYPE_DEFAULT\n  : String\(A\.EXECUTE_AGENT_TYPE\)\.trim\(\)}{const EXECUTE_AGENT_TYPE = String(A.EXECUTE_AGENT_TYPE || EXECUTE_AGENT_TYPE_DEFAULT).trim()}' relay/scripts/relay-loop.js
# fails-against-assertion: (B) explicit blank must OPT OUT, got
#
# The declaration stops before the interpolated value ON PURPOSE: the runner matches it against
# the SOURCE line, which reads `got \"$(get blank)\"`, so declaring the runtime text
# ("relay-implementer") matches no line of the body and is a CONFIG ERROR. Static prefix only.
#
# NOTE on the delimiter, because the first version of this line was VACUOUS: written with `|` as
# the s||| delimiter it collides with the `||` being INSERTED, perl aborts with a syntax error,
# the mutation never applies, and the spec then "passes" against an unmutated file. That is an
# unreached fixture, not a passing negative control. Verified by hand 2026-09-12: with the `{}`
# form above the mutation applies (1 match) and assertion (B) fires, alone.
#
# Hermetic: reads relay-loop.js, extracts the default constant + the resolution expression
# verbatim and runs them under node in a mktemp -d. No ~/.claude, no ~/.config/relay, no network.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JS="$ROOT/relay/scripts/relay-loop.js"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "FAIL: $*"; fail=$((fail+1)); return 0; }
[[ -f "$JS" ]] || { echo "FAIL: relay-loop.js missing at $JS"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "SKIP: node not available"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- extract the region under test, verbatim from the source ------------------------------
# The default constant plus the resolution expression. Extracted and EXECUTED rather than
# grepped, so the falsiness mutation changes behaviour here instead of merely failing a match.
awk '/^const EXECUTE_AGENT_TYPE_DEFAULT = /{print} \
     /^const EXECUTE_AGENT_TYPE = /{f=1} f{if(!/^const EXECUTE_AGENT_TYPE_DEFAULT = /)print} \
     f&&/\.trim\(\)$/{exit}' "$JS" > "$TMP/resolve.js"
[[ -s "$TMP/resolve.js" ]] || { echo "FAIL: could not extract the default-resolution region"; exit 1; }
grep -q 'EXECUTE_AGENT_TYPE_DEFAULT' "$TMP/resolve.js" \
  || { echo "FAIL: extracted region lacks EXECUTE_AGENT_TYPE_DEFAULT"; exit 1; }

# Fixture sanity: the extracted region must actually name the owner-decided default. If this
# control fails the rest of the file proves nothing, so it exits rather than accumulating.
grep -q "EXECUTE_AGENT_TYPE_DEFAULT = 'relay-implementer'" "$TMP/resolve.js" \
  || { echo "FAIL: fixture sanity -- default is not 'relay-implementer' in the source"; exit 1; }

cat > "$TMP/probe.js" <<'PROBE'
const fs = require('fs')
const region = fs.readFileSync(process.argv[2], 'utf8')
function resolve (args) {
  // `A` is the name the extracted region reads from.
  const fn = new Function('A', region + '\n; return EXECUTE_AGENT_TYPE')
  return fn(args)
}
const out = {
  unset:      resolve({}),
  nullish:    resolve({ EXECUTE_AGENT_TYPE: null }),
  blank:      resolve({ EXECUTE_AGENT_TYPE: '' }),
  whitespace: resolve({ EXECUTE_AGENT_TYPE: '   ' }),
  named:      resolve({ EXECUTE_AGENT_TYPE: 'some-other-agent' }),
  padded:     resolve({ EXECUTE_AGENT_TYPE: '  padded-name  ' })
}
process.stdout.write(JSON.stringify(out))
PROBE

RES="$(node "$TMP/probe.js" "$TMP/resolve.js")" || { echo "FAIL: probe did not run"; exit 1; }
get() { printf '%s' "$RES" | python3 -c "import json,sys;print(json.load(sys.stdin)['$1'])"; }

# (A) unset takes the default
[[ "$(get unset)" == "relay-implementer" ]] \
  && ok "(A) absent key resolves to the default" \
  || bad "(A) absent key must resolve to relay-implementer, got \"$(get unset)\""
[[ "$(get nullish)" == "relay-implementer" ]] \
  && ok "(A) explicit null resolves to the default" \
  || bad "(A) explicit null must resolve to relay-implementer, got \"$(get nullish)\""

# (B) THE LOAD-BEARING ONE: an explicit blank is the opt-out and must survive.
[[ -z "$(get blank)" ]] \
  && ok "(B) explicit blank opts out" \
  || bad "(B) explicit blank must OPT OUT, got \"$(get blank)\""
# Distinct wording is REQUIRED, not stylistic: the declared fails-against-assertion must match
# exactly ONE line of this file, and a duplicate message makes it a CONFIG ERROR (exit 2).
[[ -z "$(get whitespace)" ]] \
  && ok "(B) whitespace-only opts out (trimmed to blank)" \
  || bad "(B) whitespace-only must trim to an OPT OUT, got \"$(get whitespace)\""

# (C) an explicit name still wins and is trimmed
[[ "$(get named)" == "some-other-agent" ]] \
  && ok "(C) explicit name passes through" \
  || bad "(C) explicit name must pass through, got \"$(get named)\""
[[ "$(get padded)" == "padded-name" ]] \
  && ok "(C) explicit name is trimmed" \
  || bad "(C) explicit name must be trimmed, got \"$(get padded)\""

echo "summary: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
