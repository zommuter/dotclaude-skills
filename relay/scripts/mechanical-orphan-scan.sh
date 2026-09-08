#!/usr/bin/env bash
# mechanical-orphan-scan.sh (id:8a6b) — READ-ONLY scanner for the mechanical-orphan
# resolution loop. relay-doctor check-12 (id:1bd1) DETECTS the orphan; this is the shared
# collector the resolution half is built on. It reports two surfaced kinds, one TSV row each:
#
#   orphan  — an OPEN `- [ ]` `[MECHANICAL]` ROADMAP item whose `<!-- id:XXXX -->` token has NO
#             recipe JSON anywhere in pending/ | running/ | done/ AND no skeleton in drafts/. It
#             will never run — an Opus reviewer must author a recipe. (mechanical-orphan-draft.sh
#             turns each of these into a drafts/ skeleton.)
#   draft   — an un-promoted skeleton exists in drafts/ for one of this repo's open [MECHANICAL]
#             items but no real recipe in pending/running/done yet. A draft is NEVER executable
#             (the daemon only consumes pending/) — an Opus/human must fill its TODO placeholders
#             and deliberately promote drafts/<id>.json → pending/.
#
# Output (TSV, one surfaced item per line):
#   kind  id  repo  host  resource  detail
#     kind     = orphan | draft
#     host     = the item's `[host:<name>]` tag, or "-" if absent
#     resource = the item's `[INTENSIVE — <res>]` tag, or "-" if absent
#                (a literal "-" placeholder, NOT an empty field — consecutive empty TSV fields
#                 collapse under bash `IFS=$'\t' read` because TAB is IFS-whitespace, so an
#                 absent middle field is emitted as "-" and consumers map it back to empty.)
#     detail   = orphan → the item summary; draft → the draft file path
#
# UNION-ANCHORED (id:37ea): host/resource are read from the ROADMAP item line UNION its
# relocated detail note. `tools/ledger-shrink.py` moves an item's body prose into a per-id
# note and keeps only what `MUST_KEEP_PATTERNS` names; NEITHER `[host:…]` NOR `[INTENSIVE …]`
# is in that keep-set, and by ratified design neither will be. The tool's own comment states
# that `[INTENSIVE]` is "deliberately excluded … a consumer that anchors on it is a defect".
# So the consumer, not the keep-set, is the thing that has to widen. Without this, a shrunk
# item's host/resource silently degrades to "-" and the reviewer authors a recipe with no
# host binding (the id:d35a silent-no-op class).
#
# RECONSTRUCTION, precisely: item line + the FIRST non-blank line under the note's
# `## From ROADMAP` heading. That single line IS the pre-shrink tail of the item line, so the
# verdict here is byte-identical to what this scanner returned before the item was shrunk --
# including its over-matches (a backticked prose mention of `[INTENSIVE — <resource>]` matched
# pre-shrink too, and still does). Concatenating the WHOLE note would NOT be verdict-preserving:
# notes accumulate later sections, and a merged single-id-two-views note also carries the
# item's TODO-side prose, which was never on the ROADMAP line.
#
# The note path is READ OFF THE LINE, anchored to the item's OWN id (`…/<id>.md`, the id:1608 /
# `item_detail_path` shape), never a hardcoded directory. Hardcoding one is id:d4d3, where a
# check went silently inert in every repo spelling its notes directory differently. An item with
# no pointer on its line was never shrunk, so its tags are on the line and there is nothing to
# follow. A pointer that does NOT resolve makes the answer UNKNOWABLE: that is reported on
# stderr and the field stays "-" rather than being silently attributed to an absent tag (id:4347).
#
# Env override:
#   LEDGER_NOTE_ROADMAP_SECTION_RE  heading whose section holds relocated ROADMAP prose;
#                                   default `^## From ROADMAP\s*$` (PYTHON regex syntax, the
#                                   engine this script matches with; this fleet's
#                                   D3-ratified LOGICAL-ledger naming). Parameterised for the
#                                   same reason roadmap-lint.sh parameterises its TODO twin:
#                                   sibling repos head their notes differently, and the reader
#                                   bends rather than the corpus.
#
# Read-only: never writes, never moves, never spawns a model. Exits 0 whether or not any
# orphan/draft exists (a clean fleet prints nothing). The recipe drop-dir's `id` field is the
# only id-linkage per recipe-manifest.md (NOT filename) — matching mirrors relay-doctor check-12.
#
# Env overrides (hermetic testing — mirrors relay-doctor.sh / mechanical-daemon.sh):
#   RELAY_RECIPE_DIR  recipe root, default ~/.config/relay/recipes (pending/running/done/drafts)
#   RELAY_TOML        relay.toml path, default ~/.config/relay/relay.toml (own-repo name→path)
#   SRC_DIR           default repo parent, default ~/src
set -euo pipefail

