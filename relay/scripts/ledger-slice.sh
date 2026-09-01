#!/usr/bin/env bash
# relay/scripts/ledger-slice.sh — id:e68f. HOST-side ledger slicer.
#
# Before dispatching a child, the orchestrator extracts exactly what that one unit needs —
# the dispatched item's own block, its typed `gated-on:` / `children:` / `children-of:` edge
# lines, the defining line of each edge TARGET, the item's TODO.md twin (single-id-two-views),
# and a short repo-state header — writes it to a file, and hands the child the PATH.
#
# WHAT THIS IS, AND IS NOT (correction id:9663, meeting 2026-08-21 `--fabled` F5):
# this LOWERS THE DEFAULT prompt/read size. It is NOT an enforcement. The child holds Read/Bash
# and the repo checkout, and per the banked deny-probe id:5937 auto mode denies essentially
# nothing outside protected paths — nothing here stops a child opening ROADMAP.md at its
# canonical path. Do not describe the slice as a guard against over-reading; it is a cheaper
# default, and the honest claim stops there.
#
# WHY A HOST SCRIPT: relay-loop.js runs inside the Workflow sandbox, which has no filesystem
# (id:2ec4) — it cannot read a ledger or write a tmp file. Same shape as classify-repo.sh /
# provision-worktree.sh: relay-loop.js dispatches it as a mechanical model:'bash' hop and
# captures the printed path.
#
# BLOCK BOUNDS (id:b015): an item's block runs from its checkbox line to the next COLUMN-0
# checkbox line or the next `#`-heading — NOT to the first unindented line, which is what the
# original did and which silently dropped every column-0 acceptance paragraph, un-indented
# sub-bullet and fenced code block. That truncation produced a well-formed, non-empty slice
# with an honest `slice-bytes`, so nothing failed: the child simply worked a spec missing its
# acceptance criteria. Fenced content never terminates the block, and the owning section
# HEADING is stamped into the repo-state header (parked/exempt context, id:356f, lives on the
# heading, not on the item line). A multi-line `<!-- ... -->` annotation block between two
# items is absorbed by the PRECEDING item (the fail-toward-including direction) — the
# single-line bare-comment run that carries typed edges is correctly claimed by the item BELOW.
#
# ANCHORING: every id lookup goes through the comment-anchored id:46f6 engine
# (lib-typed-edges.sh) — NEVER a bare `grep id:XXXX`. A bare token grep matches a prose
# mention in some OTHER item's body (the define-vs-refer defect; id:c97c cost three
# unrecoverable inbox deletions that way).
#
# Usage: ledger-slice.sh --repo <name> --path <repo-path> --id <4-hex> [--out <file>]
#        ledger-slice.sh --repo <name> --path <repo-path> --ids <4hex,4hex,...> [--out <file>]
#        ledger-slice.sh --repo <name> --path <repo-path> --since-ckpt <git-ref> [--out <file>]
#   --out omitted ⇒ a run-stable path under ~/.cache/relay/slices/ is minted and printed.
#   --id, --ids and --since-ckpt are ALL MUTUALLY EXCLUSIVE. --ids takes a COMMA-SEPARATED
#   list (id:e68f multi-item review case, id:dd59) — the same CSV shape this script already
#   reads on `gated-on:`/`children:` edges, so one token grammar covers both. Duplicates are
#   collapsed (first-occurrence order kept); an id resolving to no ROADMAP.md item is
#   REPORTED ON STDERR and the run still exits non-zero (4) — never silently dropped
#   (id:4347) — but a slice IS still written for whichever ids DID resolve, so one bad
#   id in a 20-id review batch doesn't cost the other 19 (reported-and-continue, not
#   whole-batch-fatal; the caller sees the non-zero exit and can decide whether to abort).
#   If NONE of the ids resolve, no file is written at all, matching the single-id case.
#
#   --since-ckpt <ref> (id:dd59 review-derivation case) derives the id SET itself, then
#   slices exactly as --ids would with that derived set. Two sources, unioned and de-duped:
#     (1) 4-hex `id:`/`routed:` tokens in commit messages over `<ref>..HEAD` (this repo has
#         no HTML-comment convention in commit trailers, so the anchor here is the literal
#         keyword prefix with a word boundary before it — `\bid:XXXX\b` / `\brouted:XXXX\b` —
#         which is what this repo's own commits actually emit (`git log`, e.g. "id:e977",
#         "(id:cb22)"), and which a bare 4-hex grep would NOT be: it also rejects a keyword
#         embedded in a longer word, e.g. `invalid:1234` does not yield `id:1234`).
#     (2) 4-hex `id:`/`routed:` tokens on lines ADDED to TODO.md/ROADMAP.md over the same
#         range (`git diff <ref>..HEAD --`), extracted through the SAME comment-anchored
#         `<!-- id:XXXX -->` / `<!-- routed:XXXX -->` grammar `lib-typed-edges.sh` uses
#         elsewhere in this file — a bare `id:XXXX` mention in added prose is NOT a match.
#         This is the reverse-handoff case (`/meeting` or a manual edit adding an item
#         directly to a ledger, with no matching commit-message mention).
#   A ref that does not resolve to a commit is a LOUD, non-zero (2) failure — it is NEVER
#   treated as "no ids" and NEVER silently widened to the whole history, which would produce
#   a slice spanning every id in the repo (the exact failure review-scoped slicing exists to
#   prevent). A ref that resolves but yields a genuinely empty union (no commits, or no
#   id-bearing changes, since the checkpoint) is NOT an error — it is reported on stderr and
#   exits 5 with no file written, distinct from every other non-zero exit here, so the caller
#   can tell "nothing to slice, fall open to the unsliced brief" apart from "the slicer broke"
#   (2 = misuse/bad ref) or "some/all requested ids didn't resolve" (4). The derived id COUNT
#   and the ids themselves are always printed on stderr before slicing, so an operator can see
#   what the round actually covered.
#
# STDOUT CONTRACT (id:35b7 — ADDITIVE, the path stays the LAST line):
#   slice-bytes: <N>        # the written slice's real size, measured here on the host
#   <path>                  # the slice path — unchanged, still the last non-empty line
# The byte count exists so the pre-dispatch prompt-size gate can size the unit on the SLICE
# instead of on the ledgers (relay/scripts/prompt-size-gate.mjs). It MUST be measured, never
# assumed: the gate exists because an unmeasured estimate let loderite through by 326 tokens.
# Consumers that only want the path keep taking the last line and are unaffected.
# SIDE-EFFECT-FREE apart from writing that one file.
# Exit 0 = slice written, every requested id resolved; 2 = misuse (including a bad/unreachable
# --since-ckpt ref); 4 = at least one id owns no ROADMAP.md item (LOUD, never a silent empty
# slice — id:4347) — a slice may still have been written for the ids that DID resolve (see
# --ids above); 5 = --since-ckpt resolved to a valid ref but derived ZERO ids — nothing to
# slice, not a failure (see --since-ckpt above).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-typed-edges.sh
source "$SCRIPT_DIR/lib-typed-edges.sh"

