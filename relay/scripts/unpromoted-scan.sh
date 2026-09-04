#!/usr/bin/env bash
# unpromoted-scan.sh — list OPEN TODO.md items whose id has NO twin in
# ROADMAP.md ∪ ROADMAP.archive.md, REGARDLESS of whether the TODO line carries a
# lane tag (id:2dea).
#
# ARCHIVE (routed:8b21): the twin corpus includes ROADMAP.archive.md. Reading the live
# file alone made every already-SHIPPED item whose TODO twin was never ticked reappear
# as `promote` the moment roadmap-archive.sh swept its ROADMAP twin out — re-dispatched
# forever. Same defect class as routed:42c9 in orphan-scan.sh --cross-ledger.
#
# WHY (LIVE evidence 2026-06-25, truncocraft — SECOND instance; first was id:78ff):
# `/relay next`/`review`/handoff decide "is there work?" from OPEN ROADMAP items +
# unaudited commits ONLY. truncocraft's ROADMAP was fully `[x]`-closed while TODO.md
# held FIVE open executable items with no ROADMAP twin — so every prior `/relay` run
# read the repo as DRAINED and the un-promoted backlog sat idle for days, even though
# promoting TODO→ROADMAP is exactly handoff C2's job. "ROADMAP closed" != "nothing to
# hand off."
#
# GAP vs the existing d9b0 `orphan-scan.sh --promotion` check: that one only flags a TODO
# item ALREADY carrying an executable lane ([ROUTINE] / [HARD — pool]). truncocraft's
# stranded items carried NO lane tag at all (raw backlog prose) → they slipped past it.
# This scan is LANE-TAG-AGNOSTIC: it reports every un-twinned open TODO id and labels its
# disposition (promote vs surface) so the strong turn can triage — it NEVER auto-promotes
# an untagged item with a guessed lane.
#
# Output (TSV, report-only — exit 0 with findings; only MISUSE exits nonzero):
#   <repo>\t<id>\t<disposition>\t<title>
#     disposition = promote   → line carries an executable lane ([ROUTINE], or the pool
#                               lane in EITHER spelling — bare [HARD] (new) / [HARD — pool]
#                               (old, migration window)); directly handoff-promotable.
#                 = surface   → untagged / ambiguous → SURFACE for strong-turn triage,
#                               never auto-promote (acceptance #3). NOT emitted for a
#                               line whose lane question was already RESOLVED in the
#                               decision-queue (parked/not-an-item — 2026-07-02 fix).
#                 = laned     → carries a recognized HUMAN lane ([HARD — meeting]/
#                               [HARD — hands]/[HARD — decision gate]/[INPUT — meeting]/
#                               [INPUT — decision]/[INPUT — access]/[INPUT — author]) or
#                               [MECHANICAL] as its PRIMARY
#                               tag: lane already decided — reported for visibility,
#                               verdict-neutral (classify counts only promote/surface),
#                               never filed to the decision-queue (2026-07-02 fix for
#                               the answer-then-re-ask loop).
#                 = untracked → an open `- [ ]` item with NO `<!-- id:XXXX -->` token
#                               (id column is `----`). Cannot be correlated to ROADMAP at
#                               all — the favicon-class blind spot from the truncocraft
#                               evidence. handoff C2 mints an id (append.sh new-id) first.
#
# SCOPE (what this does NOT catch — by design): the unit of TODO work is the well-formed
# top-level checkbox line `- [ ] …`. A TODO written as free prose, a non-`-` bullet
# (`* …`), an indented sub-bullet, or a bare line with no checkbox is NOT a tracked item
# and is intentionally ignored — trying to promote arbitrary prose would false-positive on
# every narrative line. The `untracked` disposition closes the one bounded gap that bit
# truncocraft (a real checkbox item that merely lacked an id); malformed-beyond-a-checkbox
# entries are a TODO-hygiene problem, not a routing signal this scan owns.
#
# Usage:
#   unpromoted-scan.sh [SCOPE]
#     (no arg)   → the cwd repo (git rev-parse --show-toplevel)
#     <repo-dir> → that repo
#     --all      → every relay.toml `classification = "own"` repo (reads $RELAY_TOML,
#                  honors `# path:` overrides, like relay-doctor.sh / relay-reconcile.sh)
#   An UNKNOWN flag / an explicit repo path that is missing or not a git repo is a LOUD
#   reject (nonzero exit). Under --all an unreadable repo is SURFACED on stderr and
#   skipped (never silently swallowed — id:4e14 / id:415b).
#
# Conventions: set -euo pipefail; short stdout; `2>/dev/null` only with a stated reason;
# details → ~/.claude/logs/unpromoted-scan.log.
set -euo pipefail

