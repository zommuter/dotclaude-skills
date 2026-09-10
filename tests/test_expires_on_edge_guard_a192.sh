#!/usr/bin/env bash
# id:a192 -- RED SPEC for the `expires-on:` typed edge + its staleness guard.
#
# NO `# roadmap:` HEADER, DELIBERATELY. This item lives in `TODO.md`, not `ROADMAP.md`,
# so `tests/run-tests.sh`'s EXPECTED-RED carve-out (which keys on a `# roadmap:XXXX`
# item's checkbox in ROADMAP.md) does not and must not apply. Consequence, stated rather
# than hidden: this file's failures ALWAYS COUNT and the suite is RED until
# `relay/scripts/expires-on-scan.sh` ships. That is the intended signal.
#
# fails-against: a naive PROSE detector -- the obvious wrong implementation, which matches
#   English ("until id:XXXX lands") instead of the declared `expires-on:` marker. Measured
#   on this repo 2026-09-10: of 26 live tracked files carrying temporary-clause prose,
#   18 are under `tests/` and are test-header PROVENANCE ("RED until id:XXXX lands"), not
#   broken promises. A prose detector is therefore wrong in the large majority of its hits
#   and gets muted -- the failure class this repo already owns. Case (g) is the assertion
#   that pins it, and it is ordered LAST on purpose (see MULTI, below).
# fails-against-mutation: mkdir -p relay/scripts && printf '#!/usr/bin/env bash\nset -uo pipefail\nr="${1:-.}"\ngrep -rnIE "(expires-on:[0-9a-fA-F]{4})|([Uu]ntil id:[0-9a-fA-F]{4})" "$r" || true\nexit 0\n' > relay/scripts/expires-on-scan.sh && chmod +x relay/scripts/expires-on-scan.sh
# fails-against-assertion: PROSE CONTROL: prose with a closed id
#
#   WHY A MUTATION THAT *WRITES* THE STRAWMAN, rather than a `-rev:` SHA. A `-rev:` case
#   would have to name a revision at which `relay/scripts/expires-on-scan.sh` is ABSENT
#   (every revision, today), so the test would die at the "not built" sanity probe with
#   every real assertion UNREACHED -- red for the wrong reason, which is exactly the
#   vacuity `tests/verify-negative-cases.py` exists to refuse (its instance (a)). The
#   mutation instead INSTALLS the specific wrong implementation this spec exists to
#   forbid, so the case has demonstrated killing power against the one rule that must not
#   be broken, and it stays meaningful AFTER the real scanner lands (it overwrites it).
#
#   MULTI: this file uses a NON-EXITING accumulator, so several FAIL lines fire under the
#   mutation -- the strawman also breaks (a)-(f), since it neither resolves closure nor
#   honours the exemptions. The declared assertion must therefore match the LAST fired
#   FAIL line, which is why case (g) is ordered last and nothing follows it. The declared
#   substring is narrowed to the FAIL wording specifically (`PROSE CONTROL: prose with a
#   closed id`): the bare label `(g) PROSE CONTROL` appears on BOTH the pass and fail line,
#   which the runner's UNIQUE-SITE check refuses (2 sites proves nothing about which fired).
#
#   HONEST GAP in this declaration: the runner verifies BOTH directions (GREEN-NOW and
#   RED-THERE). GREEN-NOW cannot hold until the scanner exists -- that is what "RED spec"
#   means. `--list` (static checks + coverage) is the only meaningful run of this
#   declaration before the item ships; `make verify-negatives` will report this file's
#   case as failing GREEN-NOW until then. Do not "fix" that by loosening the case.
#
# ----------------------------------------------------------------- WHAT IS BEING SPECCED
# THE DEFECT. This repo carries SELF-EXPIRING PROSE: a clause that is correct only until
# some item closes. Live example in the owner's `~/.claude/CLAUDE.md`: "CAUTION, delete
# this clause when id:0246 closes: `scan-routed.sh --apply` is NOT safe to run right now."
# Nothing notices when `id:0246` closes, so a file loaded every session silently starts
# asserting something false. Measured population: 1,074 id-keyed temporary clauses
# fleet-wide; 17 already STALE in LIVE files, two of them live behavioural claims inside
# production scripts (`relay/scripts/todo-conformance.sh:953` "Until id:2654 ships, this
# ratchet...", `relay/scripts/changelog-append.sh:15` "when e647 ships"), both with ids
# that have already closed.
#
# THE DESIGN, and its one inviolable rule. A clause DECLARES its own expiry with an
# explicit typed edge: `<!-- expires-on:XXXX -->`, XXXX a 4-hex item id. The guard fails
# when XXXX is CLOSED while the marker still stands. It NEVER infers expiry from English
# prose -- see `fails-against:` above for the measurement that makes prose detection
# unusable. Only the declared marker counts.
#
# THE CONTRACT THIS FILE PINS (implementation is NOT part of this item's test):
#   relay/scripts/expires-on-scan.sh [<root>]      root defaults to git toplevel
#   env EXPIRES_ON_EXTRA_PATHS  colon-separated ABSOLUTE paths scanned IN ADDITION to
#                               <root>. EMPTY BY DEFAULT -- see LIMITATION below.
#   env EXPIRES_ON_SCAN_LOG     detail log path (repo convention: short stdout, detail
#                               to a log). Must be injectable; never hardcoded.
#   stdout, one finding per line, machine-readable, naming FILE and LINE:
#       STALE    <path>:<lineno> expires-on:<tok>    tok exists and is CLOSED
#       DANGLING <path>:<lineno> expires-on:<tok>    tok exists NOWHERE (a typo)
#   exit 1 when any finding, 0 when clean. Findings are LOUD, never advisory-quiet.
#
#   CLOSURE / EXISTENCE are OWNERSHIP-ANCHORED, reusing `relay/scripts/lib-anchored-id.sh`
#   rather than a fresh regex:
#     EXISTS  -- `token_own_checkbox_marker_in_text` (some `- [ ]`/`- [x]` line OWNS
#                `<!-- id:TOK -->`) over <root>'s TODO.md, ROADMAP.md, TODO.archive.md,
#                ROADMAP.archive.md.
#     CLOSED  -- the same predicate narrowed to `- [x]`.
#   WHY THAT PREDICATE AND NOT `token_marker_in_files`: the latter's `_own_marker_re` has a
#   KNOWN HOLE (filed `id:d9ff`) -- it accepts a marker QUOTED AS AN EXAMPLE inside another
#   item's body, because form 1 of that regex is not line-position-anchored. This repo's
#   ledgers are full of retrospective prose that quotes markers, so that hole would make
#   arbitrary tokens read as "existing" (and, for a quoted `- [x]` example, as "closed").
#   The checkbox-anchored predicate requires a real checkbox line, which is the ownership
#   property this guard's verdict actually needs. The CLOSED narrowing does not exist in
#   that library yet and must be added there as a sibling -- not hand-rolled in the scanner.
#
#   SCAN EXEMPTIONS (dated historical records; a stale promise there is CORRECT history):
#     any `*.archive.md`, and anything under `docs/meeting-notes/`.
#   Exempt from being SCANNED is NOT exempt from being CONSULTED: the archives remain
#   closure sources. Case (b) pins that distinction, because collapsing the two is the
#   obvious implementation shortcut and it would make every archived item read as
#   non-existent, silently converting STALE findings into DANGLING ones.
#
# ------------------------------------------------------------------------ LIMITATION
# The clause that MOTIVATED this item lives in `~/.claude/CLAUDE.md`, which is OUTSIDE this
# repo. A hermetic test cannot scan it and this file DOES NOT TRY -- it never reads the real
# `~/.claude/CLAUDE.md`, and `HOME` is redirected into the scratch so it could not if it
# tried. The opt-in path is specced instead (`EXPIRES_ON_EXTRA_PATHS`, empty by default) and
# asserted against a FIXTURE file in a temp dir, case (f). So: the guard as specced does not
# cover the file that prompted it until a NON-TEST entry point (a wrapper, a hook, or the
# owner's own invocation) names that path explicitly. That residual is real and is not
# closed by this item.
#
# ------------------------------------------------------------------------ HERMETICITY
# Yesterday a test in this repo destroyed 19 live production units by inheriting a default
# path (`id:1975`). Everything is therefore injected, and each variable is named with its
# reason:
#   HOME, XDG_CONFIG_HOME, XDG_DATA_HOME, XDG_CACHE_HOME -> $tmpdir  so nothing can reach
#       the real ~/.claude (logs, skills, settings) or ~/.config/relay (queues, units).
#   EXPIRES_ON_SCAN_LOG -> $tmpdir  so the scanner's detail log cannot land in ~/.claude/logs.
#   EXPIRES_ON_EXTRA_PATHS -> explicitly "" on every default-case call, so an inherited
#       value from the caller's environment cannot add a real file to the scan.
#   GIT_CONFIG_GLOBAL/GIT_CONFIG_SYSTEM -> /dev/null, GIT_CEILING_DIRECTORIES -> $tmpdir,
#       so the fixture's `git init` reads no user identity/hooksPath (the global
#       core.hooksPath points at this repo's real hooks) and git discovery cannot walk
#       upward out of the scratch into a real repo.
# No network. The fixture root is a real, committed git repo so the contract stays
# implementation-agnostic: a `git ls-files` enumeration and a filesystem walk both work.
#
# The literal marker is never written verbatim in this file -- fixtures build it through
# mark() below. Otherwise the shipped scanner would flag THIS file's own heredocs, which is
# the self-reference trap that makes a guard's first real run look like 40 false positives.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN="$ROOT/relay/scripts/expires-on-scan.sh"

