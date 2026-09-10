# id:0246 -- REVIEW FINDINGS, and why the implementation was REVERTED (2026-09-10)

The `id:0246` implementation landed as `6d5befed`, was adversarially reviewed, and was **REVERTED**
(`eb2587fd`) before being pushed. The library and spec are good work; the commit rewrote a
DESTRUCTIVE, unrecoverable write path by hand and walked into two failure classes the same file had
already fixed for `personas.md`. The reviewer's verdict was "would not ship".

**Why reverted rather than fixed in place:** the owner was away, `meeting/append.sh` is symlinked
into `~/.claude/skills` so its code is LIVE for every session the instant it is saved, and D2/D5/D7
below are live behaviour changes. Fixing six defects on a destructive path unattended risks a
seventh. Reverting restores a state that has been in place for months, costs only the
long-standing three-way divergence (whose worst effect, a false `RESOLVED`, fires solely on
`scan-routed --apply`, which is attended per the `id:5a5a` ruling and which the peer session is
holding off), and leaves a complete prescription for the next session.

One piece of good news measured during the review: **`~/.claude/projects/todo-inbox.md` is a REGULAR
FILE, not a symlink**, so D1 was latent rather than live.

## What the review established as SOUND -- do not redo this work

* The extractor itself survived 19 constructed false-resolution attacks: 6-hex in marker, a comment
  with a leading word, trailing words inside the comment, bare prose citation, `id:`-only marker,
  non-checkbox header -- all correctly rejected; a `YYYY-MM-DD-HHMM` timestamp, a token-shaped
  filename, no-inner-space comments, tabs, `- [X]` -- all correctly resolved through the noise.
* All three sites genuinely call it; no surviving `head -1`/`tail -1`/python own-token regex outside
  `.claude/worktrees/`.
* Both live inbox items refuse (rc 3) exactly as the owner's ruling requires, verified on a COPY.
* The declared negative case is honest, is the LAST fired FAIL line, and nothing in the spec
  survives a revert (all 9 notes fire at the parent rev).
* `id:798d` is honoured end-to-end.

## MUST FIX before re-landing, in the reviewer's order

1. **D1 HIGH -- a symlinked inbox is clobbered and the real store is never drained, exit 0.**
   `append.sh:301-302` is `mktemp` + `mv -- "$tmp" "$inbox"`, which REPLACES a symlink with a regular
   file; the canonical store keeps the "resolved" line and the store now exists twice, diverging.
   The replaced python used `path.write_text()`, which follows symlinks. **This file already fixes
   this class for `personas.md` (`id:00b1`/`id:96da`): `os.path.realpath` first, temp in the RESOLVED
   parent, `os.replace`** -- and `lock_path_for` three functions up does `readlink -f` for exactly
   this reason (`id:244f`: the install path is itself a per-file symlink). Copy that pattern.
2. **D8 (same fix) -- mode not preserved, 0664 -> 0600.** `mktemp` default with nothing restoring it.
   The personas path in this same file does `os.chmod(tmpname, perm)` for this reason.
3. **D2 HIGH -- the add path exits 1 AFTER durably appending, so a naive retry DOUBLE-FILES.**
   Measured: rc 1 with the entry on disk, retry -> 2 lines. `append.sh:28-31` documents rc-nonzero
   for `-t inbox` as "rejected, nothing appended", and a garbage entry does exactly that, so a
   caller cannot distinguish. The code comment even says "only the receipt is refused" and then
   picks the one status that denies it. Use `$OWN_ID_AMBIGUOUS` (3), as `inbox-done` does, and
   document it.
4. **D7 -- if the owning line is the only line, the drain fails silently and litters a git-tracked
   directory.** `grep -vxF` selects nothing -> exit 1 -> `set -e` kills the subshell before `mv`:
   rc 1, line survives, **stderr EMPTY**, and a stray `.inbox-done.XXXXXX` left in
   `~/.claude/projects/` (git-tracked). Today's store has a 3-line header so it cannot be the only
   line, but fixtures and any headerless store can. `grep -vxF … || [ $? -eq 1 ]`, plus a cleanup trap.
