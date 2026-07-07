#!/usr/bin/env bash
# relay-doctor.sh — a thin, REPORT-ONLY aggregator of the already-built mechanical
# relay-health checks (the CHEAP-FIRST-SLICE of id:0907, tracked as child id:9bec).
#
# WHY (id:0907, 2026-06-24): the 2026-06-23 `/relay --afk` session stumbled onto SIX
# latent relay-plumbing defects that no STANDING check would have surfaced. The full
# relay-health design (id:0907, [HARD — meeting]) — its HOME (standalone vs `/relay
# health` vs a `review` step), CADENCE, and FAIL-LOUD-vs-REPORT-ONLY policy — is
# DESIGN JUDGMENT and is DELIBERATELY OUT OF SCOPE here. This script builds ONLY the
# cheap slice id:0907 names: run the checks that are ALREADY built + now un-gated
# (their gate items id:09a3 roadmap-lint / id:69ef refs-install / id:000d is_finished
# are all done) and collate them into ONE readable report. It REIMPLEMENTS NOTHING —
# it is a thin orchestrator that CALLS the existing scripts.
#
# REPORT-ONLY (deliberate, id:0907 deferred decision): this script PRINTS each check's
# findings and a summary, and EXITS 0 EVEN WHEN CHECKS FIND ISSUES. The fail-loud vs
# report-only choice is the deferred `[HARD — meeting]` part of id:0907 — NOT decided
# here; we default to report-only and say so. The ONLY nonzero exits are MISUSE
# (bad args / an unknown or unreadable scope) — never a "check found a problem" exit.
#
# Checks aggregated (each CALLS the canonical script, never duplicates its logic):
#   1. cross-ledger drift   — meeting/orphan-scan.sh --cross-ledger   (per-repo)
#   2. ROADMAP grammar/lane — relay/scripts/roadmap-lint.sh           (per-repo, id:09a3)
#   3. reference-install     — every relay/references/*.md is in the Makefile relay_FILES
#                              manifest (reuses the id:69ef check mechanism — a static
#                              read of THIS repo's Makefile; cross-repo-irrelevant so it
#                              runs ONCE)
#   4. parked orphan sweep   — relay/scripts/relay-reconcile.sh --all (cross-repo)
#   5. lane/dispatch coverage — DERIVED from check 2: roadmap-lint already LOUD-rejects
#                              every open `- [ ]` item that is not [ROUTINE] or a
#                              recognized [HARD — <lane>] (i.e. not dispatchable AND not
#                              explicitly surfaced); its findings ARE the coverage report.
#   6. un-promoted backlog   — relay/scripts/unpromoted-scan.sh (per-repo, id:2dea):
#                              open TODO.md ids with no ROADMAP twin, lane-tag-AGNOSTIC,
#                              so a closed-ROADMAP/open-TODO repo reads "needs handoff",
#                              not "drained" (the truncocraft miss).
#
# Usage:
#   relay-doctor.sh [SCOPE]
#     (no arg)   → the cwd repo (git rev-parse --show-toplevel)
#     <repo-dir> → that repo
#     --all      → every relay.toml `classification = "own"` repo (reads
#                  $RELAY_TOML, honors `# path:` overrides, like the other scripts)
#   An UNKNOWN scope token / unreadable scope path is a LOUD reject (nonzero exit).
#
# Conventions (study relay-reconcile.sh / gather-repo-state.sh): set -euo pipefail;
# short stdout; `2>/dev/null` ONLY with a stated reason; a missing/unreadable repo is
# SURFACED on stderr, never silently swallowed (id:4e14). Details → ~/.claude/logs.
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROADMAP_LINT="$SCRIPTS_DIR/roadmap-lint.sh"
RECONCILE="$SCRIPTS_DIR/relay-reconcile.sh"
UNPROMOTED_SCAN="$SCRIPTS_DIR/unpromoted-scan.sh"      # id:2dea — lane-tag-agnostic un-promoted backlog
TODO_CONFORMANCE="$SCRIPTS_DIR/todo-conformance.sh"    # id:3441 — TODO grammar (no work hides in a malformed line)
CLEAN_TREE_GATE="$SCRIPTS_DIR/clean-tree-gate.sh"      # id:8018 — main-checkout residue detector (invariant I1/I7)
CLASSIFY_REPO="$SCRIPTS_DIR/classify-repo.sh"          # id:188c — verdict-invariant replay (invariant I2/I4)
# Overrides so a hermetic test can substitute a stub emitting a crafted unit (the I2/I4
# invariants are maintained by construction in the real pipeline, so a violation can only be
# produced via a stub — same override idiom as RELAY_DOCTOR_ORPHAN_SCAN above).
CLASSIFY_REPO="${RELAY_DOCTOR_CLASSIFY_REPO:-$CLASSIFY_REPO}"
CLEAN_TREE_GATE="${RELAY_DOCTOR_CLEAN_TREE_GATE:-$CLEAN_TREE_GATE}"
REPO_ROOT="$(cd "$SCRIPTS_DIR/../.." && pwd)"          # dotclaude-skills repo root
ORPHAN_SCAN="$REPO_ROOT/meeting/orphan-scan.sh"
# Allow an override so the orphan-scan path resolves when installed via symlink too.
ORPHAN_SCAN="${RELAY_DOCTOR_ORPHAN_SCAN:-$ORPHAN_SCAN}"

