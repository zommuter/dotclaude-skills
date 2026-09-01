#!/usr/bin/env bash
# tracker/fleet-import.sh — the FLEET DRIVER for the markdown→intermediate-JSON import
# (TODO id:94ce, children-of:2bb1; meeting
# docs/meeting-notes/2026-08-10-0906-tracker-substrate-replacing-markdown-ledgers.md).
#
# Runs `tracker/ledger-map.py import` over every confirmed own repo and folds the result
# into a durable per-(repo,id) state document via `tracker/fleet-state.py upsert`.
#
# WHAT IT IS NOT: it does not touch a tracker. The meeting's ratified D4 is "markdown
# stays SSOT and NO relay script writes to a tracker" — this driver produces JSON on the
# local filesystem and stops. Pushing to Plane/Vikunja is id:90f2. The recurring
# systemd --user timer is id:f116. The repo-entity verdict is id:c17d (repos[].verdict
# stays null here).
#
# ── REPO SET ──────────────────────────────────────────────────────────────────────────
# `relay.toml`'s own-set is THE authority for both the repo list and the paths, via the
# SHARED own_repos() parser in relay/scripts/lib-own-repos.sh (honours
# `classification = "own"`, the `# path:` COMMENT override, the `paused` flag, and
# $SRC_DIR-relative defaults). NEVER a `~/src/*` glob (id:7633). own_repos()'s exit
# status is checked EXPLICITLY: a corrupt relay.toml aborts loudly and writes NOTHING,
# rather than reading as an empty fleet and tombstoning the world (id:0fa0 finding (a) —
# the exact failure this driver would amplify, since an empty fleet is indistinguishable
# from "every repo deleted every item" to a naive tombstoner).
#
# ── PINNED-SHA READ: how "a mid-run ledger edit cannot yield torn state" is achieved ──
# The run has two strictly ordered phases:
#
#   PHASE 1 (pin)   for every repo, resolve `git rev-parse HEAD` — nothing is read yet.
#   PHASE 2 (read)  for every repo, extract its ledger files with
#                   `git show <pinned-sha>:<file>` into a scratch tree, and import THAT.
#
# Ledger content is therefore never read from a working tree. It comes out of an
# IMMUTABLE commit object whose id was fixed before the first byte was read, so:
#   * an uncommitted edit made mid-run is invisible to this run (it lands next run);
#   * a COMMIT made mid-run is invisible too — HEAD moved, but the pinned sha did not;
#   * every repo in one run is read at a sha captured in the same pin phase, so the
#     fleet document is a coherent cut, not a smear across the run's wall-clock.
# The pinned sha is recorded per repo as `repos[].head_sha`, and every state change
# records the sha it was observed at (`changed_at_sha`) — so the cut is auditable.
#
# $TRACKER_IMPORT_PIN_HOOK is a TEST SEAM: if set, it is run once between phase 1 and
# phase 2. tests/test_tracker_fleet_import.sh uses it to commit a real mid-run ledger
# edit and assert the run's output still reflects the pinned sha. It has no production
# use; leave it unset.
#
# ── IDEMPOTENCE ───────────────────────────────────────────────────────────────────────
# Two consecutive runs over an unchanged fleet produce byte-identical outputs. The state
# document contains NO timestamps by construction (see tracker/fleet-state.py), and an
# unchanged item's record is CARRIED, not rewritten.
#
# ── LOUD, NEVER SILENT (id:4347) ──────────────────────────────────────────────────────
# A repo whose path is missing / is not a git repo / whose import fails becomes a
# `repo_errors[]` entry AND a stderr line, and does NOT abort the other repos
# (the control-board.sh / discover-repos-mechanical.sh precedent). Critically, such a
# repo contributes NO tombstones — see fleet-state.py rule 2. The run then exits 4.
# The mapper's own unmapped-construct counts are printed to stderr and stored in the
# state document, with a per-construct DELTA against the prior run so the lossy surface
# can be watched shrinking (tracker/SCHEMA.md §3).
#
# ── HOMONYM ALLOW-LIST (owner-decided 2026-08-10; ledger-map.py side is id:ca24) ──────
# At ~60 repos and ~4000 ids over a 65 536-token space, cross-repo 4-hex homonyms are
# expected. They are adjudicated ONE TOKEN AT A TIME in tracker/homonym-allowlist.txt
# and passed to `ledger-map.py validate` EXPLICITLY. This driver NEVER passes a blanket
# downgrade: if the on-disk ledger-map.py only offers the superseded boolean
# `--allow-homonyms` (no argument), the run ABORTS with exit 5 rather than switching
# class A off wholesale. A new, unadjudicated homonym must keep failing loudly.
# Class B (ambiguous cross-repo `routed:` edge) is never downgradable at all.
#
# Usage:
#   tracker/fleet-import.sh [--state <file>] [--out <fleet.json>] [--repo <name>]
#                           [--allowlist-file <file>] [--mirror-file <file>]
#                           [--dry-run] [-h|--help]
#
#   --mirror-file     the recorded parent/plugin MIRROR convention (id:9fa2, default
#                     tracker/mirror-tokens.txt). SEPARATE from --allowlist-file: a
#                     mirror is the SAME item on both sides of a parent/plugin pair,
#                     not two unrelated items sharing a token. Each recognised mirror
#                     is COUNTED in validate's output, never silently downgraded.
#
#   --state           durable state document (default $TRACKER_STATE or
#                     ~/.cache/relay/tracker/fleet-state.json). Written atomically.
#   --out             also write the merged fleet document here (atomically).
#   --emit-unvalidated  write --out EVEN IF validate fails. Downgrades NOTHING: the exit
#                     code is unchanged (still 3), --state is still left untouched, and
#                     every collision is still reported. It only exposes the merged
#                     DIAGNOSTIC document, which is precisely what an operator needs in
#                     order to adjudicate the collisions that made validate fail
#                     (tracker/homonym-worksheet.sh is the consumer). Requires --out.
#   --repo            restrict to ONE own-set repo (still resolved via relay.toml).
#   --allowlist-file  adjudicated homonym tokens, one 4-hex token per line, `#` comments
#                     (default tracker/homonym-allowlist.txt).
#   --dry-run         do everything except write --state / --out.
#
# Env: RELAY_TOML (default ~/.config/relay/relay.toml), SRC_DIR (default ~/src),
#      TRACKER_STATE, TRACKER_IMPORT_PIN_HOOK (test seam).
#
# Exit: 0 ok · 2 usage/missing dependency · 3 relay.toml parse failure or a FATAL
#       validate (nothing written) · 4 completed with repo errors · 5 the explicit
#       homonym allow-list surface is unavailable (see above).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LEDGER_MAP="$SCRIPT_DIR/ledger-map.py"
FLEET_STATE="$SCRIPT_DIR/fleet-state.py"
LIB_OWN_REPOS="$REPO_ROOT/relay/scripts/lib-own-repos.sh"

