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
REPO_ROOT="$(cd "$SCRIPTS_DIR/../.." && pwd)"          # dotclaude-skills repo root
ORPHAN_SCAN="$REPO_ROOT/meeting/orphan-scan.sh"
# Allow an override so the orphan-scan path resolves when installed via symlink too.
ORPHAN_SCAN="${RELAY_DOCTOR_ORPHAN_SCAN:-$ORPHAN_SCAN}"

LOG="${RELAY_DOCTOR_LOG:-$HOME/.claude/logs/relay-doctor.log}"

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
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)     scope="all"; shift ;;
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
refs_install_check
parked_orphans_check

# --- coverage honesty (D4, meeting 2026-06-24): never look falsely-green ---------
# LIST the checks that are designed but NOT yet wired, so this report's coverage is
# explicit. Adding a check here without wiring it is the only failure mode that matters.
echo "=== checks NOT yet wired (coverage gaps, by design) ==="
echo "- claim/lease staleness — gated on the id:e149 heartbeat (no liveness field yet)"
echo "- discover-sig / discovery-cache health — id:c3a6 internals, not yet surfaced"
echo "- quota-config sanity (RELAY_QUOTA_DECAY_7D direction, threshold bounds) — folding in via id:a883"
echo

# --- summary -------------------------------------------------------------------
echo "=== summary ==="
echo "total issues surfaced: $issues_total (across $repos_with_issues repo(s) with per-repo findings)"
echo "REPORT-ONLY: relay-doctor exits 0 regardless of findings (the fail-loud-vs-report-only"
echo "policy is the deferred [HARD — meeting] part of id:0907 — not decided here)."
log "summary issues=$issues_total repos_with_issues=$repos_with_issues scope=$scope"
exit 0
