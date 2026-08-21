#!/usr/bin/env bash
# pre-push-privacy-gate.sh — a git `pre-push` hook that scans the OUTGOING diff for
# leak patterns before a push to a PUBLIC remote and, in WARN+LOG mode, prints the
# findings loudly AND appends them to a log, then EXITS 0 (never blocks).
#
# Design: docs/meeting-notes/2026-07-20-1241-privacy-gate-pre-push-ebd0.md (D1–D4).
# Tracks TODO/ROADMAP id:ebd0.
#
#   D1  Standalone hook installed via global `core.hooksPath` (see `make install-privacy-gate`).
#   D2  Bespoke fleet-specific pattern set is the engine core (read from a PRIVATE file);
#       `scan_pii` is a best-effort shell-out iff present — NEVER a hard cross-repo import.
#   D3  WARN+LOG first: print loudly + append findings to a log, exit 0 — never auto-block
#       (so non-interactive/agent pushes still work). A future id:df87 flip adds block-mode.
#   D4  Leak patterns + allowlist live in a NEW PRIVATE file under ~/.config (configurable
#       via env). No leak specifics live in THIS (public) file — it ships mechanism only.
#
# Git calls this hook as:  pre-push <remote-name> <remote-url>
# and feeds one line per pushed ref on stdin:
#       <local-ref> SP <local-sha> SP <remote-ref> SP <remote-sha> LF
# For a new remote branch <remote-sha> is all-zero; for a delete <local-sha> is all-zero.
#
# Configuration (all overridable; defaults are private/home paths):
#   PRIVACY_GATE_PATTERNS  path to the PRIVATE pattern+allowlist file.
#                          default: ${XDG_CONFIG_HOME:-$HOME/.config}/dotclaude-skills/privacy-patterns.txt
#                          ABSENT → clean no-op with a printed notice (exit 0).
#   PRIVACY_GATE_LOG       findings log (appended). default: $HOME/.claude/logs/privacy-gate.log
#   PRIVACY_GATE_PRIVATE_HOSTS  extra ERE of remote-URL hosts to treat as private (skip).
#   PRIVACY_GATE_SCAN_PII  path to a `scan_pii` executable; else `command -v scan_pii`.
#
# PRIVATE pattern-file format (one directive per line; '#' comments and blanks ignored):
#   allow: <ERE>          an added line matching this is SUPPRESSED (intentional/functional).
#   private-host: <ERE>   a remote-URL host matching this is treated as PRIVATE → skip.
#   <ERE>                 anything else is a leak pattern; a matching added line is a finding.
#
set -uo pipefail   # not -e: this hook must NEVER abort a push on an internal hiccup.

REMOTE_NAME="${1:-}"
REMOTE_URL="${2:-}"

PATTERNS_FILE="${PRIVACY_GATE_PATTERNS:-${XDG_CONFIG_HOME:-$HOME/.config}/dotclaude-skills/privacy-patterns.txt}"
LOG_FILE="${PRIVACY_GATE_LOG:-$HOME/.claude/logs/privacy-gate.log}"

notice() { printf 'privacy-gate: %s\n' "$*" >&2; }

# ── D4: absent pattern file → clean no-op with a notice (never silent, never blocking) ──
if [[ ! -f "$PATTERNS_FILE" ]]; then
  notice "no-op — pattern file absent ($PATTERNS_FILE). Populate it (id:7fff) to enable scanning."
  exit 0
fi

# ── Load patterns / allowlist / private-host directives from the PRIVATE file ──
leak_patterns=()
allow_patterns=()
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%$'\r'}"                       # tolerate CRLF
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line//[[:space:]]/}" ]] && continue
  case "$line" in
    allow:*)        allow_patterns+=("$(printf '%s' "${line#allow:}"        | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')") ;;
    # `private-host:` is CONSUMED BY relay/scripts/lib-private-remote.sh, which re-reads this
    # same file. It is matched here only so it never falls through to the leak-pattern arm.
    private-host:*) : ;;
    *)              leak_patterns+=("$line") ;;
  esac
