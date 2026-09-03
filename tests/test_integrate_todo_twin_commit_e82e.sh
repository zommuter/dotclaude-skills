#!/usr/bin/env bash
# roadmap:e82e — the driver-side tick's TODO TWIN must be STAGED AND COMMITTED by
# integrate.sh, not left dirty in the canonical checkout.
#
# WHY THIS FILE EXISTS AT THE integrate.sh SEAM: tests/test_roadmap_tick_todo_twin.sh
# exercises roadmap-tick.sh STANDALONE and never invokes integrate.sh, so it can never see
# the staging gap — roadmap-tick.sh performs no git mutation at all, and integrate.sh used
# to `git add -- ROADMAP.md` only. The result was a TODO.md modified-but-uncommitted in the
# CANONICAL checkout: the run reported clean (step 8's `git-lock-push --ff-only` returns
# before the id:aa93 tracked-dirty guard, which lives in the rebase branch), and one round
# later the repo classified `dirty_block` with every later integrate.sh handing back at
# step-1 EX_CLEAN_TREE PERMANENTLY — the tick is idempotent, so a retry cleared nothing.
# A green standalone suite is exactly what let this survive; hence: drive a REAL integrate.
#
# Sections:
#   (1) worked id WITH an open TODO twin  → canonical checkout CLEAN after integrate, both
#       ledgers ticked AND committed, in one scoped commit naming both files.
#   (2) worked id with NO TODO twin       → TODO.md is neither staged nor committed, and no
#       empty commit is produced (the ROADMAP-only commit still lands).
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INT="${INT_OVERRIDE:-$SRC_DIR/relay/scripts/integrate.sh}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ERRLOG="$TMP/integrate.stderr"
: >"$ERRLOG"
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; [[ -s "$ERRLOG" ]] && { echo "       last integrate.sh stderr:"; tail -n 20 "$ERRLOG" | sed 's/^/       | /'; }; exit 1; }

# TICK-VISIBILITY, changed by id:2eba (2026-09-03): integrate.sh step 6b runs
# roadmap-archive.sh AFTER the tick, and the archiver no longer leaves a stub -- it removes
# the archived line from the live ledger outright. So a just-closed id is legitimately
# ABSENT from ROADMAP.md and present as `- [x]` in ROADMAP.archive.md. Assert the UNION,
# which is what orphan-scan --cross-ledger already reads (routed:42c9). Asserting only the
# live file would pin the stub convention that id:2eba deliberately removed.
ticked_in_union() { # <checkout> <id>
  grep -q "^- \[x\].*id:$2" "$1/ROADMAP.md" 2>/dev/null && return 0
  grep -q "^- \[x\].*id:$2" "$1/ROADMAP.archive.md" 2>/dev/null
}


[[ -x "$INT" ]] || fail "integrate.sh not found/executable at $INT"

PUSH_STUB="$TMP/push-stub.sh"
cat > "$PUSH_STUB" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$PUSH_STUB"

# ── hermetic origin + main checkout seeded with BOTH ledgers ──
build() { # <suffix> <roadmap-file> <todo-file> → prints the main checkout path
  local sfx="$1" roadmap="$2" todo="$3"
  local origin seed main
  origin="$TMP/o-$sfx.git"; seed="$TMP/s-$sfx"; main="$TMP/m-$sfx"
  git init --bare -b main -q "$origin"
  git clone -q "$origin" "$seed" 2>/dev/null
  git -C "$seed" config user.email t@e.st
  git -C "$seed" config user.name t
  echo base > "$seed/f"
  cp "$roadmap" "$seed/ROADMAP.md"
  cp "$todo" "$seed/TODO.md"
  git -C "$seed" add -A
  git -C "$seed" commit -qm base
  git -C "$seed" push -q -u origin main
  git clone -q "$origin" "$main" 2>/dev/null
  git -C "$main" config user.email t@e.st
  git -C "$main" config user.name t
  printf '%s' "$main"
}

