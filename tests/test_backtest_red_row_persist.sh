#!/usr/bin/env bash
# roadmap:e833
# RED spec for id:e833 — harden-forward closing id:3134's instrument gap. TWO acceptances,
# both asserted against ONE backtest-verdict.py --append-log run over two fixture repos:
#
#   (1) PER-REPO RED-ROW PERSISTENCE. The shadow-log entry must carry an attributable row
#       for every RED bucket (repo + dispatched-verdict + classifier-verdict + sig), not just
#       the aggregate `{red: N}` count. Today only the count is stored, so a disputed RED has
#       to be reconstructed from relay-events.jsonl (id:3134's un-adjudicability). Pinned shape:
#       entry["red_rows"] is a list of {repo, dispatch_verdict, classifier_verdict, sig}, one per
#       RED, with len(red_rows) == entry["red"].
#
#   (2) SIG-FIDELITY: an execute→review advance at the SAME discover-sig must bucket EXPECTED,
#       not RED. discover-sig.sh does not hash the substantive_unaudited / audit-ckpt-target
#       signal, so a legitimate execute→review policy-delta collides on the sig and today
#       mislabels as RED (a FALSE positive). The assertion is on the OUTCOME ("not counted RED"),
#       so the executor may satisfy it via EITHER 2a (add the signal to discover-sig.sh's blob)
#       OR 2b (teach the RED bucketer to treat a same-sig execute→review advance as EXPECTED).
#
# Hermetic; same fixture idiom as test_backtest_bucketing.sh / test_backtest_append_log.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BT="$ROOT/relay/scripts/backtest-verdict.py"
DISCOVER_SIG="$ROOT/relay/scripts/discover-sig.sh"
[[ -f "$BT" ]] || { echo "FAIL: backtest-verdict.py not found"; exit 1; }
[[ -f "$DISCOVER_SIG" ]] || { echo "FAIL: discover-sig.sh not found"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export SRC_DIR="$tmp/src"; mkdir -p "$SRC_DIR"
export RELAY_TOML="$tmp/relay.toml"
export RELAY_EVENTS="$tmp/events.jsonl"
export RELAY_WORKTREE_BASE="$tmp/wt"
export RELAY_SHADOW_LOG="$tmp/shadow.jsonl"
# Hermetic: pin the decision-queue to an empty temp path so discover-sig.sh's `dq` section is
# stable — otherwise a concurrent real relay writing ~/.config/relay/decision-queue.jsonl
# perturbs the sig between the exec-state capture and the live backtest computation.
export RELAY_DECISION_QUEUE="$tmp/decision-queue.jsonl"

sig_of() {  # sig_of <repo> <path>
  printf '%s' '{"repos":[{"repo":"'"$1"'","path":"'"$2"'"}],"liveClaims":[]}' \
    | "$DISCOVER_SIG" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("sig",""))'
}

# ── repo "foo": GENUINE RED — open [ROUTINE] ⇒ live verdict=execute; dispatched as review at
#    the same sig. This disagreement is real (not an execute→review advance) and MUST stay RED
#    under either fix, so its per-repo row must be persisted (acceptance 1). ──
FOO="$SRC_DIR/foo"; mkdir -p "$FOO"
git -C "$FOO" init -q; git -C "$FOO" config user.email t@e; git -C "$FOO" config user.name t
cat > "$FOO/ROADMAP.md" <<'EOF'
# Roadmap
## Items
- [ ] [ROUTINE] do the thing <!-- id:0001 -->
EOF
printf '# TODO\n## Current\n' > "$FOO/TODO.md"
git -C "$FOO" add -A; git -C "$FOO" commit -qm init

# ── repo "bar": FALSE RED — substantive unaudited commit + zero open items ⇒ live verdict=review.
#    The audit checkpoint tag's TARGET (not hashed by discover-sig) is what flips the verdict, so
#    the execute-state sig and the review-state sig collide. We record a prior dispatch of
#    mode=execute carrying the EXECUTE-STATE sig; today that equals the live sig ⇒ mis-bucketed RED. ──
BAR="$SRC_DIR/bar"; mkdir -p "$BAR"
git -C "$BAR" init -q; git -C "$BAR" config user.email t@e; git -C "$BAR" config user.name t
printf '# Roadmap\n## Items\n' > "$BAR/ROADMAP.md"   # zero open items
printf '# TODO\n## Current\n' > "$BAR/TODO.md"
printf 'a\n' > "$BAR/a.txt"
git -C "$BAR" add -A; git -C "$BAR" commit -qm init           # C1
printf 'b\n' > "$BAR/b.txt"
git -C "$BAR" add -A; git -C "$BAR" commit -qm "substantive work"  # C2 = HEAD
BAR_C1="$(git -C "$BAR" rev-parse HEAD~1)"
BAR_C2="$(git -C "$BAR" rev-parse HEAD)"
git -C "$BAR" tag -a -m ckpt relay-ckpt-0001 "$BAR_C1"        # audit ref at C1 ⇒ substantive_unaudited ⇒ review