done < "$PATTERNS_FILE"

# ── D1: classify the remote from its URL. Private host → SKIP the scan entirely. ──
# The predicate itself is NOT defined here any more (id:4d44): it lives in ONE place,
# relay/scripts/lib-private-remote.sh, because integrate.sh's per-remote push narrowing needs
# the SAME answer and a second, drifting copy of "is this remote public" is the failure class
# this repo keeps paying for. The lib reads the very same PRIVATE pattern file (via
# $PRIVACY_GATE_PATTERNS) plus $PRIVACY_GATE_PRIVATE_HOSTS plus its builtin loopback/RFC-1918/
# *.local ERE — same three sources, same order, same result as the inline code it replaces.
#
# Lib unreadable → treat the remote as PUBLIC and SCAN. That is this gate's standing fail
# direction (never skip a scan on uncertainty), and it is loud, not silent.
priv_lib="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")/.." 2>/dev/null && pwd)/relay/scripts/lib-private-remote.sh"
is_private=0
if [[ -r "$priv_lib" ]]; then
  # shellcheck source=../relay/scripts/lib-private-remote.sh
  source "$priv_lib"
  if is_private_remote_url "$REMOTE_URL"; then is_private=1; fi
else
  notice "WARNING: shared private-remote predicate not found at $priv_lib — cannot prove '$REMOTE_NAME' is a private host, so it is treated as PUBLIC and SCANNED."
fi

if [[ "$is_private" -eq 1 ]]; then
  notice "remote '$REMOTE_NAME' ($REMOTE_URL) is a PRIVATE host — skipping leak scan."
  exit 0
fi

# ── Relay-scoping: only scan repos in the relay OWN-repo set ($RELAY_TOML) ──
# Keeps the GLOBAL core.hooksPath install convenient (one install, no per-repo onboarding,
# trivial to widen later) while dissolving "the gate fires inside every throwaway/temp repo"
# (e.g. hermetic test remotes polluting the log). RELAY_TOML is THE own-repo set — reuse
# relay/scripts/lib-own-repos.sh (never re-derive from a ~/src glob). Set PRIVACY_GATE_ALL_REPOS=1
# to scan EVERY repo (the future full-global posture).
# FAIL-OPEN TO SCAN: only a PRESENT, PARSEABLE relay.toml that does NOT list this repo triggers
# a skip. relay.toml absent/unparseable, unknown repo root, or a missing helper → SCAN (never skip
# on uncertainty — the safe direction for a privacy gate).
if [[ "${PRIVACY_GATE_ALL_REPOS:-}" != "1" ]]; then
  repo_top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  RELAY_TOML="${PRIVACY_GATE_RELAY_TOML:-${RELAY_TOML:-${XDG_CONFIG_HOME:-$HOME/.config}/relay/relay.toml}}"
  own_lib="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")/.." 2>/dev/null && pwd)/relay/scripts/lib-own-repos.sh"
  if [[ -n "$repo_top" && -f "$RELAY_TOML" && -r "$own_lib" ]]; then
    SRC_DIR="${SRC_DIR:-$HOME/src}"
    own_out=""; own_rc=0
    own_out="$(RELAY_TOML="$RELAY_TOML" SRC_DIR="$SRC_DIR"; source "$own_lib" && own_repos 2>/dev/null)" || own_rc=$?
    if [[ "$own_rc" -eq 0 ]]; then           # parsed cleanly → membership is authoritative
      member=0
      while IFS=$'\t' read -r _name p; do
        [[ -n "$p" ]] || continue
        rp="$(readlink -f "$p" 2>/dev/null || echo "$p")"
        [[ "$rp" == "$repo_top" ]] && { member=1; break; }
      done <<< "$own_out"
      if [[ "$member" -eq 0 ]]; then
        notice "repo '$repo_top' is not in the relay own-repo set — skipping leak scan (PRIVACY_GATE_ALL_REPOS=1 to scan all)."
        exit 0
      fi
    fi
    # own_rc != 0 (relay.toml parse error) → fall through to SCAN (fail-open)
  fi
  # relay.toml absent / repo root unknown / helper unreadable → fall through to SCAN (fail-open)