repo=""; path=""; id=""; ids_csv=""; since_ckpt=""; out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="${2:-}"; shift 2 ;;
    --path) path="${2:-}"; shift 2 ;;
    --id)   id="${2:-}";   shift 2 ;;
    --ids)  ids_csv="${2:-}"; shift 2 ;;
    --since-ckpt) since_ckpt="${2:-}"; shift 2 ;;
    --out)  out="${2:-}";  shift 2 ;;
    *) echo "ledger-slice.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[[ -n "$path" ]] || { echo "ledger-slice.sh: --path is required" >&2; exit 2; }
_selector_count=0
for _sel in "$id" "$ids_csv" "$since_ckpt"; do [[ -n "$_sel" ]] && _selector_count=$(( _selector_count + 1 )); done
if (( _selector_count > 1 )); then
  echo "ledger-slice.sh: --id, --ids and --since-ckpt are mutually exclusive" >&2; exit 2
fi
(( _selector_count == 1 )) || { echo "ledger-slice.sh: one of --id, --ids or --since-ckpt is required" >&2; exit 2; }
repo="${repo:-$(basename "$path")}"

roadmap="$path/ROADMAP.md"
todo="$path/TODO.md"
[[ -f "$roadmap" ]] || { echo "ledger-slice.sh: no ROADMAP.md at $roadmap — nothing to slice" >&2; exit 4; }