LOG="${UNPROMOTED_SCAN_LOG:-$HOME/.claude/logs/unpromoted-scan.log}"
SRC_DIR="${SRC_DIR:-$HOME/src}"
RELAY_TOML="${RELAY_TOML:-$HOME/.config/relay/relay.toml}"
# Sibling decision-queue helper (id:47f1 case-g exclusion). Resolves alongside this
# script whether run via the canonical path or the ~/.claude/skills symlink (both dirs
# carry the sibling). Fail-open if absent.
DQ="$(dirname "${BASH_SOURCE[0]}")/decision-queue.sh"

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
log() { printf '%s unpromoted-scan.sh %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true; }

# strip_detail_pointer <text> -- echo <text> with ONE leading `-- detail: `path/XXXX.md``
# pointer (plus the whitespace around it) removed; unchanged if it carries none.
#
# id:3795: `tools/ledger-shrink.py` plants that pointer BETWEEN the bold title and
# whatever followed it, so a lane tag that used to sit immediately after the title ends up
# immediately after the POINTER instead. `primary_lane()`'s bold branch reads only the
# position right after the title, so a trimmed item went lane-DARK: measured on this repo's
# live ledger, 60 rows carried a lane after the pointer and 18 dispositioned `surface`,
# 8 of them losing an EXECUTABLE lane ([HARD - pool] x3, [ROUTINE] x4, [HARD] x1). Since
# `promote > 0` yields `handoff` while `surface > 0 AND promote == 0` yields `human`, the
# trim could silently convert pool-executable work into a human question (the id:4b64
# failure class through a new door).
#
# This skips EXACTLY the pointer -- a known, structured token -- and nothing else. It must
# never be widened into "any text between the title and a bracket": the strict post-title
# anchor is precisely what stops a lane token mentioned in PROSE from setting the lane
# (id:fb7f, id:3e14/id:be40). `classify-repo.sh` takes the first lane hit anywhere by
# design (id:4da4) and is immune to this bug; do NOT converge the two by loosening here.
#
# Both pointer spellings are accepted: this repo's shrinker emits ASCII ` -- detail: `,
# while the reference implementation emits an em dash, and a single `-` is allowed too
# (the shrinker's own KEEP pattern is `-{1,2}\s*detail:`). Alternation of literal dash
# strings, not a bracket class, so the multibyte spelling matches byte-wise under any
# locale.
strip_detail_pointer() {
  local s="$1"
  local ptr_re='^(--|—|-)[[:space:]]*detail:[[:space:]]*`?[A-Za-z0-9_./-]*/[0-9a-f]{4}\.md`?[[:space:]]*'
  if [[ "$s" =~ $ptr_re ]]; then
    printf '%s' "${s#"${BASH_REMATCH[0]}"}"
  else
    printf '%s' "$s"
  fi
}

# primary_lane <line> — echo the item's genuine lane tag, or nothing if it has none.
# Mirrors classify-repo.sh's id:4da4 primary-lane parse: a lane tag clusters right after
# the title; any bracket-token further right is prose/history and must NOT set the lane.
# Used for the promote-vs-surface disposition (id:ed2e).
#
# id:fb7f — bold-titled items (the TODO.md convention, `- [ ] **title** [TAG] ...`) anchor
# STRICTLY: the tag must sit immediately after the title's closing `**` (+ optional
# whitespace), or the item has NO genuine lane (return empty → surface). A bare leftmost-tag
# scan mislabeled bold-titled items whose ONLY bracket-tag mention was prose deep in the body
# (backtick'd or bare) as `promote` — 33c2/a505/7b23/b8ae, 2026-07-02. Non-bold items (no
# `**title**`) fall back to the leftmost-tag-anywhere scan (ROADMAP.md's own convention puts
# the tag right after the checkbox, before any title text, so "leftmost" is already correct
# there and TODO.md's non-bold prose-summary items carry no genuine tag either way).
primary_lane() {
  local line="$1" tag rest="" lead_tag="" prefix after best_pos=-1 best_tag="" pos
  # id:719a — recognized lane vocabulary spans BOTH the old venue-keyed spelling
  # ([HARD — pool|hands|meeting|decision gate]) and the new capability-keyed spelling
  # ([INPUT — meeting|access|decision|author], bare [HARD], [MECHANICAL]) during the
  # dual-vocab window (id:7df1 gated).
  #
  # id:4b64 (routed:6629) — `[INPUT — author]` (the 5th capability lane, id:2b0b) was
  # MISSING from this list, so a properly-laned author item fell through to `surface`,
  # inflating the surface count that drives the `human` verdict AND re-asking a lane
  # question the line already answers (observed: lodelore id:e545). Every lane spelling
  # in relay/references/hard-lanes.md's capability table must appear here — the
  # per-spelling fixtures in tests/test_lane_vocab_both_sides_4b64.sh pin that.
  #
  # POOL lane = both spellings: bare [HARD] (new) and [HARD — pool] (old) are the SAME
  # lane (hard-lanes.md's 1:1 rename table), so both map to `promote` in the disposition
  # below. Everything else here is recognized-but-laned (lane question already answered).
  # id:e8d4 — two-delimiter alternation: each old-vocab tag is listed under BOTH the
  # legacy em dash and the target ASCII hyphen spelling (matches the callers below,
  # which do exact `==`/`case` string comparisons, not a regex character class).
  local -a tags=(
    "[ROUTINE]"
    "[HARD — pool]" "[HARD - pool]"
    "[HARD — hands]" "[HARD - hands]"
    "[HARD — meeting]" "[HARD - meeting]"
    "[HARD — decision gate]" "[HARD - decision gate]"
    "[INPUT — meeting]" "[INPUT - meeting]"
    "[INPUT — access]" "[INPUT - access]"
    "[INPUT — decision]" "[INPUT - decision]"
    "[INPUT — author]" "[INPUT - author]"
    "[MECHANICAL]" "[HARD]"
  )
  # id:719a — tag-before-bold-title anchor: "- [ ] [TAG] **title** ..." (new-vocab items
  # are conventionally tagged BEFORE the bold title, unlike old-vocab's after-title spot).
  # A tag here wins over any prose token regardless of order.
  if [[ "$line" =~ ^-\ \[\ \]\ (\[[^]]*\])\ \*\* ]]; then
    lead_tag="${BASH_REMATCH[1]}"
    for tag in "${tags[@]}"; do
      [[ "$lead_tag" == "$tag" ]] && { printf '%s' "$tag"; return; }
    done
  fi
  # id:4b64 — BOLD-TAG anchor: "- [ ] **[TAG]** title …". This is the shape relay's own
  # id:3801 auto-gate/auto-split EMITS (handback-followup.py renders both the gate tag and
  # every seam's tier tag bold), so without this branch the emitter and this reader
  # disagreed about relay's OWN output: the bold branch below treats `**[HARD]**` as the
  # item's TITLE, finds no tag after it, and returns empty → `surface`. A bold span whose
  # entire content is a recognized lane tag is never a prose title, so this is unambiguous.
  if [[ "$line" =~ ^-\ \[\ \]\ \*\*(\[[^]]*\])\*\* ]]; then
    lead_tag="${BASH_REMATCH[1]}"
    for tag in "${tags[@]}"; do
      [[ "$lead_tag" == "$tag" ]] && { printf '%s' "$tag"; return; }
    done
  fi
  if [[ "$line" =~ ^-\ \[\ \]\ \*\*[^*]*\*\*[[:space:]]*(.*)$ ]]; then
    rest="${BASH_REMATCH[1]}"
    # id:3795: a `-- detail:` pointer is TRANSPARENT here: the shrinker plants it between
    # the title and the lane tag, so skip exactly it and re-anchor on what follows.
    rest="$(strip_detail_pointer "$rest")"
    for tag in "${tags[@]}"; do
      case "$rest" in
        "$tag"*) printf '%s' "$tag"; return ;;
      esac
    done
    printf ''
    return
  fi
  # id:6b1c — non-bold items must ALSO be anchored, not scanned leftmost-anywhere.
  # A genuine tag sits at one of two natural positions: (a) the HEAD, immediately
  # after `- [ ] `, optionally preceded by exactly one non-tag prefix bracket
  # (`[INBOUND ...]` / `[<target-repo>]`); or (b) a CLAUSE boundary — immediately
  # (mod whitespace) before the trailing `<!-- id:... -->` marker, or before a
  # following dash aside. A bracket-token that sits fluidly mid-sentence, with
  # more prose both before AND after it before the next boundary, is prose merely
  # DISCUSSING a lane (the id:3e14/id:be40 shapes) and must NOT set the lane.
  #
  # (b) is what keeps the pre-existing id:4da4 "first recognized tag wins" behaviour
  # for a line like `(i) design item [HARD — meeting] — note: supersedes an earlier
  # [ROUTINE] plan`: `[HARD — meeting]` sits right before its own aside (a
  # clause boundary) so it counts as genuine, while the `[ROUTINE]` mentioned deeper
  # inside that very aside sits mid-sentence and does not.
  #
  # id:6bf5 — the ASIDE MARKER is two-spelling, exactly as the lane DELIMITER is.
  # The em-dash ban routes every newly written aside to `--`, so an item spelled
  # entirely in the target vocabulary -- `(i) work item [HARD - pool] -- note: ...`
  # -- hit NO boundary at all and returned empty, i.e. `surface` for a human lane
  # and, worse, `surface` for the POOL lane instead of `promote`. That is the id:4b64
  # lodelore silent-idle failure re-created in the new delimiter: a repo whose whole
  # backlog is new-vocab counts 0 in promote AND 0 in laned and classifies idle.
  # MEASURED before the fix (four fixture items, identical but for spelling):
  #   [HARD — meeting] + em-dash aside → laned      [HARD - meeting] + `--` aside → surface
  #   [HARD — pool]    + em-dash aside → promote    [HARD - pool]    + `--` aside → surface
  # Only a RUN of two or more hyphens counts. A single `-` is ordinary prose
  # punctuation and must never open a clause here.
  local head_re='^-\ \[\ \]\ (\[[^]]*\])(\ (\[[^]]*\]))?'
  if [[ "$line" =~ $head_re ]]; then
    local b1="${BASH_REMATCH[1]}" b2="${BASH_REMATCH[3]:-}"
    for tag in "${tags[@]}"; do
      [[ "$b1" == "$tag" ]] && { printf '%s' "$tag"; return; }
    done
    if [[ -n "$b2" ]]; then
      for tag in "${tags[@]}"; do
        [[ "$b2" == "$tag" ]] && { printf '%s' "$tag"; return; }
      done
    fi
  fi
  for tag in "${tags[@]}"; do
    case "$line" in
      *"$tag"*)
        prefix="${line%%"$tag"*}"
        after="${line#"$prefix$tag"}"
        if [[ "$after" =~ ^[[:space:]]*$ ]] || [[ "$after" =~ ^[[:space:]]*\<!-- ]] \
          || [[ "$after" =~ ^[[:space:]]*— ]] || [[ "$after" =~ ^[[:space:]]*-- ]]; then
          pos=${#prefix}
          if [[ "$best_pos" -lt 0 || "$pos" -lt "$best_pos" ]]; then
            best_pos=$pos; best_tag="$tag"
          fi
        fi
        ;;
    esac
  done
  printf '%s' "$best_tag"
}