RELAY_RECIPE_DIR="${RELAY_RECIPE_DIR:-$HOME/.config/relay/recipes}"
RELAY_TOML="${RELAY_TOML:-$HOME/.config/relay/relay.toml}"
SRC_DIR="${SRC_DIR:-$HOME/src}"
LEDGER_NOTE_ROADMAP_SECTION_RE="${LEDGER_NOTE_ROADMAP_SECTION_RE:-^## From ROADMAP\\s*$}"

RELAY_RECIPE_DIR="$RELAY_RECIPE_DIR" RELAY_TOML="$RELAY_TOML" SRC_DIR="$SRC_DIR" \
LEDGER_NOTE_ROADMAP_SECTION_RE="$LEDGER_NOTE_ROADMAP_SECTION_RE" python3 - "$@" <<'PY'
import glob, json, os, re, sys

recipe_dir = os.environ["RELAY_RECIPE_DIR"]
toml_path  = os.environ["RELAY_TOML"]
src        = os.environ["SRC_DIR"]

def expand(p):
    return os.path.expanduser(os.path.expandvars(p))

# --- own repos: name -> path (classification="own", honoring `path=` and the `# path:` comment
# override, skipping paused). Mirrors gather-human-backlog.sh's own_repos(). ---------------
def own_repos():
    try:
        import tomllib
    except Exception:
        return []
    if not os.path.exists(toml_path):
        return []
    with open(toml_path, "rb") as f:
        data = tomllib.load(f)
    comment_path, cur = {}, None
    sect_re = re.compile(r"^\s*\[repos\.([^\]]+)\]\s*$")
    path_re = re.compile(r"^\s*#\s*path:\s*(.+?)\s*$")
    # id:02fe -- a non-bare-key section name (zom.fi) is written quoted; tomllib returns it
    # UNQUOTED, so strip the delimiters here or the two never agree. chr(34)/chr(39) avoid
    # embedding a quote character in this shell heredoc.
    def _sect_name(raw):
        n = raw.strip()
        if len(n) >= 2 and n[0] == n[-1] and n[0] in (chr(34), chr(39)):
            return n[1:-1]
        return n
    with open(toml_path, encoding="utf-8") as f:
        for line in f:
            m = sect_re.match(line)
            if m:
                cur = _sect_name(m.group(1)); continue
            if cur:
                pm = path_re.match(line)
                if pm and cur not in comment_path:
                    comment_path[cur] = pm.group(1)
    out = []
    for name, entry in data.get("repos", {}).items():
        if entry.get("classification") != "own" or entry.get("paused"):
            continue
        path = entry.get("path") or comment_path.get(name) or os.path.join(src, name)
        out.append((name, expand(path)))
    return out

# --- recipe id -> where it lives (pending/running/done real recipes vs drafts) -------------
def collect_ids(subdirs):
    ids = set()
    for sub in subdirs:
        for fp in glob.glob(os.path.join(recipe_dir, sub, "*.json")):
            try:
                with open(fp, encoding="utf-8") as f:
                    rid = json.load(f).get("id")
            except Exception:
                continue
            if isinstance(rid, str) and rid:
                ids.add(rid)
    return ids

fed_ids   = collect_ids(("pending", "running", "done"))   # a REAL (possibly-consumed) recipe
draft_ids = collect_ids(("drafts",))                       # an un-promoted skeleton only

HOST_RE = re.compile(r"\[host:\s*([^\]]+?)\s*\]")
RES_RE  = re.compile(r"\[INTENSIVE\s*[—-]\s*([^\]]+?)\s*\]")
ID_RE   = re.compile(r"<!--\s*id:([0-9a-fA-F]{4})\s*-->")
OPEN_RE = re.compile(r"^\s*-\s\[\s\]\s")