LOG="${RELAY_DOCTOR_LOG:-$HOME/.claude/logs/relay-doctor.log}"

# recipe drop-dir — same env override as mechanical-daemon.sh / recipe-manifest.md, so a
# hermetic test can point it at a mktemp -d root instead of the real ~/.config/relay/recipes.
RELAY_RECIPE_DIR="${RELAY_RECIPE_DIR:-$HOME/.config/relay/recipes}"

# relay.toml location — same default + env override as the sibling scripts.
SRC_DIR="${SRC_DIR:-$HOME/src}"
RELAY_TOML="${RELAY_TOML:-$HOME/.config/relay/relay.toml}"

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true   # best-effort: never fail on a log dir
log() { printf '%s relay-doctor.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

# --- own repos from relay.toml (same parser as relay-reconcile.sh) -------------
# Honors `classification = "own"`, `# path:` comment overrides, the `paused` flag.
# Outputs lines of "<name>\t<path>".
own_repos() {
  [[ -f "$RELAY_TOML" ]] || return 0
  SRC_DIR="$SRC_DIR" python3 -c '
import os, re, sys, tomllib
src = os.environ["SRC_DIR"]
toml_path = sys.argv[1]
with open(toml_path, "rb") as f:
    data = tomllib.load(f)

# Recover the `# path:` COMMENT override per repo (tomllib drops comments).
comment_path = {}
cur = None
sect_re = re.compile(r"^\s*\[repos\.([^\]]+)\]\s*$")
path_re  = re.compile(r"^\s*#\s*path:\s*(.+?)\s*$")
with open(toml_path, encoding="utf-8") as f:
    for line in f:
        m = sect_re.match(line)
        if m:
            cur = m.group(1)
            continue
        if cur:
            pm = path_re.match(line)
            if pm and cur not in comment_path:
                comment_path[cur] = pm.group(1)

def expand(p):
    return os.path.expanduser(os.path.expandvars(p))

for name, entry in data.get("repos", {}).items():
    if entry.get("classification") != "own":
        continue
    if entry.get("paused"):
        continue
    path = entry.get("path") or comment_path.get(name) or os.path.join(src, name)
    print(f"{name}\t{expand(path)}")
' "$RELAY_TOML"
}

# --- parse args ----------------------------------------------------------------
scope="cwd"
repo_arg=""
strict=0   # id:a883 — opt-in strict mode: exits nonzero when any issue is found
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)     scope="all"; shift ;;
    --strict)  strict=1; shift ;;   # id:a883 — nonzero exit when issues found
    -h|--help) sed -n '2,52p' "$0"; exit 0 ;;
    --*)       echo "relay-doctor.sh: unknown flag '$1'" >&2; exit 2 ;;
    *)
      if [[ -n "$repo_arg" ]]; then
        echo "relay-doctor.sh: only one repo path may be given (got extra '$1')" >&2
        exit 2
      fi
      repo_arg="$1"; scope="repo"; shift ;;
  esac
done

# --- per-repo check runner -----------------------------------------------------
# Runs the per-repo checks against ONE repo path; accumulates issue counts into the
# globals issues_total / repos_with_issues. Surfaces an unreadable repo on stderr.
issues_total=0
repos_with_issues=0

