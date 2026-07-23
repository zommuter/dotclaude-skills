#!/usr/bin/env bash
# roadmap:86a2
# RED SPEC for id:86a2 — "Mechanize the discover-PRELUDE (relay-loop.js:993/1008) → model:'bash'".
# Authored by /relay handoff 2026-07-23 (targeted C2). OWNER-RATIFIED as a SEPARATE ROADMAP item
# (not folded into id:24ec) in the --fabled amendment round (meeting docs/meeting-notes/
# 2026-07-23-1735-relay-orphan-existence-never-blocks.md, amended action items). UN-GATED: the
# id:af30/2ec4 launch-wall is dissolved by the id:a36e proxy fix (model:bash 12/12 agents 0
# errors this session, memory relay-model-proxy-probe-gated-substrate).
#
# WHY MECHANIZABLE: the discover-prelude (relay-loop.js:1008, `label: 'discover-prelude'`,
# currently `model: 'haiku'`) does ONLY once-only global work whose steps are ALREADY shell —
# runId gen (`relay-$(date +%Y%m%d-%H%M%S)-$RANDOM`), `inject.sh take`, `claim.sh peek`,
# `discover-sig.sh`, relay.toml own-repo enumeration (lib-own-repos.sh), stop-sentinel.sh check.
# So wrap the whole prelude into ONE deterministic script dispatched via a single fenced
# `model:"bash"` command (id:c14d pattern; mirror discover-repos-mechanical.sh). No LLM judgment
# is involved — the prelude never classifies.
#
# SEAM: a NEW wrapper `relay/scripts/discover-prelude.sh` that emits the PRELUDE_SCHEMA object
# on stdout {runId, ts, repos, skippedConfig, liveClaimRepos, injectedUnits, signatures,
# stopRequested}, reading RELAY_TOML (own-repo enumeration) + running the already-shell sentinel
# helpers. Then flip the relay-loop.js dispatch from model:'haiku' to model:'bash'.
#
# RED until id:86a2's ROADMAP checkbox is ticked: (0) discover-prelude.sh does not exist yet;
# (3) the discover-prelude dispatch in relay-loop.js is still model:'haiku'.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRELUDE="$ROOT/relay/scripts/discover-prelude.sh"
LOOP="$ROOT/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

# --- (0) the wrapper script must exist and be executable (RED: not authored yet) --------------
[[ -x "$PRELUDE" ]] || fail "(0) discover-prelude.sh not authored yet (RED): $PRELUDE"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# hermetic relay.toml: two confirmed-own repos (one income) + one external (skipped).
mkdir -p "$tmp/src/alpha" "$tmp/src/beta"
export RELAY_TOML="$tmp/relay.toml"
cat > "$RELAY_TOML" <<EOF
[repos.alpha]
classification = "own"
path = "$tmp/src/alpha"

[repos.beta]
classification = "own"
income = true
path = "$tmp/src/beta"

[repos.gamma]
classification = "external"
EOF

# --- (1) BEHAVIOR: the wrapper enumerates own repos + rolls up non-own into skippedConfig ------
out1="$("$PRELUDE" 2>/dev/null)"
nrepos="$(printf '%s' "$out1" | python3 -c 'import sys,json;print(len(json.load(sys.stdin).get("repos",[])))')"
names="$(printf '%s' "$out1"  | python3 -c 'import sys,json;print(",".join(sorted(r["repo"] for r in json.load(sys.stdin).get("repos",[]))))')"
nskip="$(printf '%s' "$out1"  | python3 -c 'import sys,json;print(",".join(sorted(s["repo"] for s in json.load(sys.stdin).get("skippedConfig",[]))))')"
[[ "$nrepos" == "2" ]]      || fail "(1) prelude must enumerate the 2 own repos, got $nrepos: $out1"
[[ "$names"  == "alpha,beta" ]] || fail "(1) own repos must be {alpha,beta}, got [$names]: $out1"
[[ "$nskip"  == "gamma" ]]  || fail "(1) the external repo must roll up into skippedConfig, got [$nskip]: $out1"
# runId must be present + match the mandated shape relay-YYYYMMDD-HHMMSS-<suffix>
printf '%s' "$out1" | python3 -c 'import sys,json,re;r=json.load(sys.stdin).get("runId","");sys.exit(0 if re.match(r"^relay-\d{8}-\d{6}-",r) else 1)' \
  || fail "(1) runId must match relay-YYYYMMDD-HHMMSS-<suffix>: $out1"
pass "(1) prelude enumerates own repos + skippedConfig rollup + well-formed runId (model:'bash')"

# --- (2) DETERMINISM: the relay.toml-DERIVED parts are byte-identical across two invocations ---
# (runId/ts are intentionally per-invocation; the pure enumeration must not vary.)
out2="$("$PRELUDE" 2>/dev/null)"
pure() { python3 -c 'import sys,json;d=json.load(sys.stdin);print(json.dumps({"repos":d.get("repos"),"skippedConfig":d.get("skippedConfig")},sort_keys=True))'; }
p1="$(printf '%s' "$out1" | pure)"; p2="$(printf '%s' "$out2" | pure)"
[[ "$p1" == "$p2" ]] || fail "(2) prelude repo-enumeration is non-deterministic:\n--1--\n$p1\n--2--\n$p2"
pass "(2) prelude enumeration is deterministic across runs (mechanical, no LLM)"

# --- (3) STRUCTURAL: the discover-prelude dispatch in relay-loop.js is model:'bash', not haiku -
[[ -f "$LOOP" ]] || fail "(3) relay-loop.js not found: $LOOP"
disp_line="$(grep -nE "label: .discover-prelude" "$LOOP" | head -1 || true)"
[[ -n "$disp_line" ]] || fail "(3) could not locate the discover-prelude agent() dispatch in relay-loop.js"
printf '%s' "$disp_line" | grep -qE "model: *'bash'" \
  || fail "(3) discover-prelude must dispatch model:'bash' (currently haiku) — line: $disp_line"
pass "(3) discover-prelude dispatches model:'bash' (the flip is in place)"

echo "ALL PASS: discover-prelude mechanized to a deterministic model:'bash' discover-prelude.sh wrapper (id:86a2)"
