#!/usr/bin/env bash
# relay/scripts/classify-repo.sh — DP1 assembly wrapper (id:3f0f)
#
# Usage: classify-repo.sh --repo <name> --path <abs>
#
# Assembles the full classify-verdict input for a single repo by:
#   1. Running gather-repo-state.sh --repo --path   → base JSON fields
#   2. Deriving hasRoutine / roadmap_open / roadmap_actionable_open from <path>/ROADMAP.md
#   3. Running unpromoted-scan.sh <path>            → unpromoted {promote, surface} counts
#   4. Merging into one JSON object and piping to classify-verdict.sh → emit its output,
#      plus (id:b09e) the two ROADMAP-derived passthrough fields `actionable_routine_open`
#      and `actionable_routine_ids` (the 4-hex ids BEHIND that count, in ROADMAP file order,
#      "" for an actionable item that carries no id). len(ids) == count, by construction.
#
# SIDE-EFFECT-FREE: reads state and runs the read-only helpers; never commits, writes a
# ledger, or creates a tag. (Declared exception, id:82c4: when a relay-core shadow binary
# is detected, one line is APPENDED to the shadow-parity log — an observability write
# outside every repo, never a ledger/repo mutation. Binary absent → no write at all.)
#
# Env overrides (hermetic tests; forwarded to sub-helpers):
#   RELAY_TOML           default ~/.config/relay/relay.toml
#   RELAY_WORKTREE_BASE  default ~/.cache/relay/worktrees
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# id:bb32 — the SHARED parked-section predicate. Sourced (not re-implemented) so the
# embedded python below can read ROADMAP_PARKED_HEADING_VOCAB / ROADMAP_HEADING_LINE_PCRE
# from the environment: one definition for the bash readers AND the python one.
# shellcheck source=lib-roadmap-sections.sh
source "$SCRIPT_DIR/lib-roadmap-sections.sh"

GATHER="$SCRIPT_DIR/gather-repo-state.sh"
SCAN="$SCRIPT_DIR/unpromoted-scan.sh"
CLASSIFY="$SCRIPT_DIR/classify-verdict.sh"
RESOLVE_GATES="$SCRIPT_DIR/resolve-gates.sh"

repo="" path="" emit_mode="" chain_end_reason="" chain_ended=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --path) path="$2"; shift 2 ;;
    --emit) emit_mode="$2"; shift 2 ;;
    # id:5552 — set chain_ended/chain_end_reason on the emitted unit DIRECTLY, replacing the
    # `| jq -c '. + {chain_ended:true,...}' |` middle stage that used to patch this script's own
    # JSON one process later. That stage made the whole hop unrunnable: `jq` is not in
    # mechanical-proxy.py's _SAFE_PLUMBING, so _command_allowed() returned False, the request
    # fell open to the real API, and `model:"bash"` 404'd — the chain-end classifier re-ask was
    # 100% dead for EVERY repo (routed:c555). Owning the field here keeps the hop to two pinned
    # relay scripts, which the proxy gate already trusts unconditionally.
    --chain-ended) chain_ended=1; chain_end_reason="$2"; shift 2 ;;
    *) echo "classify-repo.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$repo" ]] || { echo "classify-repo.sh: --repo is required" >&2; exit 2; }
[[ -n "$path" ]] || { echo "classify-repo.sh: --path is required" >&2; exit 2; }

# Step 1: gather base repo state (inherits RELAY_TOML / RELAY_WORKTREE_BASE from env)
base_json="$("$GATHER" --repo "$repo" --path "$path")"

# Step 2: run unpromoted-scan.sh (read-only; suppress log stderr so hermetic tests stay quiet)
scan_tsv="$("$SCAN" "$path" 2>/dev/null || true)"

# Step 2b (id:65f5): resolve every typed `<!-- gated-on:... -->` edge on a ROADMAP item
# against its target checkbox state via the SHARED id:46f6 engine (resolve-gates.sh →
# lib-typed-edges.sh), NOT a bare substring read in the line loop below. Emits TSV rows
# `<own-id>\t<block:0|1>\t<dangling-csv>` for edges that block or dangle; a clean edge
# emits nothing. Read-only; its own stderr (a missing ROADMAP is normal) is suppressed.
gates_tsv="$("$RESOLVE_GATES" "$path" 2>/dev/null || true)"