# --- own repos from relay.toml (same parser as relay-doctor.sh) -----------------
own_repos() {
  [[ -f "$RELAY_TOML" ]] || return 0
  SRC_DIR="$SRC_DIR" python3 -c '
import os, re, sys, tomllib
src = os.environ["SRC_DIR"]
toml_path = sys.argv[1]
with open(toml_path, "rb") as f:
    data = tomllib.load(f)
comment_path = {}
cur = None
sect_re = re.compile(r"^\s*\[repos\.([^\]]+)\]\s*$")
path_re  = re.compile(r"^\s*#\s*path:\s*(.+?)\s*$")
with open(toml_path, encoding="utf-8") as f:
    for line in f:
        m = sect_re.match(line)
        if m:
            cur = m.group(1)
            continue
        if cur:
            pm = path_re.match(line)
            if pm and cur not in comment_path:
                comment_path[cur] = pm.group(1)

def expand(p):
    return os.path.expanduser(os.path.expandvars(p))

for name, entry in data.get("repos", {}).items():
    if entry.get("classification") != "own":
        continue
    if entry.get("paused"):
        continue
    path = entry.get("path") or comment_path.get(name) or os.path.join(src, name)
    print(f"{name}\t{expand(path)}")
' "$RELAY_TOML"
}

# --- per-repo scan -------------------------------------------------------------
# Emits one TSV line per un-twinned open TODO id. Honors a missing ledger gracefully
# (a repo with no TODO.md is simply nothing to promote). Returns 1 (LOUD on stderr)
# only when the path is not a readable git repo, so --all can keep going.
findings=0
repos_with_findings=0