fi

# ── Collect ADDED diff lines across every pushed ref (D3: added lines only) ──
#
# PERFORMANCE (id:b4dd — the gate took HOURS on this repo and got the public remote
# disabled). Two amplifiers were measured, both fixed here; NEITHER fix reduces what
# is detected:
#
#   (a) EMPTY-TREE RESCAN OF PUBLISHED HISTORY.  `git push --follow-tags` sends one ref
#       line per new annotated tag, each with an all-zero remote sha. The old code read
#       that as "new ref → diff against the empty tree", i.e. re-scanned the ENTIRE
#       repository history once PER TAG — 142k added lines × 28 tags, for content the
#       remote already had. Fixed by excluding commits the remote demonstrably already
#       holds (`--not` the other refs' remote shas + this remote's remote-tracking refs
#       + refs already handled earlier in this same push). With NO such haves — a
#       genuine first push of a fresh repo — the whole history is still scanned, exactly
#       as before.
#
#   (b) FORK-PER-PATTERN-PER-LINE.  The scan spawned one `grep` per pattern per added
#       line (~23 forks/line, measured ~80 ms/line). Now every pattern is applied ONCE
#       to the whole added-line stream as a file. Same patterns, same per-line ERE
#       semantics, same first-pattern-wins attribution, same allowlist precedence —
#       O(patterns) greps instead of O(patterns × lines).
#
# `git log -p` over the new commits (rather than a single range diff) is NOT simply a
# superset of the old added-line set. It widens in one direction — it also catches a
# leak that was added and then removed within the pushed range, which a single
# base..head range diff would miss — but it NARROWS in another: `git log -p` prints NO
# diff for a merge commit by default, so any line that exists only in a merge's
# RESOLVED TREE (conflict resolution, `-X ours`, a manual edit made during the merge)
# and in neither parent is invisible to a plain commit walk, while the old range-diff
# caught it. (id:5171 — corrected; the previous "superset, detection widens never
# narrows" claim here was false and is exactly the defect that item found.)
#
# Fixed by ALSO taking each merge commit's own dense-combined diff
# (`--diff-merges=dense-combined`, i.e. old `--cc`): it shows only the hunks that
# differ from EVERY parent — the content the merge itself introduced — instead of
# reprinting the whole incoming branch (which `first-parent` or `-m` would do, and
# which is already covered by that branch's own commits earlier in this same walk).
# Measured on this repo's own history (155 commits / 25 merges, realistic push size):
# baseline (no diff-merges) 19295 added lines / 1.45s; dense-combined 19820 lines
# (+525, the merge-only content) / 1.44s — no measurable cost. `first-parent` added
# 14650 duplicate lines (+76%) and `-m` added 24713 (+128%) by reprinting each merge's
# whole incoming branch a second time, so both were rejected as an unwarranted
# duplication cost for content this scan already sees via the individual commits.
#
# There is NO size cap and NO silent skip: a ref whose sha this repo cannot resolve is
# reported LOUDLY via notice() rather than dropped.

tmpdir=""
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/privacy-gate.XXXXXX" 2>/dev/null || true)"
if [[ -z "$tmpdir" || ! -d "$tmpdir" ]]; then
  notice "WARNING: could not create a temp dir — leak scan SKIPPED for this push (push NOT blocked)."
  exit 0
fi
trap 'rm -rf "$tmpdir"' EXIT