# Step 3 + 4: derive ROADMAP fields, fold unpromoted counts, pipe to classifier.
# Pass the (potentially large) gather JSON + scan TSV via TEMP FILES, never env/argv: a single
# env string over MAX_ARG_STRLEN (128KB) breaks execve of python3 AND the classifier (see
# tests/test_classify_repo_large.sh — dotclaude-skills' ~130KB unpromoted-scan TSV). Paths stay tiny.
blobdir="$(mktemp -d)"
trap 'rm -rf "$blobdir"' EXIT
printf '%s' "$base_json" > "$blobdir/base.json"
printf '%s' "$scan_tsv"  > "$blobdir/scan.tsv"
printf '%s' "$gates_tsv" > "$blobdir/gates.tsv"
export CLASSIFY_PATH="$path" BASE_FILE="$blobdir/base.json" SCAN_FILE="$blobdir/scan.tsv" GATES_FILE="$blobdir/gates.tsv"
python3 - <<'PYEOF' > "$blobdir/assembled.json"
import json, os, re, sys

# Dual-vocab window (id:4f02/id:8111 B2a, OPEN): both the OLD venue-keyed
# `[HARD — <lane>]` spelling and the NEW capability-keyed `[INPUT — <lane>]` spelling
# are recognized as human gates, equivalently. `[HARD]`/`[HARD — pool]` are equivalent
# pool tags (see LANE_TAGS/is_pool below).
HUMAN_GATES = (
    "[HARD — hands]", "[HARD — meeting]", "[HARD — decision gate]",
    "[INPUT — meeting]", "[INPUT — decision]", "[INPUT — access]",
)
# id:4da4 — recognized lane tags, in no particular order; the item's lane is whichever
# appears FIRST on the line (see the primary-lane parse below). "[HARD]" (bare, no
# dash-lane) is the new-vocab rename of "[HARD — pool]" — an EXACT-substring match, so
# it never false-matches inside "[HARD — pool]"/"[HARD — hands]"/etc. (those contain
# "[HARD —", never the literal "[HARD]").
# id:0d58 — "[MECHANICAL]" joins LANE_TAGS so it is anchored through the SAME
# positional primary-lane derivation as every other lane, rather than read by its own
# bare-substring test (see the id:0d58 note at the open_mechanical counter below).
LANE_TAGS = ("[ROUTINE]", "[HARD — pool]", "[HARD]", "[MECHANICAL]") + HUMAN_GATES

path     = os.environ["CLASSIFY_PATH"]
with open(os.environ["BASE_FILE"]) as _f: base_json = _f.read()
with open(os.environ["SCAN_FILE"]) as _f: scan_tsv  = _f.read()
with open(os.environ["GATES_FILE"]) as _f: gates_tsv = _f.read()

# id:65f5 Step 2b — fold the shared id:46f6 gate resolution (resolve-gates.sh) into two
# per-item lookups keyed by the item's OWN id:
#   gate_blocked_ids — own-ids whose typed gated-on: edge points at a still-OPEN target
#                      (excluded from actionable_routine_open, the is_human-style path).
#   gate_dangling    — own-id → dangling target token CSV (LOUD on stderr, never a block).
gate_blocked_ids = set()
gate_dangling    = {}
for _row in gates_tsv.splitlines():
    _c = _row.split("\t")
    if len(_c) < 3:
        continue
    _oid, _block, _dang = _c[0], _c[1], _c[2]
    if _block == "1":
        gate_blocked_ids.add(_oid)
    if _dang:
        gate_dangling[_oid] = _dang

# id:65f5 — LOUD why-not-ready surfaces collected during the ROADMAP loop, flushed to
# stderr at the end (never a silent execute-suppression). Each names the item id + reason.
why_not_ready = []

