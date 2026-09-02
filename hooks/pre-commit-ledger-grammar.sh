#!/usr/bin/env bash
# pre-commit-ledger-grammar.sh (id:d667) -- a git `pre-commit` hook that BLOCKS a commit whose
# `git diff --cached` ADDED lines introduce a NON-CONFORMING line into `TODO.md`, `ROADMAP.md`
# or `REVIEW_ME.md` under the b048 ledger LINE GRAMMAR. Unchanged lines are NEVER inspected,
# so the existing non-conforming corpus is grandfathered STRUCTURALLY -- there is no exemption
# list, nothing to expire, and an item can only regrow by adding a line, which is exactly what
# this catches. That is what makes it a ratchet rather than a grandfathering allow-list (the
# CLAUDE.md "a grandfathering mechanism is not a ratchet" heuristic: this is keyed on the EDIT,
# not on an identifier).
#
# SHIPS DISABLED. Arming it is an explicit, separate act -- `make install-ledger-grammar-ratchet`.
# `ROADMAP.md` is mid-migration under `id:40c0` and ~96% non-conforming today; a hook armed
# against that teaches people to reach for `--no-verify`, which is how a guard dies. Arm it
# once `40c0` has landed.
#
# `git commit --no-verify` is the documented escape hatch (same as the lane-vocab ratchet).
#
# WHAT BLOCKS AND WHAT ONLY WARNS
#   BLOCK  the STRUCTURAL classes: grammar-continuation, grammar-line, grammar-item-no-id,
#          grammar-item-after-id, grammar-item-edge-after-id, grammar-item-unknown-marker,
#          and every grammar-heading-* class.
#   WARN   grammar-item-title-long ONLY. 257 existing titles are over budget (id:64f9), so
#          enforcing titles would block routine edits to any of them and the hook would be
#          disabled within a day. Reported on stderr, never fatal.
#   A class this hook does not recognise BLOCKS, and says it is unrecognised. Fail-closed on an
#   unknown class is deliberate: a new grammar class added upstream must not slip through
#   silently (the id:4347 no-silent-swallow rule).
#
# THE GRAMMAR PREDICATE IS NOT REIMPLEMENTED HERE. It belongs to
# `relay/scripts/todo-conformance.sh` (the `grammar-*` rule family, id:b048) and this hook
# ASKS it, via that script's `--grammar-lines <path>` query mode. Two copies of a grammar
# drift, and the drift is silent -- the copy keeps passing exactly the shapes the real rule
# started rejecting. Consequences of delegating, all of them wanted:
#   * the declarative-vs-referential problem (id:0d58 / the id:4da4 leftmost-tag-after-
#     backtick-masking idiom the lane-vocab hook needs) does not arise here at all, because
#     this hook greps for NOTHING. It never inspects tags, lanes, or markers itself -- it
#     hands over whole staged file content and reads back line numbers. A fresh grep is
#     precisely what is avoided;
#   * `<!-- lint-ok: … -->` / `<!-- ref:XXXX -->` exemptions work automatically, because
#     todo-conformance's `exempt()` runs inside the scan;
#   * the edge-marker vocabulary, the id token class and the heading limits stay in ONE place
#     and this hook follows them with no change.
#
# WHY THE WHOLE STAGED BLOB IS SCANNED AND THEN FILTERED, rather than feeding the hook's added
# lines to the predicate directly: three of the heading classes (heading-no-blank,
# heading-empty-sec, heading-eof) are decided by LOOKAHEAD. A line handed over in isolation
# cannot be classified. So the STAGED version of the file (`git show :<path>`, i.e. what the
# commit will actually contain -- never the worktree, which may hold unstaged edits) is scanned
# whole, and the findings are intersected with the new-file line numbers the diff ADDED.
#
# OUT OF SCOPE, matching todo-conformance.sh (id:2065): `*.archive.md` and the shared inbox.
# This is also why the ARCHIVE-MOVE hazard of `id:7909` -- the lane-vocab ratchet cannot tell a
# MOVE from an ADDITION, so it blocks every archive commit in a repo with legacy tags -- does
# not bite here: `todo-update/archive-done.sh` and `relay/scripts/roadmap-archive.sh` move item
# blocks OUT of the live ledger (pure deletions, no added lines) and INTO `*.archive.md`, which
# this hook never scans. Verified against real archive commits, not assumed
# (tests/test_pre_commit_ledger_grammar.sh case (f)).
#
# Self-gated to relay-onboarded repos via `relay/scripts/lib-own-repos.sh` (honors the
# `# path:` comment override) -- mirrors `hooks/pre-commit-lane-vocab.sh` so a global
# `core.hooksPath` install stays convenient without firing inside every throwaway/hermetic-test
# repo. FAIL-OPEN TO SCAN, same as there: relay.toml absent/unparseable, unknown repo root, or
# a missing helper never skips the scan -- only a PRESENT, PARSEABLE relay.toml that does NOT
# list this repo skips.
#
# Env:
#   LEDGER_GRAMMAR_RELAY_TOML   override for $RELAY_TOML (default ~/.config/relay/relay.toml)
#   LEDGER_GRAMMAR_ALL_REPOS=1  scan every repo, ignoring the own-repo set
#   LEDGER_GRAMMAR_CONFORMANCE  override the todo-conformance.sh path (tests)
#
# Git calls a pre-commit hook with no args, cwd = repo root (or below it).
set -uo pipefail   # not -e: an internal hiccup must never silently pass OR silently block --
                   # every exit path below is explicit.

SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"
# This repo's own root (holds relay/, hooks/, …) -- kept distinct from the $SRC_DIR name
# lib-own-repos.sh expects (that one means "~/src, the repos root").
HOOK_REPO_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"

notice() { printf 'ledger-grammar: %s\n' "$*" >&2; }

# The three LIVE ledgers, repo-root-relative. Exact paths, not basenames: a `docs/TODO.md`
# is not one of these ledgers, and matching by basename would drag it in.
LEDGERS=(TODO.md ROADMAP.md REVIEW_ME.md)

# ── Relay-scoping: only run inside repos in the relay OWN-repo set ─────────────────────
if [[ "${LEDGER_GRAMMAR_ALL_REPOS:-}" != "1" ]]; then
  repo_top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  RELAY_TOML="${LEDGER_GRAMMAR_RELAY_TOML:-${RELAY_TOML:-${XDG_CONFIG_HOME:-$HOME/.config}/relay/relay.toml}}"
  own_lib="$HOOK_REPO_DIR/relay/scripts/lib-own-repos.sh"
  if [[ -n "$repo_top" && -f "$RELAY_TOML" && -r "$own_lib" ]]; then
    SRC_DIR="${SRC_DIR:-$HOME/src}"   # lib-own-repos.sh's own $SRC_DIR contract (repos root)
    own_out=""; own_rc=0
    own_out="$(RELAY_TOML="$RELAY_TOML" SRC_DIR="$SRC_DIR"; source "$own_lib" && own_repos 2>/dev/null)" || own_rc=$?
    if [[ "$own_rc" -eq 0 ]]; then   # parsed cleanly → membership is authoritative
      member=0
      while IFS=$'\t' read -r _name p; do
        [[ -n "$p" ]] || continue
        rp="$(readlink -f "$p" 2>/dev/null || echo "$p")"
        [[ "$rp" == "$repo_top" ]] && { member=1; break; }
      done <<< "$own_out"
      if [[ "$member" -eq 0 ]]; then
        notice "repo '$repo_top' is not in the relay own-repo set -- no-op (LEDGER_GRAMMAR_ALL_REPOS=1 to scan all)."
        exit 0
      fi
    fi
    # own_rc != 0 (relay.toml parse error) → fall through to SCAN (fail-open)
  fi
  # relay.toml absent / repo root unknown / helper unreadable → fall through to SCAN
fi

# ── The grammar predicate's owner. No fallback, no local copy. ──────────────────────────
CONFORMANCE="${LEDGER_GRAMMAR_CONFORMANCE:-$HOOK_REPO_DIR/relay/scripts/todo-conformance.sh}"
# LOUD, not fail-open: if the predicate cannot be reached, an armed ratchet that quietly
# passes everything is worse than one that stops and says so (id:71d6, the lane-vocab hook's
# same call). `--no-verify` remains the escape hatch.
if [[ ! -r "$CONFORMANCE" ]]; then
  notice "FATAL -- cannot read the ledger grammar predicate at $CONFORMANCE; refusing to guess a grammar."
  notice "use 'git commit --no-verify' to bypass, or fix the install (make install-ledger-grammar-ratchet)."
  exit 1
fi

# ── Which ledgers are staged? ───────────────────────────────────────────────────────────
staged="$(git diff --cached --name-only --diff-filter=ACM -- "${LEDGERS[@]}" 2>/dev/null || true)"
[[ -n "$staged" ]] || exit 0

blocking=""
warnings=""