fail=0
ok()  { echo "PASS: $*"; }
bad() { echo "FAIL: $*"; fail=1; }

# mark <tok> -- the declared typed edge, assembled so no literal 4-hex marker appears
# in this file's source (see the self-reference note above).
mark() { printf '<!-- expires-on:%s -->' "$1"; }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

export HOME="$tmpdir/home"
export XDG_CONFIG_HOME="$tmpdir/home/.config"
export XDG_DATA_HOME="$tmpdir/home/.local/share"
export XDG_CACHE_HOME="$tmpdir/home/.cache"
export EXPIRES_ON_SCAN_LOG="$tmpdir/expires-on-scan.log"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CEILING_DIRECTORIES="$tmpdir"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"

[[ -x "$SCAN" ]] || {
  echo "FAIL: sanity: expires-on-scan.sh not executable at $SCAN (id:a192 not built -- this is the RED spec)"
  exit 1
}

# ------------------------------------------------------------------ FIXTURE LEDGERS
# Token roles, fixed once so every case reads unambiguously:
#   c105 -- CLOSED, in TODO.md            (the ordinary stale case)
#   dcba -- CLOSED, in TODO.archive.md    (closure must still resolve through an archive)
#   0aef -- OPEN,   in TODO.md            (clause legitimately live)
#   beef -- OPEN,   in ROADMAP.md         (second live ledger is consulted too)
#   ffff -- EXISTS NOWHERE                (dangling edge / typo)
repo="$tmpdir/repo"
mkdir -p "$repo/docs/meeting-notes" "$repo/tests"