5. **D3 + D4 -- the no-silent-swallow premise is satisfied at one `echo` and defeated one level up.**
   D3: `resolved=$((resolved+1))` (`scan-routed.sh:314`) is OUTSIDE the `done_rc` branch, so with
   `inbox-done` unreachable the run printed on STDOUT `1 already-landed item(s) drained` and
   `0 finding(s)`, exit 0, while stderr said `STILL-PRESENT rc=127` and the line survived. D4: a
   refusal does `log; continue` with no `findings++` and no stdout, so a refused line can vanish into
   `clean (no dead letters; nothing to drain)` -- a false clean about a question the tool refused to
   ask. Don't count a failed drain; add a `failed_drains` counter reaching the summary AND the exit
   status; emit an `AMBIGUOUS routed:…` line on stdout with `findings++`.
6. **D9 -- spec case 8 is VACUOUS** against deleting the add-path receipt entirely: it only asserts
   stdout lacks the foreign token, so printing nothing ever passes -- including removing site 3's
   adoption. The spec's own header invokes the `id:ae08` built-but-unwired class and then fails to
   enforce it for site 3. Assert the POSITIVE receipt on a conforming entry plus a nonzero,
   named-on-stderr refusal on the ambiguous one.

## NEEDS THE OWNER -- two behaviour changes, both regressions against `d7861a6a`, both safe-direction

* **D5 -- is an INDENTED inbox line legal?** The new guard is `^-\ \[[\ xX]\]`; the python it
  replaced used `l.lstrip().startswith("- [")`. Measured on `  - [ ] …` with the twin present: parent
  drained it, HEAD leaves it and exits 0 with empty stderr -- a previously-drainable shape became
  exactly the silent no-op this item exists to kill. The file contradicts itself: the target-parse
  two lines below (`append.sh:268`) still writes `^\s*- \[`. Either tolerate the indent or refuse
  LOUDLY, but not a quiet no-op.
* **D6 -- does the multi-marker refusal extend to a line that merely CITES the token?** With a decoy
  line citing `b5b5` placed BEFORE the genuine owner: parent drained the genuine line, HEAD refuses
  rc 3 and the genuine line survives forever, with stderr claiming "ITS inbox line carries MORE THAN
  ONE anchored routed marker" while pointing at a different item's line. The owner's ruling was about
  the line that OWNS the token. Suggested: record and `continue`, refusing only if no unambiguous
  owner exists anywhere in the file.

## A FOURTH live opinion about inbox line shape -- needs its own id

`todo-conformance.sh --inbox` reports the `id:798d` LEGAL shape as `shape-prose (15 chars of prose
outside lane/gate/id/title/pointer; id:30fe)`. In one `scan-routed --apply` run the reviewer saw the
SAME line reported as non-conforming in section 1 and `RESOLVED` in section 2, counted as
`1 finding(s)` while also being drained. So the live opinions are: library owns it, `inbox-done`
drains it, `scan-routed` resolves it, `todo-conformance` calls it malformed. `id:0246` fixed three
of four.

## Latent hazards recorded, no action claimed

Uppercase token accepted by the extractor but compared case-sensitively in `inbox-done` (tokens are
minted lowercase, so not live); a line quoting its OWN marker twice refuses though every candidate
agrees (pre-existing in `own_routed_of_line`); no fenced-code-block awareness (pre-existing); the
`if [[ -f "$lib_anchored" ]]` guard at `append.sh:733` is dead code because `todo-conformance.sh:169`
sources the library unconditionally, and when the library IS absent the whole `-t inbox` write fails
rc 1 with EMPTY stderr (verified identical at the parent rev, so pre-existing); and the three
adopting sites handle exit 3 three different ways (`continue`, `exit 3`, `exit 1`) -- the
divergence-by-site shape this item exists to remove, reintroduced in the error channel.
