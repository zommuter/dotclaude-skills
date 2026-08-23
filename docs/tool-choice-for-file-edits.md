# Tool choice for file edits (auto-mode `bashFirst` scoping)

The evidence behind the short `## Tool choice for file edits` clause in the global
`~/.claude/CLAUDE.md`. That clause is deliberately terse because it is loaded into every
session of every project; the numbers, the method, and the correction history live here.

Ledger item: dotclaude-skills **`id:93b4`**. Open follow-up: **`id:efa7`** (mechanize as a
PreToolUse hook, or wait — see *Enforcement* below).

## Why the clause exists at all

Auto mode injects a standing instruction to do work through Bash (`cat`, `sed`, heredocs,
short scripts) *"rather than using the dedicated Read, Edit, or Write tools"*, falling back
*"only when Bash genuinely cannot do the job."*

That instruction is a `bashFirst` template in the CLI binary, gated on an internal feature
flag. The `autoMode` settings block (`environment` / `allow` / `soft_deny` / `hard_deny` /
`classifyAllShell`) configures the *classifier* — which shell commands are permitted — not
this guidance.

### The opt-out — `CLAUDE_CODE_THRIFTY_SONIC=0`

**Set fleet-wide** in `~/.claude/settings.json` `env` via `make install-relay-env`
(`HARNESS_ENV_DEFAULTS` in the Makefile), so it reaches every repo and every spawned
subagent, including non-interactive relay/timer sessions a shell `export` would miss.
Reported upstream in [claude-code#87575](https://github.com/anthropics/claude-code/issues/87575);
the facts below are read off the installed 2.1.237 binary, not taken on trust. The gate:

```js
function S7o(){
  if (q.CLAUDE_CODE_THRIFTY_SONIC !== void 0) return q.CLAUDE_CODE_THRIFTY_SONIC;
  switch (jBb()) {                     // bashFirstSessionAssignment()
    case "forced": return !0;
    case "none":   return !1;
    case "cohort": return nt(M6d, !1)  // A/B assignment
  }
}
```

Three properties that matter:

- **`"0"` really parses to false.** The var is registered `qe.triBool()`, falsey parser
  `["0","false","no","off"]`, truthy `["1","true","yes","on"]` — not a raw truthy string.
- **UNSET IS NOT OFF.** The env branch is guarded by `!== undefined`, so an absent entry —
  or any value outside those lists, which `triBool` maps to `undefined` — falls through to
  cohort assignment. Keep the entry present and spelled from the list.
- **Env beats the server.** It returns before the `"forced"` case, so a server-side gate
  cannot override a local setting.

**Blast radius is two call sites, both benign.** `S7o()` is consulted by `cOS`, which sets
the `bashFirst` attachment (only when the toolset has Bash *and* Edit/Write, in
`auto`/`bypassPermissions` mode); and by `TLm` → `bashFirstDescriptionTrimmed`, which
despite the generic name feeds only the **Bash tool's own description builder** —
Edit/Write/Read descriptions are untouched. Turning the flag off restores this bullet
inside the Bash tool description:

> *IMPORTANT: Avoid using this tool to run `find`, `grep`, `cat`, `head`, `tail`, `sed`,
> `awk`, or `echo` commands … use the appropriate dedicated tool … it's better to use the
> built-in tools as they provide a better user experience and make it easier to review tool
> calls and give permission.*

Both effects push the **same** direction — no countervailing collateral. It also means
`bashFirst` did two things at once: instruct the model toward Bash *and* delete the one
in-context hint arguing the other way.

### Why the four rules still stand

The escape-hatch framing is gone with the flag, but three rules never depended on it and
one gains importance:

- **shared ledgers** — about the flock, which `Edit` bypasses exactly as `sed -i` does;
  never about harness pressure.
- **protected paths** — about the permission classifier.
- **reads are cheaper from the shell** — *more* load-bearing now, because turning the flag
  off removes the harness's push toward cheap shell reads. This clause is the only thing
  carrying it.
- **edits go through Edit** — the escape-hatch framing goes; the reliability argument
  (fails ~4× less, and *loudly*) stands on its own.

## The measurement

One ~9-day window, **6,909 session transcripts**, all machines. Do not re-derive these;
cite them.

### Volume — Bash already *is* the editor

| Metric | Value |
|---|---|
| Bash calls | 44,829 of ~54,800 tool calls (**81.8%**) |
| Edit + Write calls | 4,246 |
| Bash calls that mutate a file | 5,508 (**12.3%** of Bash) |
| `python3` heredoc doing `re.sub`/`.replace` then writing back ("python-as-sed") | 682 |
| `sed -i` | 162 |

**More file edits go through Bash than through Edit + Write combined.** Any rule here is
therefore about the majority path, not an edge case.

### Reliability — the load-bearing finding

Raw error rates naively favour the shell:

| Path | Raw error rate |
|---|---|
| Edit | **11.3%** (358 / 3,175) |
| python-as-sed | **2.0%** (12 / 600) |

But categorising **all 360 Edit errors** shows **96% are guards firing, not failures**:

| Edit error class | Share |
|---|---|
| "file has not been read yet" | 88.3% |
| "target string not found" | 4.4% |
| "not unique" | 1.4% |
| "file changed underneath" | 1.1% |
| genuine failure | 16 calls |

Corrected:

| Path | True failure rate | Failure mode |
|---|---|---|
| Edit | **0.5%** | **LOUD** — refuses on a stale, ambiguous, or missing target |
| python-as-sed | **2.0%** (4× worse) | **SILENT** — no preconditions; a non-matching pattern no-ops, an over-broad one writes the wrong place |

The 4× gap understates the real difference. A python substitution has **no preconditions
at all**, so its silent-wrong-outcome rate is *not measurable from errors* — the failures
that matter most never raise anything. A fired Edit guard is information: read the file
and disambiguate. Routing around it with a script destroys that information.

### Context cost — Edit is DEARER, not cheaper

Input + `tool_result` characters per call:

| Call | Chars/call | Note |
|---|---|---|
| `Read` | **10,178** (115 in + 10,063 out) | returns the whole file; 32 MB over the window — the second-largest context consumer in the fleet |
| Bash targeted read (`cat` / `head` / `sed -n`) | **6,018** | ~40% cheaper — returns a *slice* |
| `Edit` | 1,693 | in isolation |
| Bash edit | 1,855 | in isolation |

Pricing `Edit` in isolation is wrong: **`Edit` requires a preceding `Read`**. Over the
files actually edited, 1,397 Reads enabled 3,168 Edits — **2.27 Edits amortize each
Read** — so:

> amortized `Edit` = 1,693 + (10,178 / 2.27) = **~3,711 chars**, against **1,855** for a
> Bash edit. **Edit is ~2× dearer.**

The case for Edit is **reliability, not economy**: ~2× the context buys a 4× lower failure
rate and, more importantly, failures that are loud instead of silent. Reduce the premium by
**amortizing** — Read a file once, then make all of that file's edits — never by reaching
for `sed`.

Also: **56% of (session, file) pairs touched by `Read` are never edited.** Most Read cost
is exploration, not an Edit precondition — which is why the read rule pulls the *opposite*
way from the edit rule.

**The 10,178 figure is a habit, not a floor.** `Read` accepts `offset`/`limit`, so a slice
costs what the slice costs; the fleet average is high because callers pass neither. When an
edit to that file may follow, a *bounded* `Read` dominates `sed -n`: it is equally targeted
**and** it satisfies the read-before-edit precondition, which a shell read does not. Reach
for `sed -n`/`head` when you are only looking, and for a bounded `Read` when you may edit.

**A second cost the table does not price.** Per the permission-modes documentation, *"reads
and working-directory edits outside protected paths skip the classifier, so the overhead
comes mainly from shell commands and network operations,"* and each check *"sends a portion
of the transcript plus the pending action, adding a round-trip before execution."* So in
auto mode every Bash call pays a classifier round-trip that `Read` and working-directory
`Edit` skip. That spend lands on latency and the classifier's budget rather than on this
session's context window, which is why it is absent from the table above — but it means the
~2× context premium on `Edit` is an overstatement of its true relative cost.

### Shared ledgers — the flock, not the tool

`TODO.md`, `ROADMAP.md`, `REVIEW_ME.md`, `MEMORY.md`, `personas.md`, `discoveries.md`,
`todo-inbox.md` are written by parallel sessions and are **not** `merge=union`.

Sanctioned flocked helpers:

| Helper | For |
|---|---|
| `meeting/md-merge.py` (`update-ids` / `update-sections`; `--allow-new` for a genuinely new item) | line-scoped ledger edits |
| `meeting/append.sh` | registries + the shared inbox |
| `meeting/memory-append.sh` | the `MEMORY.md` index append |
| `relay/scripts/commit-ledger.sh` | committing a ledger |

Measured: **4,608** ledger writes went through a sanctioned helper; **1,582 bypassed the
flock** — and the **larger bypass channel is the Edit/Write tool (1,100)**, not raw Bash
(482).

**"Use Edit instead of Bash" does not fix flock safety.** The Edit tool bypasses the flock
exactly as `sed -i` does. Only the helper is the fix. This is why the ledger rule is a
*separate, higher-priority tier* rather than a footnote on the edit rule.

### Protected paths

From the official permission-modes documentation, protected dirs/files include
`.claude/**`, `.git/**`, `.gitconfig`, shell rc files, `.mcp.json`, `.claude.json`.

> Writes to protected paths route to the classifier **even when an allow rule matches**.

In practice, shell commands touching them are frequently **denied** while `Read` / `Edit`
succeed — so here the dedicated tools are not merely preferred, they are the path that
works.

Separately: an agent editing `autoMode` or `permissions` config on its own initiative is
the **auto-mode-bypass class** and is correctly refused. Surface such a change for the
owner to apply; do not attempt it.

## What Bash stays right for

Running things — git, `make`, tests, scripts — pipelines, multi-file search, and **targeted
reads of large files**. The rule is about *editing files*, not about the shell. It removes
nothing from Bash's actual job.

## Correction history

Kept deliberately: each draft was wrong in a way that a reader could plausibly re-derive,
so the record is the guard against re-deriving it.

1. **"Edit is slightly cheaper than a Bash edit" (1,693 vs 1,855) — WRONG.** It priced the
   `Edit` call in isolation and ignored the *mandatory* preceding `Read`. Amortized, Edit
   is ~3,711 chars — about **2× dearer**. The honest claim is that Edit costs more and is
   worth it; the false claim was that it was free.
2. **"Edit/Read, not Bash" — WRONG, it conflated reads with edits.** Reads pull the
   opposite way: a targeted shell read (6,018 chars) is ~40% cheaper than a whole-file
   `Read` (10,178). The corrected rule is split by *operation*, not by tool family.
3. **"72% of shared-ledger writes bypass the mandated flock" — INFLATED.** The heuristic
   counted any command that merely *mentioned* a ledger filename alongside any write
   operator (e.g. `git add TODO.md && git commit`). Requiring the write to actually
   **target** the ledger corrects it to **26%**. The direction of the finding survived; the
   magnitude did not.
4. **"No setting disables it" — WRONG.** `CLAUDE_CODE_THRIFTY_SONIC=0` always existed; the
   claim was inferred from the absence of a *documented* setting and never checked against
   the binary. Re-derivable, hence kept.

## Enforcement — open

This is currently **prose**, and this repo's own precedent says prose rules fail as
enforcement: `routed:29bc` / `id:2419` had to become a blocking Stop hook before it took
effect. The corresponding question here — mechanize as a PreToolUse hook, or wait — is
**`id:efa7`**, and it is genuinely open rather than merely unstarted:

- *For mechanizing now:* the rule is deterministic on the ledger and protected-path tiers
  (path match ⇒ verdict), i.e. exactly the mechanizable half.
- *For waiting:* the clause was written to scope `bashFirst`. **That gate is now off**
  (above), so the pressure a hook would counteract is gone on this fleet — the
  constraint-archaeology case from the global CLAUDE.md design heuristics, no longer
  hypothetical. What survives the flag is the ledger/flock tier and protected paths, and
  those are the deterministic half worth mechanizing on their own merits — not as
  `bashFirst` counter-pressure.

The call is the owner's.