child() { # <main> <name> → prints the worktree path
  local main="$1" name="$2"
  local wt="$TMP/wt-$name"
  git -C "$main" worktree add -q -b "relay/$name" "$wt" main
  echo "work-$name" > "$wt/g-$name"
  git -C "$wt" add -A
  git -C "$wt" commit -qm "child work $name"
  printf '%s' "$wt"
}

cfg() { # <suffix> <repo-name> → prints the config dir
  local d="$TMP/cfg-$1"
  mkdir -p "$d"
  printf '[repos.%s]\nstatus = "active"\n' "$2" > "$d/relay.toml"
  printf '%s' "$d"
}

cat > "$TMP/roadmap.md" <<'EOF'
# Roadmap

- [ ] [ROUTINE] the worked item <!-- id:aaaa -->
- [ ] [ROUTINE] an untouched item <!-- id:bbbb -->
EOF

# =====================================================================================
# (1) worked id HAS an open TODO twin — both ledgers must end up committed and clean
# =====================================================================================
cat > "$TMP/todo-twin.md" <<'EOF'
# TODO

## Current

- [ ] the worked item, design view <!-- id:aaaa -->
- [ ] an untouched item, design view <!-- id:bbbb -->
EOF

M1="$(build twin "$TMP/roadmap.md" "$TMP/todo-twin.md")"; R1="$(basename "$M1")"
W1="$(child "$M1" twin)"
C1="$(cfg twin "$R1")"
rc=0
out="$(FABLES_CONFIG="$C1" INTEGRATE_GIT_LOCK_PUSH="$PUSH_STUB" \
  "$INT" --repo "$R1" --path "$M1" --worktree "$W1" --branch relay/twin \
         --summary "close aaaa" --run r1 --label "executor (sonnet, relay-loop)" \
         --ids aaaa --verdict execute --substantive true 2>>"$ERRLOG")" || rc=$?
[[ $rc -eq 0 ]] || fail "(1) execute integrate exited $rc: $out"

# THE regression assertion: the canonical checkout is CLEAN. Before the fix TODO.md was
# left as ` M TODO.md` here, which is exactly what wedged the repo one round later.
porc="$(git -C "$M1" status --porcelain)"
[[ -z "$porc" ]] || fail "(1) canonical checkout LEFT DIRTY after integrate — the TODO twin was written but never staged/committed:
$porc"

# both ledgers ticked ON DISK …
ticked_in_union "$M1" aaaa || fail "(1) ROADMAP twin id:aaaa not ticked (checked ROADMAP.md and ROADMAP.archive.md)"
grep -q '^- \[x\].*id:aaaa' "$M1/TODO.md"    || fail "(1) TODO twin id:aaaa not ticked"
grep -q '^- \[ \].*id:bbbb' "$M1/TODO.md"    || fail "(1) an unworked TODO item was ticked — the twin write is not id-scoped"

# … and ticked IN THE COMMITTED TREE (not merely in the working tree)
grep -q '^- \[x\].*id:aaaa' < <(git -C "$M1" show HEAD:TODO.md) \
  || fail "(1) TODO.md tick is not present in the committed tree"
# Same id:2eba union rule as on disk: the archiver may have moved the closed line out of
# ROADMAP.md and into ROADMAP.archive.md within the SAME integrate run, so the committed
# proof of the tick can legitimately live in either file. Both are read from HEAD, so this
# still proves the tick was COMMITTED and not merely left in the working tree -- which is
# the property this assertion exists for.
# `< <(…)` not `… | grep -q`: grep -q exits at the first match, which under `set -o pipefail`
# SIGPIPEs the producer and makes the pipeline status non-zero at random. That is the id:81d5
# shape and this repo lints for it with no exemptions.
grep -q '^- \[x\].*id:aaaa' \
  < <(git -C "$M1" show HEAD:ROADMAP.md 2>/dev/null; git -C "$M1" show HEAD:ROADMAP.archive.md 2>/dev/null) \
  || fail "(1) ROADMAP tick is not present in the committed tree (checked HEAD:ROADMAP.md and HEAD:ROADMAP.archive.md)"