scan_repo() {
  local name="$1" path="$2"

  if [[ ! -d "$path" ]]; then
    printf 'ERROR: %s — path not found (%s); cannot scan.\n' "$name" "$path" >&2
    log "repo=$name path-missing=$path"
    return 1
  fi
  if ! git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
    printf 'ERROR: %s (%s) is not a readable git repo — check the path override in relay.toml.\n' "$name" "$path" >&2
    log "repo=$name not-git=$path"
    return 1
  fi

  local todo="$path/TODO.md" roadmap="$path/ROADMAP.md" roadmap_archive="$path/ROADMAP.archive.md"
  # A repo with no TODO.md has no backlog to promote; no ROADMAP.md means every
  # id-bearing open TODO is un-twinned by definition (a not-yet-handed-off repo).
  [[ -f "$todo" ]] || { log "repo=$name no-todo"; return 0; }
  # routed:8b21 — the twin corpus is ROADMAP.md ∪ ROADMAP.archive.md, NOT the live file
  # alone. `roadmap-archive.sh` sweeps shipped `- [x]` items into ROADMAP.archive.md; read
  # only the live file and the twin VANISHES, so an open TODO line whose work already
  # shipped is re-reported `promote` and re-dispatched every single round, forever. The
  # same root cause made a `/relay human` existence check report shipped work as MISSING.
  # This is the exact asymmetry routed:42c9 names in orphan-scan --cross-ledger: the TODO
  # side of the fleet's scanners reads its archive, the ROADMAP side did not.
  # The anchored `<!-- id:XXXX -->` twin test below is applied UNCHANGED to the combined
  # blob, so the id:1312 bare-prose false-match guard covers the archive too.
  local roadmap_content=""
  [[ -f "$roadmap" ]] && roadmap_content="$(cat "$roadmap")" || true
  if [[ -f "$roadmap_archive" ]]; then
    roadmap_content="$roadmap_content"$'\n'"$(cat "$roadmap_archive")"
  fi

  # case-g loop-breaker (id:47f1): a surface item already filed to the decision-queue
  # for OPEN human lane-triage is no longer fresh un-promoted backlog — exclude it so
  # `handoff` stops re-firing on it every round. `decision-queue.sh list` emits open
  # records only; we collect their `source_id` tokens. Fail-open: a missing helper or
  # empty queue simply excludes nothing (never a false-clean — the scan still reports).
  #
  # RESOLVED records matter too (2026-07-02 answer-then-re-ask fix): an UNTAGGED item
  # whose lane question was already RESOLVED in the queue (parked / not-an-item) must
  # not re-surface — otherwise the next human-verdict round re-files it and the queue
  # oscillates. Resolved ids are collected separately: they suppress `surface` for
  # untagged lines ONLY; a line that gained an executable lane tag still promotes.
  local filed_ids=" " resolved_ids=" "
  if [[ -x "$DQ" ]]; then
    filed_ids="$($DQ list --repo "$name" 2>/dev/null | python3 -c '
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        sid = json.loads(line).get("source_id", "")
    except json.JSONDecodeError:
        continue
    if sid:
        print(sid)
' | tr "\n" " " || true)"
    filed_ids=" $filed_ids "
    resolved_ids="$($DQ list --repo "$name" --all 2>/dev/null | python3 -c '
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        rec = json.loads(line)
    except json.JSONDecodeError:
        continue
    if rec.get("status") == "resolved" and rec.get("source_id"):
        print(rec["source_id"])
' | tr "\n" " " || true)"
    resolved_ids=" $resolved_ids "
  fi

  local repo_findings=0 line token disposition title
  while IFS= read -r line; do
    # Exempt intentional non-items (consistent with todo-conformance.sh's exempt()): a line
    # marked <!-- lint-ok: … --> or an intentional cross-repo pointer <!-- ref:XXXX --> is a
    # deliberate non-task, not un-promoted work — never report it (incl. as `untracked`).
    [[ "$line" == *"<!-- lint-ok:"* ]] && continue
    grep -qP '<!-- ref:[0-9a-f]{4} -->' <<<"$line" && continue
    # Relay status-summary line (`- [ ] Relay: …`): the relay's own roll-up, regenerated
    # every review — never a promotable/backlog task. Its `[ROUTINE]`/`[HARD — pool]` tokens
    # are ALWAYS prose (a closed-item tally), so a substring match mis-labels it `promote`
    # → a wasteful handoff dispatch (id:ed2e — hit zkm-eml id:e662, zkm-claude-ai id:815c).
    # Mechanically exempt it here, which also removes the need for a hand-added lint-ok marker
    # on these lines (cf. meeting-rpg id:070c). Same prose-false-match family as id:4da4.
    grep -qE '^- \[ \] Relay: ' <<<"$line" && continue
    token="$(head -1 < <(grep -oP '(?<=<!-- id:)[0-9a-f]{4}(?= -->)' <<<"$line") || true)"
    if [[ -z "$token" ]]; then
      # No id token → cannot be correlated to ROADMAP at all (the favicon-class blind
      # spot from the truncocraft evidence). It is un-promoted by definition: report it
      # as `untracked` so handoff C2 mints an id (append.sh new-id) before promoting.
      # `id` column is `----` (no real token) to keep the TSV column count stable.
      title="$(sed -E 's/^- \[ \] +//' <<<"$line")"
      printf '%s\t%s\t%s\t%s\n' "$name" "----" "untracked" "$title"
      repo_findings=$((repo_findings + 1))
      continue
    fi
    # Twin = the id has its OWN trailing marker on a ROADMAP checkbox line — ANCHORED,
    # NOT a bare-substring grep over the whole file. A bare `grep -qF "id:$token"` (the
    # original) false-matches ordinary explanatory PROSE that merely mentions a token
    # ("...separate seam tracked as id:2b63") anywhere in another item's text, silently
    # treating it as already-twinned and dropping it from the backlog scan (id:1312;
    # observed 2026-07-16: `df4e` went laned → 0 rows this way). Require the token to
    # appear as its OWN `- [ ]`/`- [x]` checkbox line's `<!-- id:XXXX -->` marker,
    # mirroring the anchoring scan-routed.sh already applies to its twin check. NOT
    # end-of-line-anchored (id:798d): handback-followup.py's gate_line (id:1b1a)
    # deliberately inserts a trailing gate note AFTER the marker
    # (`<!-- id:XXXX --> — 🚧 GATED (auto, id:3801; ...)`), so an end-anchored match
    # missed every auto-GATED item and phantom-re-dispatched its TODO twin every round.
    # The `<!-- id:XXXX -->` HTML-comment form is itself the anchor that still prevents
    # the id:1312 bare-prose false-match — dropping only the `[[:space:]]*$` end-anchor
    # does not reopen that hole.
    grep -qE "^- \\[[ x]\\].*<!-- id:${token} -->" <<<"$roadmap_content" && continue
    # Already filed for OPEN human lane-triage → not fresh backlog (case-g, id:47f1).
    [[ "$filed_ids" == *" $token "* ]] && { log "repo=$name filed=$token"; continue; }

    # Disposition: an executable lane tag means directly handoff-promotable; a recognized
    # HUMAN lane tag ([HARD — meeting|hands|decision gate] / [INPUT — …]) means the
    # lane question is ANSWERED on the line itself → `laned` (reported for visibility,
    # verdict-neutral, never filed to the decision-queue — filing a lane-triage request
    # for an already-laned line is the answer-then-re-ask loop, 2026-07-02 fix); anything
    # untagged SURFACES for triage — unless its lane question was already resolved in the
    # decision-queue (parked / not-an-item), in which case it is skipped.
    # id:ed2e / id:4da4 — PRIMARY-LANE anchoring: the item's lane is the FIRST recognized
    # lane-tag on the line, NOT any substring match. A bare `grep [ROUTINE]` mis-promotes a
    # human-gated item that merely MENTIONS an executable lane later in its prose/history
    # (e.g. a `[HARD — meeting]` item whose body says "supersedes an earlier [ROUTINE] plan").
    local lane
    lane="$(primary_lane "$line")"
    # id:4b64 (routed:5ccd) — the POOL lane counts as `promote` in BOTH spellings. This
    # test used to match `[ROUTINE]|[HARD — pool]` ONLY, so bare `[HARD]` — the recorded
    # 1:1 successor of `[HARD — pool]` (relay/references/hard-lanes.md rename table) —
    # fell through to `laned`, which is verdict-NEUTRAL by design (it exists for HUMAN
    # lanes, where re-triage would be the answer-then-re-ask loop). classify-repo.sh
    # folds only {promote, surface}, so a repo whose entire apex backlog was written in
    # the NEW vocabulary counted zero in both and classified `idle` — it never
    # self-routed to handoff (VERIFIED LIVE in lodelore: id:b0c4 + id:193f both reported
    # `laned`, classify-repo returned verdict:idle, unpromoted.promote:0/.surface:0).
    # The pre-commit lane-vocab ratchet (hooks/pre-commit-lane-vocab.sh) pushes every
    # repo INTO that spelling, so the blind spot was actively spreading.
    # Human lanes stay `laned` — do NOT widen this to any other tag.
    # id:e8d4 — BOTH pool spellings promote. primary_lane's tag list gained
    # `[HARD - pool]`, so it now RETURNS the hyphen form; without the same addition
    # here that item falls to `laned` and is never promoted -- which is precisely the
    # lodelore failure described in the paragraph above, re-created in the new
    # delimiter. The tag list and this disposition must always change together.
    if [[ "$lane" =~ ^(\[ROUTINE\]|\[HARD\]|\[HARD\ —\ pool\]|\[HARD\ -\ pool\])$ ]]; then
      disposition="promote"
    elif [[ -n "$lane" ]]; then
      disposition="laned"
    elif [[ "$resolved_ids" == *" $token "* ]]; then
      log "repo=$name resolved=$token (lane question answered in decision-queue; not re-surfaced)"
      continue
    else
      disposition="surface"
    fi
    # Title: the line's prose minus the leading "- [ ] " and the trailing id comment.
    title="$(sed -E 's/^- \[ \] +//; s/[[:space:]]*<!-- (children|gated-on):[0-9a-f,]+ -->//g; s/[[:space:]]*<!-- id:[0-9a-f]{4} -->[[:space:]]*$//' <<<"$line")"
    printf '%s\t%s\t%s\t%s\n' "$name" "$token" "$disposition" "$title"
    repo_findings=$((repo_findings + 1))
  done < <(grep -E '^- \[ \] ' "$todo" 2>/dev/null || true)

  findings=$((findings + repo_findings))
  [[ "$repo_findings" -gt 0 ]] && repos_with_findings=$((repos_with_findings + 1)) || true
  log "repo=$name unpromoted=$repo_findings"
  return 0
}

