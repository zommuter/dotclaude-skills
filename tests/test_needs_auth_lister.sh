#!/usr/bin/env bash
# roadmap:1750 — offline `@needs-auth` lister (extend gather-human-backlog.sh).
#
# WHY (/meeting 2026-07-14-1135, D4; DEP a505): `/relay human` surfaces human-gated work
# but costs a Claude session. The one genuine differentiator wanted is an AI-free, OFFLINE
# lister of every `@needs-auth` REVIEW_ME box across own repos — a plain bash sweep the
# human runs with no network and no model. a505 pinned the marker + its FOUR mandatory
# fields (what-secret / where-it-goes / exact-command / why); this item adds the FILTER.
#
# Asserts (hermetic — a temp relay.toml + temp own repos with crafted REVIEW_ME.md):
#   (1) `gather-human-backlog.sh --needs-auth` lists a conforming @needs-auth box and
#       shows ALL FOUR field VALUES (what / where / command / why);
#   (2) output is PLAIN human-readable, NOT TSV (no tab characters);
#   (3) an ordinary (non-@needs-auth) REVIEW_ME box does NOT appear in the --needs-auth view;
#   (4) a CLOSED `- [x]` @needs-auth box is NOT listed (open boxes only);
#   (5) the lister is AI-free / offline — the script source spawns no model and no network
#       client (no `claude`, `curl`, `wget`, `nc`), and the run exits 0 with no network.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/relay/scripts/gather-human-backlog.sh"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ -x "$SCRIPT" ]] || fail "gather-human-backlog.sh not found/executable at $SCRIPT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- repo WITH a conforming @needs-auth box (+ a closed one + an ordinary box) ----
mkdir -p "$tmp/src/repoNA"
cat >"$tmp/src/repoNA/REVIEW_ME.md" <<'MD'
# REVIEW_ME

- [ ] Link the Signal linked device @needs-auth <!-- id:e588 -->
  - what-secret: SENTINEL_SIGNAL_QR the linked-device QR code
  - where-it-goes: SENTINEL_WHERE scanned by signal-cli on zomni
  - exact-command: `signal-cli link -n SENTINEL_CMD_relay`
  - why: SENTINEL_WHY zkm-signal ingest strands without a linked device

- [ ] An ordinary review box with no marker <!-- id:9999 -->

- [x] A CLOSED needs-auth box already provided @needs-auth <!-- id:aaaa -->
  - what-secret: SENTINEL_CLOSED should never be listed
MD

# --- a second own repo WITHOUT any @needs-auth box (control: no spurious block) ----
mkdir -p "$tmp/src/repoPlain"
cat >"$tmp/src/repoPlain/REVIEW_ME.md" <<'MD'
# REVIEW_ME

- [ ] Just a normal review item <!-- id:1212 -->
MD

cat >"$tmp/relay.toml" <<'TOML'
[repos.repoNA]
classification = "own"
confirmed = "2026-01-01"

[repos.repoPlain]
classification = "own"
confirmed = "2026-01-01"
TOML

out="$(RELAY_TOML="$tmp/relay.toml" SRC_DIR="$tmp/src" bash "$SCRIPT" --needs-auth 2>"$tmp/err")" && rc=0 || rc=$?
[[ $rc -eq 0 ]] || fail "--needs-auth should exit 0, got $rc (stderr: $(cat "$tmp/err"))"

# (1) all FOUR field values present.
grep -q 'SENTINEL_SIGNAL_QR' <<<"$out" || fail "what-secret value missing (out: $out)"
grep -q 'SENTINEL_WHERE'     <<<"$out" || fail "where-it-goes value missing (out: $out)"
grep -q 'SENTINEL_CMD_relay' <<<"$out" || fail "exact-command value missing (out: $out)"
grep -q 'SENTINEL_WHY'       <<<"$out" || fail "why value missing (out: $out)"
# and the repo is named, and the box's id surfaces.
grep -q 'repoNA' <<<"$out" || fail "repo name not shown for the @needs-auth box (out: $out)"
grep -q 'e588'   <<<"$out" || fail "box id (e588) not shown (out: $out)"

# (2) PLAIN, non-TSV: no tab characters anywhere in the listing.
if printf '%s' "$out" | grep -qP '\t'; then
  fail "--needs-auth output contains TAB characters (expected plain non-TSV, out: $out)"
fi

# (3) an ordinary non-@needs-auth box must NOT appear.
! grep -q 'An ordinary review box with no marker' <<<"$out" \
  || fail "an ordinary (non-@needs-auth) box leaked into the --needs-auth view (out: $out)"
! grep -q 'Just a normal review item' <<<"$out" \
  || fail "a plain-repo review box leaked into the --needs-auth view (out: $out)"

# (4) a CLOSED @needs-auth box must NOT be listed.
! grep -q 'SENTINEL_CLOSED' <<<"$out" \
  || fail "a CLOSED (- [x]) @needs-auth box was listed (out: $out)"

# (5) AI-free / offline: the script spawns no MODEL invocation (`claude -p`/`claude --…`)
#     and no network client (`curl`/`wget`/`nc`). Strip whole-line comments FIRST (the
#     usage/doc comments legitimately mention `claude -p`, and code legitimately references
#     the `.claude/` DIRECTORY path — neither is a model invocation).
code="$(grep -vE '^[[:space:]]*#' "$SCRIPT")"
if grep -qE '(^|[^[:alnum:]_./])claude[[:space:]]+-' <<<"$code" ; then
  fail "gather-human-backlog.sh appears to invoke the claude model CLI — the lister must be AI-free"
fi
if grep -qE '(^|[^[:alnum:]_])(curl|wget|nc)([^[:alnum:]_]|$)' <<<"$code" ; then
  fail "gather-human-backlog.sh appears to invoke a network client — the lister must be offline"
fi

pass "offline @needs-auth lister: 4 fields, plain non-TSV, filters ordinary+closed boxes, AI-free (1750)"