# --- Step 2: derive ROADMAP fields ----------------------------------------
rm = os.path.join(path, "ROADMAP.md")
# id:4f9b — the ROADMAP's SIZE IN BYTES, so relay-loop.js can size the child's assembled
# prompt BEFORE dispatch and hand back with the real reason instead of letting the child die
# with a bare `Prompt is too long`. relay-loop.js runs inside the Workflow sandbox and has NO
# filesystem access (see id:61fa's premise problem), so the measurement must be taken HERE, on
# the host, and ride along as a field. 0 when ROADMAP.md is absent/unreadable — the gate is
# FAIL-OPEN on 0, so a missing measurement never blocks a dispatch.
try:
    roadmap_bytes = os.path.getsize(rm) if os.path.isfile(rm) else 0
except OSError:
    roadmap_bytes = 0
has_routine = False
roadmap_open = 0
roadmap_actionable_open = 0
actionable_routine_open = 0
# id:b09e — the QUALIFYING item ids, not just the count. The dispatch prompt names ONE item so
# the executor child never has to survey the whole ROADMAP to find its own work (the phase two
# measured children died in). Every append below is paired 1:1 with what used to be a
# `actionable_routine_open += 1`, and the count is DERIVED as len(...) after the loop — so the
# count and the id list are STRUCTURALLY incapable of drifting apart. An actionable item that
# carries no `<!-- id:XXXX -->` contributes an EMPTY STRING placeholder: it still counts (the
# counting semantics are byte-unchanged), it just cannot be named.
actionable_routine_ids = []
open_mechanical = 0
surfaced_open = 0   # id:65f5 class 3: open executor-lane items carrying `⚠ SURFACED`

# id:356f — whole-section gating: a heading whose text names a parked bucket opens an
# exempt section; any other heading closes it. While in an exempt section, an open
# [ROUTINE] line must not count toward actionable_routine_open / roadmap_actionable_open
# / open_mechanical — parked is parked for all lanes.
#
# id:bb32 — the two patterns are READ from the shared bash lib (lib-roadmap-sections.sh,
# sourced by this script and exported into the environment), never retyped here. A
# retyped python copy is invisible to a bash-function-name grep, which is precisely how
# the third copy of this predicate survived `ef43739`'s "one definition" claim — and it
# had already drifted (this reader ignored an H1 `# Gated / deferred` that
# gather-repo-state.sh honoured). KeyError on a missing env var is deliberate: a LOUD
# failure beats silently falling back to a local copy.
_EXEMPT_HEADING_RE = re.compile(os.environ["ROADMAP_PARKED_HEADING_VOCAB"], re.IGNORECASE)
_HEADING_LINE_RE   = re.compile(os.environ["ROADMAP_HEADING_LINE_PCRE"])

