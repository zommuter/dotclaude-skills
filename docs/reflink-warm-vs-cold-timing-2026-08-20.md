# Reflink warm-vs-cold copy timing on build-dep repos (H3)

**Item:** ROADMAP `id:3c9d` (`[HARD] [INTENSIVE — disk-io]`). Measure-only, no code change.
**Date:** 2026-08-20. **Host:** zomni (Manjaro, `/home` on **btrfs**, NVMe). Measured under an
exclusive `resource:disk-io` relay lease (no competing disk churn).
**Design source:** `id:d03d` / meeting `docs/meeting-notes/2026-07-21-1518-who-may-write-realremotes-uid-scoping.md`
(H3 amendment). Gates the d03d **fleet migration** and `id:ca9e` (the single-repo pilot).

## What premise this tests

The d03d real-remotes topology proposes copying a repo per executor via
`cp -a --reflink=always` instead of `git worktree add`. The **reflink economic premise** (H3,
metric ii) is that a reflink copy is cheaper than a `git clone --local --no-hardlinks` **on a
build-dep repo**, because reflink brings the *warm* working tree (`node_modules`/`.venv`) along
at O(metadata) CoW cost, whereas the clone produces a *cold* tree that must be re-warmed.
dotclaude-skills has no build deps and structurally cannot test this — hence this standalone
measurement on real build-dep repos.

Two representative repos were chosen to bracket dep weight:

| Repo | Total | `.venv` | `.git` | Dep character |
|---|---|---|---|---|
| `zkm-ner` | 345 MB | 341 MB | 1.9 MB | **heavy** — spaCy + de/en language-model wheels, native builds; **not** offline-satisfiable |
| `zkm-stt` | 115 MB | 106 MB | 620 KB | **light** — pure-Python (`requests`, `python-frontmatter`, editable `zkm`) |

## Method

For each repo, OS page-cache primed once (`tar cf /dev/null`), then 3 iterations of each copy
method, destinations on the same btrfs `/home` filesystem. Rebuild cost of a cold clone measured
separately with `uv sync`, preserving the `zkm = {path=../..}` editable layout. Timings are
wall-clock seconds.

- **reflink** = `cp -a --reflink=always <src> <dst>` — the d03d D2 mechanism. Result: **warm** tree.
- **clone** = `git clone --local --no-hardlinks <src> <dst>` — the non-btrfs fallback. Result: **cold** tree.
- **plain-cp** = `cp -a --reflink=never <src> <dst>` — control: real byte copy, no CoW.
- **rebuild** = `uv sync` in a cold clone — the cost of re-warming what the clone dropped.

## Results

### Copy timings (seconds, 3 iterations)

| Repo | reflink (→warm) | clone (→cold) | plain-cp (control) |
|---|---|---|---|
| `zkm-ner` | 0.125 / 0.149 / 0.145 | 0.033 / 0.020 / 0.020 | 1.132 / 0.260 / 0.289 |
| `zkm-stt` | 0.060 / 0.044 / 0.043 | 0.013 / 0.011 / 0.011 | 0.401 / 0.105 / 0.114 |

### Tree warmth and disk cost (iteration 1)

| Repo | reflink `.venv` present | clone `.venv` present | reflink disk (btrfs `du -s`) | clone disk |
|---|---|---|---|---|
| `zkm-ner` | **YES** | no | 0 B exclusive / 220 MiB shared | 2.2 MB |
| `zkm-stt` | **YES** | no | 0 B exclusive / 93 MiB shared | 1.1 MB |

The reflink copy is **fully CoW-shared** — zero *exclusive* disk — so it materializes the entire
warm tree at metadata cost. The clone copies only the git objects (no `.venv`).

### Re-warming a cold clone (`uv sync`)

| Repo | offline (warm 43 GB uv cache) | online |
|---|---|---|
| `zkm-stt` (light) | **0.27 s** | — |
| `zkm-ner` (heavy) | **UNSATISFIABLE** (network required) | **16.08 s** |

## Verdict on the reflink economic premise

**The premise as literally worded — "reflink copy cheaper than cold clone" — is FALSE at the
copy step alone.** `git clone --local` is consistently *faster to copy* (0.02 s vs 0.14 s on
`zkm-ner`): it moves only ~2 MB of git objects, while reflink must create CoW metadata across
the whole 345 MB tree. Choosing reflink on raw copy-time grounds would be backwards.

**But the premise is CORRECT in substance once tree warmth is priced in.** The reflink copy is
immediately usable (warm `.venv`, 0 exclusive disk); the clone is cold and must be re-warmed by
`uv sync`. The reflink win is exactly *the rebuild cost avoided*, and that cost is dominated by
dep weight and uv-cache warmth — not by copy time:

- **Heavy / network-bound deps (`zkm-ner`, and the fleet's real targets like `llm-from-scratch`):
  ACCEPT.** Reflink turns a 16 s online rebuild — one that is *offline-unsatisfiable*, i.e. it
  also introduces a hard network dependency — into a 0.14 s local copy at zero exclusive disk.
  A ~115× wall-clock win plus removal of the network dependency. Decisive.
- **Light pure-Python deps with a warm uv cache (`zkm-stt`): REJECT as a blanket justification.**
  Clone (0.01 s) + `uv sync --offline` (0.27 s) ≈ 0.28 s, the same sub-second order as reflink
  (0.05 s). Here the "warm tree" advantage is negligible and does not justify coupling to btrfs.

**Recommendation for the d03d fleet-migration decision (`id:d03d`/`id:ca9e`, owner's call):**
adopt reflink **weighted by per-repo rebuild cost**, not uniformly. The economic case is real and
strong for heavy/native/network-bound repos and thin for light cache-hit repos. Two independent
caveats bound it: (1) reflink requires **btrfs + same-fs** — fievel (Raspbian) cannot reflink, so
its fallback *is* the expensive cold-clone-plus-rebuild path, which is precisely where heavy repos
hurt most; (2) the offline-unsatisfiable result means a cold clone's rebuild can *fail* without
network, whereas the warm reflink copy never needs one. Both push the same way: reflink's value is
highest exactly where a rebuild is slow or impossible, so the migration should target those repos
first and is not licensed as a uniform copy-time optimization.

## Reproduction

Harness: `cp -a --reflink=always` vs `git clone --local --no-hardlinks` vs `cp -a --reflink=never`,
3 iterations, OS cache primed, destinations on btrfs `/home`; `btrfs filesystem du -s` for CoW
sharing; `uv sync` (offline then online) in a cold clone with the editable-`zkm` path preserved.
All copies were made outside any git repo and removed after timing (measure-only, no repo state
touched).
