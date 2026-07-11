#!/usr/bin/env python3
"""handback-followup.py — durable follow-up for a relay HANDBACK (id:3801).

When a strong child hands back an item (size-out / decision-gated / needs-human), its
judgment used to evaporate into RELAY_STATUS for one run — so the pool re-dispatched the
SAME un-doable item every run (the d61a 4×-rerun, the f14f size-out). This makes the
handback DURABLE in the repo's ROADMAP.md, under the same id-ecosystem (single-id-two-views):

  route=decision-gate / human  → re-tag the parent item to the classifier-EXCLUDED tag
                                 `[HARD — decision gate]` (id:2d20) with an inline reason,
                                 so the pool stops dispatching it until a /meeting (or
                                 /relay human) resolves it.
  route=hard-split             → gate the parent AND append the child's recommended seam
                                 sub-items as individually-pickable `- [ ]` units (reuse
                                 provided ids, mint missing via append.sh), each noting its
                                 dependency — so the work moves forward one seam at a time.
  route=none                   → no-op (surfaced in RELAY_STATUS as before).

Idempotent: re-running on the same handback makes NO further change (a parent already
`[HARD — decision gate]` is left untouched — this also respects a human's manual gate;
a seam whose id already exists is skipped). All writes go through the flock'd
`meeting/md-merge.py update-ids` (atomic, re-reads under lock) — never a raw rewrite —
and commit+push via `git-lock-push.sh --ff-only` (manifest mode, ROADMAP.md only),
the same main-checkout ledger write-back path as /meeting / /relay human (id:15d5).

This is a CLAIM the next review re-checks (anti-gaming, id:3801 fork e): the gate is
reversible (a human/meeting re-tags it back to [ROUTINE]/[HARD — strong model]).

Usage:
  handback-followup.py <repo-root> --parent-id XXXX --route <decision-gate|hard-split|human|none>
                       [--gate-reason TEXT] [--split-json '[{...}]'] [--run-id ID] [--no-commit]
  --split-json items: [{"title": "...", "id": "be4b"?, "tier": "HARD"|"ROUTINE"?, "dep": "be4b"?}, ...]
Env: HANDBACK_ROADMAP overrides <repo-root>/ROADMAP.md; HANDBACK_NO_COMMIT=1 == --no-commit (tests).
"""
import argparse
import json
import os
import re
import subprocess
import sys

GATE_TAG = "[HARD — decision gate]"          # the exact classifier-excluded tag (id:2d20)
TIER_RE = re.compile(r"\[(?:ROUTINE|HARD[^\]]*)\]")  # first tier tag on a line
ID_RE = lambda tok: re.compile(r"<!--\s*id:" + re.escape(tok) + r"\s*-->")
SKILLS = os.path.expanduser("~/.claude/skills")


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def find_line(lines, tok):
    rx = ID_RE(tok)
    for ln in lines:
        if rx.search(ln):
            return ln.rstrip("\n")
    return None


def gate_line(line, reason, route):
    """Re-tag a parent item line to the decision-gate tag + inline reason (idempotent)."""
    if GATE_TAG in line:
        return None  # already gated (auto OR manual) — leave it untouched
    note = f" — 🚧 GATED (auto, id:3801; route:{route}): {reason}".rstrip()
    # swap the tier tag; if none present, inject a bold tag right after the checkbox.
    if TIER_RE.search(line):
        new = TIER_RE.sub(GATE_TAG, line, count=1)
    else:
        new = re.sub(r"(- \[ \]\s*)", r"\1**" + GATE_TAG + "** ", line, count=1)
    # insert the note right after the FIRST id comment (id:1b1a — the id comment is
    # not always line-terminal, e.g. `<!-- id:78ff --> <!-- xledger-ok: ... -->`; a
    # `$`-anchored match silently no-ops on those lines instead of gating them).
    return re.sub(r"(<!--\s*id:[0-9a-f]{4}\s*-->)",
                  lambda m: m.group(1) + note, new, count=1)


def mint_id(repo_root):
    r = sh([os.path.join(SKILLS, "meeting", "append.sh"), "new-id", repo_root])
    tok = (r.stdout or "").strip().split()[-1] if r.stdout.strip() else ""
    if not re.fullmatch(r"[0-9a-f]{4}", tok):
        raise RuntimeError(f"append.sh new-id returned no token: {r.stdout!r} {r.stderr!r}")
    return tok


