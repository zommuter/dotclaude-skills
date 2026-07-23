#!/usr/bin/env bash
# roadmap:24ec
# RED SPEC for id:24ec — "Mechanize relay discovery (prelude + shards) model:'haiku' → model:'bash'".
# Authored by /relay handoff 2026-07-23 (targeted C3). GATED-dep id:a36e (proxy fix) LANDED.
#
# SCOPE OF THIS SPEC (the SHARD half — the "biggest remaining real-model cost per round"):
# the `discover-run` shard (relay-loop.js:~1178) is a `model:'haiku'` agent() whose ONLY job is
# to run reconcile+classify per repo in a CHUNK and echo the JSON verbatim — pure transport, no
# judgment (classify-verdict never emits AMBIGUOUS today). Because Haiku has been observed to
# MANGLE even that (2026-07-07 discovery-off-Workflow meeting, D2), the fix is to wrap the whole
# per-chunk loop into ONE deterministic script — a NEW `relay/scripts/discover-chunk.sh` — and
# dispatch the shard as `model:"bash"` (one fenced command, zero agents). This is the id:c14d
# pattern (a former multi-step Haiku prompt → "run exactly this command") applied to discovery.
#
# discover-chunk.sh CONTRACT this pins (CASE B — no fresh id:9d97 queue, the SHIPPED default):
#   discover-chunk.sh --runid <id> --live-claims <csv> [--main-branch <name>]
#                     [--queue-latest <path>] [--queue-fresh-secs <n>]
#     reads a CHUNK JSON array on stdin:  [{"repo":<name>,"path":<abs>,"sig":<hex-or-"">}, ...]
#     emits ONE JSON on stdout: {"units":[...],"surfaced":[...],"skipped":[...]}
#       = the CONCATENATION, in chunk order, of discover-repo.sh's output for each repo
#         (LIVE reconcile+classify — NO --no-reconcile; the live loop's reap/park is load-bearing).
#     DETERMINISTIC + NO LLM: pure bash/python, no agent(), no `claude -p`.
#
# OUT OF THIS SPEC (proposed follow-on seams, see handoff report — do NOT special-case them green):
#   - CASE A content-address copy of the id:9d97 queue verdict (the id:7402 residual LLM read),
#     decision-gated on confirming the launch-wall (id:af30/id:2ec4) is dissolved by a36e.
#   - the PRELUDE mechanization (discover-prelude → model:"bash").
#
# RED until id:24ec's ROADMAP checkbox is ticked: (1) discover-chunk.sh does not exist yet;
# (2) the discover-run dispatch is still model:'haiku' in relay-loop.js.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHUNK="$ROOT/relay/scripts/discover-chunk.sh"
LOOP="$ROOT/relay/scripts/relay-loop.js"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }
mkrepo() { local d="$1"; mkdir -p "$d"; git -C "$d" init -q; git -C "$d" config user.email t@e; git -C "$d" config user.name t; git -C "$d" config commit.gpgsign false; }

# --- (0) the wrapper script must exist and be executable (RED: not authored yet) -------------
[[ -x "$CHUNK" ]] || fail "(0) discover-chunk.sh not authored yet (RED): $CHUNK"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export RELAY_WORKTREE_BASE="$tmp/wt"
export RELAY_TOML="$tmp/relay.toml"; : > "$RELAY_TOML"

# fixture chunk: one clean execute repo + one finished idle repo (distinct verdicts triangulate
# that the wrapper is a faithful concatenator, not a hard-coded single-verdict echo).
R1="$tmp/r_exec"; mkrepo "$R1"
printf '# Roadmap\n## Items\n- [ ] [ROUTINE] do it <!-- id:1111 -->\n' > "$R1/ROADMAP.md"
printf '# TODO\n## Current\n' > "$R1/TODO.md"
git -C "$R1" add -A; git -C "$R1" commit -qm init
R2="$tmp/r_idle"; mkrepo "$R2"
printf '# Roadmap\n## Items\n- [x] [ROUTINE] done <!-- id:2222 -->\n' > "$R2/ROADMAP.md"
printf '# TODO\n## Current\n- [x] done <!-- id:2223 -->\n' > "$R2/TODO.md"
git -C "$R2" add -A; git -C "$R2" commit -qm init; git -C "$R2" tag -a relay-ckpt-20260101-0000 -m ckpt

chunk_json="$(R1="$R1" R2="$R2" python3 -c '
import json, os
print(json.dumps([
  {"repo":"r_exec","path":os.environ["R1"],"sig":""},
  {"repo":"r_idle","path":os.environ["R2"],"sig":""},
]))')"

# --- (1) CASE B parity: wrapper output == concatenation of per-repo discover-repo.sh ----------
out1="$(printf '%s' "$chunk_json" | "$CHUNK" --runid myrun --live-claims "" --main-branch main)"

nunits="$(printf '%s' "$out1"  | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["units"]))')"
nskip="$(printf '%s' "$out1"   | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["skipped"]))')"
nsurf="$(printf '%s' "$out1"   | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["surfaced"]))')"
verds="$(printf '%s' "$out1"   | python3 -c 'import sys,json;print(",".join(sorted(u.get("verdict","") for u in json.load(sys.stdin)["units"])))')"

[[ "$nunits" == "2" ]] || fail "(1) chunk of 2 repos must emit 2 units (execute+idle), got $nunits: $out1"
[[ "$verds"  == "execute,idle" ]] || fail "(1) unit verdicts must be {execute,idle}, got [$verds]: $out1"
[[ "$nskip"  == "1" ]] || fail "(1) exactly the idle repo appears in skipped, got $nskip: $out1"
[[ "$nsurf"  == "0" ]] || fail "(1) neither clean repo surfaces, got $nsurf: $out1"
pass "(1) CASE B: wrapper concatenates per-repo discover-repo.sh verdicts (execute+idle)"

# --- (2) DETERMINISM: two invocations produce byte-identical output (no agent nondeterminism) -
out2="$(printf '%s' "$chunk_json" | "$CHUNK" --runid myrun --live-claims "" --main-branch main)"
[[ "$out1" == "$out2" ]] || fail "(2) wrapper is non-deterministic across two runs:\n--1--\n$out1\n--2--\n$out2"
pass "(2) wrapper output is deterministic across runs (mechanical, no LLM)"

# --- (3) STRUCTURAL: the discover-run dispatch in relay-loop.js is model:'bash', not 'haiku' --
# The RED half that pins the FLIP itself. Match the discover-run agent() dispatch line and assert
# its model is bash. (relay-loop.js:~1178 currently carries model: 'haiku'.)
[[ -f "$LOOP" ]] || fail "(3) relay-loop.js not found: $LOOP"
disp_line="$(grep -nE "label: .discover-run" "$LOOP" | head -1 || true)"
[[ -n "$disp_line" ]] || fail "(3) could not locate the discover-run agent() dispatch in relay-loop.js"
printf '%s' "$disp_line" | grep -qE "model: *'bash'" \
  || fail "(3) discover-run shard must dispatch model:'bash' (currently haiku) — line: $disp_line"
pass "(3) discover-run shard dispatches model:'bash' (the flip is in place)"

echo "ALL PASS: discover-run mechanized to a deterministic model:'bash' discover-chunk.sh wrapper (id:24ec)"
