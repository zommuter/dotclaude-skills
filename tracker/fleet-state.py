#!/usr/bin/env python3
"""tracker/fleet-state.py — the PURE half of the fleet importer (TODO id:94ce).

`fleet-import.sh` owns the impure work (relay.toml own-set enumeration, git SHA
pinning, ledger extraction, invoking `ledger-map.py`). This file owns the part that
has to be *reasoned about*: folding a freshly imported fleet document into the durable
per-`(repo, id)` state, with upserts and tombstones.

It is a **pure function of its inputs**: `upsert` reads a fleet document + a prior
state document and prints the next state document to stdout. It opens no repo, runs
no git, takes no clock reading and writes no file. That is what makes id:94ce's
headline contract testable —

    two consecutive runs over an unchanged fleet produce zero diffs

— because the *only* way the state file can change is if an item's content hash, the
repo set, or the loud-lossy report changed. There is deliberately **no timestamp
anywhere in the state document**: a wall-clock field would break the zero-diff
contract on the first re-run, and "when did this change" is answered better by the
pinned SHA that the change was observed at (`changed_at_sha`), which is both
deterministic and a pointer into git history.

State document shape
--------------------
    {
      "state_version": 1,
      "schema_version": "<ledger-map.py SCHEMA_VERSION>",
      "homonym_allowlist": ["<4-hex>", ...],   # adjudicated tokens, see fleet-import.sh
      "repos":        [ {repo, path, head_sha, verdict, labels, ledger_files}, ... ],
      "repo_errors":  [ {repo, path, reason}, ... ],
      "unmapped_counts": {construct: count, ...},
      "items": [
        {
          "uid": "<repo>/<key>",
          "repo": "<repo>",
          "state": "live" | "tombstoned",
          "content_hash": "<sha256 of the canonicalised item>",
          "changed_at_sha": "<repo HEAD sha this record last changed at>",
          "tombstoned_at_sha": "<sha>",        # present only while state == tombstoned
          "item": { ... the ledger-map.py item, verbatim ... }
        }, ...
      ]
    }

Upsert rules (all three matter for the contract)
------------------------------------------------
1. **Unchanged item ⇒ record carried BYTE-IDENTICAL.** Not rewritten with equal
   values — carried. This is what makes zero-diff robust rather than accidental.
2. **Tombstones are scoped to repos that IMPORTED SUCCESSFULLY.** An item may only be
   tombstoned if its repo is present in the fleet document's `repos[]`. A repo that
   errored (missing path, not a git repo, import failure) or that left the
   `relay.toml` own-set contributes NO tombstones — otherwise one transient failure
   mass-tombstones a whole repo's backlog, which is the expensive, silent failure
   mode this rule exists to prevent. Retained records from absent repos are reported
   loudly as `retained-absent-repo`.
3. **Resurrection is a normal transition.** A tombstoned uid that reappears goes back
   to `live` and drops `tombstoned_at_sha`; ids do come back (an archive move, a
   revert), and a permanently-dead tombstone would shadow the live item.

Stdlib only (repo convention: no venv, no deps).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys

STATE_VERSION = 1

CLI_SUMMARY = ("tracker/fleet-state.py — pure upsert/tombstone fold of a fleet "
               "document into the durable (repo,id) state document.")


def die(msg: str, code: int = 2) -> None:
    print("ERROR: %s" % msg, file=sys.stderr)
    raise SystemExit(code)


def content_hash(item: dict) -> str:
    """Canonical hash of an item. Sorted keys + tight separators, so a re-serialised
    but semantically identical item hashes the same."""
    blob = json.dumps(item, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()


def empty_state(schema_version: str) -> dict:
    return {
        "state_version": STATE_VERSION,
        "schema_version": schema_version,
        "homonym_allowlist": [],
        "repos": [],
        "repo_errors": [],
        "unmapped_counts": {},
        "items": [],
    }


def upsert(prior: dict, fleet: dict, allowlist: list, errors: list) -> tuple:
    """Fold `fleet` into `prior`. Returns (next_state, notes).

    `notes` are LOUD lines the caller prints to stderr — never swallowed
    (id:4347 no-silent-swallow).
    """
    notes = []
    schema_version = fleet.get("schema_version")
    if not schema_version:
        die("fleet document carries no schema_version — refusing to fold it into state")
    if prior.get("items") and prior.get("schema_version") != schema_version:
        # An adapter must refuse a schema_version it does not know (SCHEMA.md §5); so
        # must the state store, rather than silently mixing two document generations.
        die("schema_version drift: state=%r fleet=%r — the state store holds items "
            "produced by a different schema generation. Re-import from scratch (delete "
            "the state file) or migrate it deliberately."
            % (prior.get("schema_version"), schema_version), 3)

    prior_items = {r["uid"]: r for r in prior.get("items", [])}

    # Repos that imported successfully THIS run — the only repos whose items may be
    # tombstoned (rule 2).
    fleet_repos = {r["repo"]: r for r in fleet.get("repos", [])}
    head_sha = {name: r.get("head_sha") or "" for name, r in fleet_repos.items()}

    next_items = {}

    # --- upsert every item the fleet document carries -----------------------------
    for it in fleet.get("items", []):
        uid = it["uid"]
        repo = it["repo"]
        if uid in next_items:
            die("duplicate uid %r in the fleet document — ledger-map.py validate "
                "should have caught this; refusing to fold" % uid, 3)
        h = content_hash(it)
        old = prior_items.get(uid)
        if old is not None and old.get("state") == "live" and old.get("content_hash") == h:
            next_items[uid] = old            # rule 1: carried verbatim
            continue
        if old is not None and old.get("state") == "tombstoned":
            notes.append("resurrected: %s (was tombstoned at %s)"
                         % (uid, old.get("tombstoned_at_sha", "?")))
        next_items[uid] = {
            "uid": uid,
            "repo": repo,
            "state": "live",
            "content_hash": h,
            "changed_at_sha": head_sha.get(repo, ""),
            "item": it,
        }

    # --- tombstone / retain everything the fleet document did NOT carry -----------
    retained_absent = {}
    for uid, old in prior_items.items():
        if uid in next_items:
            continue
        repo = old.get("repo") or uid.split("/", 1)[0]
        if repo not in fleet_repos:
            # rule 2: this repo did not import this run — NOT evidence of deletion.
            next_items[uid] = old
            retained_absent[repo] = retained_absent.get(repo, 0) + 1
            continue
        if old.get("state") == "tombstoned":
            next_items[uid] = old            # already dead; carried verbatim (rule 1)
            continue
        rec = {
            "uid": uid,
            "repo": repo,
            "state": "tombstoned",
            "content_hash": old.get("content_hash", ""),
            "changed_at_sha": head_sha.get(repo, ""),
            "tombstoned_at_sha": head_sha.get(repo, ""),
            "item": old.get("item", {}),
        }
        next_items[uid] = rec
        notes.append("tombstoned: %s (vanished from %s at %s)"
                     % (uid, repo, head_sha.get(repo, "?")))

    for repo in sorted(retained_absent):
        notes.append("retained-absent-repo: %d item(s) of %r kept UNCHANGED — the repo "
                     "did not import this run (errored, paused, or left the own-set); "
                     "absence is NOT deletion" % (retained_absent[repo], repo))

    state = {
        "state_version": STATE_VERSION,
        "schema_version": schema_version,
        "homonym_allowlist": sorted(set(allowlist)),
        "repos": sorted(fleet.get("repos", []), key=lambda r: r["repo"]),
        "repo_errors": sorted(errors, key=lambda e: (e.get("repo", ""), e.get("reason", ""))),
        "unmapped_counts": dict(sorted(fleet.get("unmapped_counts", {}).items())),
        "items": [next_items[u] for u in sorted(next_items)],
    }
    return state, notes


def read_json(path: str, default=None):
    if path == "-":
        return json.load(sys.stdin)
    if not os.path.exists(path):
        if default is None:
            die("no such file: %s" % path)
        return default
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=CLI_SUMMARY)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_up = sub.add_parser("upsert", help="fold a fleet document into the state document")
    p_up.add_argument("--fleet", required=True, help="fleet document (ledger-map.py merge output)")
    p_up.add_argument("--state", required=True,
                      help="prior state document; may not exist yet (treated as empty)")
    p_up.add_argument("--allowlist", default="",
                      help="comma-separated adjudicated homonym tokens, recorded for audit")
    p_up.add_argument("--errors", default="",
                      help="JSON file holding this run's repo_errors array")

    p_di = sub.add_parser("diff", help="report live/tombstoned counts of a state document")
    p_di.add_argument("state")

    args = ap.parse_args(argv)

    if args.cmd == "upsert":
        fleet = read_json(args.fleet)
        prior = read_json(args.state, default=empty_state(fleet.get("schema_version", "")))
        allowlist = [t for t in args.allowlist.split(",") if t]
        errors = read_json(args.errors, default=[]) if args.errors else []
        state, notes = upsert(prior, fleet, allowlist, errors)
        for n in notes:
            print("fleet-state: %s" % n, file=sys.stderr)
        print(json.dumps(state, indent=2, ensure_ascii=False, sort_keys=True))
        return 0

    if args.cmd == "diff":
        st = read_json(args.state)
        live = sum(1 for r in st.get("items", []) if r.get("state") == "live")
        dead = sum(1 for r in st.get("items", []) if r.get("state") == "tombstoned")
        print("state: %d live, %d tombstoned, %d repo(s), %d repo error(s)"
              % (live, dead, len(st.get("repos", [])), len(st.get("repo_errors", []))))
        return 0

    return 2


if __name__ == "__main__":
    sys.exit(main())