content_file="$tmpdir/content"   # one added line of content per line
ref_file="$tmpdir/refs"          # parallel: the pushed ref that contributed line N
: > "$content_file"
: > "$ref_file"

# Buffer stdin first: every ref line's remote sha is evidence of what the remote already
# holds, and that evidence must be complete BEFORE the first ref is scanned.
ref_lines=()
while read -r rl; do
  [[ -n "${rl:-}" ]] && ref_lines+=("$rl")
done

haves=()
add_have() { # <sha> — record a commit-ish the remote already has (best-effort)
  local s="${1:-}"
  [[ -n "$s" ]] || return 0
  [[ "$s" =~ ^0+$ ]] && return 0
  git cat-file -e "${s}^{commit}" 2>/dev/null || return 0
  haves+=("$s")
}

# Everything this remote is already known to hold, per its remote-tracking refs.
# Reason for the redirect: a remote with no remote-tracking refs is the normal
# first-push case, not an error — it simply yields no haves and the full history
# is scanned, which is the pre-existing behaviour.
if [[ -n "$REMOTE_NAME" ]]; then
  while IFS= read -r rs; do
    add_have "$rs"
  done < <(git for-each-ref --format='%(objectname)' "refs/remotes/$REMOTE_NAME/" 2>/dev/null || true)
fi
# ...plus every remote sha git itself reported for the refs in THIS push.
for rl in "${ref_lines[@]}"; do
  read -r _lr _ls _rr rsha <<< "$rl"
  add_have "${rsha:-}"
done

for rl in "${ref_lines[@]}"; do
  read -r local_ref local_sha remote_ref remote_sha <<< "$rl"
  [[ -z "${local_ref:-}" ]] && continue
  # Deletion (local sha all-zero): nothing is being added — skip.
  if [[ -z "${local_sha:-}" || "$local_sha" =~ ^0+$ ]]; then continue; fi
  if ! git cat-file -e "${local_sha}^{commit}" 2>/dev/null; then
    notice "WARNING: ref '$local_ref' ($local_sha) is not resolvable in this repo — NOT scanned."
    continue
  fi

  # Added lines of the commits this push actually publishes = reachable from local_sha
  # but from none of the haves. No haves at all → the whole history (old behaviour).
  # Redirect reason: `git log` can still fail on a corrupt/odd object; the gate is
  # best-effort and must never abort a push, and an empty result simply scans nothing.
  if [[ "${#haves[@]}" -gt 0 ]]; then
    git log -p -U0 --format='' --no-ext-diff --no-textconv --diff-merges=dense-combined "$local_sha" --not "${haves[@]}" 2>/dev/null
  else
    git log -p -U0 --format='' --no-ext-diff --no-textconv --diff-merges=dense-combined "$local_sha" 2>/dev/null
  fi | awk -v ref="$local_ref" -v cf="$content_file" -v rf="$ref_file" '
    /^\+\+\+/ { next }
    /^\+/ {
      s = substr($0, 2)
      if (s == "") next
      print s   >> cf
      print ref >> rf
    }
  '

  # This ref is now accounted for; later refs in the same push need not rescan it.
  haves+=("$local_sha")
done

if [[ ! -s "$content_file" ]]; then
  exit 0   # nothing added to scan
fi

# ── Scan added lines against the leak patterns, honoring the allowlist ──
# One grep per pattern over the WHOLE stream (not per line). Line numbers are the join
# key back to $ref_file / $content_file. Sorting is LEXICAL throughout because `comm`
# compares as strings; the final output is re-sorted numerically so findings still
# appear in added-line order, exactly as before.
claimed_file="$tmpdir/claimed"; : > "$claimed_file"
hits_file="$tmpdir/hits";       : > "$hits_file"
match_file="$tmpdir/match"