check_repo() {
  local name="$1" path="$2"
  local repo_issues=0

  if [[ ! -d "$path" ]]; then
    printf 'ERROR: %s — path not found (%s); cannot health-check.\n' "$name" "$path" >&2
    log "repo=$name path-missing=$path"
    return 1
  fi
  if ! git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
    printf 'ERROR: %s (%s) is not a readable git repo — check the path override in relay.toml.\n' "$name" "$path" >&2
    log "repo=$name not-git=$path"
    return 1
  fi

  echo "=== repo: $name ($path) ==="

  # --- check 1: cross-ledger TODO↔ROADMAP checkbox drift ----------------------
  echo "--- cross-ledger drift (orphan-scan.sh --cross-ledger) ---"
  if [[ -x "$ORPHAN_SCAN" ]]; then
    # orphan-scan exits 0 regardless; capture its candidate lines.
    local xl
    xl="$(bash "$ORPHAN_SCAN" --cross-ledger "$path" 2>>"$LOG" || true)"
    xl="$(printf '%s' "$xl" | grep -v '^[[:space:]]*$' || true)"
    if [[ -n "$xl" ]]; then
      printf '%s\n' "$xl"
      local n; n="$(printf '%s\n' "$xl" | grep -c 'id:' || true)"
      repo_issues=$((repo_issues + n))
    else
      echo "clean (no cross-ledger checkbox drift)"
    fi
  else
    echo "SKIP — orphan-scan.sh not found at $ORPHAN_SCAN" >&2
  fi

  # --- check 2 + 5: ROADMAP grammar / lane-dispatch coverage ------------------
  echo "--- ROADMAP grammar + lane/dispatch coverage (roadmap-lint.sh) ---"
  if [[ -x "$ROADMAP_LINT" ]]; then
    if [[ -f "$path/ROADMAP.md" ]]; then
      # roadmap-lint exits nonzero on violations; report-only here — capture + show.
      local lint rc
      lint="$(bash "$ROADMAP_LINT" "$path" 2>>"$LOG")" && rc=0 || rc=$?
      if [[ "$rc" -ne 0 ]]; then
        printf '%s\n' "$lint"
        # roadmap-lint's first line says "<N> open ROADMAP item(s) violate…"
        local n; n="$(printf '%s\n' "$lint" | grep -oP '^roadmap-lint: \K[0-9]+' | head -1 || true)"
        [[ -n "$n" ]] && repo_issues=$((repo_issues + n)) || repo_issues=$((repo_issues + 1))
      else
        echo "clean (every open item carries a recognized lane tag + id)"
      fi
    else
      echo "no ROADMAP.md — not relay-managed; grammar check skipped"
    fi
  else
    echo "SKIP — roadmap-lint.sh not found at $ROADMAP_LINT" >&2
  fi

  # --- check 6: un-promoted TODO backlog (id:2dea) ----------------------------
  # LANE-TAG-AGNOSTIC: open TODO.md ids with no ROADMAP twin. A closed-ROADMAP /
  # open-TODO repo surfaces "N un-promoted — needs a handoff pass" INSTEAD of reading
  # as "drained". The truncocraft miss (2026-06-25, 2nd instance of id:78ff).
  echo "--- un-promoted TODO backlog (unpromoted-scan.sh, id:2dea) ---"
  if [[ -x "$UNPROMOTED_SCAN" ]]; then
    local up
    up="$(bash "$UNPROMOTED_SCAN" "$path" 2>>"$LOG" || true)"
    up="$(printf '%s' "$up" | grep -vE '^[[:space:]]*$' || true)"
    if [[ -n "$up" ]]; then
      local nprom nsurf nuntr ntot ropen
      nprom="$(printf '%s\n' "$up" | grep -cP '\tpromote\t' || true)"
      nsurf="$(printf '%s\n' "$up" | grep -cP '\tsurface\t' || true)"
      nuntr="$(printf '%s\n' "$up" | grep -cP '\tuntracked\t' || true)"
      ntot=$((nprom + nsurf + nuntr))
      # The truncocraft signal is DRAINED-ROADMAP + open-TODO, NOT raw un-promoted count:
      # in a design-ledger repo most TODO items are deliberately never promoted, so an
      # open ROADMAP means the un-promoted list is informational backlog, not drift.
      ropen="$(grep -cE '^- \[[ ]\] ' "$path/ROADMAP.md" 2>/dev/null || true)"
      ropen="${ropen:-0}"
      if [[ "$ropen" -eq 0 ]]; then
        # DRAINED ROADMAP but open TODO — the repo is NOT drained; it needs a handoff pass.
        printf '%s\n' "$up"
        printf 'ROADMAP is DRAINED (0 open items) but TODO has %s un-promoted item(s) — repo is NOT drained, needs a HANDOFF pass (%s promote, %s surface, %s untracked/no-id).\n' \
          "$ntot" "$nprom" "$nsurf" "$nuntr"
        repo_issues=$((repo_issues + ntot))
      else
        # Active design ledger: list is informational; run unpromoted-scan.sh for it.
        printf 'ROADMAP has %s open item(s); %s open TODO item(s) lack a ROADMAP twin (%s promote, %s surface, %s untracked) — informational handoff-C2 backlog, NOT counted as drift. Run unpromoted-scan.sh %s for the list.\n' \
          "$ropen" "$ntot" "$nprom" "$nsurf" "$nuntr" "$path"
      fi
    else
      echo "clean (every open TODO id has a ROADMAP twin)"
    fi
  else
    echo "SKIP — unpromoted-scan.sh not found at $UNPROMOTED_SCAN" >&2
  fi

  # --- check 7: TODO grammar conformance (id:3441) ----------------------------
  # Surfaces every non-conforming TODO.md line (bare prose, checkbox-less bullet,
  # open item missing an id) so no work hides in a malformed line. REPORT-ONLY here
  # (never blocks); `todo-conformance.sh --fix` (run by review/handoff) auto-fixes the
  # safe missing-id class. orphan lines are surfaced for a human, never fabricated.
  echo "--- TODO grammar conformance (todo-conformance.sh, id:3441) ---"
  if [[ -x "$TODO_CONFORMANCE" ]]; then
    if [[ -f "$path/TODO.md" ]]; then
      local tc
      tc="$(bash "$TODO_CONFORMANCE" "$path/TODO.md" 2>>"$LOG" || true)"
      tc="$(printf '%s' "$tc" | grep -vE '^[[:space:]]*$' || true)"
      if [[ -n "$tc" ]]; then
        local nmiss norph
        nmiss="$(printf '%s\n' "$tc" | grep -cP '^missing-id\t' || true)"
        norph="$(printf '%s\n' "$tc" | grep -cP '^orphan\t' || true)"
        printf '%s\n' "$tc"
        printf '%s non-conforming TODO line(s): %s missing-id (auto-fixable via --fix), %s orphan (surface — fix or annotate <!-- lint-ok -->)\n' \
          "$((nmiss + norph))" "$nmiss" "$norph"
        repo_issues=$((repo_issues + nmiss + norph))
      else
        echo "clean (every TODO line is a header, comment, or well-formed id'd item)"
      fi
    else
      echo "no TODO.md — nothing to grammar-check"
    fi
  else
    echo "SKIP — todo-conformance.sh not found at $TODO_CONFORMANCE" >&2
  fi

  # --- check 9: main-checkout residue (invariant I1/I7, id:8018) ---------------
  # Seed invalid-state (i): a gate-detection/handback path can strand an uncommitted ledger
  # edit on the main checkout (loderite id:3801 residue). Reuse clean-tree-gate.sh (the
  # deterministic porcelain observer, id:aa93) — a dirty entry is foreign residue UNLESS it is
  # lock-only (a benign uv.lock/*.lock relock the pool commits in place, id:bae5). Report-only.
  echo "--- main-checkout residue (clean-tree-gate.sh, I1/I7, id:8018) ---"
  if [[ -x "$CLEAN_TREE_GATE" ]]; then
    local ctg rc9
    ctg="$(bash "$CLEAN_TREE_GATE" "$path" 2>>"$LOG")" && rc9=0 || rc9=$?
    if [[ "$rc9" -eq 0 ]]; then
      echo "clean (main checkout has no uncommitted residue)"
    else
      # clean-tree-gate printed "dirty <N>" then the offending porcelain lines (each "  XY path").
      # Keep only NON-lock entries: lock-only dirty is the pool's own benign in-place relock.
      local resid
      resid="$(printf '%s\n' "$ctg" | grep -E '^  ' | while IFS= read -r ln; do
        p="${ln##*[[:space:]]}"
        case "$(basename "$p")" in
          *.lock|package-lock.json|pnpm-lock.yaml|yarn.lock) ;;
          *) printf '%s\n' "$ln" ;;
        esac
      done)"
      if [[ -n "$resid" ]]; then
        local n9; n9="$(printf '%s\n' "$resid" | grep -cE '^  ' || true)"
        printf 'RESIDUE — %s uncommitted non-lock entry(ies) on the main checkout (foreign/stranded ledger edit — invariant I1/I7):\n' "$n9"
        printf '%s\n' "$resid"
        repo_issues=$((repo_issues + n9))
      else
        echo "clean (dirty-lock-only — benign in-place relock, not residue)"
      fi
    fi
  else
    echo "SKIP — clean-tree-gate.sh not found at $CLEAN_TREE_GATE" >&2
  fi

  # --- check 10: verdict-invariant replay (invariant I2/I4, id:188c) -----------
  # Seed invalid-state (ii): `execute` on a repo with no executor-actionable work. Replay
  # classify-repo.sh --emit unit (side-effect-free) and cross-check the verdict (classify-
  # verdict.sh) against the derived count (classify-repo.sh) — two DIFFERENT scripts, so this
  # catches the part-1 gate-wiring bug class. COVERAGE (honest): guards verdict↔derivation
  # CONSISTENCY, not derivation CORRECTNESS (a bug shared by both is out of reach — the
  # relay-events.jsonl real-dispatched-verdict read is the noted future upgrade).
  echo "--- verdict-invariant replay (classify-repo.sh --emit unit, I2/I4, id:188c) ---"
  if [[ -x "$CLASSIFY_REPO" ]]; then
    local unit rc10
    unit="$(RELAY_TOML="$RELAY_TOML" bash "$CLASSIFY_REPO" --emit unit --repo "$name" --path "$path" 2>>"$LOG")" && rc10=0 || rc10=$?
    if [[ "$rc10" -ne 0 || -z "$unit" ]]; then
      echo "SKIP — classify-repo.sh --emit unit did not emit a unit (see $LOG)" >&2
    else
      local v10
      v10="$(printf '%s' "$unit" | python3 -c '
