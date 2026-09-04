#!/usr/bin/env bash
# todo-conformance.sh — a POSITIVE grammar for TODO.md / the shared inbox, the sibling of
# roadmap-lint.sh (id:3441). So NO work hides in a malformed ledger line.
#
# WHY (user directive 2026-06-25, escalated twice): `/relay` is only reliable if every
# TODO/inbox entry is well-formed enough to be SEEN. roadmap-lint.sh already enforces a
# grammar on open ROADMAP items; this does the same for TODO.md (and the inbox). A scan
# of the dotclaude-skills TODO found a bare `placeholder` line and a checkbox-less pointer
# bullet that NO tool saw — exactly the silent backlog this closes.
#
# This script DETECTS (classes: missing-id / orphan). To RESOLVE a finding, apply the
# owner-approved policies P1–P4 in relay/references/todo-conversion-policies.md.
#
# THE TODO GRAMMAR — a top-level (NON-indented) non-blank line is CONFORMING iff it is:
#   • a markdown header            `^#{1,6} …`
#   • an HTML-comment-only line    `^<!-- … -->$`
#   • a well-formed checkbox item  `^- \[[ xX]\] …`
#       └ an OPEN `- [ ]` item must ALSO carry an `<!-- id:XXXX -->` (4-hex) token.
# Indented continuation lines (`^[[:space:]]…`) are NEVER linted (an item's body), exactly
# like roadmap-lint. EXEMPT (never flagged): any line bearing `<!-- lint-ok: <reason> -->`
# or an intentional cross-repo pointer `<!-- ref:XXXX -->`.
#
# CLASSES (output `<class>\t<lineno>\t<text>`):
#   missing-id  an open checkbox item with no id tag — AUTO-FIXABLE (`--fix` mints+appends).
#   orphan      anything else non-conforming (bare prose, a checkbox-less `-`/`*` bullet,
#               a numbered item) — SURFACE ONLY. `--fix` NEVER touches it: converting prose
#               to a task would fabricate work whose intent is unknowable.
#
# INBOX GRAMMAR (`--inbox`): a conforming entry is blank / a `#` comment / a well-formed
#   `- [ ]/[x] [<target>] … <!-- routed:XXXX -->` line; everything else (the token-less
#   prose blocks) is `orphan`. (Inbox auto-RECONCILE on cross-repo activity is the sibling
#   id:678e — this only DETECTS + surfaces here.)
#
# HEAD-LINE LENGTH RATCHET (id:0d7c, meeting 2026-09-01-2226 D4 as amended) -------------
# Budget: 500 characters on a top-level checkbox line. Enforced as a RATCHET, not as a
# flat rule -- nearly every line in this repo's ledgers is over budget today, so a flat
# rule would be a migration, not a guard.
#
# WHY NOT the id:cb3e baseline (D4 was AMENDED to say this explicitly): that baseline is
# ID-KEYED (`state_claim_in_baseline <id> <file>`), and its own source documents at
# lib-state-claim.sh:157 that it "silently RE-GRANDFATHERS ... There is no expiry". An
# id-keyed exemption says "this item is forgiven forever", so every current id would be
# permanently exempt and free to regrow to 30 KB -- exactly what the ratchet exists to
# prevent. So this baselines the LENGTH, not the id, and enforces MONOTONIC SHRINK.
#
# THE RULE, per (ledger basename, id):
#   len <= 500                     -> conforming, silent.
#   len  > 500, no baseline entry  -> `length-over-budget`   ERROR (a NEW over-budget line;
#                                     this is also how an under-budget line that GREW past
#                                     the budget is caught, since it carries no entry).
#   len  > 500, len > baselined    -> `length-regrowth`      ERROR (monotonic shrink broken).
#   len  > 500, len <= baselined   -> `length-grandfathered` WARN, always reported.
#   ...and the COMPOSITION RULE (also ratified): a line the shrinker would REFUSE to cut is
#   `length-unshrinkable` WARN -- reported, NEVER blocking. A rule may not demand a cut the
#   tool will not make. See head_refusable() for the predicate and its sync discipline.
#
# The baseline lives in a committed file (default `relay/head-length-baseline.txt`, override
# with $LENGTH_BASELINE), format `<ledger-basename>\t<4-hex id>\t<length>`; `#` comments and
# blank lines ignored. Keying on the BASENAME, not a path, is what lets a hermetic fixture
# and the real ledger share one mechanism. Regenerating it is a DELIBERATE, SEPARATE act --
# `--regen-length-baseline <path>` prints the new snapshot to stdout and writes nothing.
# A regen TIGHTENS the ratchet (every line re-baselines at its current, smaller length);
# nothing regenerates it automatically, exactly the cb3e discipline.
#
# INERT WITHOUT A BASELINE: if the baseline file does not exist the ratchet performs NO
# length findings and says so LOUDLY on stderr. That is deliberate -- landing the rule
# without a snapshot would fail every ledger line in the fleet at once. It also means the
# ratchet is inert in OTHER repos unless they set $LENGTH_BASELINE, which is the intended
# opt-in. `*.archive.md` is out of scope entirely (id:2065), and so is `--inbox`.
#
# LEDGER LINE GRAMMAR (id:b048) ----------------------------------------------------------
# Owner-stated 2026-09-02, SUPERSEDING the block-size budget that item was originally
# scoped as. The rule is not a size at all: a line in TODO.md / ROADMAP.md is valid iff it
# is exactly one of three things, and everything else is a finding.
#
#   1. BLANK.
#   2. HEADING  `^#{1,6} <text>` -- at most ~200 chars, FOLLOWED BY A BLANK LINE, opening a
#      NON-EMPTY section (the next non-blank line is not another heading), and never the
#      last thing in the file.
#   3. ITEM     `^- \[[ xX]\]` + an optional lane tag + a title of at most ~200 chars +
#      zero or more typed-edge comments (`routed:`/`children:`/`children-of:`/`gated-on:`/
#      `answer-src:`) + the item's OWN anchored id marker + END OF LINE. Nothing, not even
#      a trailing space, after the id marker.
#
# THERE ARE NO CONTINUATION LINES. That is the whole point: Acceptance/Tests/Done-check
# prose does not live in the ledger, it lives in `docs/ledger-notes/<id>.md`. So an
# indented line is INVALID -- not "a large block". This is why the earlier block-size
# reading of id:b048 was dropped: a size budget legitimises the body it measures.
#
# REPORT-ONLY, ALWAYS. Every `grammar-*` class is a WARN: it is counted in `findings`
# (so it is always printed) and NEVER added to `strict_findings`, so it can never fail
# `--strict` and must never become a commit gate in this state. Measured 2026-09-02 on
# this repo: 395 of 1080 TODO.md lines and 1559 of 1720 ROADMAP.md lines are
# non-conforming. An ERROR would wedge the repo; promoting it is a separate, deliberate
# act after the corpus has been migrated, exactly like the `shape-prose` promotion (id:8524).
#
# CONFIGURABLE, because the owner flagged that ids may change shape when cartulary lands:
#   * the id token class is DERIVED from `lib-anchored-id.sh`'s ANCHORED_ID_MARKER_RE (the
#     one place the rest of the tooling already shares; `meeting/md-merge.py` mirrors that
#     same spelling deliberately) -- override with $LEDGER_ID_TOKEN_RE;
#   * the typed-edge vocabulary is $LEDGER_EDGE_KINDS (an ERE alternation);
#   * the two ~200 figures are the owner's APPROXIMATIONS, not ratified constants --
#     $LEDGER_HEADING_MAX / $LEDGER_ITEM_TITLE_MAX. They exist so the exact number can be
#     settled from counts later without another code change.
# Out of scope, same as the ratchet: `--inbox` and `*.archive.md`. `--no-grammar` (or
# LEDGER_GRAMMAR_CHECK=0) suppresses the rule for a caller that only wants the older
# checks; nothing else disables it.
#
# BASELINE STALENESS (id:2654) -----------------------------------------------------------
# Both ratchets above read a committed SNAPSHOT, and a snapshot's failure mode is SILENT
# LOOSENESS: an item shrinks, the recorded floor stays at the old larger value, and a later
# regrowth up to that old floor is forgiven. `--baseline-staleness` is the READ-ONLY detector
# for that (`current < baselined`), a separate MODE rather than a finding class -- see the
# block above the implementation for why, and for what it deliberately does not do.
#
# Usage:  todo-conformance.sh [--fix] [--inbox] [--strict] [--no-grammar] [<path>]
#         todo-conformance.sh --regen-length-baseline [<path>]
#         todo-conformance.sh --baseline-staleness [--strict] [<path>]
#         todo-conformance.sh --grammar-lines [<path>]   # b048 grammar only, `<lineno>TAB<class>`
#   <path> default = <cwd repo>/TODO.md (git rev-parse --show-toplevel). REPORT-ONLY
#   (exit 0 with findings); `--strict` → nonzero when findings remain. An unreadable path
#   or unknown flag is a LOUD reject (nonzero). No silent `2>/dev/null` swallow (id:415b/4e14).
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=relay/scripts/lib-state-claim.sh
source "$SCRIPTS_DIR/lib-state-claim.sh"
# shellcheck source=relay/scripts/lib-typed-edges.sh
# Twin-consumer for the id:3f7e DEP-PROSE-UNTYPED check — the SAME engine
# roadmap-lint.sh's rule 3(e) uses, so the two linters never silently diverge.
source "$SCRIPTS_DIR/lib-typed-edges.sh"
# The id-marker SSOT (id:521f). The b048 grammar DERIVES its token class from
# ANCHORED_ID_MARKER_RE rather than re-spelling `[0-9a-f]{4}` a third time -- see
# LEDGER_ID_TOKEN_RE below.
# shellcheck source=relay/scripts/lib-anchored-id.sh
source "$SCRIPTS_DIR/lib-anchored-id.sh"
# WARN→ERROR boundary baseline (id:cb3e, gated on id:5533) — same shared snapshot
# roadmap-lint.sh reads, so both linters agree on which ids are grandfathered.
STATE_CLAIM_BASELINE="${STATE_CLAIM_BASELINE:-$SCRIPTS_DIR/../state-claim-baseline.txt}"
# Head-line length ratchet (id:0d7c). Budget and baseline are both overridable so the
# hermetic test can drive them; the defaults are the shipped contract.
LEDGER_HEAD_BUDGET="${LEDGER_HEAD_BUDGET:-500}"
# Mirrors ledger-shrink.py's MIN_MOVED_CHARS. Two copies exist because this is bash and
# that is python; they are kept honest by head_refusable()'s sync discipline (see below)
# and by the fact that refusing MORE than the shrinker is safe while refusing LESS is not.
LEDGER_MIN_MOVED_CHARS="${LEDGER_MIN_MOVED_CHARS:-25}"
LENGTH_BASELINE="${LENGTH_BASELINE:-$SCRIPTS_DIR/../head-length-baseline.txt}"
# The SHAPE ratchet's baseline (id:2d17), the exact sibling of the length one above. Same
# regen-plus-detect shape the owner ratified 2026-09-02 -- a committed snapshot that only a
# deliberate --regen-shape-baseline moves. See the regen header for what it does and, more
# importantly, for the one thing it provably does NOT do.
SHAPE_BASELINE="${SHAPE_BASELINE:-$SCRIPTS_DIR/../shape-prose-baseline.txt}"

