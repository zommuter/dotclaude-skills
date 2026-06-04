# 2026-06-04 — Haiku-vs-Sonnet builder pilot

**Started:** 2026-06-04 13:00
**Session:** beebb22b-e3b3-4f77-b7d8-b293dea0f5c0
**Mode:** Class 2 planning record (no meeting was held — plan-mode output)
**Topic:** Run Haiku and Sonnet on 3 real impl-ready items with disjoint footprints; score each diff blind against its Contract line; decide D6 builder tier.

## Context

This is D6 build-gate #3. D6.3 (in `2026-06-04-1048-subagent-parallel-class1.md`) decided
"Sonnet builds + Sonnet verifies" but explicitly gated Haiku-as-builder behind a pilot.
The pilot also smoke-tests the worktree-per-item substrate (D6.2) and the merge-and-salvage
flow (D6.4) — structure mirrors what the real D6 dispatcher will run.

## Plan

Three items selected for disjoint footprint + difficulty spread:

| Item | File | Class | Contract |
|---|---|---|---|
| `fbcd` | `.gitattributes` (new) | TRIVIAL | concurrent-branch appends to personas.md union-merge |
| `9ff2` | `meeting/broker-mode.md` | SMALL-BUG | posting a `'`-containing line does not fail shell quoting |
| `3e35` | `git-diary-workflow/git-lock-push.sh` | LOGIC-HEAVY | two concurrent sessions commit only their own files; serialise |

`d00e` excluded (behaviorally coupled to 3e35; would violate disjoint-footprint rule).

**Phases:** 6 parallel builder agents (isolation: worktree) → 6 blind Sonnet verify agents →
synthesis + tier decision → salvage winning diffs via `--no-ff` merge.

## Implementation findings

### fbcd — .gitattributes merge=union

Both models produced **identical one-line output** (`meeting/personas.md merge=union`). No
discrimination possible at TRIVIAL difficulty.

Verifier verdict (both): CONTRACT_MET: yes, QUALITY: 4/5. Risk: line ordering not guaranteed;
only covers this repo's personas.md (DIARY.md / MEMORY.md require separate .gitattributes in
their respective repos).

**Salvaged:** pilot/fbcd-sonnet merged to main.

### 9ff2 — broker-mode jq apostrophe fix

Both models updated all three call sites (event, question, response) in broker-mode.md from
raw single-quoted JSON literals to `jq -n --arg` patterns. Functionally equivalent.

**Qualitative difference:** Sonnet placed the shell-quoting warning BEFORE the Discussion
section (upfront rule, then examples); Haiku placed it AFTER. Sonnet's placement is better
for skimmability — establishes the pattern once before the per-case instructions reference it.
Verifier score: both 4/5.

Residual gap (both models): the question example uses `--argjson options '<options-array>'`
which shows the pattern for a JSON array arg but doesn't show how to safely construct the
options array value when it contains persona-controlled text. Minor doc gap, not a contract
failure.

**Salvaged:** pilot/9ff2-sonnet merged to main.

### 3e35 — git-lock-push.sh manifest-scoped stage+commit

**Haiku — CRITICAL BUG:**
`git add "$manifest_file"` stages the manifest file itself (e.g. `/tmp/session.manifest`)
rather than reading the file and staging the paths listed inside it. Contract fails entirely.
Verifier: CONTRACT_MET: no, QUALITY: 2/5.

**Sonnet — CORRECT:**
Uses a `while IFS= read -r path` loop to stage each listed path individually with
`git add -- "$path"`. Adds a manifest-file-existence check with proper lock release on error.
Handles: last line without newline, empty lines, paths with spaces.
Verifier: CONTRACT_MET: yes, QUALITY: 4/5.
Residual risk: `git add` of a nonexistent listed path silently no-ops — session could commit
fewer files than intended without error. Not data-corrupting; acceptable.

**Salvage deferred:** 3e35 contract only fully holds with d00e (caller-side manifest staging)
also landed. The Sonnet diff is recorded here for reference; ship as a joint 3e35+d00e session.

Sonnet 3e35 diff (for reference, do not merge standalone):
```diff
@@ -1,20 +1,33 @@
 #!/usr/bin/env bash
-# git-lock-push.sh — flock-serialized git pull --rebase + push
+# git-lock-push.sh — flock-serialized (stage+commit +) pull --rebase + push
 #
-# Run AFTER git commit — the commit is local and safe;
-# only the pull+push needs serialization.
+# Two modes:
+#   Legacy mode (no -f): Run AFTER git commit
+#   Manifest mode (-f <file> -m <msg>): stage+commit+pull+push inside flock
+#     Only the listed paths are staged (no git add -A).
+#
+# Usage: git-lock-push.sh [REPO_PATH] [-b branch] [-f manifest-file] [-m msg]
 ...
+while getopts "b:f:m:" opt; do
+    f) manifest_file="$OPTARG" ;;
+    m) commit_msg="$OPTARG" ;;
+if [[ -n "$manifest_file" && -z "$commit_msg" ]]; then ... fi
+if [[ -n "$commit_msg" && -z "$manifest_file" ]]; then ... fi
+if [[ -n "$manifest_file" ]]; then
+  if [[ ! -f "$manifest_file" ]]; then exec 8>&-; exit 1; fi
+  while IFS= read -r path || [[ -n "$path" ]]; do
+    [[ -z "$path" ]] && continue
+    git add -- "$path"
+  done < "$manifest_file"
+  git commit -m "$commit_msg"
+fi
```

## Decisions

- **Tier: Sonnet-default confirmed.** Haiku fails on LOGIC-HEAVY items (the exact class D6
  dispatches). Sonnet correctly handles all three difficulty levels. An optional Haiku-for-trivial
  split is plausible but adds complexity for negligible savings — deferred, not adopted.
  *Out of scope:* auto-tier classifier.
- **D6 build-gate #3 SATISFIED.** Pilot evidence is sufficient; further pilots not warranted
  before building the D6 dispatcher (remaining gates: #2 = ≥3 disjoint-footprint items queued).
- **Worktree substrate validated.** 6 worktree-isolated builds + 6 `--no-ff` merges ran
  cleanly. The D6.2 substrate works as designed.
- **fbcd and 9ff2 shipped as side effects.** Both salvaged from the Sonnet builds.
  3e35 deferred (joint 3e35+d00e session required).

## Action items

- [x] Haiku-vs-Sonnet builder pilot complete; tier decision recorded. <!-- id:c0d2 -->
- [ ] **3e35 + d00e joint session** — implement manifest-scoped stage+commit in `git-lock-push.sh`
  (use Sonnet diff above as starting point) + update `git-diary-workflow/SKILL.md` steps 1b/1c
  to stage from session manifest. Ship together. See `2026-06-04-1144-worktree-per-session-d5.md`.
