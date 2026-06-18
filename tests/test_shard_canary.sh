#!/usr/bin/env bash
# roadmap:3ea3 — discover-shard classifier canary PLUMBING guard (zero-token).
#
# The Tier-B harness itself (tests/shard-canary/run.sh) spawns a real classifier agent
# and so is NOT in the default sweep (it costs tokens; run via `make shard-canary`).
# This guard asserts — token-free — that the corpus, the swappable prompt, the harness,
# the make target, and the help/phony wiring all exist and are well-formed, AND drives
# run.sh with STUB agents to prove it actually DISCRIMINATES (a wrong verdict must FAIL,
# not rubber-stamp). No model judgment is exercised here.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$SRC_DIR/tests/shard-canary"
RUN="$DIR/run.sh"
PROMPT="$DIR/shard-prompt.baseline.txt"
pass=0 fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); return 0; }
bad() { echo "BAD: $*"; fail=$((fail+1)); return 0; }

[[ -d "$DIR" ]] || { echo "FAIL: tests/shard-canary/ missing"; exit 1; }
[[ -x "$RUN" ]] && ok "run.sh exists + executable" || bad "run.sh missing/not executable"
[[ -f "$DIR/README.md" ]] && ok "README.md exists" || bad "README.md missing"

# Swappable baseline prompt: placeholders + the judgment anchors a thin must preserve.
[[ -f "$PROMPT" ]] && ok "shard-prompt.baseline.txt exists" || bad "baseline prompt missing"
for ph in '{{REPOS}}' '{{RUNID}}' '{{LIVECLAIMS}}'; do
  grep -qF "$ph" "$PROMPT" && ok "prompt has placeholder $ph" || bad "prompt missing placeholder $ph"
done
for anchor in "EXECUTABLE-HARD" "Order of precedence" "id:2d20" "DIRTY"; do
  grep -qF "$anchor" "$PROMPT" && ok "prompt retains judgment anchor: $anchor" || bad "prompt lost judgment anchor: $anchor"
done

# Corpus: each fixture has setup.sh + expected; verdict classes + the gated-HARD judgment covered.
fixtures=(review execute hard-executable hard-gated idle dirty)
for fx in "${fixtures[@]}"; do
  [[ -f "$DIR/$fx/setup.sh" && -f "$DIR/$fx/expected" ]] \
    && ok "fixture $fx has setup.sh + expected" || bad "fixture $fx incomplete"
done
grep -qx "surfaced:gated" "$DIR/hard-gated/expected" && ok "hard-gated expects surfaced:gated (id:2d20 judgment)" || bad "hard-gated expected not surfaced:gated"
grep -qx "review" "$DIR/review/expected" && ok "review fixture expects review" || bad "review expected wrong"

# Makefile target + help + phony; run.sh excluded from default sweep (subdir, non-test_* name).
grep -qE '^shard-canary:' "$SRC_DIR/Makefile" && ok "Makefile has shard-canary target" || bad "Makefile missing shard-canary target"
grep -q 'shard-canary/run.sh' "$SRC_DIR/Makefile" && ok "target invokes run.sh" || bad "target does not invoke run.sh"
grep -q 'gaming-canary shard-canary' "$SRC_DIR/Makefile" \
  && ok "shard-canary is .PHONY" || bad "shard-canary not in .PHONY"
case "$(basename "$RUN")" in test_*) bad "run.sh named test_* (would join default sweep)";; *) ok "run.sh not in default sweep";; esac

# ── Behavioural: drive the harness with a STUB agent (token-free) ─────────────
# A correct stub maps each fixture's repo name → its expected classification.
STUB_OK='python3 -c "
import sys,json,re
p=sys.stdin.read(); m=re.search(r\"canary-([a-z-]+)\",p); name=m.group(1) if m else \"\"; repo=m.group(0) if m else \"?\"
o={\"units\":[],\"surfaced\":[],\"skipped\":[]}
vm={\"review\":\"review\",\"execute\":\"execute\",\"hard-executable\":\"hard\"}
if name in vm: o[\"units\"].append({\"repo\":repo,\"verdict\":vm[name]})
elif name==\"idle\": o[\"units\"].append({\"repo\":repo,\"verdict\":\"idle\"}); o[\"skipped\"].append({\"repo\":repo,\"reason\":\"idle\"})
elif name==\"hard-gated\": o[\"surfaced\"].append({\"repo\":repo,\"reason\":\"HARD backlog is gated (id:2d20)\"})
elif name==\"dirty\": o[\"surfaced\"].append({\"repo\":repo,\"reason\":\"dirty main working tree\"})
print(json.dumps(o))
"'
out="$(CANARY_AGENT="$STUB_OK" bash "$RUN" 2>&1)"; rc=$?
{ [[ $rc -eq 0 ]] && grep -q '6 passed, 0 failed' <<<"$out"; } \
  && ok "harness PASSES all fixtures with a correct stub agent" \
  || { bad "correct-stub run did not pass cleanly (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/   | /'; }

# A wrong stub (always 'idle') must make the harness FAIL — proves it isn't a rubber stamp.
STUB_WRONG='python3 -c "
import sys,json,re
p=sys.stdin.read(); m=re.search(r\"canary-([a-z-]+)\",p); repo=m.group(0) if m else \"?\"
print(json.dumps({\"units\":[{\"repo\":repo,\"verdict\":\"idle\"}],\"surfaced\":[],\"skipped\":[]}))
"'
out="$(CANARY_AGENT="$STUB_WRONG" bash "$RUN" review hard-gated 2>&1)"; rc=$?
{ [[ $rc -ne 0 ]] && grep -q 'FAIL   review' <<<"$out"; } \
  && ok "harness FAILS a wrong verdict (discriminates, not a rubber stamp)" \
  || { bad "wrong-stub run did not fail as expected (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/   | /'; }

echo "test_shard_canary: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
