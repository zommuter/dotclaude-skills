#!/usr/bin/env python3
"""roundtrip-validate.py -- the DIRECTIONAL ROUND-TRIP VALIDATOR for a ledger trimming
pass (id:ff7c, ratified as part of the id:0d7c line-shrink format and never built).

Takes a ledger tree plus its notes corpus BEFORE and AFTER a pass and proves, mechanically,
that the pass only moved things in the improving direction. Every trimming pass so far was
checked by running four tools by hand and comparing output by eye; that is how wave 1
shipped with 40 items whose decided-markers had gone dark while the acceptance gate said
SAFE TO LAND (id:5f34).

    tools/roundtrip-validate.py --before <dir> --after <dir>

Exit 0 = clean directional verdict. Exit 1 = at least one assertion failed (LOUD, and the
finding names the item). Exit 2 = the harness itself could not run (a detector missing, a
root unreadable): a harness that cannot run must never be mistaken for a pass.

================================================================================
THE FIVE ASSERTIONS
================================================================================
(a) NO id LOST.        Every `<!-- id:XXXX -->` addressable BEFORE is addressable AFTER,
                       whether it now lives on the ledger line or inside the item's note.
                       This is the UNION test -- total disappearance. The stricter
                       "the address must still be on the LINE" is assertion (b), which is
                       where a note-only survivor is caught and named.
(b) STILL WRITABLE.    Every id still in a ledger resolves under
                       `meeting/md-merge.py update-ids`. An item tooling can no longer
                       address is functionally lost even when its text survives. md-merge
                       REFUSES a line carrying two anchored id markers (id:6059), so a
                       pass that creates one breaks writability -- and that refusal is
                       observed by RUNNING md-merge, not by re-deriving its rule.
(c) LANE AND GATE UNCHANGED.  The lane and the typed gate/decision edges a DETECTOR
                       computes per item are identical before and after. See the
                       independence section below -- this is the assertion the whole item
                       exists for.
(d) GRAMMAR MOVES ONLY TOWARD CONFORMANCE. The `grammar-*` finding set from
                       `relay/scripts/todo-conformance.sh` may shrink or stay, never grow.
(e) NO NEW FINDINGS from `meeting/orphan-scan.sh --cross-ledger` or
                       `relay/scripts/roadmap-lint.sh`.

Any single failure is loud and non-zero. `--fail-fast` stops at the first failing
assertion (the detector-backed assertions (d) and (e) are the slow ones, ~30s per root on
the live ledgers, so a cheap failure need not pay for them).

================================================================================
THE TRAP THIS FILE EXISTS TO AVOID -- and exactly how far independence reaches
================================================================================
A checker that derives its notion of correctness from the thing it checks CANNOT FAIL
(loderite id:dd44; id:0b70 for the vacuous sibling). An earlier verification of a shrink
reported "0 lane changes" using `ledger-shrink.py`'s OWN regexes, so it was never a check
at all.

So: NOTHING in this file is imported from, or copied out of, `tools/ledger-shrink.py`. It
does not import it, does not read its source, and shares no pattern with it. The one thing
it does reuse is `tools/shrink-acceptance.py`, which is a pure before/after comparator that
likewise never touches the shrinker -- reuse over duplication, per the house rule.

For (c), lanes and gates are read through the DETECTORS THAT CONSUME THEM:

  * GATE and decision edges: `relay/scripts/lib-typed-edges.sh` is SOURCED and its
    extractor functions are CALLED per line -- `typed_edges_own_id_of_line`,
    `typed_edges_gated_of_line`, `typed_edges_children_of_line`,
    `typed_edges_settles_of_line`, `typed_edges_decided_in_of_line`,
    `typed_edges_owner_hold_of_line`, `typed_edges_answer_src_of_line`. That file is the
    id:46f6 engine `classify-repo.sh` and `orphan-scan.sh` both resolve edges through, so
    this is the consumer's own answer, not a second opinion about it. Its id:6059 refusal
    of a multi-marker line is likewise observed rather than re-derived: when a line
    demonstrably carries `<!-- id:` and the authority still returns nothing, that IS the
    refusal.

  * LANE VOCABULARY: `relay/scripts/lib-lane-anchor.sh` is SOURCED and
    `lane_vocab_scrape` is CALLED against `relay/references/hard-lanes.md`, the id:78ff
    single source of truth (which declares FOUR `[INPUT - *]` lanes -- meeting, decision,
    access, author -- and every lane in both delimiter spellings). No lane token is typed
    into this file.

  * LANE ANCHORING RULE -- THE ONE REIMPLEMENTATION, STATED LOUDLY. `classify-repo.sh`
    derives an item's PRIMARY lane as the FIRST recognised lane token on the raw line
    (id:4da4, `classify-repo.sh:286`: `_found = [(ln.find(t), t) ...]; primary =
    min(_found)[1]`). That logic lives inside a python heredoc inside that script and is
    not callable from outside, so the probe below restates the SELECTION RULE -- eight
    lines of "lowest index wins, ties by token" -- while taking the VOCABULARY from the
    SSOT rather than from a copy. Why that is still an independent check: the thing under
    test is `ledger-shrink.py` (or any other trimming pass), and neither the rule nor the
    vocabulary comes from it or from any file it can influence. The residual risk is
    drift against `classify-repo.sh` itself, and it is covered two ways: the probe emits
    its scraped vocabulary and this file cross-checks it against the `LANE_TAGS` /
    `HUMAN_GATES` literals grepped out of `classify-repo.sh` (a WARN naming both sides on
    divergence), and assertion (c) additionally RUNS `classify-repo.sh --emit unit` over
    both roots and requires its own lane-derived counters and id lists to be equal. The
    per-item map says WHICH item moved; the detector run says whether the consumer's own
    view moved at all. Neither instrument alone would be enough.

  * DELIBERATELY NOT MASKING BACKTICKS. `lib-lane-anchor.sh` offers `mask_backticks`, and
    this probe does not use it -- because `classify-repo.sh` does not either. A backticked
    lane bracket in prose IS that item's computed lane today; three live items depend on
    that and it is an open owner decision (id:1254). Masking here would make the validator
    disagree with the consumer, which is the opposite of the job.

  * SUPERSET SCOPE. `classify-repo.sh`'s lane loop reads OPEN ROADMAP items only. The
    probe computes a lane for EVERY id-bearing line in EVERY ledger, closed items and
    indented id-bearing continuation lines included. A superset can only make (c) stricter,
    and the indented-id line is precisely the shape loderite's sweep silently orphaned.

================================================================================
KEYING -- why findings are keyed on (rule, item), never on a line number or a count
================================================================================
A relocation moves every line number and legitimately reduces how many TIMES a marker
occurs. So (d) and (e) compare SETS of (normalised signal, owning item id), reusing
`shrink-acceptance.normalise_signal` to strip the measurement out of a rule token -- a rule
spelled `length-grandfathered (1367 chars > budget 500)` otherwise reports LOST-and-GAINED
on every run in which the line shrank at all. `todo-conformance.sh` reports a line number,
so the probe attributes each finding to the top-level item that OWNS that line (the nearest
preceding top-level checkbox), which is what survives a relocation. A finding whose owning
item has no id falls back to a short text digest, stated here rather than hidden.

================================================================================
WHAT THIS DOES NOT JUDGE
================================================================================
Line LENGTH. A correct pass legitimately leaves long lines behind: `ledger-shrink.py`
refuses a block carrying another item's id, refuses when there is no defensible cut point,
and skips closed items. Budget enforcement belongs to the id:0d7c D4 ratchet inside
`todo-conformance.sh`. Consistent with that, the `length-*` family is excluded from (d),
which is scoped to `grammar-*` exactly as the acceptance clause words it.

It also does not judge whether the pass achieved anything. A no-op passes cleanly. This is
a REFUSAL instrument, not a progress meter.

================================================================================
DIRECTIONAL, INCLUDING FOR (b) AND (c) -- an inherited defect is not this pass's fault
================================================================================
"DIRECTIONAL" is the whole name of the thing, and it binds every assertion, not only the
two that obviously count findings. The live ledgers already carry 32 lines with two
anchored id markers, which `md-merge` and `lib-typed-edges` both refuse (id:6059). A gate
that reported those as failures would go red on the first honest pass and be baselined away
within a day -- the id:0b70 vacuous-check failure arriving from the other side.

So (b) runs md-merge over BOTH roots and only a NEWLY refused id is fatal; a pre-existing
refusal is reported, by id, as inherited. (c) likewise: a line that was already
unattributable stays unattributable without being fatal, while an item that HAD a
computable lane and gate before and has none after is fatal. The report always prints the
inherited count, so the debt is visible rather than waived silently.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_SCRIPTS_ROOT = os.path.dirname(HERE)

EXIT_CLEAN = 0
EXIT_REFUSED = 1
EXIT_HARNESS = 2


# --------------------------------------------------------------------------- #
# Reuse: shrink-acceptance.py is the prior art and is imported, not copied     #
# --------------------------------------------------------------------------- #

def load_shrink_acceptance(path):
    """Import `shrink-acceptance.py` as a module (its name is not an identifier)."""
    spec = importlib.util.spec_from_file_location("shrink_acceptance", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load shrink-acceptance.py from %s" % path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# --------------------------------------------------------------------------- #
# The lane/gate probe -- SOURCES the authorities, calls their functions        #
# --------------------------------------------------------------------------- #
#
# Emitted TSV, one row per id-bearing line:
#   L <TAB> ledger <TAB> lineno <TAB> own-id <TAB> ambiguous(0|1) <TAB> lane
#     <TAB> gated-on <TAB> children <TAB> settles <TAB> decided-in
#     <TAB> owner-hold <TAB> answer-src
# plus one row `V <TAB> <space-joined scraped lane vocabulary>`.
#
# Every marker field is produced by CALLING the lib-typed-edges.sh extractor of that name.
# The rarely-present kinds are guarded by a cheap literal test first, purely so the probe
# does not fork seven greps per line on a 674-item ledger.
PROBE = r'''
set -uo pipefail
scripts_root="$1"; root="$2"; lanes_doc="$3"; shift 3

# shellcheck source=/dev/null
source "$scripts_root/relay/scripts/lib-lane-anchor.sh"
# shellcheck source=/dev/null
source "$scripts_root/relay/scripts/lib-typed-edges.sh"

lane_vocab_scrape "$lanes_doc" || exit 3
# One row per tag: a lane NAME may contain a space ("decision gate"), so a space-joined
# vocabulary row would shred exactly the lanes it matters most to get right.
for _t in "${all_lane_tags[@]}"; do printf 'V\t%s\n' "$_t"; done

# The id:4da4 PRIMARY-LANE selection rule, restated from classify-repo.sh:286 because that
# logic sits inside a python heredoc and cannot be called. Lowest index wins; ties break on
# the token, matching python's min() over (index, token) tuples. The VOCABULARY is scraped
# from the SSOT above -- only the selection rule is restated here.
primary_lane() {
  local line="$1" tag pre pos best=-1 out=""
  for tag in "${all_lane_tags[@]}"; do
    pre="${line%%"$tag"*}"
    [[ "$pre" == "$line" ]] && continue
    pos=${#pre}
    if (( best < 0 )) || (( pos < best )) || { (( pos == best )) && [[ "$tag" < "$out" ]]; }; then
      best=$pos; out="$tag"
    fi
  done
  printf '%s' "$out"
}

for ledger in "$@"; do
  f="$root/$ledger"
  [[ -f "$f" ]] || continue
  lineno=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    case "$line" in *'<!--'*) ;; *) continue ;; esac
    has_id=0
    case "$line" in *'<!-- id:'*) has_id=1 ;; esac
    own=""
    if (( has_id )); then
      # The authority's own answer. It returns EMPTY and warns on a line carrying several
      # anchored id markers (id:6059) -- so "the line has an id marker but the engine
      # resolved none" IS the refusal, observed rather than re-derived.
      own="$(typed_edges_own_id_of_line "$line" 2>/dev/null)"
    fi
    ambig=0
    if (( has_id )) && [[ -z "$own" ]]; then ambig=1; fi
    gated=""; children=""; settles=""; decided=""; hold=""; answer=""
    case "$line" in *'<!-- gated-on:'*) gated="$(typed_edges_gated_of_line "$line")" ;; esac
    case "$line" in *'<!-- children:'*) children="$(typed_edges_children_of_line "$line")" ;; esac
    case "$line" in *'<!-- settles:'*) settles="$(typed_edges_settles_of_line "$line")" ;; esac
    case "$line" in *'<!-- decided-in:'*) decided="$(typed_edges_decided_in_of_line "$line")" ;; esac
    case "$line" in *'<!-- owner-hold:'*) hold="$(typed_edges_owner_hold_of_line "$line")" ;; esac
    case "$line" in *'<!-- answer-src:'*) answer="$(typed_edges_answer_src_of_line "$line")" ;; esac
    if (( has_id == 0 )) && [[ -z "$gated$children$settles$decided$hold$answer" ]]; then
      continue
    fi
    printf 'L\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$ledger" "$lineno" "$own" "$ambig" "$(primary_lane "$line")" \
      "$gated" "$children" "$settles" "$decided" "$hold" "$answer"
  done < "$f"
done
'''

MARKER_FIELDS = ("gated-on", "children", "settles", "decided-in", "owner-hold", "answer-src")


class HarnessError(RuntimeError):
    """The validator could not run. Never reported as a pass."""


def run_probe(scripts_root, root, ledgers, timeout):
    lanes_doc = os.path.join(scripts_root, "relay", "references", "hard-lanes.md")
    argv = ["bash", "-s", "--", scripts_root, root, lanes_doc] + list(ledgers)
    try:
        proc = subprocess.run(
            argv, input=PROBE, capture_output=True, text=True, timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise HarnessError("lane/gate probe failed on %s: %s" % (root, exc))
    if proc.returncode != 0:
        raise HarnessError(
            "lane/gate probe exited %d on %s: %s"
            % (proc.returncode, root, (proc.stderr or "").strip()[:400])
        )
    vocab = []
    lines = {}
    ambiguous = []
    for row in proc.stdout.splitlines():
        parts = row.split("\t")
        if parts[0] == "V":
            vocab.append(parts[1])
            continue
        if parts[0] != "L" or len(parts) < 12:
            continue
        ledger, lineno, own, ambig, lane = parts[1], int(parts[2]), parts[3], parts[4], parts[5]
        rec = {
            "ledger": ledger,
            "lineno": lineno,
            "lane": lane,
            "gated-on": frozenset(t for t in parts[6].split(",") if t),
            "children": frozenset(t for t in parts[7].split(",") if t),
            "settles": frozenset(t for t in parts[8].split(",") if t),
            "decided-in": frozenset(t for t in parts[9].split(",") if t),
            "owner-hold": frozenset(t for t in parts[10].split(",") if t),
            "answer-src": frozenset(t for t in parts[11].split(",") if t),
        }
        if ambig == "1":
            ambiguous.append(rec)
            continue
        if own:
            lines.setdefault((ledger, own.lower()), rec)
    if not vocab:
        raise HarnessError("lane/gate probe scraped an EMPTY lane vocabulary from %s" % lanes_doc)
    return {"vocab": vocab, "items": lines, "ambiguous": ambiguous}


# --------------------------------------------------------------------------- #
# Vocabulary drift cross-check against classify-repo.sh's own literals         #
# --------------------------------------------------------------------------- #

def classify_lane_literals(scripts_root):
    """The lane tokens literally embedded in classify-repo.sh, or None if unreadable.

    ADVISORY ONLY. Its purpose is to notice the day the SSOT scrape and the consumer's
    embedded list disagree -- which would silently weaken assertion (c) without failing
    anything. Never used to COMPUTE a lane.
    """
    path = os.path.join(scripts_root, "relay", "scripts", "classify-repo.sh")
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            src = fh.read()
    except OSError:
        return None
    toks = set()
    for m in re.finditer(r'^HUMAN_GATES = \((.*?)\)$', src, re.S | re.M):
        toks |= set(re.findall(r'"([^"]+)"', m.group(1)))
    for m in re.finditer(r'^LANE_TAGS = \((.*?)\)', src, re.M):
        toks |= set(re.findall(r'"([^"]+)"', m.group(1)))
    return toks or None


# --------------------------------------------------------------------------- #
# Assertion (a) -- no id lost                                                  #
# --------------------------------------------------------------------------- #

def assert_a_no_id_lost(sa, before_root, after_root, notes_dir, ledgers, findings):
    before = sa.collect_markers(before_root)
    after = sa.collect_markers(after_root)
    lines = []
    for kind in ("id", "routed"):
        b_union, a_union = set(), set()
        for name in ledgers:
            b_union |= before.get(name, {}).get(kind, set())
            a_union |= after.get(name, {}).get(kind, set())
        for tok in sorted(b_union - a_union):
            homes = sa.find_in_notes(after_root, notes_dir, kind, tok)
            if homes:
                findings.append((
                    "a", "WARN",
                    "%s:%s left every ledger line but survives in %s -- assertion (b) is "
                    "where that is judged, because a detail file is not an address"
                    % (kind, tok, ", ".join(homes[:3])),
                ))
            else:
                findings.append((
                    "a", "FATAL",
                    "LOST %s:%s -- addressable BEFORE, and absent from every ledger AND "
                    "from %s AFTER: destroyed outright" % (kind, tok, notes_dir),
                ))
        for tok in sorted(a_union - b_union):
            findings.append((
                "a", "FATAL",
                "MINTED %s:%s -- absent BEFORE, present AFTER; a trimming pass relocates "
                "prose, it never mints an address" % (kind, tok),
            ))
        # Per-ledger migration: the union survived, the ADDRESS moved file.
        for name in ledgers:
            b = before.get(name, {}).get(kind, set())
            a = after.get(name, {}).get(kind, set())
            for tok in sorted((b - a) & a_union):
                findings.append((
                    "a", "WARN",
                    "%s:%s MIGRATED out of %s (it is still addressable in another ledger); "
                    "assertion (c) cannot compare an item across ledgers, so its lane and "
                    "gate go unchecked" % (kind, tok, name),
                ))
        lines.append("  %-7s union before=%d after=%d" % (kind, len(b_union), len(a_union)))
    return lines


# --------------------------------------------------------------------------- #
# Assertion (b) -- still writable by md-merge.py update-ids                    #
# --------------------------------------------------------------------------- #

def md_merge_probe(md_merge, workdir, ledger, ids):
    """Run `md-merge.py update-ids` with a no-op append for `ids`. Returns (rc, stderr).

    A no-op `append: ""` leaves the line byte-identical, so the probe cannot damage the
    copy it runs on -- and it still exercises the full resolution path: the unmatched-id
    refusal (id:1b1a), the id:6059 multi-marker refusal, and the write-side final-line
    guard. The copy is a throwaway; the AFTER tree is never touched.
    """
    payload = json.dumps({"updates": [{"id": i, "append": ""} for i in sorted(ids)]})
    proc = subprocess.run(
        [sys.executable, md_merge, "update-ids", "--file", os.path.join(workdir, ledger)],
        input=payload, capture_output=True, text=True,
    )
    return proc.returncode, (proc.stderr or "").strip()


HEX4_RE = re.compile(r"\b([0-9a-f]{4})\b")


def refused_ids(root, ledger, ids, md_merge, rounds):
    """The ids in `ledger` that `md-merge update-ids` REFUSES. {id: reason}.

    Batch first: one call for every id. rc 0 means every one of them resolves and we are
    done. On a refusal, the suspects are taken from md-merge's OWN message -- it enumerates
    the ids it would not touch, both for `unmatched id(s) not found` (id:1b1a) and for
    `AMBIGUOUS own id ... REFUSING to update <id> here` (id:6059) -- and each suspect is
    then CONFIRMED by its own single-id run. The loop then re-batches the survivors and
    repeats until a batch passes.

    Why a convergence loop and not a brute-force per-id sweep: the sweep costs one
    subprocess per id (~1,900 on the live ledgers, minutes of wall time), while this costs
    one per confirmed offender plus a handful of batches. Why it is not merely a stderr
    parse: the terminating condition is a batch that PASSES, so an offender the parse
    missed keeps the batch red and the loop reports non-convergence loudly rather than
    quietly under-counting. The parse can only affect how fast we find them, never whether
    a refused id is reported.
    """
    bad = {}
    remaining = set(ids)
    with tempfile.TemporaryDirectory(prefix="rtv-mdmerge-") as work:
        src = os.path.join(root, ledger)
        for _round in range(rounds):
            if not remaining:
                return bad, True
            shutil.copy2(src, os.path.join(work, ledger))
            rc, err = md_merge_probe(md_merge, work, ledger, remaining)
            if rc == 0:
                return bad, True
            suspects = {t for t in HEX4_RE.findall(err.lower())} & remaining
            confirmed = set()
            for item_id in sorted(suspects):
                shutil.copy2(src, os.path.join(work, ledger))
                one_rc, one_err = md_merge_probe(md_merge, work, ledger, [item_id])
                if one_rc != 0:
                    bad[item_id] = (one_err.splitlines()[-1] if one_err else "").strip()
                    confirmed.add(item_id)
            if not confirmed:
                return bad, False
            remaining -= confirmed
    return bad, False


def assert_b_writable(sa, before_root, after_root, ledgers, md_merge, findings, rounds):
    if not os.path.isfile(md_merge):
        raise HarnessError("md-merge.py not found at %s" % md_merge)
    before = sa.collect_markers(before_root)
    after = sa.collect_markers(after_root)
    lines = []
    for ledger in ledgers:
        a_ids = sorted(after.get(ledger, {}).get("id", set()))
        b_ids = sorted(before.get(ledger, {}).get("id", set()))
        if not a_ids and not b_ids:
            continue
        a_bad, a_ok = ({}, True)
        b_bad, b_ok = ({}, True)
        if a_ids:
            a_bad, a_ok = refused_ids(after_root, ledger, a_ids, md_merge, rounds)
        if b_ids:
            b_bad, b_ok = refused_ids(before_root, ledger, b_ids, md_merge, rounds)
        for side, ok in (("AFTER", a_ok), ("BEFORE", b_ok)):
            if not ok:
                raise HarnessError(
                    "md-merge probe on the %s %s did not converge in %d rounds; the "
                    "writability of the remainder is UNKNOWN and must not be reported as "
                    "a pass" % (side, ledger, rounds))
        new_bad = sorted(set(a_bad) - set(b_bad))
        inherited = sorted(set(a_bad) & set(b_bad))
        for item_id in new_bad:
            findings.append((
                "b", "FATAL",
                "%s: id:%s became UNWRITABLE -- md-merge update-ids resolved it BEFORE and "
                "refuses it AFTER. %s" % (ledger, item_id, a_bad[item_id][:400]),
            ))
        for item_id in inherited:
            findings.append((
                "b", "WARN",
                "%s: id:%s was already unwritable BEFORE the pass (inherited, not caused "
                "here)" % (ledger, item_id),
            ))
        fixed = sorted(set(b_bad) - set(a_bad))
        lines.append(
            "  %-22s %d ids; refused after=%d before=%d -> %d NEW, %d inherited, %d fixed"
            % (ledger, len(a_ids), len(a_bad), len(b_bad), len(new_bad), len(inherited),
               len(fixed)))
    return lines


# --------------------------------------------------------------------------- #
# Assertion (c) -- lane and gate unchanged                                     #
# --------------------------------------------------------------------------- #

# classify-repo.sh --emit unit fields derived from the lane parse. Deliberately excludes
# every byte counter and every git-derived field (work_sig, lastCkpt, ...): those are not
# functions of the lane, and the byte counters MUST move on a real trimming pass.
CLASSIFY_LANE_FIELDS = (
    "open_hard_pool", "open_hard_pool_ids",
    "actionable_routine_open", "actionable_routine_ids",
    "open_mechanical", "open_human_lane",
    "hasRoutine", "openHard",
)


def classify_unit(scripts_root, root, timeout):
    argv = [
        os.path.join(scripts_root, "relay", "scripts", "classify-repo.sh"),
        "--repo", "roundtrip-validate", "--path", root, "--emit", "unit",
    ]
    env = dict(os.environ)
    env["LC_ALL"] = "C.UTF-8"
    try:
        proc = subprocess.run(
            argv, capture_output=True, text=True, timeout=timeout, env=env, cwd=root
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise HarnessError("classify-repo.sh failed on %s: %s" % (root, exc))
    payload = None
    for line in proc.stdout.splitlines():
        line = line.strip()
        if line.startswith("{"):
            try:
                payload = json.loads(line)
            except ValueError:
                continue
    if payload is None:
        raise HarnessError(
            "classify-repo.sh emitted no JSON for %s: %s" % (root, (proc.stderr or "")[:300])
        )
    return payload


def assert_c_lane_and_gate(before, after, before_unit, after_unit, scripts_root, findings):
    lines = []

    if before["vocab"] != after["vocab"]:
        findings.append((
            "c", "FATAL",
            "the lane vocabulary scraped from the SSOT differs between the two runs; the "
            "comparison would be meaningless",
        ))
    literals = classify_lane_literals(scripts_root)
    if literals is not None:
        scraped = set(after["vocab"])
        if literals != scraped:
            findings.append((
                "c", "WARN",
                "lane vocabulary DRIFT: classify-repo.sh embeds %s; the SSOT scrape yields "
                "%s. Assertion (c) reads the SSOT, so the consumer may now anchor a lane "
                "this check cannot see (only in SSOT: %s; only in classify-repo: %s)"
                % (len(literals), len(scraped),
                   sorted(scraped - literals) or "-", sorted(literals - scraped) or "-"),
            ))

    # Unattributable lines are DIRECTIONAL, not absolute: the live ledgers already carry
    # ~32 of them, and failing on those would make the gate red by inheritance. A REGRESSION
    # -- an item that had a computable lane and gate before and has none after -- is caught
    # by the b_items-minus-a_items loop below, which is keyed on the id rather than on a
    # line number that every relocation moves.
    lines.append("  unattributable lines (id:6059): before=%d after=%d%s"
                 % (len(before["ambiguous"]), len(after["ambiguous"]),
                    "" if len(after["ambiguous"]) <= len(before["ambiguous"])
                    else "  <-- GREW; see the per-item findings"))

    b_items, a_items = before["items"], after["items"]
    common = sorted(set(b_items) & set(a_items))
    lane_changed = gate_changed = 0
    for key in common:
        ledger, item_id = key
        b, a = b_items[key], a_items[key]
        if b["lane"] != a["lane"]:
            lane_changed += 1
            findings.append((
                "c", "FATAL",
                "%s id:%s LANE CHANGED %s -> %s"
                % (ledger, item_id, b["lane"] or "<none>", a["lane"] or "<none>"),
            ))
        for field in MARKER_FIELDS:
            if b[field] != a[field]:
                gate_changed += 1
                findings.append((
                    "c", "FATAL",
                    "%s id:%s %s EDGE CHANGED {%s} -> {%s} -- a typed edge is an address "
                    "and a detail file cannot host one"
                    % (ledger, item_id, field,
                       ",".join(sorted(b[field])) or "-", ",".join(sorted(a[field])) or "-"),
                ))
    for key in sorted(set(b_items) - set(a_items)):
        findings.append((
            "c", "FATAL",
            "%s id:%s had a computable lane/gate BEFORE and none AFTER" % key,
        ))

    for field in CLASSIFY_LANE_FIELDS:
        b, a = before_unit.get(field), after_unit.get(field)
        if isinstance(b, list) or isinstance(a, list):
            b, a = sorted(b or []), sorted(a or [])
        if b != a:
            findings.append((
                "c", "FATAL",
                "classify-repo.sh --emit unit disagrees on the lane-derived field %s: "
                "%r -> %r. This is the CONSUMER's own view of the lanes, so a change here "
                "is a dispatch change" % (field, b, a),
            ))

    lines.append("  %d items compared; %d lane changes, %d typed-edge changes"
                 % (len(common), lane_changed, gate_changed))
    lines.append("  classify-repo lane fields: " + ", ".join(
        "%s=%s" % (f, after_unit.get(f) if not isinstance(after_unit.get(f), list)
                   else "[%d]" % len(after_unit.get(f) or []))
        for f in CLASSIFY_LANE_FIELDS))
    return lines


# --------------------------------------------------------------------------- #
# Assertions (d) and (e) -- detector findings, directional                     #
# --------------------------------------------------------------------------- #

def item_owner_map(root, ledger):
    """lineno -> owning item id, or '' when the line belongs to no item.

    A `todo-conformance.sh` finding carries a LINE NUMBER, and every line number moves when
    prose is relocated, so (d) has to key on something that survives the move. Three shapes,
    and the distinction between them is load-bearing:

      * a TOP-LEVEL checkbox line owns itself -- its key is its own id, so a rule fired on
        that item stays the same finding however far the line moves;
      * an INDENTED continuation line is owned by the nearest preceding top-level item, so
        `grammar-continuation` findings follow their item into (or out of) a note;
      * ANY OTHER top-level line -- a heading, a stray prose line -- is owned by NOTHING.
        Attributing it to the item above it would collapse two DIFFERENT stray lines into
        one key, and a pass that swapped one for another would read as no change at all.
        These fall through to the text digest in the caller.
    """
    path = os.path.join(root, ledger)
    owner = {}
    current = ""
    id_re = re.compile(r"<!--\s*id:([0-9a-fA-F]{4})\s*-->")
    item_re = re.compile(r"^- \[[ xX]\] ")
    indent_re = re.compile(r"^[ \t]")
    try:
        fh = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return owner
    with fh:
        for lineno, line in enumerate(fh, start=1):
            if item_re.match(line):
                found = id_re.findall(line)
                current = found[0].lower() if len(found) == 1 else ""
                owner[lineno] = current
            elif indent_re.match(line):
                owner[lineno] = current
            else:
                current = ""
                owner[lineno] = ""
    return owner


def grammar_findings(sa, scripts_root, root, ledger, timeout):
    """The `grammar-*` finding set for one ledger, keyed (rule, owning item)."""
    argv = [os.path.join(scripts_root, "relay", "scripts", "todo-conformance.sh"),
            os.path.join(root, ledger)]
    env = dict(os.environ)
    env["LC_ALL"] = "C.UTF-8"
    try:
        proc = subprocess.run(
            argv, capture_output=True, text=True, timeout=timeout, env=env, cwd=root
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise HarnessError("todo-conformance.sh failed on %s/%s: %s" % (root, ledger, exc))
    owner = item_owner_map(root, ledger)
    out = set()
    for line in proc.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        rule = sa.normalise_signal(parts[0])
        if not rule.startswith("grammar-"):
            continue
        try:
            lineno = int(parts[1])
        except ValueError:
            lineno = 0
        text = "\t".join(parts[2:])
        key = owner.get(lineno, "")
        if not key:
            # Stated fallback: an unowned finding (a heading, a stray top-level line, an
            # item with no resolvable id) is keyed on a digest of its own text, so two
            # distinct unowned findings of the same rule do not collapse into one.
            key = "text:" + re.sub(r"\s+", " ", text).strip()[:60]
        out.add((ledger, rule, key))
    return out


def assert_d_grammar(sa, scripts_root, before_root, after_root, ledgers, timeout, findings,
                     jobs):
    lines = []
    todo = []
    for ledger in ledgers:
        for root in (before_root, after_root):
            if os.path.isfile(os.path.join(root, ledger)):
                todo.append((ledger, root))
    # todo-conformance.sh costs ~10-30s on a large ledger, so the (ledger x root) grid runs
    # concurrently. Each call is read-only and writes nothing, so they cannot interfere.
    got = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        futs = {
            key: pool.submit(grammar_findings, sa, scripts_root, key[1], key[0], timeout)
            for key in todo
        }
        for key, fut in futs.items():
            got[key] = fut.result()
    for ledger in ledgers:
        if (ledger, before_root) not in got and (ledger, after_root) not in got:
            continue
        b = got.get((ledger, before_root), set())
        a = got.get((ledger, after_root), set())
        gained = sorted(a - b)
        for _ledger, rule, key in gained:
            findings.append((
                "d", "FATAL",
                "%s GAINED grammar finding %s on %s -- the grammar moved AWAY from "
                "conformance" % (ledger, rule, key),
            ))
        lines.append("  %-22s grammar before=%-4d after=%-4d removed=%-4d gained=%d"
                     % (ledger, len(b), len(a), len(b - a), len(gained)))
    return lines


# Detectors whose findings assertion (e) forbids GAINING. Both are named in the acceptance
# clause; both are run through shrink-acceptance's registry entry, so their argv and their
# output parsing are the prior art's, not a second copy.
E_DETECTORS = ("orphan-scan--cross-ledger", "roadmap-lint")


def assert_e_no_new_findings(sa, before_root, after_root, timeout, findings, jobs):
    lines = []
    dets = [d for d in sa.DETECTOR_REGISTRY if d["name"] in E_DETECTORS]
    got = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        futs = {
            (det["name"], label): pool.submit(sa.run_detector, det, root, timeout)
            for det in dets for label, root in (("before", before_root), ("after", after_root))
        }
        for key, fut in futs.items():
            got[key] = fut.result()
    for det in dets:
        results = {}
        for label in ("before", "after"):
            parsed, err = got[(det["name"], label)]
            if err:
                raise HarnessError("%s could not run on the %s root: %s" % (det["name"], label, err))
            results[label] = parsed[0]
        gained = sorted(results["after"] - results["before"])
        for _polarity, signal, key in gained:
            findings.append((
                "e", "FATAL",
                "%s GAINED a finding: %s on item %s" % (det["name"], signal, key),
            ))
        lines.append("  %-26s before=%-4d after=%-4d removed=%-4d gained=%d"
                     % (det["name"], len(results["before"]), len(results["after"]),
                        len(results["before"] - results["after"]), len(gained)))
    return lines


# --------------------------------------------------------------------------- #
# Driver                                                                       #
# --------------------------------------------------------------------------- #

ASSERTION_TITLES = {
    "a": "no id lost (ledger line or note)",
    "b": "still writable by md-merge.py update-ids",
    "c": "lane and typed gate/decision edges unchanged",
    "d": "grammar findings move only toward conformance",
    "e": "orphan-scan --cross-ledger / roadmap-lint gain no finding",
}


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Directional round-trip validator for a ledger trimming pass (id:ff7c).")
    ap.add_argument("--before", required=True, help="root of the ledger tree BEFORE the pass")
    ap.add_argument("--after", required=True, help="root of the ledger tree AFTER the pass")
    ap.add_argument("--notes-dir", default=None,
                    help="notes corpus, relative to each root (default docs/ledger-notes)")
    ap.add_argument("--scripts-root", default=DEFAULT_SCRIPTS_ROOT,
                    help="repo holding the detectors (default: this repo)")
    # Default to THIS repo's canonical copy, not the ~/.claude symlink farm: the house rule
    # is to touch canonical paths, and it keeps a hermetic test off ~/.claude entirely.
    ap.add_argument("--md-merge", default=None,
                    help="path to md-merge.py for assertion (b) "
                         "(default: <scripts-root>/meeting/md-merge.py)")
    ap.add_argument("--only", default="abcde",
                    help="subset of assertions to run, e.g. --only abc")
    ap.add_argument("--fail-fast", action="store_true",
                    help="stop at the first failing assertion")
    ap.add_argument("--timeout", type=int, default=600, help="per-detector timeout, seconds")
    ap.add_argument("--ledgers", default=None,
                    help="comma-separated ledger basenames to compare (default: all six). "
                         "Scope this ONLY when you know the pass touched nothing else -- a "
                         "narrowed set cannot see an id that left it.")
    ap.add_argument("--jobs", type=int, default=6, help="concurrent detector runs")
    ap.add_argument("--md-merge-rounds", type=int, default=12,
                    help="max batch/confirm rounds for (b) before declaring non-convergence")
    ap.add_argument("--json", action="store_true", help="emit the findings as JSON")
    args = ap.parse_args(argv)

    sa_path = os.path.join(HERE, "shrink-acceptance.py")
    if not os.path.isfile(sa_path):
        print("roundtrip-validate: FATAL -- shrink-acceptance.py not found at %s; this "
              "validator reuses it rather than duplicating it" % sa_path, file=sys.stderr)
        return EXIT_HARNESS
    sa = load_shrink_acceptance(sa_path)
    sa.REPO_ROOT = os.path.abspath(args.scripts_root)

    md_merge = args.md_merge or os.path.join(sa.REPO_ROOT, "meeting", "md-merge.py")
    notes_dir = args.notes_dir or sa.DEFAULT_NOTES_DIR
    before_root, after_root = os.path.abspath(args.before), os.path.abspath(args.after)
    for label, root in (("--before", before_root), ("--after", after_root)):
        if not os.path.isdir(root):
            print("roundtrip-validate: FATAL -- %s is not a directory: %s" % (label, root),
                  file=sys.stderr)
            return EXIT_HARNESS

    ledgers = list(sa.LEDGER_FILES)
    if args.ledgers:
        picked = [x.strip() for x in args.ledgers.split(",") if x.strip()]
        unknown = [x for x in picked if x not in ledgers]
        if unknown:
            print("roundtrip-validate: FATAL -- --ledgers names files that are not ledgers: "
                  "%s" % ", ".join(unknown), file=sys.stderr)
            return EXIT_HARNESS
        ledgers = picked
    wanted = [c for c in "abcde" if c in args.only]
    if not wanted:
        print("roundtrip-validate: FATAL -- --only selected no assertion", file=sys.stderr)
        return EXIT_HARNESS

    findings = []
    report = []
    failed = []

    def fatal_count():
        return sum(1 for f in findings if f[1] == "FATAL")

    try:
        # (c)'s two probes and (a)'s marker scan are cheap; the classify runs are not, so
        # the two roots go in parallel.
        probes = {}
        units = {}
        if "c" in wanted:
            with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
                jobs = {
                    ("probe", "before"): pool.submit(
                        run_probe, sa.REPO_ROOT, before_root, ledgers, args.timeout),
                    ("probe", "after"): pool.submit(
                        run_probe, sa.REPO_ROOT, after_root, ledgers, args.timeout),
                    ("unit", "before"): pool.submit(
                        classify_unit, sa.REPO_ROOT, before_root, args.timeout),
                    ("unit", "after"): pool.submit(
                        classify_unit, sa.REPO_ROOT, after_root, args.timeout),
                }
                for (kind, side), fut in jobs.items():
                    (probes if kind == "probe" else units)[side] = fut.result()

        for letter in wanted:
            before_fatals = fatal_count()
            report.append("[%s] %s" % (letter, ASSERTION_TITLES[letter]))
            if letter == "a":
                report += assert_a_no_id_lost(
                    sa, before_root, after_root, notes_dir, ledgers, findings)
            elif letter == "b":
                report += assert_b_writable(
                    sa, before_root, after_root, ledgers, md_merge, findings,
                    args.md_merge_rounds)
            elif letter == "c":
                report += assert_c_lane_and_gate(
                    probes["before"], probes["after"], units["before"], units["after"],
                    sa.REPO_ROOT, findings)
            elif letter == "d":
                report += assert_d_grammar(
                    sa, sa.REPO_ROOT, before_root, after_root, ledgers, args.timeout,
                    findings, args.jobs)
            elif letter == "e":
                report += assert_e_no_new_findings(
                    sa, before_root, after_root, args.timeout, findings, args.jobs)
            if fatal_count() > before_fatals:
                failed.append(letter)
                report.append("  -> FAILED")
                if args.fail_fast:
                    break
            else:
                report.append("  -> ok")
    except HarnessError as exc:
        print("roundtrip-validate: HARNESS ERROR -- %s" % exc, file=sys.stderr)
        print("roundtrip-validate: a validator that could not RUN is not a pass.",
              file=sys.stderr)
        return EXIT_HARNESS

    if args.json:
        print(json.dumps({
            "before": before_root, "after": after_root,
            "assertions_run": wanted, "assertions_failed": failed,
            "findings": [{"assertion": a, "severity": s, "message": m} for a, s, m in findings],
        }, indent=2))
    else:
        print("roundtrip-validate: BEFORE=%s AFTER=%s" % (before_root, after_root))
        for line in report:
            print(line)
        for assertion, severity, message in findings:
            if severity == "INFO":
                continue
            print("roundtrip-validate: %-5s (%s) %s" % (severity, assertion, message),
                  file=sys.stderr if severity == "FATAL" else sys.stdout)

    if failed:
        print("roundtrip-validate: DIRECTIONAL VERDICT: REFUSED -- assertion(s) %s failed "
              "(%d fatal findings)" % (", ".join(failed), fatal_count()), file=sys.stderr)
        return EXIT_REFUSED
    print("roundtrip-validate: DIRECTIONAL VERDICT: CLEAN -- assertions %s hold"
          % ", ".join(wanted))
    return EXIT_CLEAN


if __name__ == "__main__":
    sys.exit(main())