# --- anchored lookups ---------------------------------------------------------
# `children-of:` is a live edge spelling that lib-typed-edges.sh does not (yet) extract;
# same comment-anchored grammar, kept local rather than widening the shared lib under a
# sibling executor's in-flight edits to it.
edges_children_of_kind_of_line() { grep -oP '(?<=<!-- children-of:)[0-9a-f,]+(?= -->)' <<<"$1" || true; }

# owning_line_of <token> <file>... — print "<file>:<lineno>\t<line>" for the FIRST checkbox
# line in <file>... whose OWN anchored `<!-- id:token -->` marker is <token>. First file wins
# (live ledgers before archives), mirroring resolve-gates.sh's precedence.
owning_line_of() {
  local tok="$1"; shift
  local f ln n
  for f in "$@"; do
    [[ -f "$f" ]] || continue
    while IFS= read -r n; do
      ln="${n#*:}"; n="${n%%:*}"
      [[ "$ln" =~ ^[[:space:]]*-\ \[[\ xX]\]\  ]] || continue
      [[ "$(typed_edges_own_id_of_line "$ln")" == "$tok" ]] || continue
      printf '%s:%s\t%s\n' "$(basename "$f")" "$n" "$ln"
      return 0
    done < <(grep -nF -- "id:$tok" "$f" || true)
  done
  return 1
}

