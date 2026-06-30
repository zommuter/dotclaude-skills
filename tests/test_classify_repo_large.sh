#!/usr/bin/env bash
# (no roadmap token — DEFECT-FIX regression test, always counts. Caught 2026-06-30 when the
#  id:3f0f classify-repo.sh wrapper was dogfooded on dotclaude-skills and died with
#  "Argument list too long": it passed the unpromoted-scan TSV (130KB — 115 surface items)
#  and the gather JSON as EXPORTED ENV VARS, and a single env string over MAX_ARG_STRLEN
#  (128KB) breaks execve of python3 AND classify-verdict.sh. The hermetic fixtures in
#  test_classify_repo.sh were too small to trigger it. The wrapper must pass large blobs via
#  temp files / stdin, never env/argv.
#
#  This fixture keeps the ROADMAP small (so gather-repo-state's own internal env use is not
#  the thing under test — that is a separate latent issue, TODO id:07be) and makes the
#  unpromoted-scan output exceed 128KB via many untagged TODO items, isolating the WRAPPER bug.)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CR="$ROOT/relay/scripts/classify-repo.sh"
[[ -x "$CR" ]] || { echo "classify-repo.sh missing"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export RELAY_TOML="$tmp/relay.toml"; : > "$RELAY_TOML"
export RELAY_WORKTREE_BASE="$tmp/wt"

R="$tmp/scanbig"; mkdir -p "$R"
git -C "$R" init -q; git -C "$R" config user.email t@e; git -C "$R" config user.name t

# Small ROADMAP (one open [ROUTINE]) → gather stays small + verdict is deterministically execute.
cat > "$R/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] the one real open item <!-- id:0001 -->
EOF
# Huge TODO: ~900 untagged open items, each with long text, so unpromoted-scan's TSV (which
# echoes each item's full text) exceeds the 128KB single-env-string limit.
{
  echo "# TODO"; echo "## Current"
  for i in $(seq 1 900); do
    printf -- "- [ ] untagged design backlog item %04d — %s <!-- id:%04x -->\n" \
      "$i" "a reasonably long description repeated to inflate the scan TSV output well past the limit" "$i"
  done
} > "$R/TODO.md"
git -C "$R" add -A; git -C "$R" commit -qm init

scan_bytes=$("$ROOT/relay/scripts/unpromoted-scan.sh" "$R" 2>/dev/null | wc -c)
[[ "$scan_bytes" -gt 131072 ]] || { echo "fixture scan output only $scan_bytes bytes — must exceed 128KB to exercise the bug"; exit 1; }

out="$("$CR" --repo scanbig --path "$R" 2>"$tmp/err")" || {
  echo "wrapper FAILED on a repo with >128KB scan output (the regression): $(cat "$tmp/err")"; exit 1; }
verdict="$(printf '%s' "$out" | python3 -c 'import sys,json;print(json.load(sys.stdin)["verdict"])')" || {
  echo "wrapper emitted non-JSON: $out"; exit 1; }
[[ "$verdict" == "execute" ]] || { echo "open [ROUTINE] must be execute, got $verdict"; exit 1; }

echo "PASS test_classify_repo_large"