RELAY_TOML="${RELAY_TOML:-$HOME/.config/relay/relay.toml}"
SRC_DIR="${SRC_DIR:-$HOME/src}"
export RELAY_TOML SRC_DIR

state_file="${TRACKER_STATE:-$HOME/.cache/relay/tracker/fleet-state.json}"
out_file=""
only_repo=""
allowlist_file="$SCRIPT_DIR/homonym-allowlist.txt"
mirror_file="$SCRIPT_DIR/mirror-tokens.txt"
dry_run=0
emit_unvalidated=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state) state_file="$2"; shift 2 ;;
    --out) out_file="$2"; shift 2 ;;
    --emit-unvalidated) emit_unvalidated=1; shift ;;
    --repo) only_repo="$2"; shift 2 ;;
    --allowlist-file) allowlist_file="$2"; shift 2 ;;
    --mirror-file) mirror_file="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) sed -n '2,4p;96,112p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "fleet-import.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ "$emit_unvalidated" -eq 1 && -z "$out_file" ]]; then
  echo "fleet-import.sh: --emit-unvalidated is meaningless without --out" >&2; exit 2
fi

for f in "$LEDGER_MAP" "$FLEET_STATE" "$LIB_OWN_REPOS"; do
  [[ -f "$f" ]] || { echo "fleet-import.sh: missing dependency: $f" >&2; exit 2; }