cat > "$repo/TODO.md" <<'EOF'
# TODO

## Done
- [x] A thing that has shipped <!-- id:c105 -->

## Current
- [ ] A thing still in flight <!-- id:0aef -->
EOF

cat > "$repo/ROADMAP.md" <<'EOF'
# ROADMAP
- [ ] Queued executor work <!-- id:beef -->
EOF

cat > "$repo/TODO.archive.md" <<'EOF'
# TODO archive
- [x] An archived, closed item <!-- id:dcba -->
EOF

# A ledger line that merely QUOTES a marker as an example. `ffff` must still read as
# NONEXISTENT: this is the `id:d9ff` hole in `_own_marker_re`, and the reason the contract
# above mandates the checkbox-anchored predicate instead.
{
  printf '\n'
  printf 'Prose note: a marker renders as `%s` in a ledger line.\n' "$(mark ffff)"
  printf 'Prose note: and `<!-- id:ffff -->` is what an owning marker looks like.\n'
} >> "$repo/TODO.md"

# ------------------------------------------------------------------ FIXTURE SCAN TARGETS
{
  printf '# Live doc\n\n'
  printf 'CAUTION, delete this clause when id:c105 closes: the old path is unsafe. %s\n' "$(mark c105)"
} > "$repo/live-stale.md"

