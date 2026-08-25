#!/usr/bin/env bash
# NO `# roadmap:` header ON PURPOSE — id:17ac is a DEFECT FIX (observed live on a push), not a
# ROADMAP item, so per tests/run-tests.sh's convention these failures ALWAYS count.
#
# id:17ac — `is_private_remote_url` wrote SIGPIPE noise into the push transcript.
#
#   BEFORE: source 3 looped directly over `< <(private_host_res)` and `return 0`-ed on the
#   first matching directive. That closes the process substitution's read end while the
#   producer is still walking the rest of the pattern file, so its NEXT `printf '%s\n'`
#   (i.e. the second and later `private-host:` directives) hits a closed pipe.
#
#   Why it is invisible in a terminal but LOUD under `git push`: with SIGPIPE at its default
#   disposition the producer subshell is killed silently. Git ignores SIGPIPE, and hooks
#   inherit that disposition — so in `hooks/pre-push-privacy-gate.sh` the write returns EPIPE
#   instead and bash prints `lib-private-remote.sh: line NNN: printf: write error: Broken pipe`
#   onto stderr. Push stderr is the privacy gate's ONLY evidence channel (id:293f: a clean
#   public scan prints nothing), so noise there degrades the one signal operators are trained
#   to read.
#
#   The verdict was never wrong — this pins the STDERR contract, plus the verdict, plus the
#   producer's trim parity after the `sed` fork was replaced with parameter expansion (the
#   consumer now drains to EOF, so that fork would be paid per directive rather than only up
#   to the first match).
#
# Hermetic: FIXTURE pattern files only — never the real, never-committed
# ~/.config/dotclaude-skills/privacy-patterns.txt, whose CONTENTS are never inlined here.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${LIB_PRIVATE_REMOTE_OVERRIDE:-$SRC_DIR/relay/scripts/lib-private-remote.sh}"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
rc=0
ok()  { echo "PASS: $*"; }
bad() { echo "FAIL: $*"; rc=1; }

[[ -r "$LIB" ]] || { echo "FAIL: lib not readable at $LIB"; exit 1; }

# ── FIXTURE: the FIRST directive matches and FOUR more follow it. The trailing directives are
#    the whole point — they are the writes that land on the closed pipe once the consumer has
#    short-circuited on the first. All hosts are SYNTHETIC.
PATFILE="$TMP/patterns.txt"
cat > "$PATFILE" <<'EOF'
# fixture — synthetic only
private-host: (^|@|//)zzbox1([:/]|$)
private-host: (^|@|//)zzbox2([:/]|$)
private-host: (^|@|//)zzbox3([:/]|$)
private-host: (^|@|//)zzbox4([:/]|$)
private-host: (^|@|//)zzbox5([:/]|$)
EOF
export PRIVACY_GATE_PATTERNS="$PATFILE"
unset PRIVACY_GATE_PRIVATE_HOSTS || true

# Run the predicate in a FRESH bash that IGNORES SIGPIPE — i.e. reproduce the git-hook
# environment, where a write past a closed pipe reports EPIPE rather than killing the writer.
# `set -euo pipefail` is the mode integrate.sh sources the lib in.
#
# STDERR IS COLLECTED THROUGH A PIPE DRAINED TO EOF, NOT A FILE THAT IS THEN `-s`-TESTED.
# The EPIPE message is written by the process-substitution SUBSHELL, which the outer shell
# never waits on — so a `2>"$f"` + `[[ -s "$f" ]]` check races the writer and reports "clean"
# about half the time (measured: against the pre-fix lib this file's own `-s` assertion PASSED
# while the `grep 'Broken pipe'` assertion on the same file FAILED). A command substitution on
# fd 2 blocks until EVERY writer has closed it, subshell included, so it is deterministic.
run_hooklike() { # <url> <stdout-file> → prints the run's STDERR; stdout goes to <stdout-file>
  bash -c '
    set -euo pipefail
    trap "" PIPE
    source "$1"
    if is_private_remote_url "$2"; then echo private; else echo public; fi
  ' _ "$LIB" "$1" 2>&1 >"$2"
}

OUT="$TMP/out"
check() { # <expected-verdict> <url> <why>
  local want="$1" url="$2" why="$3" err verdict
  err="$(run_hooklike "$url" "$OUT")"
  verdict="$(cat "$OUT")"
  [[ "$verdict" == "$want" ]] \
    && ok "17ac $why → $want" \
    || bad "17ac $why → '$verdict', expected '$want'"
  if [[ -n "$err" ]]; then
    bad "17ac $why left stderr noise (the id:17ac symptom): $err"
  else
    ok "17ac $why → stderr clean (no Broken pipe)"
  fi
}

# ── 1. The reported symptom: matching on the FIRST directive, with four more still to be
#      written. This is the assertion that fails against the pre-fix lib.
check private 'git@zzbox1:o/repo.git' 'first-directive match'

# ── 2. Matching on the LAST directive (the producer runs to EOF anyway).
check private 'git@zzbox5:o/repo.git' 'last-directive match'

# ── 3. No match at all — must stay PUBLIC (fail-toward-scan) and stay silent.
check public 'https://github.com/o/repo.git' 'non-matching remote'

# ── 4. Absent pattern file — no directives, no output, no noise, still PUBLIC.
PRIVACY_GATE_PATTERNS="$TMP/does-not-exist" check public 'git@zzbox1:o/repo.git' 'absent pattern file'
export PRIVACY_GATE_PATTERNS="$PATFILE"

# ── 5. Trim parity of private_host_res after the `sed` fork was replaced by ${…} trimming.
#    Leading spaces AND tabs, trailing whitespace, `#` comments, blank/whitespace-only lines,
#    an EMPTY directive, and a CRLF line ending must all behave exactly as before.
TRIMFILE="$TMP/trim.txt"
printf 'private-host:   \ttabbed\\.example   \n#  private-host:commented\\.example\n\n  \nprivate-host:\nprivate-host:crlf\\.example\r\n' > "$TRIMFILE"
got="$(PRIVACY_GATE_PATTERNS="$TRIMFILE" bash -c 'set -euo pipefail; source "$1"; private_host_res' _ "$LIB" 2>"$TMP/trim.err")"
want=$'tabbed\\.example\ncrlf\\.example'
if [[ "$got" == "$want" && ! -s "$TMP/trim.err" ]]; then
  ok "17ac private_host_res trim parity (tabs/trailing/comment/blank/empty/CRLF)"
else
  bad "17ac private_host_res trim parity — got $(printf '%q' "$got"), want $(printf '%q' "$want"); stderr: $(cat "$TMP/trim.err")"
fi

exit "$rc"
