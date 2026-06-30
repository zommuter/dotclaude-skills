#!/usr/bin/env bash
# roadmap:9062
# Spec for the INTENSIVE-lane realignment of roadmap-lint case (d) (id:9062; meeting 2026-06-30-2238).
#
# DECISION (supersedes id:297b's case-d "pool-only" rule, which was the it-infra id:9321
# false-positive): [INTENSIVE — <resource>] is OPERATIVE only on relay-dispatchable lanes
# (ROUTINE / HARD — pool) and ADVISORY-inert on human lanes (hands / meeting / decision gate
# / @manual). The dispatch hazard is already neutralised by gather's top_intensive exclusion
# (id:a707), so the lint must NOT loud-reject INTENSIVE on a human lane. New rule:
#   - ACCEPT [INTENSIVE] on [ROUTINE] or [HARD — pool]   (operative)
#   - ACCEPT [INTENSIVE] on a human lane                 (advisory, no violation)
#   - REJECT [INTENSIVE] only when NO recognised lane is present (lane-less / underivable)
#
# RECONCILE: implementing this flips test_roadmap_lint_tagprose.sh (# roadmap:297b) case (d),
# which currently asserts `[HARD — meeting] [INTENSIVE]` must ERROR. The executor MUST update
# that test to the new rule (full suite green requires it — 297b is ticked).
#
# RED until roadmap-lint.sh case (d) is realigned (today it requires [HARD — pool]).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="$ROOT/relay/scripts/roadmap-lint.sh"
[[ -x "$LINT" ]] || { echo "roadmap-lint.sh not found/executable (RED): $LINT"; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

lint_pass() { # roadmap body line(s) -> expect exit 0
  printf '# Roadmap\n## Items\n%s\n' "$1" > "$tmp/r.md"
  "$LINT" "$tmp/r.md" 2>"$tmp/e" || { echo "EXPECTED PASS but lint errored: $1 :: $(cat "$tmp/e")"; exit 1; }
}
lint_reject() { # roadmap body line(s) -> expect nonzero exit
  printf '# Roadmap\n## Items\n%s\n' "$1" > "$tmp/r.md"
  if "$LINT" "$tmp/r.md" 2>"$tmp/e"; then echo "EXPECTED REJECT but lint passed: $1"; exit 1; fi
}

# Operative lanes — INTENSIVE accepted.
lint_pass '- [ ] [ROUTINE] [INTENSIVE — local-llm] rebuild the big index <!-- id:1101 -->'
lint_pass '- [ ] [HARD — pool] [INTENSIVE — local-llm] benchmark the local model <!-- id:1102 -->'

# Human lanes — INTENSIVE accepted as ADVISORY (the it-infra id:9321 case; was a false-positive).
lint_pass '- [ ] [HARD — hands] [INTENSIVE — local-llm] GPU+sudo GGUF cleanup, you run it <!-- id:1103 -->'
lint_pass '- [ ] [HARD — meeting] [INTENSIVE — local-llm] decide the GGUF retention policy <!-- id:1104 -->'

# Lane-less INTENSIVE — still rejected (no recognised lane → underivable).
lint_reject '- [ ] [INTENSIVE — local-llm] do the heavy thing with no lane <!-- id:1105 -->'

# No regression: a clean ROADMAP without INTENSIVE still lints OK.
lint_pass '- [ ] [ROUTINE] an ordinary item <!-- id:1106 -->'

echo "PASS test_roadmap_lint_intensive_lanes"
