#!/usr/bin/env python3
"""tracker/repo-entity.py — repo-level entity derivation for the tracker intermediate doc.

TODO id:c17d (children-of:2bb1), meeting
`docs/meeting-notes/2026-08-10-0906-tracker-substrate-replacing-markdown-ledgers.md`
(Fable finding 3: without a repo-level entity the fleet board cannot answer the question
that motivated the pilot — "which repos need me?").

WHAT THIS IS
------------
The step that fills the `repos[].verdict` hole `tracker/ledger-map.py` deliberately
leaves as `null` ("Repo-entity verdict derivation is id:c17d", SCHEMA.md §Scope
boundary). It turns one board row per repo into ONE REPO ENTITY per repo, in the
`id:2bb1` intermediate-JSON shape, so the Plane/Vikunja adapters (id:90f2) can create
them as board items with no further derivation.

WHAT THIS IS NOT (the reconcile against id:8066, recorded so it is not re-litigated)
------------------------------------------------------------------------------------
  * NOT a second classifier. Every verdict is `classify-repo.sh --emit unit` VERBATIM,
    read out of `relay/scripts/control-board.sh --json`. No status vocabulary is
    authored here: `verdict` is the classifier's enum, `board_column` is
    control-board.sh's display grouping, `board_label` is `render-verdict.sh`'s label
    (the only sanctioned emitter of "drained").
  * NOT a second board renderer. `control-board.sh` is the control-arm board (id:8066)
    and stays the only renderer; this reads its `--json` and emits ENTITIES.
  * NOT a fleet driver. It never reads `relay.toml`, never resolves a path, never pins a
    SHA, never upserts or tombstones — that is id:94ce. It is a pure function of two
    JSON documents.
  * NOT a write path. Reads JSON, prints JSON. It writes NO file and, per the pilot's
    ratified rule (D4), NO relay/tracker script writes to a tracker.

KNOWN GAP, NOT FIXED HERE
-------------------------
`classify-repo.sh --emit unit` drops the `unpromoted` promote/surface counts, so a repo
entity cannot carry them (filed as id:6daf). This script deliberately does NOT re-run
`unpromoted-scan.sh` to re-derive them — a second derivation path is exactly the drift
the ledger rules forbid. When id:6daf lands, the counts arrive through the same
`--emit unit` → control-board `--json` pipe and land in `counts` with no change here.

A SECOND GAP, SURFACED
----------------------
`ledger-map.py validate` checks `items[]` exhaustively but does not validate `repos[]`
at all — a repo entity missing a required key, or carrying a bogus verdict, passes.
This script therefore ships its OWN `validate-repos` subcommand rather than trusting a
check that does not exist. Folding it into `ledger-map.py validate` is the coherent home
and is left to that file's owner.

USAGE
-----
    relay/scripts/control-board.sh --json > board.json

    # A) standalone repos-only document (valid input to `ledger-map.py merge`):
    tracker/repo-entity.py emit --board board.json > repos.json

    # B) fill the verdicts into a ledger document produced by `ledger-map.py import`:
    tracker/repo-entity.py enrich doc.json --board board.json > doc.enriched.json

    # C) check repo entities (the ledger-map.py validate gap above):
    tracker/repo-entity.py validate-repos doc.enriched.json

`--board -` reads the board from stdin. Stdlib only (repo convention: no deps).

SCHEMA VERSION: DERIVED, never restated here (id:8c7f). This file used to carry its own
literal copy, which is how the `verdict` value-space replacement it introduced shipped
under an unchanged version marker. The single source is the JSON Schema's
`properties.schema_version.const`; `ledger-map.py validate` fails loudly if any file in
`tracker/` re-hardcodes it.
"""

from __future__ import annotations

import argparse
import json
import os
import sys

SCHEMA_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "schema", "ledger-intermediate.schema.json")


def _schema_version() -> str:
    """Read the ONE declared version (id:8c7f) — never a literal in this file."""
    with open(SCHEMA_PATH, "r", encoding="utf-8") as fh:
        return json.load(fh)["properties"]["schema_version"]["const"]


SCHEMA_VERSION = _schema_version()

# The classifier's verdict enum, quoted from relay/scripts/classify-verdict.sh (the
# `verdict = "..."` assignments) plus the AMBIGUOUS escape hatch documented in its
# header. NOT authored here — tests/test_tracker_repo_entity.sh greps classify-verdict.sh
# and fails if it ever emits a verdict this list does not know.
VERDICT_ENUM = [
    "blocked", "execute", "review", "hard", "handoff",
    "human", "mechanical", "idle", "AMBIGUOUS",
]

# control-board.sh's display grouping over that enum (ORDER in control-board.sh).
BOARD_COLUMN_ENUM = [
    "blocked", "relay-poolable", "needs-feedback", "design-drained", "unclassified",
]