# --- LEDGER LINE GRAMMAR knobs (id:b048) -------------------------------------------------
# THE ID TOKEN CLASS IS NOT HARDCODED. It is derived from lib-anchored-id.sh's
# ANCHORED_ID_MARKER_RE, which is the shared spelling roadmap-lint.sh, scan-routed.sh,
# unpromoted-scan.sh and (mirrored, by its own comment at md-merge.py:181) meeting's
# md-merge.py already agree on. Deriving rather than re-spelling is the point: when ids
# change shape -- the owner flagged cartulary as the likely trigger -- that one file
# changes and this grammar follows. $LEDGER_ID_TOKEN_RE overrides it outright.
#
# The derivation is textual (strip the marker's fixed prefix/suffix and the capture
# parens) because the lib exports the WHOLE marker regex, not the token class on its own.
# If it ever stops yielding something plausible the fallback fires and says so LOUDLY --
# a silently-wrong token class would make every item read as `grammar-item-no-id`.
_ledger_derive_id_token_re() {
  local t="${ANCHORED_ID_MARKER_RE:-}"
  t="${t#*id:}"                       # -> ([0-9a-fA-F]{4})[[:space:]]*-->
  t="${t%%\[\[:space:\]\]\*-->}"       # -> ([0-9a-fA-F]{4})
  t="${t#\(}"; t="${t%\)}"            # -> [0-9a-fA-F]{4}
  if [[ -z "$t" || "$t" == *'-->'* || "$t" == *'id:'* ]]; then
    echo "todo-conformance.sh: could not derive the id token class from lib-anchored-id.sh's ANCHORED_ID_MARKER_RE ('${ANCHORED_ID_MARKER_RE:-<unset>}') -- falling back to [0-9a-fA-F]{4} (id:b048)" >&2
    printf '%s' '[0-9a-fA-F]{4}'
    return 0
  fi
  printf '%s' "$t"
}
LEDGER_ID_TOKEN_RE="${LEDGER_ID_TOKEN_RE:-$(_ledger_derive_id_token_re)}"
# The typed-edge vocabulary an item line may carry BEFORE its own id marker. An ERE
# alternation, deliberately open to extension ("and any future sibling"): a new edge kind
# is one entry here, not a code change. `children-of:` is included because it is live in
# this corpus; `lint-ok:` and `ref:` are NOT -- they are this script's own exemption
# markers and are handled earlier, by exempt(), which skips the line wholesale.
# WIDENED 2026-09-02 to the marker vocabulary actually LIVE in this corpus, counted rather
# than guessed (`grep -ohE '<!-- *[a-z-]+:' TODO.md ROADMAP.md`): relates 5, owner-hold 3,
# xledger-ok 2, xgate 1, settles 1, relay 1, invocation-flags 1, claiming 1. They were
# reporting as `grammar-item-unknown-marker`, which is a FALSE positive -- they are known,
# in-use markers, and at least one is load-bearing: `xledger-ok:` SUPPRESSES an orphan-scan
# --cross-ledger drift report, so flagging it as unknown trains a reader to ignore the very
# class that hides a real divergence. Adding a live marker here is bookkeeping, not a
# vocabulary decision; inventing one that nothing emits would be the opposite.
LEDGER_EDGE_KINDS="${LEDGER_EDGE_KINDS:-routed|children|children-of|gated-on|answer-src|relates|settles|owner-hold|xledger-ok|xgate|relay|invocation-flags|claiming}"
# APPROXIMATE, by the owner's own framing ("~200ish"), and named so the figure can be
# settled from counts later without touching code. Conformance counts at candidate values
# are in the id:b048 report; nothing downstream depends on the exact number.
LEDGER_HEADING_MAX="${LEDGER_HEADING_MAX:-200}"
# Deepest legal heading level (owner ruling 2026-09-02: "deeper level okay, but only up to
# level four"). Unlike the two ~200 char figures above this is an EXACT ruling, not an
# approximation. Slack today -- the live ledgers carry 2 level-1, 83 level-2 and 6 level-3
# headings and nothing deeper -- so it is a forward guard, not a cleanup trigger.
LEDGER_HEADING_MAX_LEVEL="${LEDGER_HEADING_MAX_LEVEL:-4}"
LEDGER_ITEM_TITLE_MAX="${LEDGER_ITEM_TITLE_MAX:-200}"
LEDGER_GRAMMAR_CHECK="${LEDGER_GRAMMAR_CHECK:-1}"
# append.sh (the id mint) lives in meeting/ at the repo root; resolve via the scripts dir.
APPEND_SH="${TODO_CONFORMANCE_APPEND:-$(cd "$SCRIPTS_DIR/../.." && pwd)/meeting/append.sh}"
LOG="${TODO_CONFORMANCE_LOG:-$HOME/.claude/logs/todo-conformance.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
log() { printf '%s todo-conformance.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

fix=0 inbox=0 strict=0 path="" regen_length=0 regen_shape=0 grammar_lines=0 staleness=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix)    fix=1; shift ;;
    --inbox)  inbox=1; shift ;;
    --strict) strict=1; shift ;;
    --regen-length-baseline) regen_length=1; shift ;;
    --regen-shape-baseline) regen_shape=1; shift ;;
    --baseline-staleness) staleness=1; shift ;;
    --grammar-lines) grammar_lines=1; shift ;;
    --no-grammar) LEDGER_GRAMMAR_CHECK=0; shift ;;
    -h|--help) sed -n '2,80p' "$0"; exit 0 ;;
    --*) echo "todo-conformance.sh: unknown flag '$1'" >&2; exit 2 ;;
    *)
      [[ -n "$path" ]] && { echo "todo-conformance.sh: only one path may be given (got extra '$1')" >&2; exit 2; }
      path="$1"; shift ;;
  esac
done

if [[ -z "$path" ]]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$root" ]] || { echo "todo-conformance.sh: no path given and cwd is not a git repo" >&2; exit 2; }
  path="$root/TODO.md"
fi
[[ -f "$path" ]] || { echo "todo-conformance.sh: file not found: $path" >&2; exit 2; }
[[ -r "$path" ]] || { echo "todo-conformance.sh: file not readable: $path" >&2; exit 2; }

# id_tag_present <line> : true if the line carries an `<!-- id:XXXX -->` token. Accepts a
# bare 4-hex id AND a suffixed variant (`id:2dea-ref`, `id:abcd-A`) so --fix never
# double-tags an item that already has an id-namespaced token.
id_tag_present() { grep -qP '<!-- id:[0-9a-f]{4}[-a-z0-9]* -->' <<<"$1"; }
# exempt <line> : intentional opt-out (lint-ok) or an intentional cross-repo pointer (ref:).
exempt() { [[ "$1" == *"<!-- lint-ok:"* ]] || grep -qP '<!-- ref:[0-9a-f]{4} -->' <<<"$1"; }

# --- head-line length ratchet (id:0d7c) --------------------------------------------------
# LENGTH_MUST_KEEP_RE -- the tokens that must stay on the head line no matter where the cut
# falls (the anchor id, the inbox twin, the lane tag, gate markers). Mirrors the shrinker's
# MUST_KEEP list; used here ONLY to compute how much movable prose a cut would actually
# free, never to rewrite anything. This script never edits a line for length.
# The `[-—–]` class is a MATCHER, not prose: the lane-tag delimiter is mid-migration from an
# em dash to a spaced hyphen, so both spellings must be recognised (match both, emit the new
# one) or a lane tag in the old spelling is invisible here.
LENGTH_MUST_KEEP_RE='<!--[[:space:]]*(id|routed|gated-on):[^>]*-->|\[(ROUTINE|HARD|MECHANICAL)\]|\[(HARD|INPUT)[[:space:]]*[-—–][[:space:]]*[A-Za-z ]+\]|gated-on:[0-9a-f]{4}|🚧|`?@(manual|owner-gated|container|owner-answered:[0-9-]+)`?|BLOCKED on'