done

# shellcheck source=../relay/scripts/lib-own-repos.sh
source "$LIB_OWN_REPOS"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# --------------------------------------------------------------------------------------
# Homonym allow-list — read + surface detection
# --------------------------------------------------------------------------------------
allow_tokens=()
if [[ -f "$allowlist_file" ]]; then
  while read -r line; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [[ -z "$line" ]] && continue
    if [[ ! "$line" =~ ^[0-9a-f]{4}$ ]]; then
      echo "fleet-import.sh: $allowlist_file: not a 4-hex id token: '$line' — refusing to guess." >&2
      exit 2
    fi
    allow_tokens+=("$line")
  done < "$allowlist_file"
fi

# Build the `validate` flags for the adjudicated tokens.
#
# The surface is the EXPLICIT per-token allow-LIST (id:ca24, owner-decided 2026-08-10),
# which supersedes the boolean `--allow-homonyms` that id:2bb1 shipped. Both of ca24's
# spellings are probed from `validate --help`, the file form first; the superseded boolean
# is REFUSED, never used as a fallback, because using it would downgrade EVERY class-A
# collision including ones no human has adjudicated. That refusal is a FAIL-CLOSED guard
# against the boolean being reintroduced, not a live code path — it is unreachable against
# the ledger-map.py in this repo today, and tests/test_tracker_fleet_import.sh reaches it
# deliberately with a stub that exposes only the boolean.
homonym_flags=()
build_homonym_flags() {
  [[ ${#allow_tokens[@]} -eq 0 ]] && return 0     # empty list ⇒ STRICT ⇒ no flag at all
  local help
  help="$(python3 "$LEDGER_MAP" validate --help 2>&1)" || {
    echo "fleet-import.sh: could not read 'ledger-map.py validate --help'" >&2; exit 2; }

  if grep -qE -- '--allow-homonym-file' <<<"$help"; then
    # id:ca24's shipped surface (SINGULAR). This is the canonical spelling.
    local f="$tmpdir/allow.txt"
    printf '%s\n' "${allow_tokens[@]}" > "$f"
    homonym_flags=(--allow-homonym-file "$f")
    return 0
  fi
  if grep -qE -- '--allow-homonym[ =]' <<<"$help"; then
    # id:ca24's repeatable per-token form (SINGULAR).
    local t
    for t in "${allow_tokens[@]}"; do homonym_flags+=(--allow-homonym "$t"); done
    return 0
  fi
  if grep -qE -- '--allow-homonyms' <<<"$help"; then
    cat >&2 <<EOF
fleet-import.sh: REFUSING to run with an adjudicated homonym allow-list.

  $LEDGER_MAP still exposes the SUPERSEDED boolean '--allow-homonyms' (no argument).
  That flag downgrades EVERY class-A cross-repo collision, including tokens nobody has
  adjudicated, which is exactly what the owner's 2026-08-10 decision removed. This
  driver will not pass it (id:ca24 replaces it with an explicit per-token allow-LIST).

  Either land id:ca24, or empty $allowlist_file and run STRICT.
EOF
    exit 5
  fi
  echo "fleet-import.sh: ledger-map.py validate exposes no homonym allow-list flag at all" >&2
  exit 5
}

# Parent/plugin MIRROR convention (id:9fa2, owner-ratified 2026-09-01). Passed as a
# SEPARATE surface from the homonym allow-list on purpose: the allow-list claims "these
# items are unrelated", which is the wrong claim for a deliberate mirror of ONE item
# across a parent repo and its plugin repo. Absence of the flag on the on-disk
# ledger-map.py is STRICTER, not laxer (the mirrors simply stay fatal), so it is a
# warning here rather than the fail-closed abort the boolean allow-list gets.
mirror_flags=()
build_mirror_flags() {
  [[ -f "$mirror_file" ]] || return 0
  grep -qE '^[[:blank:]]*[0-9a-f]{4}[[:blank:]]*$' "$mirror_file" || return 0   # empty ⇒ no flag
  local help
  help="$(python3 "$LEDGER_MAP" validate --help 2>&1)" || {
    echo "fleet-import.sh: could not read 'ledger-map.py validate --help'" >&2; exit 2; }
  if grep -qE -- '--mirror-file' <<<"$help"; then
    mirror_flags=(--mirror-file "$mirror_file")
    return 0
  fi
  echo "fleet-import.sh: $LEDGER_MAP exposes no --mirror-file surface (id:9fa2); the recorded parent/plugin mirrors in $mirror_file stay FATAL for this run." >&2
}

# --------------------------------------------------------------------------------------
# PHASE 1 — enumerate the own-set and PIN every repo's HEAD sha (no content read yet)
# --------------------------------------------------------------------------------------
own_file="$tmpdir/own.tsv"
own_rc=0
own_repos > "$own_file" || own_rc=$?
if [[ "$own_rc" -ne 0 ]]; then
  echo "fleet-import.sh: FAILED to parse relay.toml ($RELAY_TOML), rc=$own_rc — own-repo enumeration aborted; NOTHING written. An unparseable registry is NOT an empty fleet." >&2
  exit 3
fi

pinned="$tmpdir/pinned.tsv"   # name \t path \t sha
: > "$pinned"
errors_jsonl="$tmpdir/errors.jsonl"
: > "$errors_jsonl"

record_error() {   # $1=repo $2=path $3=reason
  echo "fleet-import.sh: repo-error [$1]: $3" >&2
  REPO="$1" RPATH="$2" REASON="$3" python3 -c '
import json, os
print(json.dumps({"repo": os.environ["REPO"], "path": os.environ["RPATH"],
                  "reason": os.environ["REASON"]}, sort_keys=True))
' >> "$errors_jsonl"
}

n_seen=0
while IFS=$'\t' read -r name path; do
  [[ -z "$name" ]] && continue
  if [[ -n "$only_repo" && "$name" != "$only_repo" ]]; then continue; fi
  n_seen=$((n_seen + 1))
  if [[ ! -d "$path" ]]; then
    record_error "$name" "$path" "path does not exist"
    continue
  fi
  sha=""
  if ! sha="$(git -C "$path" rev-parse HEAD 2>>"$tmpdir/git.err")"; then
    record_error "$name" "$path" "not a git repo, or HEAD unresolvable (see stderr above)"
    continue
  fi
  printf '%s\t%s\t%s\n' "$name" "$path" "$sha" >> "$pinned"
done < "$own_file"

if [[ -n "$only_repo" && "$n_seen" -eq 0 ]]; then
  echo "fleet-import.sh: --repo '$only_repo' is not a confirmed own repo in $RELAY_TOML" >&2
  exit 2
fi
[[ -s "$tmpdir/git.err" ]] && cat "$tmpdir/git.err" >&2

# TEST SEAM (documented above): a real mid-run ledger edit happens HERE, after every sha
# is pinned and before a single byte of ledger content is read.
if [[ -n "${TRACKER_IMPORT_PIN_HOOK:-}" ]]; then
  echo "fleet-import.sh: running TRACKER_IMPORT_PIN_HOOK (test seam) after the pin phase" >&2
  bash -c "$TRACKER_IMPORT_PIN_HOOK"
fi

# --------------------------------------------------------------------------------------
# PHASE 2 — read each repo's ledgers AT ITS PINNED SHA and import
# --------------------------------------------------------------------------------------
LEDGERS=(TODO.md TODO.archive.md ROADMAP.md ROADMAP.archive.md REVIEW_ME.md REVIEW_ME.archive.md)

docs=()
while IFS=$'\t' read -r name path sha; do
  [[ -z "$name" ]] && continue
  tree="$tmpdir/trees/$name"
  mkdir -p "$tree"
  n_files=0
  for f in "${LEDGERS[@]}"; do
    # `ls-tree` first, so a MISSING ledger (normal) is distinguished from a git failure
    # (loud) without swallowing stderr anywhere.
    if [[ -n "$(git -C "$path" ls-tree -r --name-only "$sha" -- "$f")" ]]; then
      if ! git -C "$path" show "$sha:$f" > "$tree/$f"; then
        record_error "$name" "$path" "git show $sha:$f failed"
        continue
      fi
      n_files=$((n_files + 1))
    fi
  done
  if [[ "$n_files" -eq 0 ]]; then
    # Not an error: a repo may legitimately carry no ledger at this sha. It still counts
    # as a SUCCESSFUL import (empty), so its items — if the state store holds any — are
    # correctly tombstoned rather than retained.
    echo "fleet-import.sh: note [$name]: no ledger files at $sha" >&2
  fi
  raw="$tmpdir/$name.raw.json"
  if ! python3 "$LEDGER_MAP" import "$name" "$tree" > "$raw"; then
    record_error "$name" "$path" "ledger-map.py import failed"
    continue
  fi
  # Rewrite the repo entity: ledger-map.py records `path` AS GIVEN (the scratch tree),
  # which would churn on every run and break idempotence. The authority for the path is
  # relay.toml, and the pinned sha is what makes the read reproducible — record both.
  doc="$tmpdir/$name.json"
  RPATH="$path" SHA="$sha" python3 -c '
import json, os, sys
d = json.load(open(sys.argv[1]))
for r in d["repos"]:
    r["path"] = os.environ["RPATH"]
    r["head_sha"] = os.environ["SHA"]
print(json.dumps(d, indent=2, ensure_ascii=False, sort_keys=True))
' "$raw" > "$doc"
  docs+=("$doc")
done < "$pinned"

# --------------------------------------------------------------------------------------
# Merge → validate (with the EXPLICIT allow-list) → upsert
# --------------------------------------------------------------------------------------
fleet="$tmpdir/fleet.json"
if [[ ${#docs[@]} -eq 0 ]]; then
  # No repo imported. That is either an empty own-set or a total failure; either way it
  # is NOT evidence that every item was deleted, and fleet-state.py's rule 2 keeps every
  # prior record (no repo appears in repos[], so nothing may be tombstoned).
  echo "fleet-import.sh: NO repo imported — writing an empty fleet document; no item can be tombstoned from it." >&2
  python3 -c '
import json
print(json.dumps({"schema_version": __import__("sys").argv[1], "repos": [], "items": [],
                  "unmapped": [], "unmapped_counts": {}}, indent=2, sort_keys=True))
' "$(python3 -c 'import re,sys; print(re.search(r"SCHEMA_VERSION = \"([^\"]+)\"", open(sys.argv[1]).read()).group(1))' "$LEDGER_MAP")" > "$fleet"
else
  python3 "$LEDGER_MAP" merge "${docs[@]}" > "$fleet"
fi

build_homonym_flags
build_mirror_flags

run_validate() {
  local rc=0
  python3 "$LEDGER_MAP" validate "${homonym_flags[@]+"${homonym_flags[@]}"}" \
    "${mirror_flags[@]+"${mirror_flags[@]}"}" "$fleet" \
    > "$tmpdir/val.out" 2> "$tmpdir/val.err" || rc=$?
  return "$rc"
}

publish_out() {   # atomic publish of the merged fleet document to $out_file
  mkdir -p "$(dirname "$out_file")"
  cp "$fleet" "$out_file.tmp.$$"
  mv -f "$out_file.tmp.$$" "$out_file"
}

val_rc=0
run_validate || val_rc=$?
cat "$tmpdir/val.err" >&2 || true
if [[ "$val_rc" -ne 0 ]]; then
  if [[ "$emit_unvalidated" -eq 1 && "$dry_run" -eq 0 ]]; then
    publish_out
    echo "fleet-import.sh: --emit-unvalidated: wrote the UNVALIDATED merged document to $out_file (diagnostic only — it did NOT pass validate)." >&2
  fi
  echo "fleet-import.sh: validate FAILED (rc=$val_rc) — NOTHING written to $state_file. A cross-repo collision that is not on $allowlist_file must be adjudicated, not switched off." >&2
  exit 3
fi
cat "$tmpdir/val.out"

# repo_errors as a JSON array
python3 -c '
import json, sys
print(json.dumps([json.loads(l) for l in open(sys.argv[1]) if l.strip()]))
' "$errors_jsonl" > "$tmpdir/errors.json"

allow_csv=""
[[ ${#allow_tokens[@]} -gt 0 ]] && allow_csv="$(IFS=,; echo "${allow_tokens[*]}")"

next_state="$tmpdir/state.next.json"
python3 "$FLEET_STATE" upsert --fleet "$fleet" --state "$state_file" \
  --allowlist "$allow_csv" --errors "$tmpdir/errors.json" > "$next_state"

# --- loud-lossy report, with a delta against the prior state --------------------------
PRIOR="$state_file" NEXT="$next_state" python3 - <<'PY' >&2
import json, os
nxt = json.load(open(os.environ["NEXT"]))
prior = {}
p = os.environ["PRIOR"]
if os.path.exists(p):
    try:
        prior = json.load(open(p)).get("unmapped_counts", {})
    except (ValueError, OSError) as e:
        print("fleet-import: prior state unreadable for the lossy delta (%s) — "
              "reporting absolute counts only" % e)
counts = nxt.get("unmapped_counts", {})
if not counts:
    print("fleet-import: loud-lossy report: NO unmapped constructs")
else:
    parts = []
    for k in sorted(counts):
        d = counts[k] - prior.get(k, 0)
        parts.append("%s=%d(%+d)" % (k, counts[k], d) if prior else "%s=%d" % (k, counts[k]))
    print("fleet-import: loud-lossy report (construct=count(delta)): " + ", ".join(parts))
for k in sorted(set(prior) - set(counts)):
    print("fleet-import: loud-lossy construct %r went to ZERO (was %d)" % (k, prior[k]))
live = sum(1 for r in nxt["items"] if r["state"] == "live")
dead = len(nxt["items"]) - live
print("fleet-import: %d repo(s), %d live item(s), %d tombstone(s), %d repo error(s)"
      % (len(nxt["repos"]), live, dead, len(nxt["repo_errors"])))
PY

if [[ "$dry_run" -eq 1 ]]; then
  echo "fleet-import.sh: --dry-run — no file written" >&2
else
  # Atomic publish: write to a sibling temp file and rename(2). A crash or a full disk
  # therefore leaves the PREVIOUS state intact rather than a truncated document — the
  # "a failed pass never leaves partial state" half of the contract.
  mkdir -p "$(dirname "$state_file")"
  cp "$next_state" "$state_file.tmp.$$"
  mv -f "$state_file.tmp.$$" "$state_file"
  if [[ -n "$out_file" ]]; then
    publish_out
  fi
fi

if [[ -s "$errors_jsonl" ]]; then
  echo "fleet-import.sh: completed WITH repo errors (see above) — those repos contributed no tombstones." >&2
  exit 4
fi
exit 0