# --- parse args ----------------------------------------------------------------
scope="cwd"
repo_arg=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)     scope="all"; shift ;;
    -h|--help) sed -n '2,52p' "$0"; exit 0 ;;  # +6: the routed:8b21 archive note
    --*)       echo "unpromoted-scan.sh: unknown flag '$1'" >&2; exit 2 ;;
    *)
      if [[ -n "$repo_arg" ]]; then
        echo "unpromoted-scan.sh: only one repo path may be given (got extra '$1')" >&2
        exit 2
      fi
      repo_arg="$1"; scope="repo"; shift ;;
  esac
done

case "$scope" in
  cwd)
    root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -z "$root" ]]; then
      echo "unpromoted-scan.sh: cwd is not inside a git repo and no repo path was given" >&2
      exit 2
    fi
    scan_repo "$(basename "$root")" "$root" || true
    ;;
  repo)
    if [[ ! -d "$repo_arg" ]]; then
      echo "unpromoted-scan.sh: scope path not found: $repo_arg" >&2
      exit 2
    fi
    if ! git -C "$repo_arg" rev-parse --git-dir >/dev/null 2>&1; then
      echo "unpromoted-scan.sh: scope path is not a git repo: $repo_arg" >&2
      exit 2
    fi
    abspath="$(cd "$repo_arg" && pwd)"
    scan_repo "$(basename "$abspath")" "$abspath" || true
    ;;
  all)
    any=0
    while IFS=$'\t' read -r rname rpath; do
      [[ -n "$rname" ]] || continue
      any=1
      scan_repo "$rname" "$rpath" || true
    done < <(own_repos)
    if [[ "$any" -eq 0 ]]; then
      echo "unpromoted-scan.sh: --all found NO own repos in $RELAY_TOML (is it readable?)" >&2
    fi
    ;;
esac

log "summary findings=$findings repos_with_findings=$repos_with_findings scope=$scope"
exit 0