import sys, json
u = json.load(sys.stdin)
verdict = u.get("verdict", "")
intensive = u.get("intensive", "") or ""
aro = u.get("actionable_routine_open", 0) or 0
issues = []
if verdict == "execute" and aro <= 0:
    issues.append("I2 VIOLATED: verdict=execute but actionable_routine_open=" + str(aro) + " (execute-on-no-work; classify-verdict.sh gates execute on it)")
if intensive and verdict not in ("execute", "hard"):
    issues.append("I4 VIOLATED: intensive=" + repr(intensive) + " but verdict=" + repr(verdict) + " (INTENSIVE operative only on dispatchable lanes; id:5ac6)")
disp = intensive if intensive else "-"
print("\n".join(issues) if issues else "OK verdict=" + verdict + " actionable_routine_open=" + str(aro) + " intensive=" + disp)
' 2>>"$LOG" || echo "ERR — could not parse unit")"
      if printf '%s' "$v10" | grep -q 'VIOLATED'; then
        printf '%s\n' "$v10"
        local n10; n10="$(printf '%s\n' "$v10" | grep -c 'VIOLATED' || true)"
        repo_issues=$((repo_issues + n10))
      else
        printf '%s (guards consistency, not derivation-correctness)\n' "$v10"
      fi
    fi
  else
    echo "SKIP — classify-repo.sh not found at $CLASSIFY_REPO" >&2
  fi

  # --- check 11: last_ckpt tag existence (invariant I8, id:333c) ---------------
  # The integrator writes each own repo's last_ckpt (relay-loop.js:1426); a failed push /
  # aborted tag can desync it. A dangling last_ckpt is an invalid state rev-parse catches.
  echo "--- last_ckpt tag existence (invariant I8, id:333c) ---"
  local lckpt
  lckpt="$(python3 - "$RELAY_TOML" "$name" <<'PY' 2>>"$LOG" || true
