#!/usr/bin/env bash
# No roadmap header -- this is a defect-fix spec (filed 2026-09-08 alongside the id:c3c1
# probe-instrument repair). Failures always count.
#
# The global CLAUDE.md carries a HARD, no-exceptions ban on em dashes (U+2014) and en
# dashes (U+2013): "Never emit an em dash or an en dash. Not in prose, not in commit
# messages, not in code comments ... This is a hard style rule, not a preference."
#
# `agents/*.md` is the highest-leverage place in this repo for that ban to be violated,
# and the LAST place anyone looks:
#   * an agent definition's markdown BODY becomes that agent type's SYSTEM PROMPT, and
#     its `description:` is injected into the agent-registry block of EVERY delegated
#     agent's preamble -- so one em dash in `agents/` is an em dash the model is shown
#     as exemplar text on every single dispatch, which is precisely how the style
#     regresses;
#   * nothing else covers this directory. `tests/test_ledger_shrink_0d7c.sh` case (G)
#     greps for `[\x{2013}\x{2014}]`, but only inside a FIXTURE repo's
#     `docs/ledger-notes/` -- it is a check on GENERATED output and structurally cannot
#     see hand-authored files anywhere else. All four definitions in `agents/` carried
#     em dashes until this spec landed.
#
# Scope note (id:b818): this sweep is anchored to `$ROOT/agents/*.md` -- a fixed,
# non-recursive directory -- so it cannot walk into `.claude/worktrees/<agent>/` and
# report on a sibling branch's in-flight files.
#
# fails-against-mutation: sed -i '1s/--/\xe2\x80\x94/' agents/echo-runner.md
# fails-against-assertion: FAIL: an agent definition contains an em dash or en dash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Overridable so the negative case can be exercised against a scratch directory without
# mutating the real tree.
AGENTS="${AGENTS_DIR_UNDER_TEST:-$ROOT/agents}"

rc=0

if [[ ! -d "$AGENTS" ]]; then
  echo "ERROR: agents directory not found: $AGENTS" >&2
  exit 3
fi

shopt -s nullglob
defs=("$AGENTS"/*.md)
shopt -u nullglob

if [[ ${#defs[@]} -eq 0 ]]; then
  # A vacuous pass is worse than a failure here: it would report green forever if the
  # directory were renamed. Treat "nothing to check" as a check that could not RUN.
  echo "ERROR: no agent definitions found under $AGENTS -- this check would be vacuous" >&2
  exit 3
fi

offenders=()
for f in "${defs[@]}"; do
  if grep -qP '[\x{2013}\x{2014}]' -- "$f"; then
    offenders+=("$(basename -- "$f")")
    grep -nP '[\x{2013}\x{2014}]' -- "$f" | sed "s|^|  $(basename -- "$f"):|" >&2
  fi
done

if [[ ${#offenders[@]} -gt 0 ]]; then
  echo "FAIL: an agent definition contains an em dash or en dash (hard style ban, global CLAUDE.md); offenders: ${offenders[*]}" >&2
  rc=1
fi

if [[ $rc -eq 0 ]]; then
  echo "ok: ${#defs[@]} agent definition(s) free of em/en dashes"
fi
exit $rc