{
  printf '# Live script\n'
  printf '# Until id:dcba ships, this ratchet is advisory only. %s\n' "$(mark dcba)"
} > "$repo/relay-ish.sh"

{
  printf '# Live doc, clause still valid\n'
  printf 'Hold dispatch until id:0aef closes. %s\n' "$(mark 0aef)"
  printf 'And a second live edge. %s\n' "$(mark beef)"
} > "$repo/live-open.md"

{
  printf '# Live doc with a typo in its edge\n'
  printf 'This clause points at an id that does not exist. %s\n' "$(mark ffff)"
} > "$repo/live-dangling.md"

# THE CONTROL. Prose that names a CLOSED id and carries NO marker. Both spellings that
# dominate the real corpus: the test-header provenance form (18 of 26 live matches), and
# the inline-doc form.
cat > "$repo/tests/test_provenance_shape.sh" <<'EOF'
#!/usr/bin/env bash
# RED until id:c105 lands -- this header records WHAT this test was authored against.
# It is provenance, not a promise, and it stays correct forever.
echo ok
EOF

cat > "$repo/live-prose-only.md" <<'EOF'
# Live doc, prose only
Once id:c105 closes we can simplify this, but nothing here is wrong today.
This was written when id:dcba shipped.
EOF

# EXEMPT targets: dated historical records. A stale promise here is correct history.
printf 'Historical: delete when id:c105 closes. %s\n' "$(mark c105)" >> "$repo/TODO.archive.md"
printf '# Meeting note\n\nDecision: revisit when id:c105 closes. %s\n' "$(mark c105)" \
  > "$repo/docs/meeting-notes/2026-01-01-1200-example.md"

# OUTSIDE the repo -- stands in for the real ~/.claude/CLAUDE.md, which this test never reads.
outside="$tmpdir/outside"
mkdir -p "$outside"
printf '# Stand-in for an out-of-repo config file\nCAUTION, delete when id:c105 closes. %s\n' \
  "$(mark c105)" > "$outside/CLAUDE.md"

git -C "$repo" init -q
git -C "$repo" add -A
git -C "$repo" -c user.name=t -c user.email=t@e commit -qm fixture

# ------------------------------------------------------------------ RUNNER
# Captures stdout+stderr MERGED and the exit status, without `set -e` killing us and
# without a pipe (tests/lint-pipefail-sigpipe.py bans producer-into-early-consumer pipes
# under pipefail; every match below uses `<<<` or `< <(...)` for the same reason).
scan_out=''; scan_rc=0
run_scan() {  # run_scan [extra-paths] -- always pins EXPIRES_ON_EXTRA_PATHS explicitly
  scan_rc=0
  scan_out="$(EXPIRES_ON_EXTRA_PATHS="${1:-}" bash "$SCAN" "$repo" 2>&1)" || scan_rc=$?
}
has() { grep -qE -- "$1" <<<"$scan_out"; }

# ------------------------------------------------------------------ (a) STALE is reported
run_scan
if has "^STALE[[:space:]]+.*live-stale\.md:[0-9]+[[:space:]]+expires-on:c105$"; then
  ok "(a) a marker whose id is CLOSED is reported STALE, naming file and line"
else
  bad "(a) STALE not reported for live-stale.md / closed id c105 -- got:
$scan_out"
fi
[[ "$scan_rc" -eq 1 ]] \
  && ok "(a2) exit status 1 on findings (loud, not advisory)" \
  || bad "(a2) expected exit 1 with findings present, got $scan_rc"

# ------------------------------------------------------------------ (b) closure via archive
# The archives are EXEMPT as scan targets but REMAIN closure sources. Collapsing those two
# roles is the obvious shortcut and would turn this STALE finding into a DANGLING one.
if has "^STALE[[:space:]]+.*relay-ish\.sh:[0-9]+[[:space:]]+expires-on:dcba$"; then
  ok "(b) closure resolves through TODO.archive.md (archives are consulted, not scanned)"