REPO_REQUIRED_KEYS = ["repo", "path", "verdict", "labels"]


def die(msg: str, code: int = 2):
    print("repo-entity.py: %s" % msg, file=sys.stderr)
    raise SystemExit(code)


def load_json(path: str):
    if path == "-":
        return json.load(sys.stdin)
    if not os.path.exists(path):
        die("no such file: %s" % path)
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def entity_from_board_row(row: dict, generated_at: str) -> dict:
    """One control-board.sh `--json` repo row -> one repo entity. Pure."""
    name = row.get("repo", "")
    column = row.get("column", "")
    if column not in BOARD_COLUMN_ENUM:
        # Loud, never silent (id:4347): an unknown column means control-board.sh grew a
        # grouping this file does not know. Carry it verbatim rather than guessing.
        print("repo-entity.py: WARN [%s]: unknown board column %r — carried verbatim"
              % (name, column), file=sys.stderr)

    producer_error = bool(row.get("producer_error"))
    verdict = row.get("verdict") or ""
    if producer_error or not verdict:
        # The classifier produced nothing for this repo. `verdict: null` is the schema's
        # own "not derived" value; the reason is carried so the board is not a dead end.
        verdict_out = None
        labels = ["verdict:unavailable", "board:%s" % (column or "unclassified")]
        print("repo-entity.py: producer-error [%s]: %s"
              % (name, row.get("reason", "") or "classifier produced no verdict"),
              file=sys.stderr)
    else:
        if verdict not in VERDICT_ENUM:
            print("repo-entity.py: WARN [%s]: verdict %r is not in the known enum %r — "
                  "carried VERBATIM (this file never rewrites a classifier verdict)"
                  % (name, verdict, VERDICT_ENUM), file=sys.stderr)
        verdict_out = verdict
        labels = ["verdict:%s" % verdict, "board:%s" % column]

    return {
        "repo": name,
        "path": row.get("path", ""),
        # The contract (id:c17d): a repo's board status EQUALS classify-repo.sh's verdict.
        "verdict": verdict_out,
        "labels": labels,
        # control-board.sh's grouping + render-verdict.sh's display label, carried
        # ALONGSIDE the raw verdict so the grouping collapses nothing (id:8066 rule).
        "board_column": column,
        "board_label": row.get("label", ""),
        "verdict_reason": row.get("reason", ""),
        "counts": {
            "actionable_routine_open": int(row.get("actionable_routine_open", 0) or 0),
            "open_hard_pool": int(row.get("open_hard_pool", 0) or 0),
            "open_mechanical": int(row.get("open_mechanical", 0) or 0),
        },
        "verdict_source": "classify-repo.sh --emit unit (via control-board.sh --json)",
        "verdict_generated_at": generated_at,
    }


def board_entities(board: dict) -> dict:
    """board document -> {repo name: entity}. Loud on a duplicate repo name."""
    generated_at = board.get("generated_at", "")
    if "repos" not in board:
        die("board document has no `repos` key — is this control-board.sh --json output?", 2)
    out = {}
    for row in board.get("repos", []):
        name = row.get("repo", "")
        if not name:
            die("board row without a `repo` name: %r" % row, 3)
        if name in out:
            die("board lists repo %r twice — a repo name is the first half of the "
                "composite (repo, id) key and must be unique" % name, 3)
        out[name] = entity_from_board_row(row, generated_at)
    return out


def cmd_emit(args) -> int:
    ents = board_entities(load_json(args.board))
    doc = {
        "schema_version": SCHEMA_VERSION,
        # Sorted by repo name so the document is byte-deterministic (same discipline as
        # ledger-map.py's sorted output).
        "repos": [ents[k] for k in sorted(ents)],
        "items": [],
        "unmapped": [],
        "unmapped_counts": {},
    }
    print(json.dumps(doc, indent=2, sort_keys=True))
    return 0


