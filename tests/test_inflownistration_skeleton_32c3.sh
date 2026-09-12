#!/usr/bin/env bash
# roadmap:68c1 -- skeleton seam of id:32c3: inflownistration/SKILL.md, the parameter-less
# router, mode (a), and the Makefile wiring.
#
# WHAT THIS PINS, and why each half is here:
#
# (A) The ROUTER's three branches and the never-act rule. The router is the whole skill's
#     safety property: a bare invocation AUDITS and RECOMMENDS, it never runs a mode. All
#     three branches are asserted INDEPENDENTLY, because a router that documents only the
#     interesting two ((b) for a claim, (c) for a described system) and drops the default
#     leaves a bare invocation with no defined behaviour -- which in practice means the
#     model picks one, which is precisely the acting the rule forbids.
#
# (B) The absent-repo DEGRADATION. This skill is PUBLIC and the concept's home repo is
#     PRIVATE, so on most machines the repo is simply not there. The required behaviour is
#     a stated, non-fatal message plus the pointer list -- not an error, and emphatically
#     not a reconstruction from memory, which would mint exactly the unratified restatement
#     that mode (b) exists to detect. The test therefore requires BOTH the absent-path
#     branch AND an explicit non-fatal/exit-0 statement: a SKILL.md that merely mentions the
#     path satisfies neither.
#
# (C) No `/infln` alias ANYWHERE in the tree, asserted tree-wide rather than over SKILL.md
#     alone: the ratified scope bans the alias outright, and an alias would most plausibly
#     appear in the Makefile or a frontmatter block, not in the prose that bans it.
#
# (D) The Makefile wiring, exercised rather than grepped -- `install-inflownistration` into
#     an overridden DEST_DIR must produce a live symlink, and `status` must report the
#     skill. Grepping the SKILLS line would pass against a skill whose _FILES variable was
#     never defined, which installs an empty directory.
#
# HERMETIC: installs only into a `mktemp -d` DEST_DIR. Never touches ~/.claude.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$ROOT/inflownistration/SKILL.md"

fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

# --- (0) the file exists at all -------------------------------------------------------
if [[ ! -f "$SKILL" ]]; then
  echo "FAIL: no inflownistration/SKILL.md at $SKILL"
  exit 1
fi
pass "(0) inflownistration/SKILL.md exists"

body="$(cat "$SKILL")"

if [[ "$(head -1 "$SKILL")" != "---" ]] || ! grep -q '^name: inflownistration$' "$SKILL"; then
  fail "(0) SKILL.md lacks the frontmatter block naming the skill"
else
  pass "(0) SKILL.md carries frontmatter naming the skill"
fi

# --- (A) the router: three branches, independently ------------------------------------
if ! grep -qiE '^## Router \(no arguments\)' "$SKILL"; then
  fail "(A) SKILL.md has no router section for the parameter-less invocation"
else
  pass "(A) SKILL.md has a router section"
fi

# Each branch must name BOTH its trigger and the mode it offers, on one line -- a document
# that lists the three modes elsewhere does not thereby define the routing.
if ! grep -qiE 'claim.*\*\*\(b\)|\(b\).*claim' "$SKILL"; then
  fail "(A) the router does not offer (b) for a CLAIM that restates a ratified decision"
else
  pass "(A) router branch: a claim routes to (b)"
fi

if ! grep -qiE 'system.*\*\*\(c\)|\(c\).*system' "$SKILL"; then
  fail "(A) the router does not offer (c) for a described SYSTEM"
else
  pass "(A) router branch: a described system routes to (c)"
fi

if ! grep -qiE '\*\*\(a\) surface\*\*|\(a\).*(otherwise|neither|nothing to go on)' "$SKILL"; then
  fail "(A) the router has no DEFAULT branch -- a bare invocation with no match is undefined"
else
  pass "(A) router branch: anything else routes to (a)"
fi

# The never-act rule, stated as a rule and not merely implied by the word 'recommend'.
if ! grep -qiE 'never act|never acts' "$SKILL"; then
  fail "(A) SKILL.md never states the never-act rule"
elif ! grep -qiE 'recommend' "$SKILL"; then
  fail "(A) SKILL.md states never-act but never says what it does instead (audit, then RECOMMEND)"
else
  pass "(A) the audit-then-RECOMMEND, never-act rule is stated"
fi

if ! grep -qiE 'never chains|does not run \(b\)|Offering \(b\) does not run \(b\)' "$SKILL"; then
  fail "(A) the router does not say that offering a mode is not running it"
else
  pass "(A) the router explicitly does not chain into the mode it offers"
fi

# --- (B) mode (a): the four docs and the absent-repo degradation -----------------------
missing_docs=()
for doc in provenance.md grammar.md instances.md prior-art.md; do
  grep -qF "docs/$doc" "$SKILL" || missing_docs+=("$doc")
