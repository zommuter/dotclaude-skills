#!/usr/bin/env bash
# Defect-fix test (NO roadmap item -- this is a same-day regression guard for damage the suite
# itself caused, so per CLAUDE.md §Testing it omits a `# roadmap:` header and its failures
# always count).
#
# THE INCIDENT (2026-09-10, first-hand, not reconstructed): running `make test` DESTROYED 19
# live injected review units. `tests/test_prelude_mechanized_86a2.sh` invokes
# `relay/scripts/discover-prelude.sh`, whose step 6 runs a **CONSUMING** `inject.sh take`.
# inject.sh resolves its queue from `$INJECT_BASE` (default `~/.config/relay`), and that test
# isolated `RELAY_TOML` and nothing else -- so the suite drained the REAL global injection queue
# into `inject.done/`. Consumed injections have NO re-enqueue path, so they were lost from both
# the inbox and the ledger. Evidence: `~/.claude/logs/relay-inject.log` at 07:35:35 recorded
# `inject.sh take scope=<global> consumed=19 left-pending=0`, matching a `discover-prelude.sh
# emitted prelude runId=relay-20260910-073535-10596 repos=2` line at the same second -- repos=2
# being that test's two-repo fixture relay.toml, where a real pool's prelude reports repos=60.
# The 19 were 18 code.lawless OCR review units plus ai-codebench 0ce2.
#
# WHY A DYNAMIC CANARY AND NOT A GREP LINT: the obvious static rule -- "a test that references
# discover-prelude.sh / inject.sh must set INJECT_BASE" -- was tried first and is WRONG. Nine
# test files match that execution shape today and only ONE of them actually consumed; the other
# eight are hermetic by other means (they never reach a take, or build their own base). A lint
# would have reported eight false positives, and a guard that cries wolf eight times out of nine
# gets muted, which is how the leak survives. So this test MEASURES the property instead of
# inferring it: plant a canary unit in a scratch queue, run the candidate, and assert the canary
# is still there. It costs ~1.1s for all nine candidates.
#
# The candidate set is DERIVED, not hardcoded, so a newly added test that executes the prelude
# or a consuming inject op is covered automatically -- the whole point, since the leak arrived
# with a test nobody thought to check.
#
# fails-against: added in the same commit as the INJECT_BASE isolation it guards, so there is no
#   ancestor tree to overlay. The negative case is a MUTATION that removes exactly that
#   isolation from test_prelude_mechanized_86a2.sh, reproducing the live incident: the canary is
#   then consumed and this guard must name that file. Relative path only, inside the scratch tree.
# fails-against-mutation: sed -i '/^export INJECT_BASE=/d' tests/test_prelude_mechanized_86a2.sh
# fails-against-assertion: CONSUMED the canary injection unit
#
# Hermetic: every candidate runs with INJECT_BASE/HOME-independent scratch dirs created by
# mktemp; the REAL ~/.config/relay is never read or written by this file.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF="$(basename "${BASH_SOURCE[0]}")"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

# Candidates: test files that EXECUTE the prelude wrapper or a consuming/queue-mutating inject
# op. Matching on execution shape rather than on any mention keeps tests that merely grep
# relay-loop.js for the string 'discover-prelude' out of the set.
mapfile -t candidates < <(
  for f in "$ROOT"/tests/test_*.sh; do
    [[ "$(basename "$f")" == "$SELF" ]] && continue
    if grep -qE '"\$(PRELUDE|INJECT_SH)"|(^|[^a-z.-])(bash |exec |timeout [0-9]+ )?[^ ]*(discover-prelude|inject)\.sh (take|add|peek)' "$f"; then
      basename "$f"
    fi
  done
)

(( ${#candidates[@]} > 0 )) \
  || fail "candidate discovery found NO tests executing the prelude or a consuming inject op -- the detector stopped discriminating (it matched 9 files when written), so this guard would pass vacuously"

consumers=()
for t in "${candidates[@]}"; do
  pb="$(mktemp -d)"
  mkdir -p "$pb/inject.d"
  printf '{"repo":"canary-not-a-real-repo","verdict":"review","item":"zzzz"}\n' > "$pb/inject.d/canary.json"
  # Every state root the prelude touches goes to scratch, so a candidate that is only
  # accidentally hermetic today cannot pass by reading real state.
  # INJECT_LOG is isolated for the READER's sake, not the queue's: an isolated INJECT_BASE
  # still appends to the shared ~/.claude/logs/relay-inject.log, where a scratch consume reads
  # as `take scope=<global> consumed=N` against the LIVE queue. This guard runs on every
  # `make test`, so without this it would manufacture a steady stream of phantom takes in the
  # one log an operator consults when injections go missing.
  INJECT_BASE="$pb" CLAIM_BASE="$pb/claim" STOP_PATH="$pb/STOP-absent" \
    RELAY_DISCOVER_PRELUDE_LOG="$pb/prelude.log" INJECT_LOG="$pb/relay-inject.log" \
    timeout 180 bash "$ROOT/tests/$t" >/dev/null 2>&1 || true
  [[ -f "$pb/inject.d/canary.json" ]] || consumers+=("$t")
done

if (( ${#consumers[@]} > 0 )); then
  for t in "${consumers[@]}"; do
    echo "  leak: tests/$t moved the canary out of inject.d/ (it ran a consuming \`inject.sh take\` against the INJECT_BASE it inherited)"
  done
  fail "${#consumers[@]} test file(s) CONSUMED the canary injection unit -- under \`make test\` that is the REAL ~/.config/relay/inject.d, and consumed injections have no re-enqueue path (19 live review units were lost this way on 2026-09-10)"
fi

pass "all ${#candidates[@]} prelude/inject-executing test(s) leave a planted injection unit untouched"
echo "ALL PASS: the test suite cannot drain the live relay injection queue"