else
  bad "(b) a marker closed only in TODO.archive.md was not reported STALE -- got:
$scan_out"
fi
has "^DANGLING[[:space:]]+.*expires-on:dcba" \
  && bad "(b2) dcba reported DANGLING -- the archive was skipped as a closure source too" \
  || ok "(b2) dcba is not mis-reported as dangling"

# ------------------------------------------------------------------ (c) OPEN id is silent
for tok in 0aef beef; do
  if has "expires-on:$tok"; then
    bad "(c) a marker whose id is still OPEN ($tok) was reported -- the clause is legitimately live -- got:
$scan_out"
  else
    ok "(c) an OPEN id's marker ($tok) is not reported"
  fi
done

# ------------------------------------------------------------------ (d) DANGLING is DISTINCT
# A marker naming an id that exists nowhere is a TYPO. It must fail loudly under its own
# condition, never pass quietly as "not closed yet" -- a typo'd edge that reads as live is
# a guard that silently protects nothing.
if has "^DANGLING[[:space:]]+.*live-dangling\.md:[0-9]+[[:space:]]+expires-on:ffff$"; then
  ok "(d) a marker naming a nonexistent id is reported DANGLING, as its own condition"
else
  bad "(d) dangling edge (expires-on:ffff) not reported as a DISTINCT DANGLING condition -- got:
$scan_out"
fi
has "^STALE[[:space:]]+.*expires-on:ffff" \
  && bad "(d2) a nonexistent id was reported STALE -- the two conditions are conflated" \
  || ok "(d2) DANGLING is not reported as STALE"

# ------------------------------------------------------------------ (e) exempt SCAN targets
for exempt in 'TODO\.archive\.md' 'docs/meeting-notes/'; do
  if has "$exempt"; then
    bad "(e) an EXEMPT path ($exempt) was scanned -- dated historical records keep their stale promises -- got:
$scan_out"
  else
    ok "(e) exempt path not scanned: $exempt"
  fi
done

# ------------------------------------------------------------------ (f) extra paths OPT IN
# Asserted against a FIXTURE standing in for ~/.claude/CLAUDE.md. The real file is never
# read by this test -- see LIMITATION in the header.
has "$(printf '%s' "$outside/CLAUDE.md" | sed 's/[.[\*^$]/\\&/g')" \
  && bad "(f) an out-of-repo path was scanned with EXPIRES_ON_EXTRA_PATHS empty -- the default must add nothing" \
  || ok "(f) default scan adds no out-of-repo path (EXPIRES_ON_EXTRA_PATHS empty)"

run_scan "$outside/CLAUDE.md"
if has "^STALE[[:space:]]+.*outside/CLAUDE\.md:[0-9]+[[:space:]]+expires-on:c105$"; then
  ok "(f2) EXPIRES_ON_EXTRA_PATHS opts an out-of-repo file into the scan"
else
  bad "(f2) EXPIRES_ON_EXTRA_PATHS did not bring the named out-of-repo file into the scan -- got:
$scan_out"
fi

# ------------------------------------------------------------------ (g) THE CONTROL, LAST
# Ordered last deliberately: it is the declared `fails-against-assertion`, and the runner
# requires the declaration to match the LAST fired FAIL line (this file accumulates).
# 18 of 26 live tracked files carrying temporary-clause prose are test-header provenance.
# A prose detector is wrong on nearly all of them and gets muted. Only the declared marker
# counts -- no exceptions, no heuristics, no "high-confidence prose" tier.
run_scan
g_fail=0
for proseish in 'test_provenance_shape\.sh' 'live-prose-only\.md'; do
  has "$proseish" && g_fail=1
done
if [[ "$g_fail" -eq 0 ]]; then
  ok "(g) PROSE CONTROL: prose naming a CLOSED id with NO expires-on marker is not reported"
else
  bad "(g) PROSE CONTROL: prose with a closed id and NO marker was reported -- expiry must NEVER be inferred from English; the marker is the only signal -- got:
$scan_out"
fi

[[ "$fail" -eq 0 ]] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