def cmd_enrich(args) -> int:
    doc = load_json(args.doc)
    ents = board_entities(load_json(args.board))

    if doc.get("schema_version") != SCHEMA_VERSION:
        die("document schema_version %r != %r — refusing to enrich a version this file "
            "does not know (SCHEMA.md §5)" % (doc.get("schema_version"), SCHEMA_VERSION), 3)

    matched = set()
    unresolved = []
    for repo_ent in doc.get("repos", []):
        name = repo_ent.get("repo", "")
        ent = ents.get(name)
        if ent is None:
            unresolved.append(name)
            # Never invent a verdict: leave it null and LABEL the absence.
            repo_ent.setdefault("labels", [])
            if "verdict:unavailable" not in repo_ent["labels"]:
                repo_ent["labels"].append("verdict:unavailable")
            print("repo-entity.py: WARN: repo %r is in the document but not on the board "
                  "— verdict left null" % name, file=sys.stderr)
            continue
        matched.add(name)
        # The board is authoritative for the verdict fields ONLY; everything the mapper
        # put on the entity (ledger_files, labels it derived) survives.
        merged_labels = list(repo_ent.get("labels", []))
        for lab in ent["labels"]:
            if lab not in merged_labels:
                merged_labels.append(lab)
        repo_ent.update({k: v for k, v in ent.items() if k not in ("labels", "path")})
        repo_ent["labels"] = merged_labels
        if not repo_ent.get("path"):
            repo_ent["path"] = ent["path"]

    missing = [n for n in sorted(ents) if n not in matched]
    for name in missing:
        if args.add_missing:
            doc.setdefault("repos", []).append(ents[name])
            print("repo-entity.py: added board-only repo %r as a new repo entity "
                  "(--add-missing)" % name, file=sys.stderr)
        else:
            print("repo-entity.py: WARN: repo %r is on the board but not in the document "
                  "— NOT added (pass --add-missing to add it)" % name, file=sys.stderr)

    if args.strict and (unresolved or missing):
        die("strict: %d document repo(s) without a board verdict, %d board repo(s) not in "
            "the document" % (len(unresolved), len(missing)), 3)

    print(json.dumps(doc, indent=2, sort_keys=True))
    return 0


def validate_repos(doc: dict) -> list:
    """Repo-entity invariants. Returns a list of error strings (empty == OK)."""
    errs = []
    seen = set()
    for r in doc.get("repos", []):
        name = r.get("repo", "")
        for k in REPO_REQUIRED_KEYS:
            if k not in r:
                errs.append("repo %r: missing required key %r" % (name, k))
        if not name:
            errs.append("a repo entity has an empty `repo` name — it is half the "
                        "composite (repo, id) key")
        elif name in seen:
            errs.append("duplicate repo entity %r" % name)
        seen.add(name)

        v = r.get("verdict", None)
        if v is not None and not isinstance(v, str):
            errs.append("repo %r: verdict %r is neither a string nor null" % (name, v))
        col = r.get("board_column")
        if col is not None and col not in BOARD_COLUMN_ENUM:
            errs.append("repo %r: board_column %r not in %r" % (name, col, BOARD_COLUMN_ENUM))
        # The id:c17d contract, asserted structurally: a repo with a real verdict may not
        # be filed under `unclassified`, and a repo with no verdict may not claim a
        # classified column. That is the "board status EQUALS the verdict" invariant.
        if v and col == "unclassified":
            errs.append("repo %r: verdict %r but board_column 'unclassified' — the board "
                        "status must equal the classifier verdict" % (name, v))
        if v is None and col not in (None, "", "unclassified"):
            errs.append("repo %r: no verdict but board_column %r — a null verdict cannot "
                        "be classified" % (name, col))
        if not isinstance(r.get("labels", []), list):
            errs.append("repo %r: labels is not a list" % name)
    return errs


def cmd_validate_repos(args) -> int:
    doc = load_json(args.doc)
    errs = validate_repos(doc)
    if errs:
        for e in errs:
            print("repo-entity.py: ERROR: %s" % e, file=sys.stderr)
        print("validate-repos: FAILED (%d error(s))" % len(errs), file=sys.stderr)
        return 3
    n = len(doc.get("repos", []))
    withv = len([r for r in doc.get("repos", []) if r.get("verdict")])
    print("validate-repos: OK (%d repo entit(y/ies), %d with a verdict)" % (n, withv))
    return 0


def main(argv=None) -> int:
    # A plain string, NOT `__doc__`: `python3 -OO` strips docstrings (the crash fixed in
    # ledger-map.py's review — do not reintroduce it here).
    ap = argparse.ArgumentParser(
        prog="repo-entity.py",
        description="Repo-level entity derivation (TODO id:c17d): fill classify-repo.sh's "
                    "verdict into the tracker intermediate document's repo entities.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_emit = sub.add_parser("emit", help="board JSON -> repos-only intermediate document")
    p_emit.add_argument("--board", required=True, help="control-board.sh --json output ('-' = stdin)")
    p_emit.set_defaults(func=cmd_emit)

    p_enr = sub.add_parser("enrich", help="fill verdicts into a ledger-map.py document")
    p_enr.add_argument("doc", help="intermediate document ('-' = stdin)")
    p_enr.add_argument("--board", required=True, help="control-board.sh --json output ('-' = stdin)")
    p_enr.add_argument("--add-missing", action="store_true",
                       help="also add board repos that the document does not carry")
    p_enr.add_argument("--strict", action="store_true",
                       help="exit 3 if any repo is unmatched in either direction")
    p_enr.set_defaults(func=cmd_enrich)

    p_val = sub.add_parser("validate-repos", help="repo-entity invariants (the ledger-map.py gap)")
    p_val.add_argument("doc")
    p_val.set_defaults(func=cmd_validate_repos)

    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
