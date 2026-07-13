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

RELAY_RECIPE_DIR="$RELAY_RECIPE_DIR" RELAY_TOML="$RELAY_TOML" SRC_DIR="$SRC_DIR" python3 - "$@" <<'PY'
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
    with open(toml_path, encoding="utf-8") as f:
        for line in f:
            m = sect_re.match(line)
            if m:
                cur = m.group(1); continue
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