import sys, tomllib
try:
    d = tomllib.load(open(sys.argv[1], "rb"))
except Exception:
    sys.exit(0)
print(d.get("repos", {}).get(sys.argv[2], {}).get("last_ckpt", "") or "")
PY
)"
  if [[ -z "$lckpt" ]]; then
    echo "clean (no last_ckpt recorded — not yet checkpointed)"
  elif git -C "$path" rev-parse --verify -q "refs/tags/$lckpt" >/dev/null 2>&1; then
    echo "clean (last_ckpt $lckpt resolves to a tag)"
  else
    printf 'DANGLING — relay.toml last_ckpt=%s names a tag that does NOT exist in %s (invariant I8; a failed push / aborted tag desynced it).\n' "$lckpt" "$name"
    repo_issues=$((repo_issues + 1))
  fi

  # --- check 12: mechanical-orphan (id:1bd1) ----------------------------------
  # handoff.md:77-92 names the failure mode: tagging an item `[MECHANICAL]` alone
  # routes it to the pool-inert `mechanical` verdict, but WITHOUT an authored recipe
  # in the drop-dir (recipe-manifest.md) nothing ever runs it — it sits silently
  # forever. Detect: for every OPEN `- [ ]` ROADMAP item carrying `[MECHANICAL]`,
  # pull its `<!-- id:XXXX -->` token and check whether ANY recipe JSON in
  # pending/, running/, or done/ has a top-level `id` field matching it (the `id`
  # field is the recipe schema's only explicit id-linkage, per recipe-manifest.md —
  # NOT filename, which is unconstrained). A recipe already consumed and moved to
  # done/ still counts (the item WAS fed); only "no recipe anywhere" is an orphan.
  echo "--- mechanical-orphan (recipe drop-dir vs [MECHANICAL] ROADMAP items, id:1bd1) ---"
  if [[ -f "$path/ROADMAP.md" ]]; then
    local mech_orphans
    mech_orphans="$(python3 - "$path/ROADMAP.md" "$RELAY_RECIPE_DIR" <<'PY' 2>>"$LOG" || true
import glob, json, os, re, sys

roadmap_path, recipe_dir = sys.argv[1], sys.argv[2]

open_ids = []
with open(roadmap_path, encoding="utf-8") as f:
    for line in f:
        # only top-level OPEN items, and only ones tagged [MECHANICAL]
        if not re.match(r"^\s*-\s\[\s\]\s", line):
            continue
        if "[MECHANICAL]" not in line:
            continue
        m = re.search(r"<!--\s*id:([0-9a-fA-F]{4})\s*-->", line)
        if m:
            open_ids.append(m.group(1))