if os.path.isfile(rm):
    in_exempt_section = False
    with open(rm, errors="replace") as f:
        for ln in f:
            if _HEADING_LINE_RE.match(ln):
                in_exempt_section = bool(_EXEMPT_HEADING_RE.search(ln))
                continue
            if not re.match(r"\s*- \[ \] ", ln):
                continue
            roadmap_open += 1
            # id:4da4 — PRIMARY-LANE anchoring: an item's lane is the FIRST recognized lane-tag
            # on the line. Lane tags cluster right after the title; any bracket-token further
            # right is prose/history and must NOT set the lane. This is robust where a
            # title-scope + backtick-strip is not: leAIrn2learn id:c3f5 is a [HARD — pool] item
            # (tag at char 85) with a backtick'd `[ROUTINE]` 1600 chars into its handback history
            # (char 1640) — 16 desynced backticks let the strip miss it, so it mis-fired execute
            # (/relay --once 2026-07-01). Taking the FIRST lane-tag makes it correctly `hard`.
            _found = [(ln.find(t), t) for t in LANE_TAGS if ln.find(t) >= 0]
            primary = min(_found)[1] if _found else ""
            is_routine    = primary == "[ROUTINE]"
            is_pool       = primary in ("[HARD — pool]", "[HARD]")
            # id:0d58 — [MECHANICAL] capability tier: counted ONLY when it is the anchored
            # primary lane (id:4da4), same as every other lane. A bare-substring test here
            # let a backtick'd `[MECHANICAL]` mention on a differently-laned line (e.g. a
            # [ROUTINE] or [HARD — pool] item) falsely inflate open_mechanical and mis-fire
            # the priority-6 `mechanical` verdict; routing it through `primary` closes that
            # (no human/pool exclusion needed beyond anchoring — the tag itself IS
            # pool-inert/human-inert by definition, unlike [ROUTINE]/[HARD — pool] which need
            # the @manual/blocked carve-outs below).
            is_mechanical = primary == "[MECHANICAL]"
            if is_mechanical and not in_exempt_section:
                open_mechanical += 1
            # id:65f5 — the item's OWN id (anchored trailing `<!-- id:XXXX -->`), the handle
            # for the shared gate resolution + the LOUD why-not-ready surfaces below.
            _oid_m  = re.search(r"<!--\s*id:([0-9a-fA-F]{4})\s*-->", ln)
            own_id  = _oid_m.group(1) if _oid_m else ""
            # id:65f5 class 1 — @owner-verify (owner-on-device-pending) joins the conservative
            # is_human-style exclusion (under-dispatch-safe): excluded from actionable_routine_open,
            # with a LOUD why-not-ready surface (never a silent suppression).
            is_owner_verify = "@owner-verify" in ln
            # id:65f5 class 2 — typed gated-on: edge points at a still-OPEN target (resolved via
            # the shared id:46f6 engine in resolve-gates.sh, keyed by own id). A dangling target
            # is surfaced LOUDLY below but does NOT block (never a silent forever-block).
            gate_blocked = bool(own_id) and own_id in gate_blocked_ids
            # id:65f5 class 3 — an open executor-lane item carrying `⚠ SURFACED` (no RED spec
            # authored) must route the repo to `handoff`, never `execute`: excluded from
            # actionable_routine_open AND counted into surfaced_open (fed to the handoff branch).
            is_surfaced = "⚠ SURFACED" in ln
            # @manual excludes conservatively (a rare prose mention only ever UNDER-dispatches,
            # never mis-dispatches — the safe direction for the executor gate). @owner-verify
            # joins this same conservative path (meeting D2, 2026-07-20-1918).
            # id:0cf5 (routed:02d9) — @container joins them. handoff.md:233 / review.md:304 tell
            # an author to mark a DECOMPOSED parent @container because "collectors exclude that
            # marker"; roadmap-lint.sh:396 and gather-human-backlog.sh:298 did, this one did not,
            # so an @container parent still fired verdict=execute on a container whose SEAMS are
            # the work (loderite ids c19e/2b24, 2026-07-29). Same under-dispatch-safe direction
            # as @manual: the marker can only REMOVE work from the dispatch set, never add it.
            is_container = "@container" in ln
            # id:7517 — @owner-gated joins the same conservative path (OWNER RULING 2026-08-14,
            # answering routed:34a2's open question). Only the owner can discharge an
            # owner-gated item, so dispatching one to an executor is wasted work by
            # construction; excluding it is the fail-safe direction, identical in kind to
            # @manual/@owner-verify/@container. Keep the THREE dispatch predicates in agreement
            # (gather-repo-state.sh's top_intensive + open_hard_pool carry the same exclusion) —
            # and do NOT rely on lib-roadmap-sections.sh's parked-heading vocab for this: that
            # protection is an ACCIDENT of substring matching (`@owner-gated` contains `gated`)
            # which id:f391/id:6446 remove.
            is_owner_gated = "@owner-gated" in ln
            is_human   = (primary in HUMAN_GATES or "@manual" in ln or is_owner_verify
                          or is_container or is_owner_gated)
            # id:4da4 — a [ROUTINE]/@wire item that declares a dependency BLOCK / gate is NOT
            # executor-actionable — the executor can only no-op it (zkm-threema id:180b
            # "[ROUTINE] (BLOCKED on id:7364)" was dispatched execute → empty handback,
            # /relay --once 2026-07-01). Conservative markers only under-dispatch (safe).
            blocked = ("🚧" in ln) or ("BLOCKED on" in ln) or ("blocked on" in ln) or gate_blocked
            # id:ac7f — @wire is an ORTHOGONAL marker (like @manual/@needs-auth, NOT a lane),
            # defined by the executor-verifiable-via-a-host/e2e-RED-spec property (design
            # 2026-07-19-1152 D4). An open @wire item on a PRIMARY EXECUTOR lane
            # ([ROUTINE]/[HARD — pool]/[HARD]) counts toward actionable_routine_open, so the
            # classify-verdict execute gate fires (verdict=execute) — the SAME lane WITHOUT
            # @wire stays plain pool-lane hard work (verdict=hard). @manual stays EXCLUDED
            # (is_human above), the safe under-dispatch direction that must never flip.
            has_wire = "@wire" in ln
            if is_routine:
                has_routine = True
                # id:4da4 — actionable_routine = open [ROUTINE], primary-lane, NOT @manual/human-gated,
                # NOT dependency-blocked. This (not bare has_routine) is what the execute verdict
                # gates on, else an @manual-only or blocked [ROUTINE] repo mis-fires execute.
                # id:65f5 — also excludes a `⚠ SURFACED` (no-RED-spec) item, which routes to
                # handoff via surfaced_open below, never execute.
                if not is_human and not blocked and not is_surfaced and not in_exempt_section:
                    actionable_routine_ids.append(own_id)
                if is_surfaced and not is_human and not in_exempt_section:
                    surfaced_open += 1
            elif has_wire and is_pool:
                # id:ac7f — @wire on a pool lane ([HARD — pool]/[HARD]) is executor-actionable
                # (a host/e2e RED spec makes it executor-verifiable); count it alongside
                # [ROUTINE]. Same @manual/blocked/exempt carve-outs as the routine branch,
                # plus the id:65f5 SURFACED carve-out.
                if not is_human and not blocked and not is_surfaced and not in_exempt_section:
                    actionable_routine_ids.append(own_id)
                if is_surfaced and not is_human and not in_exempt_section:
                    surfaced_open += 1
            # id:65f5 — LOUD why-not-ready surfaces (collected, flushed to stderr after the loop).
            # An excluded @owner-verify item and a dangling gated-on: target are surfaced by id +
            # marker so the exclusion is never silent (mechanize-reliability: loud, not swallowed).
            if is_owner_verify and not in_exempt_section:
                why_not_ready.append(
                    "id:{} not executor-ready — @owner-verify (owner-on-device-pending); "
                    "excluded from actionable_routine_open".format(own_id or "?"))
            if own_id and own_id in gate_dangling and not in_exempt_section:
                why_not_ready.append(
                    "id:{} gated-on: target(s) [{}] resolve NOWHERE (dangling) — not a block, "
                    "but the marker may be stale; fix the edge".format(own_id, gate_dangling[own_id]))
            if (is_routine or is_pool) and not is_human and not in_exempt_section:
                roadmap_actionable_open += 1

