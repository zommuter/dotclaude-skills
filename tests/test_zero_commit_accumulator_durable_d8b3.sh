#!/usr/bin/env bash
# roadmap:d8b3
#
# id:d8b3 — the ZERO-COMMIT branch of executor-contract rule 2c (id:5eeb) leaks its own
# escalation counter, so the escalation it gates is UNREACHABLE.
#
# The branch tells the executor to write `HANDBACK: <item-id> ... ZERO-COMMIT` into
# RELAY_LOG.md and, before writing it, to count prior occurrences with
# `grep -c "HANDBACK: <item-id> .*ZERO-COMMIT" RELAY_LOG.md`. But that line is committed
# on the HANDBACK branch, and the integrator never merges a handback — so the next
# attempt branches from main, sees a RELAY_LOG.md without it, and reads 0. The count
# never reaches the `>= 1` that returns `route="hard-split"`. Observed live on run
# relay-20260831-220243-21277: git-annex handed back `hard` TWICE via this exact branch
# (rule 2c fired at 273,449 B against the 300,000 B threshold, zero-commit both times)
# and the id:1432 repeat-handback ALERT flagged it.
#
# RED until d8b3 lands. Contract, from the item: two successive zero-commit 2c handbacks
# for one repo leave a count of 2 readable by the THIRD attempt.
#
# The store is deliberately NOT pinned by name. What IS pinned is the property that makes
# any store correct: it must survive a discarded branch, i.e. live OUTSIDE the repo
# working tree. `relay/scripts/relay-state-write.sh event-append <abs-path>` is an
# already-built, flock'd, branch-independent append-only substrate that satisfies this
# and does NOT write owner-facing config; an implementation is free to use it or another
# store with the same property. Writing the counter into `relay.toml` would satisfy the
# letter of this test but is OWNER-FACING CONFIG — see the ROADMAP item's note.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="$ROOT/relay/references/executor-contract.md"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$CONTRACT" ]] || fail "executor-contract.md not found at $CONTRACT"

# --- isolate the ZERO-COMMIT branch's own text -----------------------------------------
python3 - "$CONTRACT" > "$tmp/branch.txt" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
i = src.find('**ZERO-COMMIT branch')
if i < 0:
    sys.exit(0)
# the branch ends at the next paragraph that starts a new rule/verdict discussion
tail = src[i:]
m = re.search(r'\n\s*A `warn` verdict', tail)
sys.stdout.write(tail[:m.start()] if m else tail[:4000])
PY

[[ -s "$tmp/branch.txt" ]] || fail "id:d8b3: could not locate the ZERO-COMMIT branch in the contract"

# --- (a) the branch must name a CONCRETE accumulator path outside the working tree ------
# This is the load-bearing assertion, and it is deliberately a PATH match rather than a
# lexeme match: the branch's own problem statement already contains the words "NOTHING
# durable", so any `durable|survives`-style keyword check passes VACUOUSLY against the
# present, broken text (measured — that is exactly how the first draft of this test
# self-satisfied). A path either is outside the repo or it is not.
store="$(grep -oE '(~|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?|/)[A-Za-z0-9._/${}-]*\.(jsonl|json|txt|state|toml)' "$tmp/branch.txt" \
         | grep -vE '(^|/)(RELAY_LOG|ROADMAP|TODO|REVIEW_ME)\.' | head -1 || true)"

[[ -n "$store" ]] \
  || fail "id:d8b3 (a): the ZERO-COMMIT branch names no accumulator path outside the repo — the count is read only from RELAY_LOG.md, which is committed on the handback branch the integrator never merges, so it is structurally always 0 and route=\"hard-split\" is unreachable"

case "$store" in
  /*|'~'/*|'$'*) : ;;
  *) fail "id:d8b3 (a): accumulator path '$store' is repo-relative — it would be discarded with the handback branch" ;;
esac

# --- (b) it must say WHY RELAY_LOG.md cannot be the store ------------------------------
# Without the reason recorded at the point of use, the next contract edit reintroduces it.
grep -qiE 'never merge|not merged|discard|thrown away|handback branch' "$tmp/branch.txt" \
  || fail "id:d8b3 (b): the branch does not record why RELAY_LOG.md is not a valid store (the integrator never merges a handback)"

echo "PASS: id:d8b3 — the ZERO-COMMIT accumulator is stored where a discarded handback cannot lose it"