def seam_line(item, parent_id, repo_root, existing_ids, lines_text):
    tok = (item.get("id") or "").strip()
    title = item.get("title", "").strip() or "(untitled seam)"
    marker = f"seam of id:{parent_id}"
    if tok and tok in existing_ids:
        return None, tok  # idempotent: explicit-id seam already in the file
    if not tok:
        # title-dedup for an id-less seam: if a seam with this title already exists under
        # this parent's marker, reuse it (DON'T re-mint a duplicate on a later re-run).
        for L in lines_text.splitlines():
            if marker in L and title in L:
                m = re.search(r"id:([0-9a-f]{4})", L)
                return None, (m.group(1) if m else "exists")
        tok = mint_id(repo_root)
    tier = (item.get("tier") or "HARD").upper()
    tag = "**[ROUTINE]**" if tier == "ROUTINE" else "**[HARD — strong model]**"
    dep = (item.get("dep") or "").strip()
    dep_clause = f" (after id:{dep})" if dep else ""
    title = item.get("title", "").strip() or "(untitled seam)"
    line = f"- [ ] {tag} {title}{dep_clause} — seam of id:{parent_id} (auto, id:3801) <!-- id:{tok} -->"
    return line, tok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("repo_root")
    ap.add_argument("--parent-id", required=True)
    ap.add_argument("--route", required=True,
                    choices=["decision-gate", "hard-split", "human", "none"])
    ap.add_argument("--gate-reason", default="")
    ap.add_argument("--split-json", default="")
    ap.add_argument("--run-id", default="")
    ap.add_argument("--no-commit", action="store_true")
    a = ap.parse_args()

    if a.route == "none":
        print("route=none — nothing durable to write")
        return 0

    repo = os.path.abspath(os.path.expanduser(a.repo_root))
    roadmap = os.environ.get("HANDBACK_ROADMAP") or os.path.join(repo, "ROADMAP.md")
    if not os.path.exists(roadmap):
        print(f"no ROADMAP at {roadmap} — nothing to do (non-fatal)", file=sys.stderr)
        return 0
    with open(roadmap) as f:
        lines = f.readlines()
    existing_ids = set(re.findall(r"<!--\s*id:([0-9a-f]{4})\s*-->", "".join(lines)))

    parent = find_line(lines, a.parent_id)
    if parent is None:
        print(f"parent id:{a.parent_id} not found in {roadmap} — nothing to do (non-fatal)",
              file=sys.stderr)
        return 0

    updates = []
    reason = a.gate_reason.strip() or "handed back by a strong child as not single-turn-doable"

    if a.route in ("decision-gate", "human"):
        r = reason + (" — needs /relay human" if a.route == "human" else " — needs a /meeting")
        gated = gate_line(parent, r, a.route)
        if gated is None:
            print(f"id:{a.parent_id} already gated — idempotent no-op")
        else:
            updates.append({"id": a.parent_id, "line": gated})

    elif a.route == "hard-split":
        try:
            split = json.loads(a.split_json) if a.split_json else []
        except json.JSONDecodeError as e:
            print(f"bad --split-json: {e}", file=sys.stderr)
            return 2
        seam_ids = []
        lines_text = "".join(lines)
        for item in split:
            line, tok = seam_line(item, a.parent_id, repo, existing_ids, lines_text)
            seam_ids.append(tok)
            if line is not None:
                updates.append({"id": tok, "line": line})
                existing_ids.add(tok)
        # gate the parent as DECOMPOSED (do not pick directly); idempotent.
        r = f"DECOMPOSED into seams {', '.join('id:' + s for s in seam_ids)} — pick those, not this. {reason}"
        gated = gate_line(parent, r, "hard-split")
        if gated is not None:
            updates.append({"id": a.parent_id, "line": gated})

    if not updates:
        print("no changes needed (fully idempotent)")
        return 0

    do_commit = not (a.no_commit or os.environ.get("HANDBACK_NO_COMMIT") == "1")
    msg = (f"roadmap: durable handback follow-up for id:{a.parent_id} "
           f"(route={a.route}, id:3801)"
           + (f"\n\nrun={a.run_id}" if a.run_id else ""))

    # id:e5e9 (seed invalid-state i; relay-doctor check 9 / invariant I1) — write AND commit
    # ATOMICALLY under md-merge's flock (the id:148b/id:2147 pattern) when committing, so a death
    # between the write and the commit can never strand a dirty ROADMAP.md on the main checkout.
    # PREVIOUSLY this was TWO steps — md-merge write-only, THEN git-lock-push manifest commit —
    # with a stranding window between them (the loderite id:3801 residue that motivated id:4da4).
    # In no-commit mode, write only (the deliberate dry path).
    merge_cmd = [sys.executable, os.path.join(SKILLS, "meeting", "md-merge.py"),
                 "update-ids", "--file", roadmap]
    if a.route == "hard-split":
        # id:1b1a — md-merge's update-ids now fails LOUD on an unmatched id by
        # default; hard-split is the only route that mints genuinely NEW seam
        # ids, so it alone opts in to the append behaviour.
        merge_cmd += ["--allow-new"]
    if do_commit:
        merge_cmd += ["--commit", msg]
    merge = sh(merge_cmd, input=json.dumps({"updates": updates}))
    if merge.returncode != 0:
        print(f"md-merge failed: {merge.stderr}", file=sys.stderr)
        return 1
    print(f"id:{a.parent_id} route={a.route}: {len(updates)} ROADMAP line(s) written"
          + (" + committed" if do_commit else ""))

    if not do_commit:
        return 0

    # The ROADMAP.md change is ALREADY committed (atomically, above) — only the pull+push needs
    # serialization now. git-lock-push LEGACY mode (no -f/-m) pushes the already-committed HEAD
    # (--ff-only for the tag/merge-safe integration branch). A push failure here is NON-FATAL:
    # the commit is safe locally (no residue), the next push catches it up. The push-script path
    # honors HANDBACK_GIT_LOCK_PUSH so a hermetic death-simulation test can stub it (id:e5e9).
    push_sh = os.environ.get("HANDBACK_GIT_LOCK_PUSH") or os.path.expanduser(
        "~/.claude/skills/git-diary-workflow/git-lock-push.sh")
    gp = sh([push_sh, repo, "--ff-only"])
    sys.stdout.write(gp.stdout)
    if gp.returncode != 0:
        print(f"git-lock-push non-zero (committed-locally/non-fatal): {gp.stderr}",
              file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