# one scoped commit touching BOTH ledgers, and NOTHING else (id:debf: never -A/./-u)
tickmsg="$(git -C "$M1" log -1 --format=%s -- TODO.md)"
[[ "$tickmsg" == *"tick worked items"* ]] \
  || fail "(1) TODO.md's last commit is not the tick commit (got: '$tickmsg')"
tick_sha="$(git -C "$M1" log -1 --format=%H --grep='tick worked items')"
[[ -n "$tick_sha" ]] || fail "(1) no 'tick worked items' commit at all"
mapfile -t touched < <(git -C "$M1" show --name-only --format= "$tick_sha" | sort)
[[ "${touched[*]}" == "ROADMAP.md TODO.md" ]] \
  || fail "(1) the tick commit touched '${touched[*]}', expected exactly 'ROADMAP.md TODO.md' — staging is not scoped"
pass "(1) id:e82e — an integrate whose worked id has an open TODO twin commits BOTH ledgers and leaves the checkout clean"

# =====================================================================================
# (2) worked id has NO TODO twin — TODO.md must not be staged, and no empty commit
# =====================================================================================
cat > "$TMP/todo-notwin.md" <<'EOF'
# TODO

## Current

- [ ] some entirely unrelated item <!-- id:cccc -->
EOF

M2="$(build notwin "$TMP/roadmap.md" "$TMP/todo-notwin.md")"; R2="$(basename "$M2")"
W2="$(child "$M2" notwin)"
C2="$(cfg notwin "$R2")"
before_todo_commit="$(git -C "$M2" rev-parse HEAD)"
rc=0
out="$(FABLES_CONFIG="$C2" INTEGRATE_GIT_LOCK_PUSH="$PUSH_STUB" \
  "$INT" --repo "$R2" --path "$M2" --worktree "$W2" --branch relay/notwin \
         --summary "close aaaa" --run r1 --label "executor (sonnet, relay-loop)" \
         --ids aaaa --verdict execute --substantive true 2>>"$ERRLOG")" || rc=$?
[[ $rc -eq 0 ]] || fail "(2) execute integrate exited $rc: $out"

porc="$(git -C "$M2" status --porcelain)"
[[ -z "$porc" ]] || fail "(2) canonical checkout left dirty:
$porc"
ticked_in_union "$M2" aaaa || fail "(2) ROADMAP id:aaaa not ticked (checked ROADMAP.md and ROADMAP.archive.md)"
grep -q '^- \[ \].*id:cccc' "$M2/TODO.md"    || fail "(2) an unrelated TODO item was ticked"

# TODO.md must carry NO commit newer than the base commit …
todo_commits="$(git -C "$M2" rev-list "$before_todo_commit"..HEAD -- TODO.md | wc -l)"
[[ "$todo_commits" -eq 0 ]] \
  || fail "(2) TODO.md was committed ($todo_commits commit(s)) although the worked id has no TODO twin"

# … and the tick commit must exist, touching ROADMAP.md ALONE (no empty commit either way)
mapfile -t touched < <(git -C "$M2" show --name-only --format= \
  "$(git -C "$M2" log -1 --format=%H --grep='tick worked items')" | sort)
[[ "${touched[*]}" == "ROADMAP.md" ]] \
  || fail "(2) the tick commit touched '${touched[*]}', expected 'ROADMAP.md' alone"
[[ -n "${touched[0]:-}" ]] || fail "(2) the tick commit is EMPTY"
pass "(2) id:e82e — an id with no TODO twin neither stages TODO.md nor produces an empty commit"

echo "ALL PASS: $(basename "$0")"