while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  # Defensive: the archive carve-out (id:2065) can never be reached via $LEDGERS, but state
  # it rather than rely on the pathspec, so a later widening of $LEDGERS cannot smuggle an
  # archive file in. Announced, never silent.
  if [[ "$f" == *.archive.md ]]; then
    echo "ledger-grammar: skipping staged archive file (id:2065 carve-out): $f"
    continue
  fi

  # 1. The STAGED content -- what the commit will contain. Never the worktree.
  blob="$(mktemp)" || { notice "FATAL -- mktemp failed."; exit 1; }
  if ! git show ":$f" > "$blob" 2>/dev/null; then
    [ -e "$blob" ] && rm -- "$blob"
    notice "could not read the staged blob for '$f' -- skipping it (nothing to check)."
    continue
  fi

  # 2. Ask the predicate which of its lines are non-conforming.
  #    A nonzero exit is a LOUD stop, for the same reason as the unreadable-script branch.
  find_out=""; find_rc=0
  find_out="$(bash "$CONFORMANCE" --grammar-lines "$blob" 2>/dev/null)" || find_rc=$?
  [ -e "$blob" ] && rm -- "$blob"
  if [[ "$find_rc" -ne 0 ]]; then
    notice "FATAL -- the grammar predicate ($CONFORMANCE --grammar-lines) failed on '$f' (rc=$find_rc)."
    notice "use 'git commit --no-verify' to bypass."
    exit 1
  fi
  [[ -n "$find_out" ]] || continue

  # 3. Which NEW-file line numbers did this commit ADD? Parse the -U0 hunk headers:
  #    `@@ -a,b +c,d @@` -- the new-file counter starts at c; a `+` line consumes one and
  #    advances it, a `-` line does not. With -U0 there are no context lines.
  added_lines=""
  newno=0
  while IFS= read -r dl; do
    case "$dl" in
      '@@'*)
        # `@@ -12,0 +13,2 @@ …` → 13
        hdr="${dl#*+}"; hdr="${hdr%%[ ,]*}"
        [[ "$hdr" =~ ^[0-9]+$ ]] && newno="$hdr"
        ;;
      '+++'*) ;;
      '---'*) ;;
      '+'*)
        added_lines+="$newno"$'\n'
        newno=$((newno+1))
        ;;
      '-'*) ;;
      '\'*) ;;   # "\ No newline at end of file"
      *) ;;
    esac
  done < <(git diff --cached -U0 --no-color -- "$f" 2>/dev/null || true)
  [[ -n "$added_lines" ]] || continue

  # 4. Intersect: a finding counts only if the diff ADDED that exact line.
  while IFS=$'\t' read -r ln cls; do
    [[ -n "${ln:-}" && -n "${cls:-}" ]] || continue
    grep -qxF "$ln" <<< "$added_lines" || continue
    text="$(sed -n "${ln}p" <<< "$(git show ":$f" 2>/dev/null)")"
    case "$cls" in
      grammar-item-title-long*)
        # WARN ONLY, deliberately (id:64f9) -- see the header.
        warnings+="  $f:$ln  $cls"$'\n'"      | $text"$'\n'
        ;;
      grammar-continuation*|grammar-line*|grammar-item-no-id*|grammar-item-after-id*|\
      grammar-item-edge-after-id*|grammar-item-unknown-marker*|grammar-heading-*)
        blocking+="  $f:$ln  $cls"$'\n'"      | $text"$'\n'
        ;;
      *)
        blocking+="  $f:$ln  $cls  [class not recognised by this hook -- blocking rather than swallowing it]"$'\n'"      | $text"$'\n'
        ;;
    esac
  done <<< "$find_out"
done <<< "$staged"

if [[ -n "$warnings" ]]; then
  {
    echo "ledger-grammar: WARN -- a staged (added) line has an over-long title. Not blocking (id:64f9)."
    printf '%s' "$warnings"
  } >&2
fi

if [[ -n "$blocking" ]]; then
  {
    echo "ledger-grammar: BLOCKED -- a staged (added) line is non-conforming under the b048 ledger line grammar."
    echo "ledger-grammar: a ledger line must be BLANK, a HEADING followed by a blank line, or an ITEM"
    echo "ledger-grammar: '- [ ] [lane] title <typed edges> <!-- id:XXXX -->' with NOTHING after the id marker."
    echo "ledger-grammar: there are no continuation lines -- that prose belongs in docs/ledger-notes/<id>.md."
    echo "ledger-grammar: fix the line, or use --no-verify to skip this check."
    printf '%s' "$blocking"
  } >&2
  exit 1
fi

exit 0