# id:b09e — DERIVE the count from the id list so the two can never disagree (spec invariant 3:
# len(actionable_routine_ids) == actionable_routine_open, always). This replaces the former
# `actionable_routine_open += 1` counter; the accepted-item predicate above is untouched.
actionable_routine_open = len(actionable_routine_ids)

# --- Step 3: fold unpromoted-scan TSV counts ------------------------------
promote = 0
surface = 0
for ln in scan_tsv.splitlines():
    cols = ln.split("\t")
    if len(cols) >= 3:
        if cols[2] == "promote":
            promote += 1
        elif cols[2] == "surface":
            surface += 1

# --- Merge into full JSON object ------------------------------------------
base = json.loads(base_json)
base["hasRoutine"]              = has_routine
base["roadmap_open"]            = roadmap_open
base["roadmap_actionable_open"] = roadmap_actionable_open
base["actionable_routine_open"] = actionable_routine_open
base["actionable_routine_ids"]  = actionable_routine_ids   # id:b09e
base["roadmap_bytes"]           = roadmap_bytes            # id:4f9b
base["open_mechanical"]         = open_mechanical
base["surfaced_open"]           = surfaced_open   # id:65f5 → classify-verdict handoff branch
base["unpromoted"]              = {"promote": promote, "surface": surface}

# id:65f5 — flush every collected why-not-ready line to stderr LOUDLY (the exclusions
# above are never silent). stdout stays the pure JSON object the pipeline consumes.
for _line in why_not_ready:
    print("classify-repo: why-not-ready: " + _line, file=sys.stderr)