fed_ids = set()
for sub in ("pending", "running", "done"):
    for fp in glob.glob(os.path.join(recipe_dir, sub, "*.json")):
        try:
            with open(fp, encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            continue
        rid = data.get("id")
        if isinstance(rid, str) and rid:
            fed_ids.add(rid)

for oid in open_ids:
    if oid not in fed_ids:
        print(oid)
PY
)"
    if [[ -n "$mech_orphans" ]]; then
      local moid
      while IFS= read -r moid; do
        [[ -n "$moid" ]] || continue
        printf '⚠️ [MECHANICAL] item id:%s has no authored recipe in %s/{pending,running,done} — it will never run (author its A2 recipe per handoff.md).\n' "$moid" "$RELAY_RECIPE_DIR"
        repo_issues=$((repo_issues + 1))
      done <<<"$mech_orphans"
    else
      echo "clean (every open [MECHANICAL] item has an authored recipe somewhere in the drop-dir)"
    fi
  else
    echo "no ROADMAP.md — nothing to check for mechanical-orphans"
  fi

  if [[ "$repo_issues" -gt 0 ]]; then
    repos_with_issues=$((repos_with_issues + 1))
    issues_total=$((issues_total + repo_issues))
  fi
  echo "repo $name: $repo_issues issue(s)"
  echo
  log "repo=$name issues=$repo_issues"
  return 0
}