# relay.toml MUST exist before any sig capture — discover-sig.sh hashes the [repos.<name>] block,
# so a sig computed with the toml absent would not match backtest's live cur_sig (which sees it).
cat > "$RELAY_TOML" <<'EOF'
[repos.foo]
classification = "own"

[repos.bar]
classification = "own"
EOF

FOO_SIG="$(sig_of foo "$FOO")"

# Capture the EXECUTE-STATE sig: audit ref advanced to HEAD (nothing unaudited). Under CURRENT
# discover-sig this is byte-identical to the review-state sig (the gap); under fix 2a it differs.
git -C "$BAR" tag -f -a -m ckpt relay-ckpt-0001 "$BAR_C2" >/dev/null 2>&1
BAR_EXEC_SIG="$(sig_of bar "$BAR")"
git -C "$BAR" tag -f -a -m ckpt relay-ckpt-0001 "$BAR_C1" >/dev/null 2>&1   # restore review-state

# foo dispatched review (live execute) → genuine RED; bar dispatched execute (live review) → false RED today.
{
  printf '{"kind":"dispatch","repo":"foo","mode":"review","sig":"%s"}\n' "$FOO_SIG"
  printf '{"kind":"dispatch","repo":"bar","mode":"execute","sig":"%s"}\n' "$BAR_EXEC_SIG"
} > "$RELAY_EVENTS"

# ── run once with --json + --append-log; assert both acceptances ──
out="$(python3 "$BT" --json --append-log)" || { echo "FAIL: backtest must exit 0 (report-only)"; exit 1; }

RELAY_SHADOW_LOG="$RELAY_SHADOW_LOG" FOO_SIG="$FOO_SIG" python3 - "$out" <<'PYEOF'
import json, os, sys
o = json.loads(sys.argv[1])
rows = {r["repo"]: r for r in o["rows"]}
foo, bar = rows["foo"], rows["bar"]

fails = []
def ok(cond, msg):
    if not cond: fails.append(msg)

# sanity: live verdicts as designed
ok(foo["verdict"] == "execute", f"foo live verdict must be execute, got {foo}")
ok(bar["verdict"] == "review",  f"bar live verdict must be review, got {bar}")

# ── acceptance (2): bar (execute→review at same sig) must NOT be counted RED ──
ok(bar["note"] != "RED", f"execute→review at same sig must NOT bucket RED, got {bar}")

# ── acceptance (1): shadow-log entry carries attributable per-repo RED rows ──
with open(os.environ["RELAY_SHADOW_LOG"]) as f:
    entry = json.loads(f.readline())
ok("red_rows" in entry, f"shadow-log entry must carry per-repo 'red_rows', got keys {sorted(entry)}")
if "red_rows" in entry:
    rr = entry["red_rows"]
    ok(isinstance(rr, list), f"red_rows must be a list, got {type(rr).__name__}")
    ok(len(rr) == entry.get("red"),
       f"len(red_rows)={len(rr)} must equal aggregate red={entry.get('red')}")
    for e in rr:
        ok({"repo", "dispatch_verdict", "classifier_verdict", "sig"} <= set(e),
           f"each red row needs repo/dispatch_verdict/classifier_verdict/sig, got {e}")
    foo_rows = [e for e in rr if e.get("repo") == "foo"]
    ok(len(foo_rows) == 1, f"the genuine foo RED must be persisted exactly once, got {foo_rows}")
    if foo_rows:
        e = foo_rows[0]
        ok(e.get("dispatch_verdict") == "review",
           f"foo red row dispatch_verdict must be review, got {e}")
        ok(e.get("classifier_verdict") == "execute",
           f"foo red row classifier_verdict must be execute, got {e}")
        ok(e.get("sig") == os.environ["FOO_SIG"],
           f"foo red row must carry the dispatch sig {os.environ['FOO_SIG']}, got {e}")
    # bar must NOT appear as a RED row (it is the exempted false-RED)
    ok(not [e for e in rr if e.get("repo") == "bar"],
       "bar (execute→review same-sig) must NOT appear in red_rows")

if fails:
    print("RED (expected until id:e833 lands):")
    for m in fails: print("  - " + m)
    sys.exit(1)
print("PASS test_backtest_red_row_persist")
PYEOF
