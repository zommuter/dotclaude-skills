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
EMPTY_TREE="4b825dc642cb6eb9a060e54bf8d69288fbee4904"  # git's canonical empty-tree object

notice() { printf 'privacy-gate: %s\n' "$*" >&2; }

# ── D4: absent pattern file → clean no-op with a notice (never silent, never blocking) ──
if [[ ! -f "$PATTERNS_FILE" ]]; then
  notice "no-op — pattern file absent ($PATTERNS_FILE). Populate it (id:7fff) to enable scanning."
  exit 0
fi

# ── Load patterns / allowlist / private-host directives from the PRIVATE file ──
leak_patterns=()
allow_patterns=()
priv_host_res=()
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%$'\r'}"                       # tolerate CRLF
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line//[[:space:]]/}" ]] && continue
  case "$line" in
    allow:*)        allow_patterns+=("$(printf '%s' "${line#allow:}"        | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')") ;;
    private-host:*) priv_host_res+=("$(printf '%s' "${line#private-host:}"  | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')") ;;
    *)              leak_patterns+=("$line") ;;
  esac
done < "$PATTERNS_FILE"

# ── D1: classify the remote from its URL. Private host → SKIP the scan entirely. ──
# Built-in defaults cover loopback / RFC-1918 / *.local; the private file and
# PRIVACY_GATE_PRIVATE_HOSTS add site-specific hosts (kept OUT of this public file).
builtin_private='(^|@|//)(localhost|127\.0\.0\.1|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)|\.local($|[:/])'
is_private=0
if [[ -n "$REMOTE_URL" ]] && grep -Eq -e "$builtin_private" <<<"$REMOTE_URL"; then
  is_private=1
fi
if [[ -n "${PRIVACY_GATE_PRIVATE_HOSTS:-}" ]] && grep -Eq -e "$PRIVACY_GATE_PRIVATE_HOSTS" <<<"$REMOTE_URL"; then
  is_private=1
fi
for re in "${priv_host_res[@]}"; do
  [[ -n "$re" ]] && grep -Eq -e "$re" <<<"$REMOTE_URL" && is_private=1
done

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
added_lines=""
while read -r local_ref local_sha remote_ref remote_sha; do
  [[ -z "${local_ref:-}" ]] && continue
  # Deletion (local sha all-zero): nothing is being added — skip.
  if [[ "$local_sha" =~ ^0+$ ]]; then continue; fi
  # New branch (remote sha all-zero): diff against the empty tree = whole history added.
  base="$remote_sha"
  if [[ -z "$remote_sha" || "$remote_sha" =~ ^0+$ ]]; then base="$EMPTY_TREE"; fi
  # `git diff base..local`; only '+' lines (excluding the '+++' file header) are additions.
  d=""
  # git may exit non-zero if a sha is unknown to this repo; tolerate it (best-effort) — a
  # scan failure must not block a push. Reason for the redirect: git prints "fatal: bad
  # object" to stderr for an unknown base, which is expected/handled, not a real error.
  d="$(git diff "$base".."$local_sha" 2>/dev/null || true)"
  while IFS= read -r dl; do
    [[ "$dl" == +++* ]] && continue
    [[ "$dl" == +* ]] && added_lines+="${local_ref}"$'\t'"${dl:1}"$'\n'
  done <<< "$d"
done

if [[ -z "$added_lines" ]]; then
  exit 0   # nothing added to scan
fi

# ── Scan added lines against the leak patterns, honoring the allowlist ──
findings=""
while IFS=$'\t' read -r ref content; do
  [[ -z "${content:-}" ]] && continue
  # Allowlisted content is intentional/functional — suppress it.
  suppressed=0
  for a in "${allow_patterns[@]}"; do
    [[ -n "$a" ]] && grep -Eq -e "$a" <<<"$content" && { suppressed=1; break; }
  done
  [[ "$suppressed" -eq 1 ]] && continue
  for p in "${leak_patterns[@]}"; do
    if grep -Eq -e "$p" <<<"$content"; then
      findings+="${ref}"$'\t'"${p}"$'\t'"${content}"$'\n'
      break
    fi
  done
done <<< "$added_lines"

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
  pii_out="$(cut -f2- <<<"$added_lines" | "$scan_pii_bin" 2>/dev/null || true)"
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
