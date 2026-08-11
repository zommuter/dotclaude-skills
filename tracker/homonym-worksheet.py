#!/usr/bin/env python3
"""tracker/homonym-worksheet.py — render the cross-repo homonym ADJUDICATION worksheet.

TODO id:e977 (the decision aid for id:ca24's per-token allow-list). Stdlib only.

WHAT THIS IS
------------
`ledger-map.py validate` reports every class-A cross-repo homonym (the same bare 4-hex
token minted independently in >=2 repos) as a bare token plus a repo list. That is
enough to FAIL an import and nowhere near enough to ADJUDICATE one: the owner has to
answer "same thing, or coincidence?", and a token with no titles attached carries no
evidence either way.

This renders the evidence, one token at a time:
  * every (repo, id) that mints the token, with its title, its per-view statuses and
    the file:line it came from;
  * whether either item REFERENCES the other — a `routed:`/`settles:`/`decided-in:`
    edge on the shared token, a `blocked_by`/`parent`/`children` edge that crosses into
    a sibling minting repo, or a prose mention of a sibling minting repo's NAME in the
    item's title/body;
  * whether the titles share significant vocabulary.
That last pair of signals is the whole point: it is what separates a birthday collision
(4 hex = 65 536 tokens over ~4 800 live ids, so collisions are near-certain and
harmless — the composite (repo,id) key already disambiguates) from a real cross-repo
link somebody forgot to mark up.

WHAT IT IS NOT
--------------
It does NOT adjudicate. It never writes tracker/homonym-allowlist.txt, and every token
in the emitted DRAFT allow-list is written COMMENTED OUT behind an `# UNCONFIRMED `
marker, so a draft pasted verbatim into the live allow-list still reads as STRICT.
A human names each token by deleting that marker (id:ca24; owner-decided 2026-08-10).

CLASS B (an ambiguous cross-repo `routed:` edge) is never adjudicable and is reported
as a COUNT plus its tokens only — fix the edge, do not allow-list it.

Authority: the class-A/class-B verdict is PARSED from `ledger-map.py validate`'s own
output, never re-derived here — one collision detector, not two that can disagree.

Usage:
  homonym-worksheet.py --fleet <fleet.json> --validate-log <validate.err>
                       --out-worksheet <file.md> --out-draft <file.txt>
                       [--allowlist <live allowlist.txt>] [--title-chars N]
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys

CLASS_A_RE = re.compile(
    r"cross-repo id collision \(class A, HOMONYM\): bare token '([0-9a-f]{4})' "
    r"exists in repos (\[[^\]]*\])")
CLASS_B_RE = re.compile(
    r"cross-repo id collision \(class B, AMBIGUOUS REFERENCE\): bare token "
    r"'([0-9a-f]{4})' exists in repos (\[[^\]]*\])")
# An ADJUDICATED class-A homonym is a warning, not an error — a worksheet regenerated
# with the live allow-list in force must still SHOW those tokens, or the artifact would
# silently shrink as tokens get accepted and nobody could re-check an old decision.
CLASS_A_WARN_RE = re.compile(
    r"cross-repo id homonym \(class A\): '([0-9a-f]{4})' in repos (\[[^\]]*\])")

# Words that carry no discriminating signal when two titles share them.
STOPWORDS = {
    "that", "this", "with", "from", "into", "when", "then", "than", "them", "they",
    "have", "will", "must", "never", "only", "also", "each", "over", "same", "such",
    "make", "made", "does", "done", "todo", "item", "items", "note", "notes", "line",
    "lines", "file", "files", "test", "tests", "code", "work", "step", "steps",
    "after", "before", "every", "still", "which", "where", "would", "could", "should",
    "there", "their", "what", "just", "like", "more", "less", "very", "some", "none",
    "keep", "kept", "used", "uses", "using", "case", "cases", "call", "calls", "run",
    "runs", "read", "reads", "write", "writes", "path", "paths", "name", "names",
    "list", "lists", "flag", "flags", "mode", "modes", "task", "tasks", "fix", "fixes",
    "add", "adds", "one", "two", "per", "not", "the", "and", "for", "its", "via",
}
WORD_RE = re.compile(r"[a-z][a-z0-9_-]{3,}")


def die(msg: str) -> None:
    sys.stderr.write("homonym-worksheet: %s\n" % msg)
    raise SystemExit(2)


def parse_validate_log(path: str):
    """Return (class_a: {tok: [repos]}, class_b: {tok: [repos]}).

    LOUD, never silent: a log that contains no collision verdict AND no
    'validate: N error(s)' summary line is a log this script cannot trust, and it says
    so rather than reporting a confident zero.
    """
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError as exc:
        die("--validate-log: %s" % exc)
    class_a, class_b = {}, {}
    for rx, sink in ((CLASS_A_RE, class_a), (CLASS_A_WARN_RE, class_a),
                     (CLASS_B_RE, class_b)):
        for tok, repos in rx.findall(text):
            sink[tok] = sorted(set(json.loads(repos.replace("'", '"'))))
    if not class_a and not class_b and "validate:" not in text:
        die("--validate-log %r carries no `validate:` summary line and no collision "
            "verdict — refusing to report a zero I cannot substantiate. Did "
            "fleet-import.sh actually reach the validate step?" % path)
    return class_a, class_b


def significant_words(text: str) -> set:
    return {w for w in WORD_RE.findall((text or "").lower()) if w not in STOPWORDS}


def repo_of(uid: str) -> str:
    return uid.split("/", 1)[0]


def cross_refs(item: dict, sibling_repos, token: str):
    """Evidence that `item` points at one of `sibling_repos` (the OTHER minters)."""
    hits = []
    text = "%s %s" % (item.get("title") or "", item.get("body") or "")
    low = text.lower()

    for ln in item.get("links") or []:
        if ln.get("token") == token:
            hits.append("edge `%s:%s` on the SHARED token" % (ln.get("kind"), token))
        tgt = ln.get("target_uid")
        if tgt and repo_of(tgt) in sibling_repos:
            hits.append("edge `%s` -> %s" % (ln.get("kind"), tgt))

    for field in ("blocked_by", "children"):
        for other in item.get(field) or []:
            if isinstance(other, str) and "/" in other and repo_of(other) in sibling_repos:
                hits.append("`%s` -> %s" % (field, other))
    parent = item.get("parent")
    if isinstance(parent, str) and "/" in parent and repo_of(parent) in sibling_repos:
        hits.append("`parent` -> %s" % parent)

    for sib in sibling_repos:
        # Word-boundary-ish: repo names contain '-', so \b on the ends is enough.
        if re.search(r"(?<![\w-])%s(?![\w-])" % re.escape(sib.lower()), low):
            hits.append("prose mentions repo %r" % sib)

    return hits


def truncate(s: str, n: int) -> str:
    s = " ".join((s or "").split())
    if not s:
        return "(no title)"
    return s if len(s) <= n else s[: n - 1] + "…"


def md_cell(s: str) -> str:
    return s.replace("|", "\\|")


def status_blurb(it: dict) -> str:
    bits = []
    for view in ("todo", "roadmap", "review"):
        st = it.get("%s_status" % view)
        if st and st != "absent":
            bits.append("%s=%s" % (view, st))
    if it.get("archived"):
        bits.append("archived")
    return ", ".join(bits) or "no view"


def source_blurb(it: dict) -> str:
    return ", ".join("%s:%s" % (s.get("file"), s.get("line"))
                     for s in (it.get("sources") or [])[:3]) or "(no source)"


def document_frequency(items):
    """How many items each significant word occurs in, over the whole fleet.

    A RAW shared-word count is useless as a relatedness signal: every relay ledger item
    is full of the same boilerplate ("acceptance", "done-check", "green", "relay",
    "meeting"), so two utterly unrelated items reliably share half a dozen words. Only a
    RARE shared word is evidence, and rarity has to be measured against this fleet's own
    vocabulary rather than guessed at with a hand-written stopword list.
    """
    df = {}
    for it in items:
        for w in significant_words("%s %s" % (it.get("title") or "", it.get("body") or "")):
            df[w] = df.get(w, 0) + 1
    return df


def analyse(doc: dict, class_a: dict, title_chars: int):
    items_all = doc.get("items", [])
    df = document_frequency(items_all)
    # A word is RARE if it occurs in at most 0.5% of items (floor 3, so a small fleet
    # does not make every word "rare"). Two rare words in common is the flag.
    rare_max = max(3, int(0.005 * max(1, len(items_all))))
    by_uid = {i["uid"]: i for i in items_all if i.get("uid")}
    rows = []
    for tok in sorted(class_a):
        repos = class_a[tok]
        members = [by_uid[u] for u in sorted(by_uid)
                   if by_uid[u].get("id") == tok and by_uid[u].get("repo") in repos]
        entries = []
        any_ref = False
        for it in members:
            sibs = {r for r in repos if r != it.get("repo")}
            hits = cross_refs(it, sibs, tok)
            any_ref = any_ref or bool(hits)
            entries.append({"item": it, "hits": hits})
        shared = None
        for e in entries:
            w = significant_words("%s %s" % (e["item"].get("title") or "",
                                             e["item"].get("body") or ""))
            shared = w if shared is None else (shared & w)
        shared = sorted(w for w in (shared or ()) if df.get(w, 0) <= rare_max)
        # Two independent flags. EITHER makes the token "needs a look"; neither makes it
        # a likely birthday collision. Deliberately generous — a false "needs a look"
        # costs the owner one glance, a false "coincidence" costs a wrong adjudication.
        overlap_flag = len(shared) >= 2
        rows.append({
            "token": tok, "repos": repos, "entries": entries,
            "shared_words": shared, "cross_ref": any_ref,
            "needs_look": any_ref or overlap_flag,
            "titles": [truncate(e["item"].get("title") or "", title_chars)
                       for e in entries],
        })
    return rows


def render(rows, class_b, doc, live_allow, validate_log, fleet_path):
    n_a, n_b = len(rows), len(class_b)
    look = [r for r in rows if r["needs_look"]]
    easy = [r for r in rows if not r["needs_look"]]
    n_repos = len(doc.get("repos", []))
    n_items = len(doc.get("items", []))

    o = []
    w = o.append
    w("# Cross-repo homonym adjudication worksheet")
    w("")
    w("> GENERATED by `tracker/homonym-worksheet.sh` (TODO id:e977). Do not hand-edit — "
      "re-run it. **Nothing here is adjudicated.** The decision is the owner's, one "
      "token at a time (id:ca24).")
    w("")
    w("| | |")
    w("|---|---|")
    w("| fleet | %d repos, %d items (incl. archived) |" % (n_repos, n_items))
    w("| class A (homonym, adjudicable) | **%d** |" % n_a)
    w("| class B (ambiguous cross-repo edge, NEVER adjudicable) | **%d** |" % n_b)
    w("| already on the live allow-list | %d |" % len(live_allow))
    w("| needs a look (cross-reference and/or shared vocabulary) | **%d** |" % len(look))
    w("| looks like a birthday collision (no signal at all) | %d |" % len(easy))
    w("| derived from | `%s` + `%s` |" % (os.path.basename(fleet_path),
                                          os.path.basename(validate_log)))
    w("")
    w("A class-A homonym is the same bare 4-hex token minted independently in two repos. "
      "The composite `(repo,id)` key already disambiguates it, so at ~%d ids over a "
      "65 536-token space a collision is EXPECTED and usually harmless. The question to "
      "answer per token is only: **same thing, or coincidence?** The two evidence "
      "columns below are what distinguishes them — a cross-reference means the two items "
      "may be one piece of work that was never marked up." % n_items)
    w("")

    if class_b:
        w("## Class B — NOT adjudicable, fix the edge")
        w("")
        for tok in sorted(class_b):
            w("- `%s` — repos %s. A cross-repo `routed:` edge on this token cannot "
              "resolve to one `(repo,id)`. The allow-list does not and will not "
              "downgrade this." % (tok, ", ".join(class_b[tok])))
        w("")
    else:
        w("## Class B — none")
        w("")
        w("No ambiguous cross-repo edge in this cut. Class B is fatal and unadjudicable "
          "by design; zero is the expected healthy value.")
        w("")

    w("## A. Needs a look (%d)" % len(look))
    w("")
    if not look:
        w("None — no token carries a cross-reference or shared vocabulary.")
        w("")
    for r in look:
        why = []
        if r["cross_ref"]:
            why.append("CROSS-REFERENCE")
        if len(r["shared_words"]) >= 2:
            why.append("shared vocabulary: %s"
                       % ", ".join("`%s`" % x for x in r["shared_words"][:8]))
        w("### `%s` — %s" % (r["token"], "; ".join(why)))
        w("")
        for e in r["entries"]:
            it = e["item"]
            w("- **%s** — %s" % (it["uid"], md_cell(truncate(it.get("title") or "", 220))))
            w("  - %s · %s" % (status_blurb(it), source_blurb(it)))
            for h in e["hits"]:
                w("  - **references sibling:** %s" % h)
        w("")

    w("## B. Looks like a birthday collision (%d)" % len(easy))
    w("")
    w("No cross-reference in either direction and <2 shared significant words. These are "
      "the candidates for a bulk confirmation — but the confirmation is still yours.")
    w("")
    w("| token | (repo, id) | titles |")
    w("|---|---|---|")
    for r in easy:
        uids = "<br>".join("`%s`" % e["item"]["uid"] for e in r["entries"])
        titles = "<br>".join(md_cell(t) for t in r["titles"])
        w("| `%s` | %s | %s |" % (r["token"], uids, titles))
    w("")

    w("## How to adjudicate")
    w("")
    w("1. Read the token's rows above. Ask only: *are these two items the same piece of "
      "work?*")
    w("2. **Coincidence** → accept it: the composite key already disambiguates. Confirm "
      "the token in the draft allow-list by deleting its `# UNCONFIRMED ` prefix.")
    w("3. **Actually related** → do NOT allow-list it. Mark the relationship up in the "
      "ledgers (a `routed:`/`gated-on:` edge), or renumber one side with a fresh id from "
      "`meeting/append.sh new-id`.")
    w("4. Move confirmed lines into `tracker/homonym-allowlist.txt`. A line still "
      "carrying `# UNCONFIRMED ` parses as a comment, so a draft pasted wholesale stays "
      "STRICT — it can never accept a token by accident.")
    w("")
    return "\n".join(o) + "\n"


def render_draft(rows, live_allow):
    o = []
    w = o.append
    w("# DRAFT homonym allow-list — GENERATED by tracker/homonym-worksheet.sh (id:e977).")
    w("#")
    w("# NOTHING HERE IS ADJUDICATED. Every token is commented out behind an")
    w("# `# UNCONFIRMED ` marker, so this file — pasted verbatim into")
    w("# tracker/homonym-allowlist.txt — still parses as an EMPTY (STRICT) allow-list.")
    w("#")
    w("# A human accepts ONE token by deleting the `# UNCONFIRMED ` prefix on its line")
    w("# (id:ca24, owner-decided 2026-08-10). Sections mirror the worksheet: section A")
    w("# tokens carry a cross-reference and/or shared vocabulary and should be READ")
    w("# before any of them is accepted.")
    w("")
    for label, pred in (("A — NEEDS A LOOK (cross-reference and/or shared vocabulary)",
                         lambda r: r["needs_look"]),
                        ("B — looks like a birthday collision (no signal)",
                         lambda r: not r["needs_look"])):
        sel = [r for r in rows if pred(r)]
        w("# ---- %s: %d ----" % (label, len(sel)))
        for r in sel:
            note = "cross-ref" if r["cross_ref"] else (
                "shared: %s" % ",".join(r["shared_words"][:4]) if r["shared_words"]
                else "no signal")
            w("# UNCONFIRMED %s  # %s — %s" % (r["token"], ", ".join(r["repos"]), note))
            for e in r["entries"]:
                w("#     %s: %s" % (e["item"]["uid"], truncate(e["item"].get("title") or "", 96)))
        w("")
    if live_allow:
        w("# ---- already accepted in the live allow-list (unchanged, shown for context) ----")
        for t in sorted(live_allow):
            w("%s" % t)
        w("")
    return "\n".join(o) + "\n"


def read_allowlist(path):
    toks = set()
    if not path or not os.path.exists(path):
        return toks
    for line in open(path, encoding="utf-8"):
        line = line.split("#", 1)[0].strip()
        if re.fullmatch(r"[0-9a-f]{4}", line):
            toks.add(line)
    return toks


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--fleet", required=True)
    ap.add_argument("--validate-log", required=True)
    ap.add_argument("--out-worksheet", required=True)
    ap.add_argument("--out-draft", required=True)
    ap.add_argument("--allowlist", default=None)
    ap.add_argument("--title-chars", type=int, default=110)
    args = ap.parse_args()

    try:
        doc = json.load(open(args.fleet, encoding="utf-8"))
    except (OSError, ValueError) as exc:
        die("--fleet: %s" % exc)

    class_a, class_b = parse_validate_log(args.validate_log)
    live_allow = read_allowlist(args.allowlist)
    rows = analyse(doc, class_a, args.title_chars)

    missing = [r["token"] for r in rows if len(r["entries"]) < 2]
    if missing:
        die("validate reported %d homonym token(s) the fleet document does not carry in "
            ">=2 repos (%s) — the log and the document are out of step; refusing to "
            "render a worksheet from a mismatched pair."
            % (len(missing), ", ".join(missing)))

    for path, text in ((args.out_worksheet,
                        render(rows, class_b, doc, live_allow, args.validate_log,
                               args.fleet)),
                       (args.out_draft, render_draft(rows, live_allow))):
        d = os.path.dirname(os.path.abspath(path))
        if d:
            os.makedirs(d, exist_ok=True)
        tmp = "%s.tmp.%d" % (path, os.getpid())
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(tmp, path)

    look = sum(1 for r in rows if r["needs_look"])
    sys.stderr.write(
        "homonym-worksheet: class A=%d (needs a look: %d, birthday-collision: %d), "
        "class B=%d — %s\n"
        % (len(rows), look, len(rows) - look, len(class_b), args.out_worksheet))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