print(json.dumps(base))
PYEOF

"$CLASSIFY" < "$blobdir/assembled.json" > "$blobdir/verdict.json"

# --- relay-core SHADOW (id:82c4 island-1 strangler; meeting id:23ab D3/a0b6) ------------
# If a Lean `relay-core` binary is present, run it over the SAME assembled input in
# SHADOW: the bash verdict.json above remains the ONLY authoritative output — the Lean
# output is only COMPARED (canonicalized `jq -S -c .` on both sides, Amendment F2: key
# order sorts, evidence-array order stays contractual) and the result appended to the
# shadow-parity log. A MISMATCH is LOUD (stderr + log entry with both canonical forms)
# but NEVER alters the authoritative output or this script's exit code; the FLIP
# (100% corpus parity + N=5 clean shadow rounds) is a separate, gated step — nothing
# reads the Lean output for decisions. Binary absent → this block is a no-op: zero
# behavior change, zero new output, zero log writes.
#
# Detection order: RELAY_CORE_BIN env override wins when set — set-but-not-executable
# DISABLES the shadow entirely (the hermetic-test kill switch: tests set
# RELAY_CORE_BIN=/nonexistent so a later real install can never leak log writes into
# them); else `relay-core` on PATH; else ~/.local/bin/relay-core.
shadow_bin=""
if [[ -n "${RELAY_CORE_BIN-}" ]]; then
  if [[ -x "$RELAY_CORE_BIN" ]]; then shadow_bin="$RELAY_CORE_BIN"; fi
elif command -v relay-core >/dev/null; then
  shadow_bin="$(command -v relay-core)"
elif [[ -x "$HOME/.local/bin/relay-core" ]]; then
  shadow_bin="$HOME/.local/bin/relay-core"
fi
if [[ -n "$shadow_bin" ]]; then
  shadow_log="${RELAY_CORE_SHADOW_LOG:-$HOME/.claude/logs/relay-core-shadow.jsonl}"
  mkdir -p "$(dirname "$shadow_log")"
  shadow_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  shadow_hash="$(sha256sum < "$blobdir/assembled.json" | cut -d' ' -f1)"
  lean_raw=""
  if ! lean_raw="$("$shadow_bin" < "$blobdir/assembled.json")"; then
    # A nonzero Lean exit is itself shadow evidence: surfaced here (binary's own stderr
    # passes through untouched) and recorded below as a MISMATCH via the INVALID-JSON
    # marker. It never propagates — bash output stays authoritative.
    echo "classify-repo: relay-core shadow binary exited nonzero (recording MISMATCH)" >&2
  fi
  bash_canon="$(jq -S -c . < "$blobdir/verdict.json")"
  # jq stderr suppressed HERE ONLY because unparseable Lean output is an EXPECTED
  # mismatch condition converted to the explicit INVALID-JSON marker below — a loud
  # logged signal, not a swallowed failure. Empty output (e.g. a crashed binary) is
  # the same condition: jq emits no value for no input, so map "" → INVALID-JSON.
  if ! lean_canon="$(printf '%s' "$lean_raw" | jq -S -c . 2>/dev/null)" || [[ -z "$lean_canon" ]]; then
    lean_canon="INVALID-JSON"
  fi
  if [[ "$lean_canon" == "$bash_canon" ]]; then
    jq -cn --arg ts "$shadow_ts" --arg h "$shadow_hash" \
      '{ts:$ts, input_hash:$h, result:"match"}' >> "$shadow_log"
  else
    echo "classify-repo: relay-core SHADOW MISMATCH (input sha256 $shadow_hash) — bash output stays authoritative; details in $shadow_log" >&2
    jq -cn --arg ts "$shadow_ts" --arg h "$shadow_hash" --arg b "$bash_canon" --arg l "$lean_canon" \
      '{ts:$ts, input_hash:$h, result:"MISMATCH", bash:$b, lean:$l}' >> "$shadow_log"
  fi
fi