# --- check 3: reference-install completeness (id:69ef mechanism) ----------------
# This is a STATIC read of THIS repo's Makefile + relay/references; it is cross-repo
# irrelevant (it audits the dotclaude-skills install manifest, not the scanned repo),
# so it runs ONCE regardless of scope. Reuses the SAME mechanism the id:69ef test
# (tests/test_relay_refs_install_complete.sh) verifies — not a second copy of logic.
refs_install_check() {
  echo "=== reference-install completeness (id:69ef) ==="
  local mk="$REPO_ROOT/Makefile"
  local refs="$REPO_ROOT/relay/references"
  if [[ ! -f "$mk" || ! -d "$refs" ]]; then
    echo "SKIP — Makefile or relay/references not found under $REPO_ROOT" >&2
    echo
    return 0
  fi
  # Join the backslash-continued relay_FILES := … manifest (same awk as the id:69ef test).
  local manifest
  manifest="$(awk '
    /^relay_FILES[[:space:]]*:=/ { cap=1 }
    cap {
      line=$0
      cont=(line ~ /\\[[:space:]]*$/)
      sub(/\\[[:space:]]*$/, "", line)
      printf "%s ", line
      if (!cont) exit
    }
  ' "$mk")"
  if [[ -z "$manifest" ]]; then
    echo "WARN — could not find a relay_FILES := manifest in $mk" >&2
    echo
    return 0
  fi
  local missing=0 f base
  for f in "$refs"/*.md; do
    [[ -e "$f" ]] || continue
    base="references/$(basename "$f")"
    if ! grep -qF -- "$base" <<<"$manifest"; then
      printf 'MISSING: %s is not in the Makefile relay_FILES manifest (will not be installed)\n' "$base"
      missing=$((missing + 1))
    fi
  done
  if [[ "$missing" -gt 0 ]]; then
    issues_total=$((issues_total + missing))
    echo "$missing reference doc(s) absent from the install manifest"
  else
    echo "clean (every relay/references/*.md is in relay_FILES)"
  fi
  echo
  log "refs-install missing=$missing"
}

# --- check 5: quota-config sanity (id:a883) ------------------------------------
# Validates RELAY_QUOTA_DECAY_7D direction (START < END) and quota threshold bounds
# (0 < threshold ≤ 1). Reads from $RELAY_QUOTA_DECAY_7D env var (same as relay-loop.js).
# Report-only by default; contributes to issues_total so --strict can gate on it.
quota_config_check() {
  echo "=== quota-config sanity (id:a883) ==="
  local q_issues=0

  # RELAY_QUOTA_DECAY_7D: must be START:END with START < END (spend-conserving-then-use-it-up).
  local decay="${RELAY_QUOTA_DECAY_7D:-}"
  if [[ -n "$decay" ]]; then
    local start end
    if [[ "$decay" =~ ^([0-9]*\.?[0-9]+):([0-9]*\.?[0-9]+)$ ]]; then
      start="${BASH_REMATCH[1]}"
      end="${BASH_REMATCH[2]}"
      # python3 for reliable float comparison (bash only does integers)
      local cmp
      cmp="$(python3 -c "
s, e = float('$start'), float('$end')
if s >= e:
    print('BAD')
elif not (0 < s <= 1 and 0 < e <= 1):
    print('OOB')
else:
    print('OK')
" 2>/dev/null || echo 'ERR')"
      case "$cmp" in
        BAD)
          printf 'WARN: RELAY_QUOTA_DECAY_7D=%s has START(%.2f) >= END(%.2f) — backward direction.\n' \
            "$decay" "$start" "$end"
          printf '      Weekly quota is USE-IT-OR-LOSE-IT: START < END conserves early then spends down.\n'
          printf '      A START >= END schedule false-stops a healthy run near reset (observed 2026-06-22).\n'
          q_issues=$((q_issues + 1)) ;;
        OOB)
          printf 'WARN: RELAY_QUOTA_DECAY_7D=%s — START or END out of (0,1] range (got %s:%s).\n' \
            "$decay" "$start" "$end"
          q_issues=$((q_issues + 1)) ;;
        OK)  echo "RELAY_QUOTA_DECAY_7D=$decay — direction OK (START<END, both in (0,1])" ;;
        *)   printf 'WARN: could not parse RELAY_QUOTA_DECAY_7D=%s\n' "$decay"
             q_issues=$((q_issues + 1)) ;;
      esac
    else
      printf 'WARN: RELAY_QUOTA_DECAY_7D=%s does not match START:END format (e.g. 0.30:0.90).\n' "$decay"
      q_issues=$((q_issues + 1))
    fi
  else
    echo "RELAY_QUOTA_DECAY_7D not set (no time-decay applied; pool uses flat RELAY_QUOTA_THRESHOLD)"
  fi

  # RELAY_QUOTA_THRESHOLD: if set, must be in (0, 1].
  local thresh="${RELAY_QUOTA_THRESHOLD:-}"
  if [[ -n "$thresh" ]]; then
    local ok
    ok="$(python3 -c "
t = float('$thresh')
print('OK' if 0 < t <= 1 else 'OOB')
" 2>/dev/null || echo 'ERR')"
    if [[ "$ok" == "OK" ]]; then
      echo "RELAY_QUOTA_THRESHOLD=$thresh — in bounds (0,1]"
    else
      printf 'WARN: RELAY_QUOTA_THRESHOLD=%s out of (0,1] range.\n' "$thresh"
      q_issues=$((q_issues + 1))
    fi
  fi

  if [[ "$q_issues" -gt 0 ]]; then
    issues_total=$((issues_total + q_issues))
    echo "$q_issues quota-config issue(s) found"
  else
    [[ -n "$decay" || -n "$thresh" ]] && echo "quota-config OK" || true
  fi
  echo
  log "quota-config issues=$q_issues"
}

# --- check 8: inbox routed dead-letters (id:678e slice 1, cross-repo once-only) ---
# Reports routed inbox items whose target repo never ingested them + non-conforming
# inbox entries. REPORT-ONLY (never writes — slice-2 auto-write is gated). Cross-repo
# irrelevant to a single scanned repo, so it runs ONCE regardless of scope.
routed_deadletter_check() {
  echo "=== inbox routed dead-letters (scan-routed.sh, id:678e) ==="
  local sr="$SCRIPTS_DIR/scan-routed.sh"
  if [[ -x "$sr" ]]; then
    local out
    out="$(RELAY_TOML="$RELAY_TOML" SRC_DIR="$SRC_DIR" bash "$sr" 2>>"$LOG" || true)"
    # The scan prints its own sections; surface its DEAD-LETTER/UNRESOLVED lines + count.
    if [[ -n "$out" ]]; then
      printf '%s\n' "$out" | grep -E '^(DEAD-LETTER|UNRESOLVED|NON-CONFORMING|missing-id|orphan|clean|scan-routed:)' || printf '%s\n' "$out"
      local n; n="$(printf '%s\n' "$out" | grep -cE '^(DEAD-LETTER|UNRESOLVED)' || true)"
      [[ "$n" -gt 0 ]] && issues_total=$((issues_total + n)) || true
      log "routed-deadletters n=${n:-0}"
    fi
  else
    echo "SKIP — scan-routed.sh not found at $sr (or no inbox)" >&2
  fi
  echo
}

# --- check 4: parked orphan sweep (cross-repo) ---------------------------------
parked_orphans_check() {
  echo "=== parked orphan branches (relay-reconcile.sh --all) ==="
  if [[ -x "$RECONCILE" ]]; then
    # relay-reconcile --all exits 0 and prints a "<N> parked orphan(s)…" tail line;
    # surface its stdout AND any stderr (unreadable-repo notes) — do NOT swallow.
    local rec
    rec="$(RELAY_TOML="$RELAY_TOML" SRC_DIR="$SRC_DIR" bash "$RECONCILE" --all 2> >(while IFS= read -r l; do echo "  (reconcile) $l" >&2; done) || true)"
    printf '%s\n' "$rec"
    # The tail line "<N> parked orphan(s) across all own repos" carries the count.
    local n; n="$(printf '%s\n' "$rec" | grep -oP '^\K[0-9]+(?= parked orphan)' | tail -1 || true)"
    [[ -n "$n" && "$n" -gt 0 ]] && issues_total=$((issues_total + n)) || true
    log "parked-orphans n=${n:-0}"
  else
    echo "SKIP — relay-reconcile.sh not found at $RECONCILE" >&2
  fi
  echo
}

# --- registry parse check (loud-fail; id:2945, 2026-06-30) ---------------------
# A malformed relay.toml (e.g. a duplicate key from a concurrent writer) makes the
# strict tomllib parser throw, so EVERY own_repos() enumeration silently returns an
# empty set (0 own repos) — the health report then looks falsely clean while scan-routed
# mis-reports every routed target as UNRESOLVED. The health tool is exactly where a
# corrupt registry must surface, so validate it parses and surface a LOUD issue if not.
registry_parse_check() {
  echo "=== relay.toml registry parse (id:2945) ==="
  if [[ ! -f "$RELAY_TOML" ]]; then
    echo "relay.toml not found at $RELAY_TOML — no own-repo registry (skip)"
    echo
    return 0
  fi
  local perr
  if perr="$(python3 - "$RELAY_TOML" <<'PY' 2>&1
import sys, tomllib
try:
    with open(sys.argv[1], "rb") as f:
        tomllib.load(f)
except Exception as e:
    print(f"{type(e).__name__}: {e}"); sys.exit(2)
PY
  )"; then
    echo "relay.toml parses OK ($RELAY_TOML)"
  else
    echo "ISSUE — relay.toml does NOT parse ($RELAY_TOML): $perr"
    echo "  → every own_repos() enumeration silently returns EMPTY (0 own repos); scan-routed"
    echo "    then mis-reports every routed target as UNRESOLVED, and the pool sees no own repos."
    echo "    Fix the TOML (commonly a duplicate key) and re-run. (This corruption hid 8 phantom"
    echo "    UNRESOLVED on 2026-06-30 — id:2945.)"
    issues_total=$((issues_total + 1))
  fi
  echo
}

# --- header --------------------------------------------------------------------
echo "relay-doctor — relay-machinery health report (REPORT-ONLY; cheap-first-slice of id:0907, id:9bec)"
echo "Scope: $scope    (report-only: issues are surfaced, NEVER cause a nonzero exit — only misuse does)"
echo

# --- run per-repo checks per scope ---------------------------------------------
case "$scope" in
  cwd)
    root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -z "$root" ]]; then
      echo "relay-doctor.sh: cwd is not inside a git repo and no repo path was given" >&2
      exit 2
    fi
    check_repo "$(basename "$root")" "$root" || true
    ;;
  repo)
    # An explicit repo path that does not exist is MISUSE → loud nonzero reject.
    if [[ ! -d "$repo_arg" ]]; then
      echo "relay-doctor.sh: scope path not found: $repo_arg" >&2
      exit 2
    fi
    if ! git -C "$repo_arg" rev-parse --git-dir >/dev/null 2>&1; then
      echo "relay-doctor.sh: scope path is not a git repo: $repo_arg" >&2
      exit 2
    fi
    abspath="$(cd "$repo_arg" && pwd)"
    check_repo "$(basename "$abspath")" "$abspath" || true
    ;;
  all)
    any=0
    while IFS=$'\t' read -r rname rpath; do
      [[ -n "$rname" ]] || continue
      any=1
      check_repo "$rname" "$rpath" || true
    done < <(own_repos)
    if [[ "$any" -eq 0 ]]; then
      echo "relay-doctor.sh: --all found NO own repos in $RELAY_TOML (is it readable?)" >&2
      # Empty own-repo set under --all is a config problem, not a healthy result:
      # surface it but stay report-only (exit 0) — it's not arg MISUSE.
    fi
    ;;
  *)
    echo "relay-doctor.sh: internal error — unknown scope '$scope'" >&2
    exit 2
    ;;
esac

# --- cross-repo / once-only checks ---------------------------------------------
registry_parse_check   # id:2945 — loud-fail if relay.toml is corrupt (else everything silently empty)
refs_install_check
parked_orphans_check
routed_deadletter_check   # id:678e slice 1 — inbox routed dead-letters (report-only)
quota_config_check   # id:a883 — quota-config sanity (RELAY_QUOTA_DECAY_7D + threshold bounds)

# --- coverage honesty (D4, meeting 2026-06-24): never look falsely-green ---------
# LIST the checks that are designed but NOT yet wired, so this report's coverage is
# explicit. Adding a check here without wiring it is the only failure mode that matters.
echo "=== checks NOT yet wired (coverage gaps, by design) ==="
echo "- claim/lease staleness — invariant I5 (no worktree without a live claim/orphan ref); gated on the id:e149 heartbeat (no liveness field yet)"
echo "- decision-queue vs closed-id consistency — invariant I9 (no decision-queue entry for an already-[x] id); gated on the id:b444 decision-queue schema"
echo "- discover-sig / discovery-cache health — id:c3a6 internals, not yet surfaced"
echo

# --- summary -------------------------------------------------------------------
echo "=== summary ==="
echo "total issues surfaced: $issues_total (across $repos_with_issues repo(s) with per-repo findings)"
if [[ "$strict" -eq 0 ]]; then
  echo "REPORT-ONLY: relay-doctor exits 0 regardless of findings (use --strict for a nonzero-on-issues gate; id:a883)."
  log "summary issues=$issues_total repos_with_issues=$repos_with_issues scope=$scope strict=0"
  exit 0
else
  echo "--strict mode (id:a883): exits nonzero when any issue is found."
  log "summary issues=$issues_total repos_with_issues=$repos_with_issues scope=$scope strict=1"
  [[ "$issues_total" -eq 0 ]] && exit 0 || exit 1
fi