# --- SINCE-CKPT DERIVATION (id:dd59) -------------------------------------------
# Turns a git ref into an --ids CSV, then falls straight into the (unmodified) multi-id
# path below. Kept local rather than added to lib-typed-edges.sh — same discipline as
# edges_children_of_kind_of_line above (a shared lib under a sibling's in-flight edits).
if [[ -n "$since_ckpt" ]]; then
  [[ -d "$path/.git" ]] || git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || { echo "ledger-slice.sh: $path is not a git working tree — --since-ckpt needs one" >&2; exit 2; }

  # The ref must resolve to an actual commit. This check is the whole point: a typo'd or
  # deleted tag must fail LOUDLY here, never fall through to a log/diff command that
  # degrades to "whole history" and silently produces a slice spanning every id in the
  # repo — exactly the failure review-scoped slicing exists to prevent.
  if ! git -C "$path" rev-parse --verify -q "${since_ckpt}^{commit}" >/dev/null; then
    echo "ledger-slice.sh: --since-ckpt '$since_ckpt' does not resolve to a commit in $repo ($path) — refusing to fall back to the whole history (id:dd59)" >&2
    exit 2
  fi

  declare -a since_ids=(); declare -A since_seen=()
  _since_add() {
    local t="${1,,}"
    [[ -n "${since_seen[$t]:-}" ]] && return 0
    since_seen[$t]=1
    since_ids+=("$t")
  }

  # (1) commit messages/trailers — keyword-prefixed with a word boundary before the
  # keyword, NOT a bare 4-hex grep (that would also match commit-hash fragments and
  # ordinary hex-looking English words like "dead"/"beef"/"cafe"). This also rejects a
  # keyword embedded in a longer word (`invalid:1234` is not `id:1234`).
  while IFS= read -r _tok; do
    [[ -n "$_tok" ]] && _since_add "$_tok"
  done < <(git -C "$path" log --format='%B' "${since_ckpt}..HEAD" -- \
             | grep -oP '(?<=\bid:)[0-9a-fA-F]{4}\b|(?<=\brouted:)[0-9a-fA-F]{4}\b' || true)

  # (2) lines ADDED to TODO.md/ROADMAP.md over the same range — the reverse-handoff case
  # (a /meeting write or a manual edit with no matching commit-message mention). Anchored
  # the SAME way lib-typed-edges.sh anchors everywhere else: only the HTML-comment-wrapped
  # `<!-- id:XXXX -->` / `<!-- routed:XXXX -->` form counts; a bare mention in added prose
  # does not (the define-vs-refer trap, id:c97c).
  for _f in "$todo" "$roadmap"; do
    [[ -f "$_f" ]] || continue
    while IFS= read -r _line; do
      # git diff prefixes an added line with a single '+'; '+++' is the file header, never
      # content, and diff hunk headers ('@@') are not lines of the file either.
      [[ "$_line" == +++* || "$_line" == @@* ]] && continue
      [[ "$_line" == +* ]] || continue
      _content="${_line#+}"
      while IFS= read -r _tok; do
        [[ -n "$_tok" ]] && _since_add "$_tok"
      done < <(grep -oP '(?<=<!-- id:)[0-9a-f]{4}(?= -->)|(?<=<!-- routed:)[0-9a-f]{4}(?= -->)' <<<"$_content" || true)
    done < <(git -C "$path" diff "${since_ckpt}..HEAD" -- "$_f")
  done

  if (( ${#since_ids[@]} == 0 )); then
    echo "ledger-slice.sh: --since-ckpt $since_ckpt ($repo) derived NO ids — no commits, or no id-bearing changes, in TODO.md/ROADMAP.md/commit messages since that checkpoint. Nothing to slice; this is NOT a failure (id:dd59 exit 5) — the caller should fall back to the unsliced brief." >&2
    exit 5
  fi
  echo "ledger-slice.sh: --since-ckpt $since_ckpt ($repo) derived ${#since_ids[@]} id(s): ${since_ids[*]}" >&2
  ids_csv="$(IFS=,; echo "${since_ids[*]}")"
fi

# --- MULTI-ID PATH (id:dd59) --------------------------------------------------
# Everything below this block, down to the `exit`, is new. The single-`--id` path
# (further down) is untouched line-for-line from before this change, so its output
# stays byte-identical. --since-ckpt reaches this same path by resolving to --ids CSV above.
if [[ -n "$ids_csv" ]]; then
  # Split on commas, validate each token, lowercase, and de-dup preserving the
  # first-occurrence order — a caller passing the same id twice (or an id list built
  # by a union of two ROADMAP scans) must not double-emit that item's block.
  declare -a req_ids=()
  declare -A req_seen=()
  IFS=',' read -ra _raw_ids <<<"$ids_csv"
  for tok in "${_raw_ids[@]}"; do
    [[ -z "$tok" ]] && { echo "ledger-slice.sh: --ids contains an empty token (check for a stray comma) in '$ids_csv'" >&2; exit 2; }
    [[ "$tok" =~ ^[0-9a-fA-F]{4}$ ]] || { echo "ledger-slice.sh: --ids token '$tok' is not 4 hex digits (in '$ids_csv')" >&2; exit 2; }
    tok="${tok,,}"
    [[ -n "${req_seen[$tok]:-}" ]] && continue
    req_seen[$tok]=1
    req_ids+=("$tok")
  done
  (( ${#req_ids[@]} > 0 )) || { echo "ledger-slice.sh: --ids resolved to no ids (got '$ids_csv')" >&2; exit 2; }

  if [[ -z "$out" ]]; then
    out="${RELAY_SLICE_DIR:-$HOME/.cache/relay/slices}/${repo}-$(IFS=+; echo "${req_ids[*]}").md"
  fi
  mkdir -p "$(dirname "$out")"

  mapfile -t RM < "$roadmap"
  last=$(( ${#RM[@]} - 1 ))

  # One forward pass computes fence state + owning section heading for every line,
  # shared across every requested id (same file, read once) — see id:b015 for why
  # fenced content must never be mistaken for a heading or a checkbox.
  declare -a IN_FENCE
  _fence=0
  section=""
  declare -a SECTION_OF_LINE
  for ((i = 0; i <= last; i++)); do
    l="${RM[$i]}"
    if [[ "$l" =~ ^[[:space:]]{0,3}(\`\`\`|~~~) ]]; then
      _fence=$(( 1 - _fence ))
    fi
    IN_FENCE[$i]=$_fence
    if (( _fence == 0 )) && [[ "$l" =~ ^#{1,6}[[:space:]] ]]; then
      section="$l"
    fi
    SECTION_OF_LINE[$i]="$section"
  done

  is_next_items_edge_comment_multi() {
    local j="$1"
    while (( j <= last )) && [[ "${RM[$j]}" =~ ^[[:space:]]*\<!--.*--\>[[:space:]]*$ ]]; do
      j=$(( j + 1 ))
    done
    (( j <= last )) && [[ "${RM[$j]}" =~ ^-\ \[[\ xX]\] ]]
  }

  declare -a resolved_ids=() resolved_linenos=() unresolved_ids=() todo_only_ids=()
  declare -A lineno_seen=()
  # Union edge tokens across every requested item, de-duped in first-seen order and
  # excluding a requested id pointing at itself OR at another requested id — the
  # co-dispatched item already gets its own "## Dispatched item" section, so listing
  # it again under Typed edges would be a byte-for-byte duplicate of that section's
  # content, not new information a reviewer needs.
  declare -a edge_tokens=() uniq_tokens=()
  declare -A edge_seen=()

  for tok in "${req_ids[@]}"; do
    item_lineno=""
    while IFS= read -r n; do
      line="${n#*:}"; n="${n%%:*}"
      [[ "$line" =~ ^[[:space:]]*-\ \[[\ xX]\]\  ]] || continue
      [[ "$(typed_edges_own_id_of_line "$line")" == "$tok" ]] || continue
      item_lineno="$n"
      break
    done < <(grep -nF -- "id:$tok" "$roadmap" || true)

    if [[ -z "$item_lineno" ]]; then
      # id:dd59 — TODO-ONLY items are still WORKED items. ROADMAP.md is the relay's
      # execution queue, but plenty of ids live only in TODO.md (the design ledger) and
      # get worked there — measured live: of 6 ids derived from one real checkpoint
      # range, FOUR (e977, cb22, 3e13, dd59) owned no ROADMAP line, so anchoring the
      # slice on ROADMAP alone showed a reviewer 2 of 6 worked items with no signal
      # that the rest existed. That trades this gate's LOUD refusal for quiet
      # under-review, which is strictly worse than the oversize problem it fixes.
      # So: fall back to the TODO.md owning line and emit it in its own section. Only
      # an id owning NEITHER is genuinely unresolved and drives the exit-4 path.
      if owning_line_of "$tok" "$todo" >/dev/null; then
        todo_only_ids+=("$tok")
        continue
      fi
      echo "ledger-slice.sh: id:$tok owns no ROADMAP.md checkbox item AND no TODO.md entry in $repo — omitted from the slice, not silently dropped (id:4347)" >&2
      unresolved_ids+=("$tok")
      continue
    fi
    # Two requested ids resolving to the SAME checkbox line (shouldn't happen with
    # distinct ids, but a stale/duplicate ledger marker is not this script's problem
    # to diagnose) must not double-emit that item's block.
    if [[ -n "${lineno_seen[$item_lineno]:-}" ]]; then
      continue
    fi
    lineno_seen[$item_lineno]=1
    resolved_ids+=("$tok")
    resolved_linenos+=("$item_lineno")
  done

  if (( ${#resolved_ids[@]} == 0 )); then
    echo "ledger-slice.sh: none of the requested ids (${req_ids[*]}) own a ROADMAP.md checkbox item in $repo ($roadmap) — refusing to write an empty slice (id:4347)" >&2
    exit 4
  fi

  declare -a BLOCKS=() HEADINGS=()
  for k in "${!resolved_ids[@]}"; do
    tok="${resolved_ids[$k]}"
    item_lineno="${resolved_linenos[$k]}"
    idx=$(( item_lineno - 1 ))

    start=$idx
    while (( start > 0 )); do
      prev="${RM[$((start-1))]}"
      [[ "$prev" =~ ^[[:space:]]*\<!--.*--\>[[:space:]]*$ ]] || break
      start=$(( start - 1 ))
    done

    end=$idx
    while (( end < last )); do
      j=$(( end + 1 ))
      if (( IN_FENCE[j] == 0 )); then
        nxt="${RM[$j]}"
        [[ "$nxt" =~ ^-\ \[[\ xX]\] ]] && break
        [[ "$nxt" =~ ^#{1,6}[[:space:]] ]] && break
        is_next_items_edge_comment_multi "$j" && break
      fi
      end=$j
    done
    while (( end > idx )) && [[ -z "${RM[$end]//[[:space:]]/}" ]]; do end=$(( end - 1 )); done

    block=()
    for ((i = start; i <= end; i++)); do block+=("${RM[$i]}"); done
    BLOCKS[$k]="$(printf '%s\n' "${block[@]}")"
    HEADINGS[$k]="${SECTION_OF_LINE[$idx]}"

    for l in "${block[@]}"; do
      for csv in "$(typed_edges_gated_of_line "$l")" "$(typed_edges_children_of_line "$l")" "$(edges_children_of_kind_of_line "$l")"; do
        [[ -z "$csv" ]] && continue
        IFS=',' read -ra toks <<<"$csv"
        for t in "${toks[@]}"; do [[ -n "$t" ]] && edge_tokens+=("${t,,}"); done
      done
    done
  done

  for t in "${edge_tokens[@]:-}"; do
    [[ -z "$t" ]] && continue
    [[ -n "${req_seen[$t]:-}" ]] && continue
    [[ -n "${edge_seen[$t]:-}" ]] && continue
    edge_seen[$t]=1
    uniq_tokens+=("$t")
  done

  tmp="$(mktemp "${out}.XXXXXX")"
  trap '[ -e "$tmp" ] && rm -- "$tmp"' EXIT
  {
    echo "# Ledger slice — ${repo} ids:$(IFS=,; echo "${resolved_ids[*]}")"
    echo
    echo "## Repo state"
    echo "- repo: ${repo}"
    echo "- path: ${path}"
    echo "- dispatched items:"
    for k in "${!resolved_ids[@]}"; do
      echo "  - id:${resolved_ids[$k]} (ROADMAP.md:${resolved_linenos[$k]})"
    done
    if (( ${#unresolved_ids[@]} > 0 )); then
      echo "- UNRESOLVED (requested, no owning ROADMAP.md item — see stderr): $(IFS=,; echo "${unresolved_ids[*]}")"
    fi
    echo "- ROADMAP.md: $( [[ -f "$roadmap" ]] && wc -c < "$roadmap" || echo 0 ) B; TODO.md: $( [[ -f "$todo" ]] && wc -c < "$todo" || echo 0 ) B"
    echo "- generated by relay/scripts/ledger-slice.sh (id:e68f, multi-id form id:dd59)"
    echo
    echo "> This slice is the DEFAULT context for this review, not a boundary (id:9663): the"
    echo "> ledgers remain readable at their canonical paths. Read them only if this slice is"
    echo "> genuinely insufficient, and say so in your handback if it was."
    echo
    echo "## Dispatched items (ROADMAP.md)"
    for k in "${!resolved_ids[@]}"; do
      echo
      echo "### id:${resolved_ids[$k]}"
      echo
      if [[ -n "${HEADINGS[$k]}" ]]; then
        echo "- owning section: ${HEADINGS[$k]}"
      else
        echo "- owning section: _(none — item sits above any heading)_"
      fi
      echo
      printf '%s\n' "${BLOCKS[$k]}"
    done
    echo
    echo "## Typed edges"
    echo
    if (( ${#uniq_tokens[@]} == 0 )); then
      echo "_(none — no dispatched item carries a gated-on: / children: / children-of: edge outside this set)_"
    else
      for t in "${uniq_tokens[@]}"; do
        if row="$(owning_line_of "$t" "$roadmap" "$todo" "$path/ROADMAP.archive.md" "$path/TODO.archive.md")"; then
          echo "- id:${t} — ${row%%$'\t'*}"
          echo "  ${row#*$'\t'}"
        else
          echo "- id:${t} — DANGLING: resolves to no item line in this repo's ledgers"
        fi
      done
    fi
    echo
    echo "## TODO.md twins (design ledger, same ids)"
    for tok in "${resolved_ids[@]}"; do
      echo
      echo "### id:${tok}"
      echo
      if row="$(owning_line_of "$tok" "$todo")"; then
        echo "${row#*$'\t'}"
      else
        echo "_(none — this id has no TODO.md entry)_"
      fi
    done
    # id:dd59 — ids worked in the DESIGN ledger only. These carry no ROADMAP.md line, so
    # they appear in no section above; without this they were dropped from the slice
    # entirely and a reviewer had no signal they existed.
    if (( ${#todo_only_ids[@]} > 0 )); then
      echo
      echo "## TODO-only items (worked in the design ledger; no ROADMAP.md entry)"
      for tok in "${todo_only_ids[@]}"; do
        echo
        echo "### id:${tok}"
        echo
        if row="$(owning_line_of "$tok" "$todo")"; then
          echo "${row#*$'\t'}"
        fi
      done
    fi
  } > "$tmp"

  mv -- "$tmp" "$out"
  trap - EXIT
  printf 'slice-bytes: %s\n' "$(wc -c < "$out" | tr -d '[:space:]')"
  printf '%s\n' "$out"
  if (( ${#unresolved_ids[@]} > 0 )); then
    exit 4
  fi
  exit 0
fi

# --- SINGLE-ID PATH (unchanged — byte-identical to the pre-id:dd59 script) ----
[[ "$id" =~ ^[0-9a-fA-F]{4}$ ]] || { echo "ledger-slice.sh: --id must be 4 hex digits (got '$id')" >&2; exit 2; }
id="${id,,}"

if [[ -z "$out" ]]; then
  out="${RELAY_SLICE_DIR:-$HOME/.cache/relay/slices}/${repo}-${id}.md"
fi
mkdir -p "$(dirname "$out")"

# --- locate the dispatched item in ROADMAP.md ---------------------------------
item_lineno=""
while IFS= read -r n; do
  line="${n#*:}"; n="${n%%:*}"
  [[ "$line" =~ ^[[:space:]]*-\ \[[\ xX]\]\  ]] || continue
  [[ "$(typed_edges_own_id_of_line "$line")" == "$id" ]] || continue
  item_lineno="$n"
  break
done < <(grep -nF -- "id:$id" "$roadmap" || true)

if [[ -z "$item_lineno" ]]; then
  echo "ledger-slice.sh: id:$id owns no ROADMAP.md checkbox item in $repo ($roadmap) — refusing to write an empty slice a child would read as 'no work here' (id:4347)" >&2
  exit 4
fi

mapfile -t RM < "$roadmap"
last=$(( ${#RM[@]} - 1 ))
idx=$(( item_lineno - 1 ))

# Preceding SIBLING typed-edge comments: the id:46f6 grammar allows an edge either on the
# item's own line or on bare comment lines immediately above it. Walk back over those only.
start=$idx
while (( start > 0 )); do
  prev="${RM[$((start-1))]}"
  [[ "$prev" =~ ^[[:space:]]*\<!--.*--\>[[:space:]]*$ ]] || break
  start=$(( start - 1 ))
done

# --- fence state + owning section heading (id:b015) ---------------------------
# One forward pass computes, per line: whether it sits INSIDE a fenced code block, and which
# `#`-heading owns it. Both are needed below and both must ignore fenced content — a `# foo`
# comment or a `- [ ]` sample inside a bash fence is not a heading and not an item.
declare -a IN_FENCE
_fence=0
section=""
section_of_item=""
for ((i = 0; i <= last; i++)); do
  l="${RM[$i]}"
  if [[ "$l" =~ ^[[:space:]]{0,3}(\`\`\`|~~~) ]]; then
    _fence=$(( 1 - _fence ))
  fi
  IN_FENCE[$i]=$_fence
  if (( _fence == 0 )) && [[ "$l" =~ ^#{1,6}[[:space:]] ]]; then
    section="$l"
  fi
  (( i == idx )) && section_of_item="$section"
done

# is_next_items_edge_comment <index> — true when RM[$1] is a bare `<!-- ... -->` comment line
# that belongs to the NEXT item (i.e. a run of such comment lines terminated by a column-0
# checkbox). This is the mirror of the backward walk above, which claims exactly those lines
# for the item BELOW them.
is_next_items_edge_comment() {
  local j="$1"
  while (( j <= last )) && [[ "${RM[$j]}" =~ ^[[:space:]]*\<!--.*--\>[[:space:]]*$ ]]; do
    j=$(( j + 1 ))
  done
  (( j <= last )) && [[ "${RM[$j]}" =~ ^-\ \[[\ xX]\] ]]
}

# The item's own block (id:b015): the checkbox line plus EVERYTHING up to the next column-0
# checkbox line or the next heading. Column-0 prose, un-indented bullets and fenced code
# blocks that belong to the item are INCLUDED — bounding the block by "the first unindented
# line" silently dropped them, and the slice stayed well-formed and non-empty while the child
# worked a spec missing its acceptance criteria (WRONG WORK, not a crash). Content inside a
# fence never terminates the block, so a fenced sample checkbox/heading cannot split it.
end=$idx
while (( end < last )); do
  j=$(( end + 1 ))
  if (( IN_FENCE[j] == 0 )); then
    nxt="${RM[$j]}"
    # Next item's checkbox — column 0 only; an INDENTED `- [ ]` is this item's own sub-checkbox.
    [[ "$nxt" =~ ^-\ \[[\ xX]\] ]] && break
    [[ "$nxt" =~ ^#{1,6}[[:space:]] ]] && break
    is_next_items_edge_comment "$j" && break
  fi
  end=$j
done
# Trim trailing blank lines (the separator before the next item is not part of this block).
while (( end > idx )) && [[ -z "${RM[$end]//[[:space:]]/}" ]]; do end=$(( end - 1 )); done

block=()
for ((i = start; i <= end; i++)); do block+=("${RM[$i]}"); done

# --- collect typed edge tokens from the block --------------------------------
edge_tokens=()
for l in "${block[@]}"; do
  for csv in "$(typed_edges_gated_of_line "$l")" "$(typed_edges_children_of_line "$l")" "$(edges_children_of_kind_of_line "$l")"; do
    [[ -z "$csv" ]] && continue
    IFS=',' read -ra toks <<<"$csv"
    for t in "${toks[@]}"; do [[ -n "$t" ]] && edge_tokens+=("${t,,}"); done
  done
done
# de-dup, drop a self-edge
declare -A seen=(); uniq_tokens=()
for t in "${edge_tokens[@]:-}"; do
  [[ -z "$t" || "$t" == "$id" || -n "${seen[$t]:-}" ]] && continue
  seen[$t]=1; uniq_tokens+=("$t")
done

# --- write the slice ----------------------------------------------------------
tmp="$(mktemp "${out}.XXXXXX")"
trap '[ -e "$tmp" ] && rm -- "$tmp"' EXIT
{
  echo "# Ledger slice — ${repo} id:${id}"
  echo
  echo "## Repo state"
  echo "- repo: ${repo}"
  echo "- path: ${path}"
  echo "- dispatched item: id:${id} (ROADMAP.md:${item_lineno})"
  # id:b015 — the owning section heading. Parked/exempt-section context (id:356f) is carried
  # by the HEADING, not by the item line, so a slice without it hides why an item is where it is.
  if [[ -n "$section_of_item" ]]; then
    echo "- owning section: ${section_of_item}"
  else
    echo "- owning section: _(none — item sits above any heading)_"
  fi
  echo "- ROADMAP.md: $( [[ -f "$roadmap" ]] && wc -c < "$roadmap" || echo 0 ) B; TODO.md: $( [[ -f "$todo" ]] && wc -c < "$todo" || echo 0 ) B"
  echo "- generated by relay/scripts/ledger-slice.sh (id:e68f)"
  echo
  echo "> This slice is the DEFAULT context for this unit, not a boundary (id:9663): the"
  echo "> ledgers remain readable at their canonical paths. Read them only if this slice is"
  echo "> genuinely insufficient, and say so in your handback if it was."
  echo
  echo "## Dispatched item (ROADMAP.md)"
  echo
  printf '%s\n' "${block[@]}"
  echo
  echo "## Typed edges"
  echo
  if (( ${#uniq_tokens[@]} == 0 )); then
    echo "_(none — this item carries no gated-on: / children: / children-of: edge)_"
  else
    for t in "${uniq_tokens[@]}"; do
      if row="$(owning_line_of "$t" "$roadmap" "$todo" "$path/ROADMAP.archive.md" "$path/TODO.archive.md")"; then
        echo "- id:${t} — ${row%%$'\t'*}"
        echo "  ${row#*$'\t'}"
      else
        # LOUD but not fatal, mirroring resolve-gates.sh: a dangling target is reported,
        # never silently dropped and never a forever-block.
        echo "- id:${t} — DANGLING: resolves to no item line in this repo's ledgers"
      fi
    done
  fi
  echo
  echo "## TODO.md twin (design ledger, same id)"
  echo
  if row="$(owning_line_of "$id" "$todo")"; then
    echo "${row#*$'\t'}"
  else
    echo "_(none — this id has no TODO.md entry)_"
  fi
} > "$tmp"

mv -- "$tmp" "$out"
trap - EXIT
# id:35b7 — additive stdout contract: the measured slice size first, the path LAST (unchanged).
printf 'slice-bytes: %s\n' "$(wc -c < "$out" | tr -d '[:space:]')"
printf '%s\n' "$out"