if [[ "$emit_mode" != "unit" ]]; then
  # Default mode: the classify-verdict object PLUS the two id:b09e passthrough fields
  # (`actionable_routine_open` + `actionable_routine_ids`) folded in at the top level.
  #
  # Why the fold happens HERE and not inside classify-verdict.sh: classify-verdict.sh is the
  # surface the Lean `relay-core` strangler shadows byte-for-byte (id:82c4, the block above).
  # The shadow compares `verdict.json` — the PURE verdict contract — so folding the ROADMAP-
  # derived ids in AFTERWARDS leaves that parity surface untouched (a Lean binary that does not
  # know the new fields still matches). The ids are a property of the ROADMAP parse this script
  # owns, not of the verdict function. SIDE-EFFECT-FREE: a read + a jq merge, no writes.
  jq -c --slurpfile a "$blobdir/assembled.json" \
    '. + {actionable_routine_open: ($a[0].actionable_routine_open // 0),
          actionable_routine_ids:  ($a[0].actionable_routine_ids  // [])}' \
    "$blobdir/verdict.json"
  exit 0
fi

# --emit unit: build the FULL DISCOVER_SCHEMA unit (id:3d61) by merging the gather
# passthrough fields (base) + deterministic derivations from toml_block/latest_ckpt_msg +
# classify-verdict's verdict/reason/intensive. SIDE-EFFECT-FREE: reads only.
REPO_ARG="$repo" PATH_ARG="$path" \
CHAIN_ENDED="$chain_ended" CHAIN_END_REASON="$chain_end_reason" \
python3 - "$blobdir/assembled.json" "$blobdir/verdict.json" <<'PYEOF'
import json, os, re, sys

with open(sys.argv[1]) as f:
    base = json.load(f)
with open(sys.argv[2]) as f:
    v = json.load(f)

toml_block = base.get("toml_block", "") or ""
ckpt_msg   = base.get("latest_ckpt_msg", "") or ""

income = bool(re.search(r'(?m)^\s*income\s*=\s*true\s*$', toml_block))

m = re.search(r'(?m)^\s*last_strong_ckpt\s*=\s*"([^"]*)"\s*$', toml_block)
last_strong_ckpt = m.group(1) if m else ""
fr = re.search(r'(?m)^\s*fable_rechecked\s*=\s*(\S+)\s*$', toml_block)
fable_rechecked_val = fr.group(1).strip('"') if fr else ""
fable_rechecked = fable_rechecked_val not in ("", "false", "False")
# id:5884: strongRecheckPending is model-BLIND if it only checks
# last_strong_ckpt/fable_rechecked — a relay.toml entry whose strong checkpoint
# was ALREADY produced by a Fable model (strong_model contains "fable",
# case-insensitive) would otherwise queue a same-tier Fable-rechecks-Fable
# review (routed:1c2b). strong_model ABSENT/empty (legacy entry) keeps the
# conservative default: pending stays true (unknown-model errs toward the
# cheap optional recheck).
sm = re.search(r'(?m)^\s*strong_model\s*=\s*"([^"]*)"\s*$', toml_block)
strong_model = sm.group(1) if sm else ""
strong_model_is_fable = "fable" in strong_model.lower()
strong_recheck_pending = bool(last_strong_ckpt) and not fable_rechecked and not strong_model_is_fable

# id:a42e: a checkpoint annotation that merely MENTIONS "fable-standin" (e.g. a
# genuine Fable recheck describing the standin review it audited) must not
# re-trigger standin once the durable id:e030 watermark shows the recheck was
# already consumed — otherwise relay-loop.js's `standin || strongRecheckPending`
# elevation re-dispatches an idle→review on every Fable pool round.
standin = ("fable-standin" in ckpt_msg) and not fable_rechecked

open_hard_pool = base.get("open_hard_pool", 0) or 0

unit = {
    "repo": os.environ["REPO_ARG"],
    "path": os.environ["PATH_ARG"],
    "verdict": v.get("verdict", ""),
    "reason": v.get("reason", ""),
    "intensive": v.get("intensive", ""),
    # id:258d — passthrough from classify-verdict.sh's verdict.json (already produces both,
    # verbatim, for every verdict branch). Schema-safe extra fields, same treatment as
    # actionable_routine_open above.
    "priority_rank": v.get("priority_rank", 0),
    "evidence": v.get("evidence", []),
    "lastCkpt": base.get("latest_ckpt", "") or "",
    "income": income,
    "hasRoutine": bool(base.get("hasRoutine", False)),
    "openHard": open_hard_pool,
    "standin": standin,
    "is_finished": bool(base.get("is_finished", False)),
    "top_intensive": base.get("top_intensive", "") or "",
    # id:2799 — per-lane split passthrough (gather-repo-state.sh); relay-loop.js's id:ad74
    # backstop reads these instead of the lane-blind top_intensive above when patching a
    # non-idle unit's .intensive, so it never stamps an unrelated lane's resource claim.
    # Schema-safe extra fields (additional properties allowed), same as top_intensive.
    "top_intensive_routine": base.get("top_intensive_routine", "") or "",
    "top_intensive_hard": base.get("top_intensive_hard", "") or "",
    "substantive_unaudited": bool(base.get("substantive_unaudited", True)),
    "work_sig": base.get("work_sig", "") or "",
    "open_hard_pool": open_hard_pool,
    # id:7517 (routed:2d94) — the RESOLVED pool-lane ids BEHIND open_hard_pool, in ROADMAP file
    # order, computed by gather-repo-state.sh's own open_hard_pool walk (same predicate, so the
    # list and the count can never disagree). relay-loop.js's unitPrompt HANDS this list to the
    # HARD-execute child, which is FORBIDDEN from re-deriving it by grep: a child that grepped
    # only the retired "[HARD — pool]" spelling found 0 and refused 5 real bare-"[HARD]" items
    # (loderite run relay-20260814-133435-24323). Schema-safe extra field, exactly like
    # actionable_routine_ids (id:b09e) below.
    "open_hard_pool_ids": base.get("open_hard_pool_ids", []),
    "strongRecheckPending": strong_recheck_pending,
    # id:188c (relay-doctor check 10 / invariant I2) — expose the derived executor-actionable
    # [ROUTINE] count so the invalid-state detector can cross-check `verdict==execute ⟹
    # actionable_routine_open>0` (classify-verdict.sh:91 gates execute on it). Extra field is
    # schema-safe (DISCOVER_SCHEMA units allow additional properties); consumers ignore it.
    "actionable_routine_open": base.get("actionable_routine_open", 0),
    # id:b09e — the ids BEHIND that count, in ROADMAP file order. relay-loop.js's unitPrompt
    # names actionable_routine_ids[0] in the execute dispatch so the child goes straight to its
    # item instead of surveying the ledger. Schema-safe extra field (additional properties
    # allowed), same treatment as actionable_routine_open above. "" entries mark actionable
    # items that carry no id (unnameable, but still counted).
    "actionable_routine_ids": base.get("actionable_routine_ids", []),
    # id:4f9b — ROADMAP.md size in bytes, measured on the HOST (the Workflow sandbox where
    # relay-loop.js runs cannot stat a file). relay-loop.js's pre-dispatch size gate turns
    # this into "ROADMAP too large — run roadmap-archive.sh" instead of a child dying with a
    # bare `Prompt is too long`. Schema-safe extra field; 0 ⇒ unmeasured ⇒ gate fails OPEN.
    "roadmap_bytes": base.get("roadmap_bytes", 0),
    # id:7616 — [MECHANICAL] capability tier: schema-safe extra field (additional
    # properties allowed), same treatment as actionable_routine_open above. No daemon
    # consumer reads this yet (A3, gated) — it is passthrough plumbing only.
    "open_mechanical": base.get("open_mechanical", 0),
}

# id:5552 — chain-end re-ask fields, set here rather than by a `jq` stage in the caller's
# pipeline. Emitted ONLY when --chain-ended was passed, so an ordinary `--emit unit` is
# byte-identical to before (no consumer sees a new key it did not see yesterday).
if os.environ.get("CHAIN_ENDED") == "1":
    unit["chain_ended"] = True
    unit["chain_end_reason"] = os.environ.get("CHAIN_END_REASON", "")

print(json.dumps(unit))
PYEOF
