#!/usr/bin/env bash
# tests/shard-canary/run.sh — discover-SHARD classifier canary (id:3ea3).
#
# The shard classifier prompt (relay-loop.js shardPrompt) is the dominant relay
# token line (id:9cb1: ~48% of run cost, all sonnet). Thinning it is the high-value
# token lever — but it encodes classifier JUDGMENT (the EXECUTABLE-HARD gate id:2d20,
# the dirty/diverged guards, verdict precedence), so it is NOT a zero-behavior change.
# This canary is the safety net: a golden corpus of git-repo fixtures with KNOWN
# verdicts. Point it at the current prompt to baseline, then at a thinned candidate;
# if every fixture still yields its expected verdict, the thin is behavior-preserving.
#
# Like gaming-canary (id:414a), this is a MODEL harness run ON-DEMAND via
# `make shard-canary` — NOT part of run-tests.sh's default sweep (it spawns a real
# classifier agent and costs tokens). The PLUMBING (fixtures/prompt/target exist and
# are well-formed) is guarded zero-token by tests/test_shard_canary.sh.
#
# Usage:
#   tests/shard-canary/run.sh                          # all fixtures, baseline prompt
#   tests/shard-canary/run.sh review hard-gated        # a subset by dir name
#   tests/shard-canary/run.sh --prompt-file <f> [names] # test a THINNED candidate prompt
#
# Before/after equivalence workflow (the point):
#   tests/shard-canary/run.sh                                   # 1. baseline → all green
#   cp shard-prompt.baseline.txt shard-prompt.thin.txt && edit  # 2. thin it
#   tests/shard-canary/run.sh --prompt-file shard-prompt.thin.txt  # 3. must STILL be all green
#
# Agent invocation (overridable for hermetic self-test / CI):
#   CANARY_AGENT="<cmd>"  — reads the full prompt on STDIN, prints the shard JSON
#                           ({units,surfaced,skipped}) on STDOUT. Default:
#                           `claude -p --output-format json` (headless, costs tokens).
#
# Each fixture dir contains:
#   setup.sh <repodir>  — builds the git repo state (tags, ROADMAP.md, dirty tree, …)
#   expected            — the verdict: review|execute|hard|handoff|idle, OR
#                         surfaced:<substr> (repo must be SURFACED with a reason
#                         containing <substr>, e.g. surfaced:gated / surfaced:dirty)
#
# Exit: 0 if every fixture's classification matches `expected`; 1 otherwise.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROMPT_FILE="$HERE/shard-prompt.baseline.txt"
names=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt-file) PROMPT_FILE="$2"; shift 2 ;;
    *) names+=("$1"); shift ;;
  esac
done
[[ -f "$PROMPT_FILE" ]] || { echo "shard-canary: prompt file not found: $PROMPT_FILE" >&2; exit 2; }

run_agent() {
  if [[ -n "${CANARY_AGENT:-}" ]]; then bash -c "$CANARY_AGENT"
  elif command -v claude >/dev/null 2>&1; then claude -p --output-format json 2>/dev/null
  else echo "__NO_AGENT__"; fi
}

# Extract ONE repo's classification from the shard JSON reply. Prints:
#   <verdict>            for a unit (review|execute|hard|handoff|idle)
#   surfaced\t<reason>   if the repo is in surfaced[]
#   idle                 if the repo is only in skipped[]
#   __UNPARSEABLE__      if no shard object / repo not found
# Robust to the claude-CLI envelope ({"result":"...json..."}).
classify_of() {
  local reply="$1" repo="$2"
  python3 - "$reply" "$repo" <<'PY'
import json, re, sys
raw, repo = sys.argv[1], sys.argv[2]
def find_shard(o):
    if isinstance(o, dict):
        if any(k in o for k in ("units","surfaced","skipped")): return o
        for v in o.values():
            r = find_shard(v)
            if r is not None: return r
    elif isinstance(o, str):
        try: return find_shard(json.loads(o))
        except Exception:
            m = re.search(r'\{.*"(units|surfaced|skipped)".*\}', o, re.S)
            if m:
                try: return find_shard(json.loads(m.group(0)))
                except Exception: return None
    return None
try: parsed = json.loads(raw)
except Exception: parsed = raw
sh = find_shard(parsed)
if sh is None: print("__UNPARSEABLE__"); sys.exit(0)
for u in (sh.get("units") or []):
    if u.get("repo") == repo:
        print(u.get("verdict","__NOVERDICT__")); sys.exit(0)
for s in (sh.get("surfaced") or []):
    if s.get("repo") == repo:
        print("surfaced\t" + (s.get("reason","") or "")); sys.exit(0)
for s in (sh.get("skipped") or []):
    if s.get("repo") == repo:
        print("idle"); sys.exit(0)
print("__NOTFOUND__")
PY
}

fixtures=()
if [[ ${#names[@]} -gt 0 ]]; then fixtures=("${names[@]}")
else for d in "$HERE"/*/; do [[ -f "$d/setup.sh" && -f "$d/expected" ]] && fixtures+=("$(basename "$d")"); done; fi

pass=0 fail=0 skip=0
for name in "${fixtures[@]}"; do
  dir="$HERE/$name"
  if [[ ! -f "$dir/setup.sh" || ! -f "$dir/expected" ]]; then
    echo "FAIL   $name (missing setup.sh or expected)"; (( fail++ )); continue
  fi
  expected="$(tr -d '[:space:]' < "$dir/expected")"
  repo="canary-$name"
  work="$(mktemp -d)"; repodir="$work/$repo"
  ( bash "$dir/setup.sh" "$repodir" ) >/dev/null 2>&1 || { echo "FAIL   $name (setup.sh failed)"; rm -rf "$work"; (( fail++ )); continue; }

  repos_json="$(python3 -c 'import json,sys; print(json.dumps([{"repo":sys.argv[1],"path":sys.argv[2],"income":False}]))' "$repo" "$repodir")"
  prompt="$(sed -e "s#{{RUNID}}#relay-20260618-canary#g" -e "s#{{LIVECLAIMS}}#[]#g" "$PROMPT_FILE")"
  # substitute the repos JSON last (may contain slashes) via python to avoid sed delimiter issues
  prompt="$(REPOS="$repos_json" PROMPT="$prompt" python3 -c 'import os;print(os.environ["PROMPT"].replace("{{REPOS}}",os.environ["REPOS"]))')"

  reply="$(printf '%s' "$prompt" | run_agent)"
  rm -rf "$work"
  if [[ "$reply" == "__NO_AGENT__" ]]; then echo "SKIP   $name (no agent: set CANARY_AGENT or install claude CLI)"; (( skip++ )); continue; fi

  got="$(classify_of "$reply" "$repo")"
  verdict="${got%%$'\t'*}"; reason="${got#*$'\t'}"
  ok=0
  if [[ "$expected" == surfaced:* ]]; then
    sub="${expected#surfaced:}"
    [[ "$verdict" == "surfaced" ]] && printf '%s' "$reason" | grep -qi "$sub" && ok=1
  else
    [[ "$verdict" == "$expected" ]] && ok=1
  fi
  if [[ "$ok" == 1 ]]; then echo "PASS   $name (verdict=$verdict)"; (( pass++ ))
  else echo "FAIL   $name (expected '$expected', got '$verdict${reason:+ — $reason}')"; (( fail++ )); fi
done

echo "shard-canary: $pass passed, $fail failed, $skip skipped  (prompt: $(basename "$PROMPT_FILE"))"
[[ "$fail" -eq 0 ]]