done
if (( ${#missing_docs[@]} > 0 )); then
  fail "(B) mode (a) does not point at all four docs; missing: ${missing_docs[*]}"
else
  pass "(B) mode (a) points at all four topical docs"
fi

if ! grep -qF '~/src/inflownistration' "$SKILL"; then
  fail "(B) SKILL.md never names the home repo path whose absence it must survive"
else
  pass "(B) SKILL.md names the home repo path"
fi

if ! grep -qiE 'does not exist|not present|absent' "$SKILL"; then
  fail "(B) SKILL.md defines no absent-repo branch"
elif ! grep -qiE 'non-fatal|exit 0|Never fail|degraded success' "$SKILL"; then
  fail "(B) the absent-repo branch is not declared NON-FATAL -- a missing private repo must not be an error"
else
  pass "(B) the absent-repo branch is defined and declared non-fatal"
fi

# The degradation must forbid reconstructing the missing content, which is the failure mode
# an LLM reaches for first when a pointer target is unreadable.
if ! grep -qiE 'never reconstruct|not reconstruct|reconstruction is an unratified' "$SKILL"; then
  fail "(B) the absent-repo branch does not forbid reconstructing the missing docs from memory"
else
  pass "(B) the absent-repo branch forbids reconstruction from memory"
fi

# --- (C) no /infln alias, tree-wide ---------------------------------------------------
# Scoped to NON-markdown files plus this file's own exclusion: every markdown hit in this
# repo is PROSE saying the alias is banned (the ledger item, the detail note, the skill's
# own rule), and an alias that actually existed would have to live in a Makefile target, a
# script, or a frontmatter block. Note the excludes must precede `--`, or grep reads them as
# file operands and the check silently searches the whole tree -- which is how the first
# version of this assertion reported every prose mention as a violation.
alias_hits="$(grep -rn --exclude-dir=.git --exclude='*.md' \
  --exclude='test_inflownistration_*.sh' -e '/infln' "$ROOT" 2>/dev/null || true)"
if [[ -n "$alias_hits" ]]; then
  fail "(C) an /infln alias appears in the tree: $alias_hits"
else
  pass "(C) no /infln alias anywhere in the tree"
fi
if ! grep -qF 'no `/infln` alias' "$SKILL"; then
  fail "(C) SKILL.md does not record that the alias is deliberately absent"
else
  pass "(C) SKILL.md records the deliberate absence of the alias"
fi

# --- (D) Makefile wiring, exercised ---------------------------------------------------
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
DEST="$tmp/skills"

if ! make -C "$ROOT" -s DEST_DIR="$DEST" install-inflownistration >"$tmp/install.log" 2>&1; then
  fail "(D) make install-inflownistration failed or the target is missing: $(cat "$tmp/install.log")"
else
  pass "(D) make install-inflownistration succeeds into an overridden DEST_DIR"
fi

if [[ ! -L "$DEST/inflownistration/SKILL.md" ]]; then
  fail "(D) install produced no symlink at inflownistration/SKILL.md"
elif [[ ! -e "$DEST/inflownistration/SKILL.md" ]]; then
  fail "(D) install produced a DANGLING symlink at inflownistration/SKILL.md"
else
  pass "(D) install produced a live symlink for SKILL.md"
fi

status_out="$(make -C "$ROOT" -s DEST_DIR="$DEST" status 2>&1 || true)"
if ! grep -qE '^inflownistration:' <<<"$status_out"; then
  fail "(D) make status does not report the inflownistration skill (not a SKILLS member?)"
elif ! grep -qE '^  ok  SKILL\.md' <<<"$(make -C "$ROOT" -s DEST_DIR="$DEST" status-inflownistration 2>&1 || true)"; then
  fail "(D) status-inflownistration does not report SKILL.md as installed"
else
  pass "(D) make status reports the skill and its installed file"
fi

if ! make -C "$ROOT" -s DEST_DIR="$DEST" uninstall-inflownistration >/dev/null 2>&1; then
  fail "(D) uninstall-inflownistration failed or the target is missing"
elif [[ -e "$DEST/inflownistration/SKILL.md" ]]; then
  fail "(D) uninstall-inflownistration left SKILL.md behind"
else
  pass "(D) uninstall-inflownistration removes the symlink"
fi

# --- (E) fleet style: no em/en dashes in the new skill source -------------------------
if grep -qP '[\x{2013}\x{2014}]' "$SKILL"; then
  fail "(E) SKILL.md contains an em or en dash (CLAUDE.md: ASCII dashes only)"
else
  pass "(E) SKILL.md carries no em or en dash"
fi

echo
if [[ $fails -eq 0 ]]; then
  echo "ALL PASS: inflownistration skeleton + router (id:68c1, seam of id:32c3)"
  exit 0
fi
echo "$fails assertion(s) failed"
exit 1