# Allowlisted content is intentional/functional — suppress it. Claimed FIRST so an
# allowlisted line can never be reported by a later leak pattern (old precedence).
for a in "${allow_patterns[@]}"; do
  [[ -n "$a" ]] || continue
  grep -n -E -e "$a" "$content_file" 2>/dev/null | cut -d: -f1 >> "$claimed_file"
done
sort -u -o "$claimed_file" "$claimed_file" 2>/dev/null || true

# First matching pattern wins, patterns tried in file order — same as the old inner loop.
for p in "${leak_patterns[@]}"; do
  [[ -n "$p" ]] || continue
  grep -n -E -e "$p" "$content_file" 2>/dev/null | cut -d: -f1 | sort -u > "$match_file"
  [[ -s "$match_file" ]] || continue
  new_hits="$(comm -23 "$match_file" "$claimed_file" 2>/dev/null || true)"
  [[ -n "$new_hits" ]] || continue
  while IFS= read -r ln; do
    [[ -n "$ln" ]] && printf '%s\t%s\n' "$ln" "$p" >> "$hits_file"
  done <<< "$new_hits"
  printf '%s\n' "$new_hits" >> "$claimed_file"
  sort -u -o "$claimed_file" "$claimed_file" 2>/dev/null || true
done

findings=""
if [[ -s "$hits_file" ]]; then
  findings="$(awk -F'\t' '
    NR == FNR { pat[$1] = $2; next }
    (FNR in pat) {
      i = index($0, "\t")
      printf "%s\t%s\t%s\n", substr($0, 1, i - 1), pat[FNR], substr($0, i + 1)
    }
  ' "$hits_file" <(paste -d'\t' "$ref_file" "$content_file") 2>/dev/null || true)"
  [[ -n "$findings" ]] && findings+=$'\n'
fi

# ── D2: best-effort `scan_pii` shell-out iff present (never a hard dependency) ──
scan_pii_bin="${PRIVACY_GATE_SCAN_PII:-}"
if [[ -z "$scan_pii_bin" ]]; then
  # `command -v` may legitimately find nothing; that is the no-op branch, not an error.
  scan_pii_bin="$(command -v scan_pii 2>/dev/null || true)"
fi
if [[ -n "$scan_pii_bin" && -x "$scan_pii_bin" ]]; then
  pii_out=""
  # Best-effort augmentation: feed the added content to scan_pii; any crash is ignored so a
  # broken/absent PII tool can never block a push (redirect reason: tool-internal errors are
  # non-fatal here by design — D2 "best-effort, never a hard dependency").
  pii_out="$("$scan_pii_bin" < "$content_file" 2>/dev/null || true)"
  while IFS= read -r pl; do
    [[ -z "$pl" ]] && continue
    findings+="(scan_pii)"$'\t'"scan_pii"$'\t'"${pl}"$'\n'
  done <<< "$pii_out"
fi

# ── D3: WARN+LOG. Print loudly, append to the log, ALWAYS exit 0. ──
if [[ -n "$findings" ]]; then
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  {
    printf '========================================================================\n'
    printf 'privacy-gate WARNING — potential leak in a push to a PUBLIC remote\n'
    printf '  remote : %s (%s)\n' "$REMOTE_NAME" "$REMOTE_URL"
    printf '  This is WARN mode: the push is NOT blocked. Review the findings below.\n'
    printf '========================================================================\n'
    while IFS=$'\t' read -r ref pat content; do
      [[ -z "${ref:-}" ]] && continue
      printf '  [%s] pattern<%s>  %s\n' "$ref" "$pat" "$content"
    done <<< "$findings"
  } >&2

  # Append findings to the log for FP calibration (id:df87): timestamp + remote + ref + finding.
  while IFS=$'\t' read -r ref pat content; do
    [[ -z "${ref:-}" ]] && continue
    printf '%s\t%s\t%s\t%s\t%s\n' "$ts" "$REMOTE_URL" "$ref" "$pat" "$content" >> "$LOG_FILE"
  done <<< "$findings"
fi

exit 0