# --- union anchor: the item line + its relocated `## From ROADMAP` prose (id:37ea) --------
SECTION_RE = re.compile(os.environ.get(
    "LEDGER_NOTE_ROADMAP_SECTION_RE") or r"^## From ROADMAP\s*$")
ANY_SECTION_RE = re.compile(r"^##\s")

def detail_rel_path(line, oid):
    """The item's OWN detail-note path as spelled ON the line, or None.

    Anchored to `/<oid>.md` (item_detail_path's rule): a mention of some OTHER id's note is
    prose, not this item's body. The directory is whatever the line says -- never a constant.
    """
    m = re.search(r"[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*/" + re.escape(oid) + r"\.md",
                  line, re.IGNORECASE)
    return m.group(0) if m else None

def relocated_tail(repo_path, line, oid):
    """The pre-shrink TAIL of this item line, recovered from its detail note ("" if none).

    Exactly one line: the first non-blank under the `## From ROADMAP` heading. See the header
    for why the whole note must NOT be concatenated.
    """
    rel = detail_rel_path(line, oid)
    if not rel:
        return ""                      # never shrunk: the tags, if any, are on the line
    fp = os.path.join(repo_path, rel)
    if not os.path.isfile(fp):
        # UNKNOWABLE, not absent. Say so rather than let it read as "no tag" (id:4347).
        print("mechanical-orphan-scan: WARNING - id:%s points at '%s', which does not exist; "
              "host/resource are unknowable and reported as '-'" % (oid, rel), file=sys.stderr)
        return ""
    try:
        with open(fp, encoding="utf-8") as f:
            lines = f.read().split("\n")
    except Exception:
        return ""
    heads = [i for i, l in enumerate(lines) if ANY_SECTION_RE.match(l)]
    want = [i for i in heads if SECTION_RE.match(lines[i])]
    if want:
        start = want[0]
    elif len(heads) == 1:
        # A merged single-id-two-views note with ONE section and no ROADMAP heading: the
        # item has exactly one relocated body and this is it. With two or more non-ROADMAP
        # sections there is no non-guessing answer, so read none.
        start = heads[0]
    else:
        return ""
    for j in range(start + 1, len(lines)):
        if ANY_SECTION_RE.match(lines[j]):
            break
        if lines[j].strip():
            return lines[j]
    return ""

def scan_repo(name, path):
    roadmap = os.path.join(path, "ROADMAP.md")
    if not os.path.isfile(roadmap):
        return
    with open(roadmap, encoding="utf-8") as f:
        for line in f:
            if not OPEN_RE.match(line) or "[MECHANICAL]" not in line:
                continue
            m = ID_RE.search(line)
            if not m:
                continue
            oid = m.group(1)
            hm = HOST_RE.search(line); host = hm.group(1) if hm else "-"
            rm = RES_RE.search(line);  res  = rm.group(1) if rm else "-"
            # The line stays authoritative; the note is consulted only for what the shrink
            # could have taken off the line, and only when the pointer is actually there.
            if host == "-" or res == "-":
                tail = relocated_tail(path, line, oid)
                if tail:
                    if host == "-":
                        hm2 = HOST_RE.search(tail); host = hm2.group(1) if hm2 else "-"
                    if res == "-":
                        rm2 = RES_RE.search(tail);  res  = rm2.group(1) if rm2 else "-"
            if oid in fed_ids:
                continue  # a real recipe exists (pending/running/done) — not surfaced
            if oid in draft_ids:
                draft_fp = os.path.join(recipe_dir, "drafts", f"{oid}.json")
                print("\t".join(("draft", oid, name, host, res, draft_fp)))
            else:
                summary = re.sub(r"^\s*-\s\[\s\]\s", "", line).rstrip("\n")
                summary = re.sub(r"\s+", " ", summary).strip()
                print("\t".join(("orphan", oid, name, host, res, summary)))

# argv (optional): explicit "name=path" pairs for hermetic tests; else scan relay.toml own repos.
args = sys.argv[1:]
if args:
    for a in args:
        if "=" in a:
            n, p = a.split("=", 1)
            scan_repo(n, expand(p))
else:
    for n, p in own_repos():
        if os.path.isdir(p):
            scan_repo(n, p)
PY