# head_refusable <line> → 0 (REFUSABLE: the shrinker would decline to cut this line).
#
# THE COMPOSITION RULE this implements (ratified, not optional): a line the shrinker refuses
# to cut is REPORTED but never BLOCKS. Measured on today's corpus, 150 of 674 TODO items and
# 43 of 127 ROADMAP items have no bold run at all; without this, ticking one of their
# checkboxes would block a commit with no mechanical remedy, and a human under commit
# pressure would have to hand-invent a title.
#
# It is a LOCAL MIRROR of `splitHead`'s refusal conditions, deliberately NOT an import: the
# ratchet must not take a dependency on the shrinker (different language, different repo of
# origin, and a lint that cannot run without a rewriter is a lint that gets disabled).
#
# HOW IT STAYS IN SYNC -- and this is the important part, because this fleet has recorded
# that a prose "keep this in sync" instruction has NEVER held. The sync obligation here is
# DIRECTIONAL, not symmetric:
#   * Refusing MORE than the shrinker does is always SAFE. It only means some line that
#     could have been cut is reported instead of blocked; the ratchet is lenient, never
#     wrong. No sync action is needed, ever.
#   * Refusing LESS than the shrinker does is the FORBIDDEN direction -- that is precisely
#     "a rule demanding a cut the tool will not make".
# Therefore this predicate is written to be at least as refusing as the shrinker, and it is
# only ever allowed to be WIDENED (more refusal). Concretely: D4 grants the shrinker a
# FALLBACK cut point for bold-less items. That fallback is deliberately NOT mirrored here --
# copying it would narrow refusal, the forbidden direction, on a guess about its exact
# shape. When the fallback ships, narrowing this predicate to match is a deliberate,
# separate act with its own test, exactly like a baseline regeneration.
#
# Conditions mirrored today:
#   (a) no bold run -> no defensible cut point -> refuse;
#   (b) less than 40 chars of movable residue after the cut once must-keep tokens are set
#       aside -> nothing worth moving -> refuse.
# An ALREADY-POINTERED line is deliberately NOT refusable, though the shrinker declines to
# re-split it: its remedy exists and is mechanical (append the excess prose to the detail
# file it already points at). Treating it as refusable would make every line exempt the
# moment the shrink lands, silently zeroing the ratchet.
head_refusable() {
  local l="$1" bold rest residue
  # `-m1` rather than `| head -1`: piping into an early-exiting consumer under
  # `set -o pipefail` lets SIGPIPE on the producer become the pipeline's status
  # (id:81d5). Reading from a here-string is not a pipe, so nothing can break.
  bold="$( { grep -oP -m1 '\*\*[^*]+\*\*' <<<"$l" || true; } )"
  [[ -z "$bold" ]] && return 0                       # (a) no bold run
  rest="${l#*"$bold"}"
  residue="$(sed -E "s/${LENGTH_MUST_KEEP_RE}//g" <<<"$rest")"
  residue="$(sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' <<<"$residue")"
  # (b) nothing meaningful to move. MIRRORS ledger-shrink.py's MIN_MOVED_CHARS, which the
  # owner lowered 40 -> 25 on 2026-09-02. Narrowing this predicate is the "deliberate,
  # separate act with its own test" the header above promises, not a silent follow -- and it
  # is narrowing, the direction the header calls forbidden to do carelessly: at 40 this
  # reported `length-unshrinkable` for items the tool now cuts, which is safe but stale.
  # Leaving it at 40 would have understated the ratchet by exactly the 11 items 25 unlocks.
  (( ${#residue} < LEDGER_MIN_MOVED_CHARS )) && return 0
  return 1
}

# LENGTH_BASELINE_MAP["<ledger>/<id>"] = baselined length. Loaded ONCE (a per-line grep over
# an 800-entry file would be 800 greps per run).
# --- STRUCTURAL SHAPE CHECK (id:30fe) ----------------------------------------------
#
# The owner's bar, stated 2026-09-02 once the wave-1 shrink had landed: an item line
# carries ONLY a lane tag, gate markers, its `id:` anchor, a short title and a detail
# pointer -- and NO PROSE. The D4 length ratchet above cannot express that. Length is a
# single number, and a 237-char line can be perfectly conforming or entirely prose; the
# ratchet reports both identically. This rule asks the structural question instead.
#
# METHOD: strip every ALLOWED component and report whatever text survives. That direction
# matters. A positive grammar ("the line must MATCH this regex") fails closed on every
# shape nobody anticipated, and this ecosystem keeps growing marker vocabulary -- loderite
# alone carries `lint-ok:`, `xgate:` and `children-of:` that this repo has never seen.
# Stripping what is allowed and reporting the remainder degrades gracefully: an unknown
# HTML comment is stripped structurally (the c5d78046 rule -- an html comment IS metadata
# by construction here, and item prose never uses one), so a new marker type costs a
# little under-reporting rather than a wall of false violations.
#
# The allowed set is deliberately taken from LENGTH_MUST_KEEP_RE rather than re-listed.
# That regex is already the mirror of the shrinker's keep-set, and a THIRD hand-maintained
# copy of the same vocabulary is precisely the drift shape that produced this whole class
# of defect (loderite measured its own mirror having already drifted from its shrinker's
# list on 2026-09-02). One mirror is a liability; two is a guarantee.
#
# SEVERITY: WARN, reported and never blocking. 460 of 840 item lines fail this today
# (measured on `3ef0be1d`: TODO 359/692 conforming, ROADMAP 11/127, REVIEW_ME 10/21), so
# an ERROR would be a migration rather than a guard -- the same reasoning the length rule
# gives for not being flat. It becomes an ERROR when `id:6546` (strict-shape wave 2) has
# driven the count to zero, which is a deliberate separate act like a baseline regen.
#
# NOT added to shrink-acceptance.py's TODO_CONFORMANCE_NONBLOCKING set, deliberately: that
# set exists for rules whose MESSAGE carries a moving measurement, and this rule's identity
# is stable. A shape violation that NEWLY fires for an item across a shrink is a real
# regression and the gate should refuse on it.
# Matches ANY directory, not just `docs/ledger-notes` -- loderite's pointers say
# `docs/roadmap-notes`, and a check that only recognises its own repo's spelling reports
# every foreign pointer as prose. Keyed on the trailing `/<4-hex>.md`, which is the part
# the format actually fixes.
SHAPE_POINTER_RE='[[:space:]]*-{1,2}[[:space:]]*detail:[[:space:]]*`?[A-Za-z0-9_./-]*/[0-9a-f]{4}\.md`?'

# strip_chrome <text> → <text> with the detail pointer and every must-keep token removed.
#
# THE ONE STRIPPER (id:60eb, and the id:4983 rule "make ONE source serve both the actor and
# the checker"). Two rules in this file measure the same line and used to disagree about what
# a detail pointer is: `shape_residue` (id:30fe) excluded "lane/gate/id/title/POINTER" from
# its residue, while `grammar_item_class`'s title check (id:b048) counted the pointer AS
# TITLE TEXT. Since the id:0d7c topology REQUIRES that pointer on any item whose body was
# relocated -- and roadmap-lint.sh rule 3(c) reports DETAIL-POINTER-MISSING without it --
# planting a mandatory pointer pushed a conforming item over the title budget with no prose
# added at all. Observed on `id:7408` / `id:372a` in commit 39146fc7.
#
# So both callers now go through this. A SECOND spelling of the pointer pattern is exactly
# the drift this fixes; do not inline one.
#
# Lanes, gate glyphs and the at-sign marker family come from the ONE mirror
# (LENGTH_MUST_KEEP_RE). Do not name an at-sign token literally in this file:
# shrink-acceptance.py's marker registry greps these scripts for the markers they read, and
# a trailing comment is not a comment line, so a token written here is discovered as a real
# marker and reported as a keep-list GAP.
#
# THE STRIP IS ANCHORED, NOT GLOBAL (id:a580) -----------------------------------------------
# id:60eb's first cut applied LENGTH_MUST_KEEP_RE with `//g` over the whole title. That is
# the direction that HIDES a violation, and it is a real regression against the step 5 it
# replaced: step 5 stripped only LEADING bracket groups, so a keep-token quoted in mid-PROSE
# still counted as title. Under a global strip it stops counting, and `BLOCKED on` alone buys
# an over-long title 10 free characters. Four ~201-char pure-prose fixtures (`BLOCKED on`,
# `[HARD]`, the gate glyph, `gated-on:abcd`) were reported by the old script and went SILENT
# under the global one. The band is narrow -- roughly 201-210 chars for one 10-char token,
# since the token has to be what carries the title across the budget -- which is exactly why
# it survived review: it is invisible unless a fixture is built to the band.
#
# So the strip is anchored to the three regions where a token is CHROME by position:
#   * everything at or after the detail pointer -- the shrinker parks relocated lane/gate
#     tokens there, which is what id:60eb case (g) pins, so that region keeps the global
#     strip verbatim;
#   * a LEADING run of keep-tokens -- the lane tag and gate glyphs an item opens with, which
#     is what shape_residue needs (grammar_item_class has already dropped leading BRACKET
#     groups by the time it calls in, but not a leading glyph or at-sign marker);
#   * a TRAILING run of keep-tokens.
# Anything between those runs is PROSE and is counted, which restores the pre-60eb property
# without reverting 60eb: a mandatory pointer still cannot push an item over budget.
#
# MEASURED on this repo's live ledgers when the anchoring landed: 69 TODO.md and 5 ROADMAP.md
# title measurements grow (characters the global strip was eating out of the real title
# region), and exactly ONE verdict flips -- `id:5ed7`, 199 -> 201, whose entire subject is
# that unanchored substring matching re-applies a marker to anything that merely WRITES about
# it. The measurement was reproducing the bug that item describes.
#
# KNOWN CONSEQUENCE, SURFACED RATHER THAN QUIETLY ABSORBED: `shape_residue` measures through
# this same helper, so the anchoring makes shape residues measure LARGER too, and
# relay/shape-prose-baseline.txt was captured under the global strip. Measured when this
# landed: 16 TODO.md and 6 ROADMAP.md items move from `shape-grandfathered` WARN to
# `shape-regrowth` ERROR with their ledger lines BYTE-IDENTICAL -- a measurement change, not
# a regrowth. (`--strict` already exited 1 on both ledgers beforehand, so nothing newly
# wedges.) The mechanical remedy is the deliberate regen the shape-baseline header documents,
# BOTH ledgers into the one file; it is an owner act and was deliberately NOT performed here.
#
# _chrome_edge_strip <text> -- remove a LEADING and a TRAILING run of keep-tokens, nothing in
# between. `+` on the outer group so a no-match leaves the text untouched; the inner
# alternation cannot match empty, so the repetition terminates.
_chrome_edge_strip() {
  local s="$1"
  s="$(sed -E "s/^([[:space:]]*(${LENGTH_MUST_KEEP_RE}))+[[:space:]]*//" <<<"$s")"
  sed -E "s/([[:space:]]*(${LENGTH_MUST_KEEP_RE}))+[[:space:]]*\$//" <<<"$s"
}

strip_chrome() {
  local s="$1" head tail
  # ONE spelling of the pointer pattern, still (id:4983): the bash-regex probe below reads
  # the same variable the sed does. `$SHAPE_POINTER_RE` unbraced deliberately -- id:60eb's
  # test counts the LINES mentioning the braced form to pin "applied in exactly one place".
  if [[ "$s" =~ $SHAPE_POINTER_RE ]]; then
    head="${s%%"${BASH_REMATCH[0]}"*}"
    tail="${s#*"${BASH_REMATCH[0]}"}"
    # At/after the pointer: chrome by position. Strip globally, pointer included -- a
    # re-split line can carry a second pointer here.
    tail="$(sed -E "s#${SHAPE_POINTER_RE}##g;s/${LENGTH_MUST_KEEP_RE}//g" <<<"$tail")"
    # No separator re-inserted: the pointer match absorbs its own leading whitespace, so
    # this concatenation is byte-identical to the old global strip minus the anchoring.
    printf '%s%s\n' "$(_chrome_edge_strip "$head")" "$tail"
    return 0
  fi
  _chrome_edge_strip "$s"
}

# shape_residue <line> → the prose surviving after every allowed component is removed.
SHAPE_TITLE_MAX="${SHAPE_TITLE_MAX:-200}"

shape_residue() {
  local l="$1" bold title s
  s="$(sed -E 's/^-[[:space:]]\[[[:space:]xX]\][[:space:]]*//' <<<"$l")"
  s="$(sed -E 's/<!--[^>]*-->//g' <<<"$s")"            # structural: ALL html comments
  s="$(strip_chrome "$s")"
  # THE TITLE. First a bold run if there is one -- and only the FIRST: a second bold run is
  # prose wearing emphasis, which is exactly how `**RED SPEC LANDED 2026-08-13**` survived
  # wave 1 on dozens of lines.
  #
  # With NO bold run, the title is the leading text up to the first sentence or clause
  # boundary. That is the owner's ratified titling rule (2026-09-02) and this predicate
  # must agree with the shrinker's, or the checker demands a shape the tool will not
  # produce -- the same composition rule head_refusable() documents. 183 open items have no
  # bold run; without this branch every one of them reports its own TITLE as prose, and so
  # does every bold-less fixture in the suite.
  bold="$( { grep -oP -m1 '\*\*[^*]+\*\*' <<<"$s" || true; } )"
  if [[ -n "$bold" ]]; then
    s="${s/"$bold"/ }"
  else
    # Cut at the FIRST `. ` / ` -- ` / `: ` / `; `; with no boundary the whole run is the
    # title. Non-greedy, so an item with several sentences yields the first, not the last.
    title="$( { grep -oP -m1 '^.*?(?=\.[[:space:]]|[[:space:]]--[[:space:]]|:[[:space:]]|;[[:space:]])' <<<"$s" || true; } )"
    [[ -z "$title" ]] && title="$s"
    # A title longer than this is not a title -- it is an unpunctuated paragraph. The
    # length ratchet catches the extreme cases; this catches the 400-char middle.
    (( ${#title} > SHAPE_TITLE_MAX )) && title="${title:0:SHAPE_TITLE_MAX}"
    s="${s#"$title"}"
  fi
  # Drop pure punctuation and whitespace: a stripped line legitimately leaves separators
  # behind (`--`, `()`, backticks) and those are not prose.
  sed -E 's/[[:space:][:punct:]]+//g' <<<"$s"
}

# --- SHAPE RATCHET (id:2d17) -------------------------------------------------------------
#
# The saturation this fixes, stated as the measurement: with ~114 shape-prose findings
# standing, finding 115 is reported in the SAME WORDS as findings 1..114 and escalates
# none of them, so the rule regulates nothing. Splitting the one class into three -- and
# escalating only the two that are NEW information -- is what makes #115 visible.
#
#   residue > 8, no baseline entry      -> `shape-new`           ERROR (a NEW prose item)
#   residue > 8, residue >  baselined   -> `shape-regrowth`      ERROR (it got worse)
#   residue > 8, residue <= baselined   -> `shape-grandfathered` WARN, always reported
#
# INERT WITHOUT A BASELINE: with no baseline file the class stays exactly today's
# report-only `shape-prose`, so every repo that has not captured one is unaffected and
# id:8524 (the blanket WARN->ERROR promotion) remains a separate, later act.
#
# READ THE REGEN HEADER BEFORE TRUSTING THIS. A snapshot baseline cannot catch the
# id:718c shape (shrink, then regrow to less than the baselined value), and id:718c is
# the incident this item was filed for. That gap is deliberate and owner-ratified; it is
# not an oversight in this implementation.
declare -A SHAPE_BASELINE_MAP=()
SHAPE_RATCHET_ON=0

shape_baseline_load() {
  local f="$1" ledger id len
  while read -r ledger id len; do
    [[ -z "${ledger:-}" || "$ledger" == \#* ]] && continue
    [[ -n "${id:-}" && -n "${len:-}" ]] || continue
    SHAPE_BASELINE_MAP["$ledger/$id"]="$len"
  done < "$f"
}

# shape_class <line> → "" | "shape-prose (…)" | "shape-new (…)" | "shape-regrowth (…)"
#                        | "shape-grandfathered (…)"
shape_class() {
  local l="$1" r id base
  [[ "$l" =~ ^-\ \[[\ xX]\]\  ]] || return 0
  r="$(shape_residue "$l")"
  # 8 chars of slack: a stray word fragment left by an unrecognised marker is not worth a
  # finding, and the threshold keeps the rule from firing on its own stripping artefacts.
  (( ${#r} > 8 )) || return 0
  if (( SHAPE_RATCHET_ON == 0 )); then
    echo "shape-prose (${#r} chars of prose outside lane/gate/id/title/pointer; id:30fe)"
    return 0
  fi
  id="$(length_id_of "$l")"
  # An id-less line cannot be keyed to a baseline. An OPEN one is already reported as
  # `missing-id`; fixing that is what brings it under the ratchet. Never guess a key.
  if [[ -z "$id" ]]; then
    echo "shape-prose (${#r} chars of prose outside lane/gate/id/title/pointer; id:30fe)"
    return 0
  fi
  base="${SHAPE_BASELINE_MAP["$LENGTH_LEDGER_KEY/$id"]:-}"
  if [[ -z "$base" ]]; then
    echo "shape-new (${#r} chars of prose, not baselined; a NEW prose item; id:2d17)"
  elif (( ${#r} > base )); then
    echo "shape-regrowth (${#r} chars of prose > baselined $base; prose may only shrink; id:2d17)"
  else
    echo "shape-grandfathered (${#r} chars of prose, within baseline $base; id:2d17)"
  fi
}

# --- LEDGER LINE GRAMMAR (id:b048) -------------------------------------------------------
#
# ONE finding per non-conforming LINE, first failure wins. That is deliberate: the owner's
# measurement is a per-LINE conformance count, so emitting two classes for one line would
# make the report's arithmetic disagree with the number the rule was specified against.
#
# Classes (all WARN, never escalated -- see the header):
#   grammar-continuation        an indented line. Under this grammar there is no such thing
#                               as a continuation; the prose belongs in docs/ledger-notes/.
#   grammar-line                a top-level line that is neither blank, heading, nor item.
#   grammar-heading-long        heading over $LEDGER_HEADING_MAX chars.
#   grammar-heading-no-blank    heading not followed by an empty line.
#   grammar-heading-too-deep    heading deeper than $LEDGER_HEADING_MAX_LEVEL.
#   grammar-heading-empty-sec   the next non-blank line is a SIBLING-or-SHALLOWER heading
#                               (empty section). A DEEPER heading is legal nesting.
#   grammar-heading-eof         heading is the last non-blank thing in the file.
#   grammar-item-no-id          item with no anchored `<!-- id:… -->` marker of its own.
#   grammar-item-edge-after-id  a typed edge sits AFTER the id marker (order is fixed).
#   grammar-item-after-id       anything else after the id marker, trailing space included.
#   grammar-item-unknown-marker an HTML comment before the id that is not a known edge kind.
#   grammar-item-title-long     title over $LEDGER_ITEM_TITLE_MAX chars.
#
# UNDERSPECIFIED, resolved conservatively and flagged rather than guessed silently:
#   (i)  the owner said "an optional lane tag", singular. This corpus routinely carries
#        several leading bracket groups (`[HARD - pool] [INTENSIVE - gpu]`, the
#        `[INBOUND routed:… from …]` ingest prefix). Stripping ZERO OR MORE leading bracket
#        groups is the reading that does not invent findings for shapes the fleet's own
#        tools write; a strict one-tag reading would report thousands of lines whose lane
#        syntax is not in question.
#   (ii) an HTML-comment-only line (`<!-- … -->` alone) is CONFORMING under this script's
#        older TODO grammar and is NOT one of the owner's three shapes. Reported as
#        `grammar-line`; if those lines are meant to stay, the fix is one more shape, not
#        a silent exemption.
#  (iii) `*.archive.md` and `--inbox` are out of scope, matching the length ratchet
#        (id:2065). Archives are history; re-grammaring them buys nothing.

# GRAMMAR_FIND[<lineno>] = "<class> (<detail>)". Built in ONE pre-pass because the heading
# rules are multi-line (blank-after / non-empty-section / not-at-EOF) and need lookahead --
# but every finding still points at the offending heading's own line number.
declare -A GRAMMAR_FIND=()

# Composed once, not per line: bash's `[[ =~ ]]` takes the RHS as an ERE, and writing `<`
# or `>` inline there needs escapes that a POSIX ERE then reinterprets (`\<` is a GNU
# word-boundary operator, not a literal). Building the pattern in a variable keeps every
# metacharacter meaning what it looks like.
GRAMMAR_ID_MARKER_RE="<!--[[:space:]]*id:${LEDGER_ID_TOKEN_RE}[[:space:]]*-->"
GRAMMAR_EDGE_MARKER_RE="<!--[[:space:]]*(${LEDGER_EDGE_KINDS}):[^>]*-->"

# grammar_item_class <line> → "" | "<class> (<detail>)"
grammar_item_class() {
  local l="$1" rest tail title
  # 1. the checkbox itself.
  rest="$(sed -E 's/^-[[:space:]]\[[[:space:]xX]\][[:space:]]*//' <<<"$l")"
  # 2. the item's OWN id marker must be the very last thing on the line.
  # No `[[:space:]]*` before the `$`: "nothing after the id marker" is literal, and a
  # trailing space is one of the edges the owner named explicitly.
  if [[ ! "$l" =~ ${GRAMMAR_ID_MARKER_RE}$ ]]; then
    if [[ "$l" =~ ${GRAMMAR_ID_MARKER_RE} ]]; then
      # Greedy `^.*` deliberately: the tail is what follows the LAST id marker.
      tail="$(sed -E "s/^.*${GRAMMAR_ID_MARKER_RE}//" <<<"$l")"
      if [[ "$tail" =~ ${GRAMMAR_EDGE_MARKER_RE} ]]; then
        echo "grammar-item-edge-after-id (a typed edge follows the id marker; the id marker ends the line)"
      else
        echo "grammar-item-after-id (${#tail} chars follow the id marker, trailing whitespace included)"
      fi
      return 0
    fi
    echo "grammar-item-no-id (no anchored id marker of its own)"
    return 0
  fi
  # 3. strip the id marker, then every trailing typed-edge comment.
  rest="$(sed -E "s/[[:space:]]*${GRAMMAR_ID_MARKER_RE}[[:space:]]*\$//" <<<"$rest")"
  while [[ "$rest" =~ ${GRAMMAR_EDGE_MARKER_RE}[[:space:]]*$ ]]; do
    rest="$(sed -E "s/[[:space:]]*${GRAMMAR_EDGE_MARKER_RE}[[:space:]]*\$//" <<<"$rest")"
  done
  # 4. an HTML comment surviving here is a marker this grammar does not know, sitting where
  #    only the lane tag and the title may be. Reported, never silently accepted.
  if [[ "$rest" == *'<!--'* ]]; then
    echo "grammar-item-unknown-marker (an HTML comment appears before the id marker that is not one of: ${LEDGER_EDGE_KINDS//|/, })"
    return 0
  fi
  # 5. lane tags: zero or more leading bracket groups (see UNDERSPECIFIED (i)).
  title="$(sed -E 's/^([[:space:]]*\[[^]]*\])+[[:space:]]*//' <<<"$rest")"
  # 5b. the detail pointer and any remaining must-keep token are CHROME, not title (id:60eb).
  #     Through strip_chrome(), the same helper shape_residue uses -- the pointer is mandatory
  #     under id:0d7c, so counting it as title penalised an item for obeying the format.
  title="$(strip_chrome "$title")"
  title="$(sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' <<<"$title")"
  if (( ${#title} > LEDGER_ITEM_TITLE_MAX )); then
    echo "grammar-item-title-long (${#title} chars of title, approximate max $LEDGER_ITEM_TITLE_MAX)"
    return 0
  fi
  return 0
}

# grammar_scan <path> — fill GRAMMAR_FIND for every non-conforming line in <path>.
grammar_scan() {
  local path="$1" n i l nxt j cls
  GRAMMAR_FIND=()
  local -a L=()
  mapfile -t L < "$path"
  n=${#L[@]}
  for (( i = 0; i < n; i++ )); do
    l="${L[i]}"
    [[ -z "${l//[[:space:]]/}" ]] && continue                # 1. BLANK
    exempt "$l" && continue                                  # explicit opt-out, as elsewhere
    if [[ "$l" =~ ^#{1,6}[[:space:]] ]]; then                # 2. HEADING
      # Heading DEPTH, needed twice below: for the level cap and for the nesting rule.
      hashes="${l%%[[:space:]]*}"; lvl=${#hashes}
      if (( ${#l} > LEDGER_HEADING_MAX )); then
        GRAMMAR_FIND[$((i+1))]="grammar-heading-long (${#l} chars, approximate max $LEDGER_HEADING_MAX)"
        continue
      fi
      # Owner ruling 2026-09-02: nesting is legal, but only down to level four.
      if (( lvl > LEDGER_HEADING_MAX_LEVEL )); then
        GRAMMAR_FIND[$((i+1))]="grammar-heading-too-deep (level $lvl; max $LEDGER_HEADING_MAX_LEVEL)"
        continue
      fi
      if (( i + 1 >= n )); then
        GRAMMAR_FIND[$((i+1))]="grammar-heading-eof (a heading is the last line of the file; it opens no section)"
        continue
      fi
      nxt="${L[i+1]}"
      if [[ -n "${nxt//[[:space:]]/}" ]]; then
        GRAMMAR_FIND[$((i+1))]="grammar-heading-no-blank (a heading must be followed by an empty line)"
        continue
      fi
      # Next NON-blank line must exist. If it is another heading, the section is empty
      # ONLY when that heading is a SIBLING or SHALLOWER (same level or fewer hashes).
      # A DEEPER heading is legitimate nesting and counts as content -- owner ruling
      # 2026-09-02 ("deeper level okay, but only up to level four"; the level cap is
      # enforced above, on the deeper heading's own line, so it is not re-checked here).
      # The literal reading -- ANY following heading means empty -- flagged the standard
      # ledger preamble `# TODO` / `## Current` in every file, which is not a defect.
      cls=""
      for (( j = i + 2; j < n; j++ )); do
        [[ -z "${L[j]//[[:space:]]/}" ]] && continue
        if [[ "${L[j]}" =~ ^#{1,6}[[:space:]] ]]; then
          nh="${L[j]%%[[:space:]]*}"
          if (( ${#nh} <= lvl )); then
            cls="grammar-heading-empty-sec (the section is empty -- the next non-blank line is a level-${#nh} heading at line $((j+1)), a sibling or shallower of this level-$lvl one)"
          fi
        fi
        break
      done
      if (( j >= n )) && [[ -z "$cls" ]]; then
        cls="grammar-heading-eof (nothing but blank lines follow; the heading opens no section)"
      fi
      [[ -n "$cls" ]] && GRAMMAR_FIND[$((i+1))]="$cls"
      continue
    fi
    if [[ "$l" =~ ^[[:space:]] ]]; then                      # an indented line
      GRAMMAR_FIND[$((i+1))]="grammar-continuation (${#l} chars; this grammar has no continuation lines -- the prose belongs in the item's docs/ledger-notes file)"
      continue
    fi
    if [[ "$l" =~ ^-\ \[[\ xX]\] ]]; then                    # 3. ITEM
      cls="$(grammar_item_class "$l")"
      [[ -n "$cls" ]] && GRAMMAR_FIND[$((i+1))]="$cls"
      continue
    fi
    GRAMMAR_FIND[$((i+1))]="grammar-line (a top-level line that is neither blank, heading, nor item)"
  done
  return 0
}

declare -A LENGTH_BASELINE_MAP=()
LENGTH_RATCHET_ON=0
LENGTH_LEDGER_KEY=""

length_baseline_load() {
  local f="$1" ledger id len
  while read -r ledger id len; do
    [[ -z "${ledger:-}" || "$ledger" == \#* ]] && continue
    [[ -n "${id:-}" && -n "${len:-}" ]] || continue
    LENGTH_BASELINE_MAP["$ledger/$id"]="$len"
  done < "$f"
}

# length_id_of <line> → the line's own 4-hex id token, or "".
length_id_of() {
  { grep -oP '<!--\s*id:\K[0-9a-f]{4}(?=[-a-z0-9]*\s*-->)' <<<"$1" || true; } | tail -1
}

# length_ratchet_class <line> → "" | "<class> (<detail>)". See the header for the rule.
length_ratchet_class() {
  local l="$1" id len base
  [[ "$l" =~ ^-\ \[[\ xX]\]\  ]] || return 0
  id="$(length_id_of "$l")"
  # An id-less line cannot be keyed to a baseline at all. An OPEN one is already reported as
  # `missing-id`; fixing that is what brings it under the ratchet. Never guess a key.
  [[ -n "$id" ]] || return 0
  len=${#l}
  (( len > LEDGER_HEAD_BUDGET )) || return 0
  base="${LENGTH_BASELINE_MAP["$LENGTH_LEDGER_KEY/$id"]:-}"
  if head_refusable "$l"; then
    echo "length-unshrinkable ($len chars, budget $LEDGER_HEAD_BUDGET; the shrinker would refuse this line, so it is reported and never blocks)"
  elif [[ -z "$base" ]]; then
    echo "length-over-budget ($len chars > budget $LEDGER_HEAD_BUDGET, not baselined)"
  elif (( len > base )); then
    echo "length-regrowth ($len chars > baselined $base; an over-budget line may only shrink)"
  else
    echo "length-grandfathered ($len chars > budget $LEDGER_HEAD_BUDGET, within baseline $base)"
  fi
}

# classify_todo <line> → echoes "" (conforming/skip) | "missing-id" | "orphan"
classify_todo() {
  local l="$1"
  [[ -z "${l//[[:space:]]/}" ]] && return 0            # blank
  [[ "$l" =~ ^[[:space:]] ]] && return 0               # indented continuation — never linted
  exempt "$l" && return 0
  [[ "$l" =~ ^#{1,6}[[:space:]] ]] && return 0         # header
  [[ "$l" =~ ^[[:space:]]*\<!--.*--\>[[:space:]]*$ ]] && return 0   # html-comment-only line
  if [[ "$l" =~ ^-\ \[[\ xX]\]\  ]]; then              # a checkbox item
    if [[ "$l" =~ ^-\ \[\ \]\  ]] && ! id_tag_present "$l"; then
      echo "missing-id"; return 0
    fi
    return 0                                           # conforming item
  fi
  echo "orphan"                                        # anything else top-level
}

# classify_inbox <line> → "" | "orphan"
classify_inbox() {
  local l="$1"
  [[ -z "${l//[[:space:]]/}" ]] && return 0
  [[ "$l" =~ ^[[:space:]] ]] && return 0
  exempt "$l" && return 0
  [[ "$l" =~ ^# ]] && return 0                          # the inbox `#` comment header lines
  # conforming routed entry: checkbox + [target] + routed token
  if [[ "$l" =~ ^-\ \[[\ xX]\]\ \[.+\]\  ]] && grep -qP '<!-- routed:[0-9a-f]{4} -->' <<<"$l"; then
    return 0
  fi
  echo "orphan"
}

# --- length-ratchet activation + regeneration (id:0d7c) ----------------------------------
LENGTH_LEDGER_KEY="$(basename "$path")"

# `--regen-length-baseline` is the DELIBERATE, SEPARATE act the header promises: it prints a
# fresh snapshot to stdout and writes nothing, so capturing it is an explicit redirect the
# operator performs and commits. Exclusive mode -- no linting, no --fix.
if [[ "$regen_length" -eq 1 ]]; then
  cat <<'REGEN_HEADER'
# head-length-baseline.txt -- committed snapshot for the head-line LENGTH RATCHET
# (id:0d7c, meeting 2026-09-01-2226 decision D4 AS AMENDED). GENERATED, not hand-edited.
#
# FORMAT: <ledger basename>TAB<4-hex id>TAB<length in chars>. `#` comments and blank lines
# are ignored. One row per top-level checkbox line that was OVER the 500-char budget at
# capture time; an under-budget line has nothing to grandfather and never enters this file.
#
# WHAT IT IS: the LENGTH each over-budget ledger head line had when the ratchet landed.
# todo-conformance.sh reads it and enforces MONOTONIC SHRINK -- a listed line may be edited
# only if the result is no longer than the recorded length; an over-budget line with NO row
# here is a NEW violation and fails --strict.
#
# WHY LENGTH-KEYED AND NOT ID-KEYED, which is the amendment: relay/state-claim-baseline.txt
# (id:cb3e) is a flat list of ids, and lib-state-claim.sh:157 documents that it "silently
# RE-GRANDFATHERS ... There is no expiry". An id-keyed exemption means "this item is
# forgiven forever" -- all 674 current TODO items would be permanently exempt and free to
# regrow to 30 KB, which is exactly what the ratchet exists to prevent. Keying the LENGTH
# grandfathers today's corpus (so the rule lands with no migration) while still refusing
# every regrowth.
#
# KNOWN WEAKNESS, disclosed in the same spirit as the cb3e file: this is a SNAPSHOT, not a
# live derivation. A line listed at 9,000 chars stays forgiven at 9,000 chars until this
# file is regenerated. There is no expiry and no automatic refresh -- but unlike the
# id-keyed baseline it cannot forgive UNBOUNDED growth, only the length already on record.
#
# REGENERATING IS A DELIBERATE, SEPARATE ACT, and it TIGHTENS the ratchet (every line
# re-baselines at its current, smaller length). Do it after a shrink pass lands:
#   relay/scripts/todo-conformance.sh --regen-length-baseline TODO.md    >  relay/head-length-baseline.txt
#   relay/scripts/todo-conformance.sh --regen-length-baseline ROADMAP.md | grep -v '^#' >> relay/head-length-baseline.txt
#
# OUT OF SCOPE: *.archive.md (id:2065) and the shared inbox.
REGEN_HEADER
  printf '# Captured %s.\n' "$(date '+%Y-%m-%d')"
  while IFS= read -r line || [[ -n "$line" ]]; do
    (( ${#line} > LEDGER_HEAD_BUDGET )) || continue
    [[ "$line" =~ ^-\ \[[\ xX]\]\  ]] || continue
    _rid="$(length_id_of "$line")"
    [[ -n "$_rid" ]] || continue
    printf '%s\t%s\t%d\n' "$LENGTH_LEDGER_KEY" "$_rid" "${#line}"
  done < "$path"
  exit 0
fi

# `--regen-shape-baseline` -- the SHAPE ratchet's capture path (id:2d17). Same contract as
# its length sibling above: prints to stdout, writes nothing, exclusive mode.
if [[ "$regen_shape" -eq 1 ]]; then
  cat <<'REGEN_SHAPE_HEADER'
# shape-prose-baseline.txt -- committed snapshot for the SHAPE RATCHET (id:2d17).
# GENERATED, not hand-edited.
#
# FORMAT: <ledger basename>TAB<4-hex id>TAB<prose residue length in chars>. `#` comments
# and blank lines are ignored. One row per top-level checkbox line whose shape residue
# exceeded the 8-char slack at capture time; a conforming line has nothing to grandfather
# and never enters this file.
#
# WHAT IT BUYS: it splits one saturated class into three, so a NEW prose item
# (`shape-new`) and a WORSENED one (`shape-regrowth`) are ERRORS that fail --strict, while
# the standing corpus reports as `shape-grandfathered` WARN and never blocks. That is what
# makes finding 115 visible next to findings 1..114 -- the saturation id:2d17 was filed for.
#
# ── WHAT IT PROVABLY DOES *NOT* CATCH, AND WHY THAT IS DELIBERATE ────────────────────────
#
# This is a SNAPSHOT, exactly like head-length-baseline.txt, and it inherits that file's
# disclosed weakness in a sharper form. Applied to id:718c, the incident id:2d17 was filed
# for, IT DOES NOT FIRE:
#
#     id:718c went 4,367 -> 222 -> 1,316 chars in one afternoon.
#     Baselined at 4,367, the regrowth to 1,316 is `1316 <= 4367` -> shape-grandfathered
#     WARN. Only a baseline tightened to the observed 222 makes it an ERROR.
#
# So a shrink-then-regrow BELOW the baselined value is forgiven until this file is
# regenerated. Catching that needs a baseline that TIGHTENS on observation, and
# self-tightening was CONSIDERED AND REJECTED by the owner on 2026-09-02: it would give a
# READER a write side effect, dirtying the tree on every run (which the id:aa93 guard turns
# into a deferred relay dispatch), and it would need a flock plus a concept that does not
# exist -- which invocation is AUTHORITATIVE -- since this checker also runs against
# fixtures, worktrees and hermetic tests, where a tightening run would poison the real
# baseline.
#
# What makes the snapshot safe is therefore NOT this file. It is the separate, READ-ONLY
# staleness detector (id:2654): `current < baselined` is a pure read, and it turns "remember
# to regenerate" into "the checker tells you to regenerate". Precedent: mech-currency.sh
# (id:0384) detects a stale in-memory allowlist, fails closed, names the remedy, and
# deliberately does not auto-restart. **Until id:2654 ships, this ratchet's floor can go
# silently stale, and that is a known open gap -- not a bug in this file.**
#
# REGENERATING IS A DELIBERATE, SEPARATE ACT, and it TIGHTENS the ratchet. Do it after a
# shrink pass lands:
#   relay/scripts/todo-conformance.sh --regen-shape-baseline TODO.md    >  relay/shape-prose-baseline.txt
#   relay/scripts/todo-conformance.sh --regen-shape-baseline ROADMAP.md | grep -v '^#' >> relay/shape-prose-baseline.txt
#
# OUT OF SCOPE: *.archive.md (id:2065) and the shared inbox.
REGEN_SHAPE_HEADER
  printf '# Captured %s.\n' "$(date '+%Y-%m-%d')"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^-\ \[[\ xX]\]\  ]] || continue
    _rid="$(length_id_of "$line")"
    [[ -n "$_rid" ]] || continue
    _res="$(shape_residue "$line")"
    (( ${#_res} > 8 )) || continue
    printf '%s\t%s\t%d\n' "$LENGTH_LEDGER_KEY" "$_rid" "${#_res}"
  done < "$path"
  exit 0
fi

# --- BASELINE STALENESS DETECTOR (id:2654) -----------------------------------------------
#
# `--baseline-staleness [--strict] <path>` -- a PURE READ that answers one question about
# BOTH snapshot ratchets above: has the recorded floor gone LOOSER than reality?
#
#   current < baselined  ->  BASELINE-STALE. The floor forgives more than reality requires;
#                            regenerate it and commit.
#
# WHY THIS EXISTS. Both baselines are committed snapshots that only a deliberate regen moves,
# which is the cb3e discipline on purpose. Their shared failure mode is SILENT LOOSENESS:
# after a shrink pass every shrunk item keeps its OLD, LARGER floor, and a later regrowth back
# up to that floor is `*-grandfathered` WARN rather than a `*-regrowth` ERROR. Measured on the
# fleet: loderite's id:718c went 4,367 -> 222 -> 1,316 chars in one afternoon and nothing
# fired. Forgetting the regen is indistinguishable from compliance -- so "remember to
# regenerate" is not a mechanism, and this turns it into one the checker can state.
#
# ── WHY A SEPARATE MODE, AND NOT A FINDING IN THE ORDINARY REPORT ─────────────────────────
#
# THIS IS THE LOAD-BEARING DESIGN CHOICE, so it is recorded here rather than in a commit
# message. `current < baselined` is TRUE EXACTLY WHEN AN ITEM HAS BEEN IMPROVED. A shrink IS
# the stale state. Two consequences, both verified against the suite rather than reasoned
# about:
#
#   * ESCALATING it (adding to strict_findings) fires on every legitimate shrink and breaks
#     both `tests/test_todo_conformance_length_ratchet_0d7c.sh` case (b) and
#     `tests/test_shape_prose_regrowth_baseline_2d17.sh` case (0), each of which pins
#     "improving an item never breaks the ratchet". Recorded as dead end 1 in
#     docs/ledger-notes/cf64.md; do not re-propose it.
#   * Emitting it as a non-escalating WARN LINE in the ordinary report still breaks 2d17's
#     case (0), whose assertion is stricter than "does not fail --strict": the shrunk item
#     must report NO finding at all. A WARN line keyed to that item is a finding.
#
# So the detector is a MODE, not a class: an explicit, separate invocation whose output is
# the whole report. The ordinary lint stream is byte-for-byte unchanged, which is what lets a
# shrink stay clean while staleness is still visible on demand. The precedent is
# mech-currency.sh (id:0384) -- a dedicated read-only check that detects a stale snapshot,
# names the remedy, and deliberately does NOT apply it. Self-tightening (writing the tightened
# floor from a read) was CONSIDERED AND REJECTED by the owner on 2026-09-02: a reader must not
# have a write side effect (tree dirt feeds the id:aa93 deferral), it would need a flock, and
# there is no concept of an AUTHORITATIVE invocation because this checker runs constantly
# against fixtures, worktrees and hermetic tests where a tightening run would poison the real
# baseline.
#
# EXIT STATUS. Bare `--baseline-staleness` ALWAYS exits 0 -- report-only, exactly as the item
# scopes it, so wiring it anywhere can never block. `--baseline-staleness --strict` exits 1
# when anything is stale, for a caller that deliberately wants a gate. That opt-in is not a
# promotion: no existing caller passes --strict to this mode, and the ordinary lint path never
# reaches this code at all.
#
# CLASSES (output `<class>\t<id>\t<detail>`; `#`-prefixed summary lines follow):
#   length-baseline-stale / shape-baseline-stale    current < baselined; slack = the gap.
#   length-baseline-orphan / shape-baseline-orphan  the baselined id is not in this ledger at
#     all. The floor forgives a line that is not there, and grandfathers it at the old value
#     the moment the id returns -- the same looseness, in its extreme form. Reported apart
#     because its remedy is the same regen but its cause (a closed or archived item) is not a
#     shrink.
#
# Out of scope, matching both ratchets (id:2065): `--inbox` and `*.archive.md`.
if [[ "$staleness" -eq 1 ]]; then
  if [[ "$inbox" -eq 1 || "$LENGTH_LEDGER_KEY" == *.archive.md ]]; then
    echo "# baseline-staleness: $LENGTH_LEDGER_KEY is out of scope for both ratchets (id:2065); nothing checked."
    log "baseline-staleness out-of-scope path=$path inbox=$inbox"
    exit 0
  fi

  # The ledger, once: id -> its head line. A per-entry grep over a 329-row baseline would be
  # 329 scans of the ledger.
  declare -A STALE_LEDGER_LINE=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^-\ \[[\ xX]\]\  ]] || continue
    _sid="$(length_id_of "$line")"
    [[ -n "$_sid" ]] || continue
    STALE_LEDGER_LINE["$_sid"]="$line"
  done < "$path"

  stale_n=0 stale_slack=0 orphan_n=0 checked_n=0 families_n=0

  # The two per-family "current value" predicates. Each reuses the SAME function the ratchet
  # itself uses, so the detector can never disagree with the rule it is auditing.
  stale_value_length() { local l="$1"; printf '%d' "${#l}"; }
  stale_value_shape()  { local r; r="$(shape_residue "$1")"; printf '%d' "${#r}"; }

  # stale_family <family> <baseline file> <value-fn> <regen flag>
  stale_family() {
    local fam="$1" bfile="$2" vfn="$3" flag="$4"
    local ledger id base cur slack fam_n=0 fam_orphan=0
    if [[ ! -f "$bfile" || ! -r "$bfile" ]]; then
      # LOUD, never silent: a detector that quietly checks nothing is the same silent-inert
      # failure the ratchets' own INERT announcements exist to avoid (id:4347).
      echo "todo-conformance.sh: baseline-staleness: no $fam baseline at $bfile -- that ratchet is INERT here, nothing to check (id:2654)" >&2
      return 0
    fi
    families_n=$((families_n+1))
    while read -r ledger id base; do
      [[ -z "${ledger:-}" || "$ledger" == \#* ]] && continue
      [[ -n "${id:-}" && -n "${base:-}" ]] || continue
      # A baseline file legitimately carries rows for SEVERAL ledgers (TODO.md and ROADMAP.md
      # are appended into one file). Only this path's basename is ours to judge; another
      # ledger's rows would all read as orphans.
      [[ "$ledger" == "$LENGTH_LEDGER_KEY" ]] || continue
      checked_n=$((checked_n+1))
      if [[ -z "${STALE_LEDGER_LINE[$id]:-}" ]]; then
        orphan_n=$((orphan_n+1)); fam_orphan=$((fam_orphan+1))
        printf '%s-baseline-orphan\t%s\tbaselined %s, but no item with this id is in %s; the floor forgives a line that is not there\n' \
          "$fam" "$id" "$base" "$LENGTH_LEDGER_KEY"
        continue
      fi
      cur="$("$vfn" "${STALE_LEDGER_LINE[$id]}")"
      (( cur < base )) || continue
      slack=$((base - cur))
      stale_n=$((stale_n+1)); fam_n=$((fam_n+1)); stale_slack=$((stale_slack+slack))
      printf '%s-baseline-stale\t%s\tcurrent %s < baselined %s; the floor forgives %s more chars than reality requires\n' \
        "$fam" "$id" "$cur" "$base" "$slack"
    done < "$bfile"
    if (( fam_n > 0 || fam_orphan > 0 )); then
      # THE REMEDY, named rather than implied -- the whole point of the mech-currency posture.
      #
      # IT MUST REGENERATE **EVERY** LEDGER, NOT JUST THIS ONE. A baseline file legitimately
      # holds rows for several ledgers (today: 242 TODO.md + 87 ROADMAP.md shape rows in one
      # file). The obvious single-ledger form
      #     todo-conformance.sh --regen-shape-baseline TODO.md > relay/shape-prose-baseline.txt
      # TRUNCATES the file and DELETES the other ledger's rows. Those items then classify
      # `shape-new`, which ESCALATES, so the next --strict run converts 87 warnings into
      # errors. A remedy that damages the repo when followed literally is worse than no
      # remedy: the caller trusts it precisely because it is printed by the detector.
      # (Found by independent review 2026-09-03; the first version printed exactly that.)
      #
      # `--regen-*` emits a header block, so the second and later ledgers must strip it --
      # naive concatenation duplicates the header. This mirrors the recipe the regen headers
      # themselves document.
      local bpath="${bfile}"
      echo "# $fam: $fam_n stale, $fam_orphan orphaned. Regenerate ALL ledgers and COMMIT:"
      echo "#   relay/scripts/todo-conformance.sh $flag TODO.md    >  $bpath"
      echo "#   relay/scripts/todo-conformance.sh $flag ROADMAP.md | grep -v '^#' >> $bpath"
      echo "#   (regenerating only $LENGTH_LEDGER_KEY would DELETE the other ledger's rows)"
    fi
    return 0
  }

  stale_family length "$LENGTH_BASELINE" stale_value_length --regen-length-baseline
  stale_family shape  "$SHAPE_BASELINE"  stale_value_shape  --regen-shape-baseline

  if (( families_n == 0 )); then
    echo "# baseline-staleness: no baseline exists for either ratchet; nothing to check (id:2654)."
  elif (( stale_n == 0 && orphan_n == 0 )); then
    echo "# baseline-staleness: current -- all $checked_n baselined entries for $LENGTH_LEDGER_KEY (across $families_n ratchet(s)) still sit at or above their recorded floor (id:2654)."
  else
    echo "# baseline-staleness: STALE -- $stale_n of $checked_n baselined entries for $LENGTH_LEDGER_KEY (across $families_n ratchet(s)) are below their recorded floor ($stale_slack chars of total slack), $orphan_n orphaned. Regenerate the baselines named above and commit them; nothing was written by this run."
  fi
  log "baseline-staleness path=$path checked=$checked_n stale=$stale_n orphan=$orphan_n slack=$stale_slack strict=$strict"
  if [[ "$strict" -eq 1 ]] && (( stale_n + orphan_n > 0 )); then
    exit 1
  fi
  exit 0
fi

# `--grammar-lines` (id:d667) -- the b048 LINE GRAMMAR as a per-line query, and nothing else.
# Prints `<lineno>TAB<class> (<detail>)` for every non-conforming line in <path>, sorted by
# line number; silent when the file conforms; always exit 0 (this is a QUERY, not a verdict).
#
# WHY THIS EXISTS AS A MODE rather than a caller re-deriving the grammar: the pre-commit
# ledger-grammar ratchet (hooks/pre-commit-ledger-grammar.sh, id:d667) needs to know which
# of a STAGED file's lines are non-conforming so it can intersect that set with the lines
# the diff ADDED. A second copy of the grammar in the hook would drift from this one
# SILENTLY -- the hook would keep passing exactly the shapes the grammar started rejecting.
# So the predicate stays here, in one place, and the hook asks.
#
# It must be a WHOLE-FILE scan, not a per-line one: three of the heading classes
# (heading-no-blank / heading-empty-sec / heading-eof) are decided by LOOKAHEAD, so a line
# handed over in isolation cannot be classified at all. The caller passes the whole staged
# blob and filters by line number afterwards.
#
# Exclusive mode: no length ratchet, no state-claim, no shape check, no --fix. Honors the
# same out-of-scope carve-outs as the in-report grammar (id:2065): `--inbox` and
# `*.archive.md` produce NO output at all.
if [[ "$grammar_lines" -eq 1 ]]; then
  if [[ "$LEDGER_GRAMMAR_CHECK" -eq 1 && "$inbox" -eq 0 && "$LENGTH_LEDGER_KEY" != *.archive.md ]]; then
    grammar_scan "$path"
    if (( ${#GRAMMAR_FIND[@]} > 0 )); then
      for _gl in "${!GRAMMAR_FIND[@]}"; do
        printf '%s\t%s\n' "$_gl" "${GRAMMAR_FIND[$_gl]}"
      done | sort -n
    fi
  fi
  log "grammar-lines path=$path findings=${#GRAMMAR_FIND[@]}"
  exit 0
fi

# The ratchet is INERT unless it has a baseline, and says so LOUDLY. Out of scope entirely:
# the inbox (short routing lines, no detail-file tree) and `*.archive.md` (id:2065).
if [[ "$inbox" -eq 0 && "$LENGTH_LEDGER_KEY" != *.archive.md ]]; then
  if [[ -f "$LENGTH_BASELINE" && -r "$LENGTH_BASELINE" ]]; then
    length_baseline_load "$LENGTH_BASELINE"
    LENGTH_RATCHET_ON=1
  else
    echo "todo-conformance.sh: head-length ratchet INERT -- no baseline at $LENGTH_BASELINE (id:0d7c; regenerate with --regen-length-baseline)" >&2
    log "length-ratchet inert baseline=$LENGTH_BASELINE path=$path"
  fi
  # The SHAPE ratchet (id:2d17), same scope and same inert-and-loud contract. Silent-inert
  # is deliberately NOT an option: a saturation fix that quietly does nothing is the very
  # failure class this item exists to close.
  if [[ -f "$SHAPE_BASELINE" && -r "$SHAPE_BASELINE" ]]; then
    shape_baseline_load "$SHAPE_BASELINE"
    SHAPE_RATCHET_ON=1
  else
    echo "todo-conformance.sh: shape ratchet INERT -- no baseline at $SHAPE_BASELINE (id:2d17; regenerate with --regen-shape-baseline)" >&2
    log "shape-ratchet inert baseline=$SHAPE_BASELINE path=$path"
  fi
fi

findings=0 fixed=0
# strict_findings (id:cb3e) — the WARN→ERROR boundary subset of findings: every
# non-state-claim finding, PLUS state-claim findings whose id is NOT in the
# checked-in baseline. `findings` still counts everything (drives reporting: a
# baselined state-claim hit is always printed, never silently dropped); only
# strict_findings drives the --strict nonzero exit below.
strict_findings=0
out_lines=()
declare -a fix_lines=()   # 1-based line numbers needing a minted id

# scan_path: walk $path, populate out_lines[] / findings / fix_lines[]. Tracks the
# heading-as-item state (id:c095) so a `- [ ]/[x]` status sub-line under a
# `## [LANE] … <!-- id -->` heading-item is NOT flagged/auto-fixed (the heading owns
# the id). `$1`=collect-fix (1 → record missing-id line numbers for --fix).
scan_path() {
  local collect_fix="$1" line cls lr gr lineno=0 heading_is_item=0
  findings=0; strict_findings=0; out_lines=(); fix_lines=()
  # b048 grammar pre-pass. Out of scope for `--inbox` (a routing queue, not a ledger) and
  # for `*.archive.md` (id:2065). Re-run per scan so a --fix rescan sees the fixed lines.
  GRAMMAR_FIND=()
  if [[ "$LEDGER_GRAMMAR_CHECK" -eq 1 && "$inbox" -eq 0 && "$LENGTH_LEDGER_KEY" != *.archive.md ]]; then
    grammar_scan "$path"
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno+1))
    if [[ "$inbox" -eq 0 ]]; then
      if [[ "$line" =~ ^#{1,6}[[:space:]] ]]; then
        # Heading-as-item (id:c095) is signalled by a relay LANE tag in the heading
        # (`## [ROUTINE] …` / `## [HARD — pool] …`) — the heading IS an executable item
        # whose `- [ ]/[x]` children are status markers. A plain section heading
        # (`## Current`, `## [HUMAN] … <!-- id:1ef9 -->`) is NOT a heading-as-item even
        # if it carries an id for batch-tracking — its children are REAL items that must
        # be linted. So detect on the LANE tag ONLY (matches roadmap-lint), never on a
        # bare id token (the id-token branch wrongly hid real items under id'd sections).
        # id:e8d4 — two-delimiter alternation (em dash OR ASCII hyphen, optional
        # surrounding space), fixing the `'[HARD-'` defect: that literal had no
        # space, so it matched NEITHER the em-dash spelling NOR the hyphen target
        # spelling `[HARD - pool]` (space-hyphen-space) -- a third, silently-missed
        # spelling (hazard 4, docs/migration-em-dash-delimiter.md).
        if [[ "$line" == *'[ROUTINE]'* || "$line" =~ \[HARD[[:space:]]*[—-] ]]; then
          heading_is_item=1
        else
          heading_is_item=0
        fi
      elif [[ "$heading_is_item" -eq 1 && "$line" =~ ^-\ \[[\ xX]\]\  ]]; then
        # A status sub-line of a heading-as-item is not a separate ITEM for the older
        # checks -- but it is still a LINE, and the b048 grammar is a line grammar. Emit
        # its grammar finding (WARN) before skipping the rest.
        gr="${GRAMMAR_FIND[$lineno]:-}"
        if [[ -n "$gr" ]]; then
          findings=$((findings+1))
          out_lines+=("$(printf '%s\t%d\t%s' "$gr" "$lineno" "$line")")
        fi
        continue   # status sub-line of a heading-as-item — not a separate item
      fi
    fi
    if [[ "$inbox" -eq 1 ]]; then cls="$(classify_inbox "$line")"; else cls="$(classify_todo "$line")"; fi
    # State-claim doctrine check (id:5533, AMENDS id:dafa): the SAME shared engine
    # roadmap-lint.sh's DECIDED-LEFT-OPEN rule uses, so the two linters can never
    # silently return different verdicts on identical line text. Runs on any OPEN
    # `- [ ]` top-level item regardless of its missing-id/orphan/conforming class
    # (a decided-but-open item can otherwise carry a perfectly well-formed id).
    sc=""
    dp=""
    if [[ "$inbox" -eq 0 && "$line" =~ ^-\ \[\ \]\  ]]; then
      sc="$(state_claim_violation "$line")"
      # id:3f7e DEP-PROSE-UNTYPED (twin of roadmap-lint.sh rule 3(e), same shared
      # engine — lib-typed-edges.sh). WARN-only: adds to `findings` (always
      # reported) but never to `strict_findings` (never fails --strict) — the
      # ROADMAP.md item's own ruling is WARN, not ERROR, and that never escalates.
      dp="$(typed_edges_dep_prose_untyped_of_line "$line")"
    fi
    # Head-line length ratchet (id:0d7c). Computed BEFORE the skip below, since a line can
    # be perfectly conforming by grammar and still be over budget / regrown.
    lr=""
    if [[ "$LENGTH_RATCHET_ON" -eq 1 ]]; then
      lr="$(length_ratchet_class "$line")"
    fi
    # Structural shape check (id:30fe). Independent of the length ratchet on purpose: it
    # asks a different question, it needs no baseline, and it must still run in a repo
    # that has no baseline file at all (loderite today). WARN-only -- see the header.
    sh="$(shape_class "$line")"
    # Ledger line grammar (id:b048) — precomputed by grammar_scan, looked up by line number
    # so the multi-line heading rules still point at the offending line.
    gr="${GRAMMAR_FIND[$lineno]:-}"
    if [[ -z "$cls" && -z "$sc" && -z "$dp" && -z "$lr" && -z "$sh" && -z "$gr" ]]; then continue; fi
    if [[ -n "$cls" ]]; then
      findings=$((findings+1)); strict_findings=$((strict_findings+1))
      out_lines+=("$(printf '%s\t%d\t%s' "$cls" "$lineno" "$line")")
      [[ "$cls" == "missing-id" && "$collect_fix" -eq 1 ]] && fix_lines+=("$lineno")
    fi
    if [[ -n "$sc" ]]; then
      findings=$((findings+1))
      # WARN→ERROR boundary (id:cb3e): a baselined id never counts toward
      # strict_findings — it is reported (below) but can never fail --strict.
      # `|| true`: a state-claim violation on an id-LESS line is legitimate (that line is
      # already reported as `missing-id`), and grep's no-match exit 1 was, under `set -o
      # pipefail`, killing the whole scan mid-file. Measured 2026-09-02 on this repo's own
      # TODO.md: the script exited 1 having printed NOTHING at all, silently reporting zero
      # findings on 576 real ones. Found while wiring id:0d7c; it is not the ratchet's own
      # bug, but it made every rule in this file dead on the live ledger. The empty id then
      # falls through to state_claim_in_baseline, which returns "not baselined" for "".
      _sc_id="$( { grep -oP '<!--\s*id:\K[0-9a-f]{4}(?=[-a-z0-9]*\s*-->)' <<<"$line" || true; } | tail -1)"
      if state_claim_in_baseline "$_sc_id" "$STATE_CLAIM_BASELINE"; then
        out_lines+=("$(printf 'decided-left-open (baselined id:cb3e)\t%d\t%s' "$lineno" "$line")")
      else
        strict_findings=$((strict_findings+1))
        out_lines+=("$(printf 'decided-left-open\t%d\t%s' "$lineno" "$line")")
      fi
    fi
    if [[ -n "$dp" ]]; then
      findings=$((findings+1))
      out_lines+=("$(printf 'dep-prose-untyped (id:%s)\t%d\t%s' "$dp" "$lineno" "$line")")
    fi
    if [[ -n "$lr" ]]; then
      findings=$((findings+1))
      # Only the two RATCHET-BREAKING classes escalate. `length-grandfathered` and
      # `length-unshrinkable` are always reported and can never fail --strict: the first is
      # the grandfathering that lets this land without a migration, the second is the
      # ratified composition rule (a rule may not demand a cut the tool will not make).
      case "$lr" in
        length-over-budget*) strict_findings=$((strict_findings+1)) ;;  # id:0d7c NEWOVER
        length-regrowth*)    strict_findings=$((strict_findings+1)) ;;  # id:0d7c REGROWTH
      esac
      out_lines+=("$(printf '%s\t%d\t%s' "$lr" "$lineno" "$line")")
    fi
    if [[ -n "$sh" ]]; then
      findings=$((findings+1))
      # `shape-prose` and `shape-grandfathered` NEVER escalate: 460 of 840 lines fail the
      # bare class, so --strict would refuse every commit until id:8524 lands, and the
      # grandfathered class is the standing corpus by definition. Promoting THOSE is
      # id:8524's closing act, not this one's.
      #
      # `shape-new` and `shape-regrowth` DO escalate (id:2d17). That asymmetry is the whole
      # fix: they are the two classes that did not exist at capture time, so escalating
      # them adds information rather than re-litigating the backlog. A baseline may
      # grandfather, never silence -- so the standing set keeps being REPORTED either way.
      case "$sh" in
        shape-new*|shape-regrowth*) strict_findings=$((strict_findings+1)) ;;
      esac
      out_lines+=("$(printf '%s\t%d\t%s' "$sh" "$lineno" "$line")")
    fi
    if [[ -n "$gr" ]]; then
      findings=$((findings+1))
      # NEVER escalates, by design and by the owner's instruction: 395 of 1080 TODO.md
      # lines and 1559 of 1720 ROADMAP.md lines fail this today, so an ERROR here would
      # wedge the repo. Promotion is a deliberate separate act after the migration, like
      # the shape-prose promotion (id:8524). Do not add this to strict_findings.
      out_lines+=("$(printf '%s\t%d\t%s' "$gr" "$lineno" "$line")")
    fi
  done < "$path"
  return 0   # the while's EOF-exit status (1) must not become scan_path's return (set -e)
}

scan_path "$fix"

# --- AUTO-FIX: append a minted id to each well-formed open item missing one --------------
# Only the missing-id class (never orphan). flock the file; mint via append.sh new-id.
if [[ "$fix" -eq 1 && "${#fix_lines[@]}" -gt 0 ]]; then
  lock="$path.conformance.lock"
  exec 9>"$lock"
  if flock -w 30 9; then
    for ln in "${fix_lines[@]}"; do
      # Re-read the line under the lock (line numbers are stable — no prior edit reflows).
      cur="$(sed -n "${ln}p" "$path")"
      # Idempotency: already has a canonical token → nothing to do.
      id_tag_present "$cur" && continue
      # SAFETY: if the line carries a NON-canonical inline id (`(id:560c)` / bare `id:560c`,
      # as some repos use), do NOT mint — that would create a DUPLICATE id. Surface it for a
      # human/handoff to MIGRATE the notation to `<!-- id:XXXX -->` (reusing the same token).
      if grep -qP '\bid:[0-9a-f]{4}\b' <<<"$cur"; then
        echo "todo-conformance.sh: line $ln has a non-canonical inline id — NOT auto-minted (migrate to <!-- id:XXXX --> by hand to avoid a duplicate id)" >&2
        log "skip-inline-id line=$ln file=$path"
        continue
      fi
      tok="$(head -1 < <(bash "$APPEND_SH" new-id 2>>"$LOG" | grep -oP '^[0-9a-f]{4}$') || true)"
      if [[ -z "$tok" ]]; then
        echo "todo-conformance.sh: could not mint an id for line $ln (append.sh new-id failed)" >&2
        continue
      fi
      esc_tok="$tok"
      sed -i "${ln}s|[[:space:]]*\$| <!-- id:${esc_tok} -->|" "$path"
      fixed=$((fixed+1))
      log "fixed missing-id line=$ln id=$tok file=$path"
    done
    flock -u 9
  else
    echo "todo-conformance.sh: could not acquire fix lock on $path within 30s" >&2
  fi
  exec 9>&-
  [ -e "$lock" ] && rm -- "$lock"   # lock may already be gone (concurrent unlink); no force, no swallow
fi

# --- report -----------------------------------------------------------------------------
if [[ "$findings" -gt 0 ]]; then
  # Re-derive the post-fix surface: missing-id lines that were just fixed are no longer
  # reported (so a --fix run shows only what remains for a human).
  if [[ "$fix" -eq 1 && "$fixed" -gt 0 ]]; then
    scan_path 0   # re-derive the post-fix surface (fixed missing-id lines now have ids)
    echo "todo-conformance: auto-fixed $fixed missing-id item(s) in $path" >&2
  fi
  [[ "${#out_lines[@]}" -gt 0 ]] && printf '%s\n' "${out_lines[@]}"
fi
log "path=$path inbox=$inbox findings=$findings strict_findings=$strict_findings fixed=$fixed strict=$strict"

if [[ "$strict" -eq 1 && "$strict_findings" -gt 0 ]]; then
  exit 1
fi
exit 0
