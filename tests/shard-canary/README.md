# shard-canary — discover-SHARD classifier behavior canary (id:3ea3)

The discover-shard classifier prompt (`relay-loop.js` `shardPrompt`) is the single
biggest relay token line (id:9cb1 — ~48% of run cost, all sonnet post-c3a6). Thinning
it is the highest-value remaining token lever, but it encodes classifier **judgment**:
the EXECUTABLE-HARD gate (id:2d20), the dirty/diverged guards (id:c3f7), and verdict
precedence (review > execute > hard > handoff > idle). So shard-prompt thinning is **not**
a zero-behavior change and must not be shipped on faith.

This canary is the safety net. It is a golden corpus of git-repo fixtures with **known
verdicts**; the harness runs the shard classifier prompt against each and asserts the
verdict it returns matches `expected`. To validate a thinned prompt, run the corpus
against it and confirm every fixture still classifies the same way.

## Before/after equivalence workflow (the point)

```bash
make shard-canary                                              # 1. baseline → all green
cp tests/shard-canary/shard-prompt.baseline.txt \
   tests/shard-canary/shard-prompt.thin.txt                    # 2. copy + thin it (edit)
tests/shard-canary/run.sh --prompt-file \
   tests/shard-canary/shard-prompt.thin.txt                    # 3. MUST still be all green
```

Only when the thinned candidate is all-green do you port it into `relay-loop.js`
`shardPrompt` and update `shard-prompt.baseline.txt` to the new wording. Keep
`shard-prompt.baseline.txt` a faithful copy of the live prompt so the corpus is
exercised against what actually ships.

## Why it is on-demand (not in `make test`)

Like `gaming-canary` (id:414a), the default path spawns a real classifier agent
(`claude -p`) and **costs tokens** — so it is **not** in `run-tests.sh`'s default sweep.
The zero-token PLUMBING (fixtures/prompt/target exist + well-formed + the harness
discriminates a wrong verdict) is guarded by `tests/test_shard_canary.sh`.

## Layout

- `shard-prompt.baseline.txt` — the current shard classifier prompt, with `{{REPOS}}`,
  `{{RUNID}}`, `{{LIVECLAIMS}}` placeholders the harness fills per fixture.
- `<fixture>/setup.sh <repodir>` — builds the git repo state (tags, ROADMAP.md, dirty
  tree, …) the classifier reads.
- `<fixture>/expected` — `review` | `execute` | `hard` | `handoff` | `idle`, or
  `surfaced:<substr>` (repo must be surfaced with a reason containing `<substr>`).

## Corpus

| fixture | state | expected |
|---|---|---|
| `review` | ckpt tag + an unaudited commit after it | `review` |
| `execute` | ckpt at HEAD, open `[ROUTINE]` | `execute` |
| `hard-executable` | ckpt at HEAD, no routine, plain `[HARD — strong model]` | `hard` |
| `hard-gated` | ckpt at HEAD, only `[HARD — decision gate]` + gated section | `surfaced:gated` (id:2d20) |
| `idle` | ckpt at HEAD, all items ticked | `idle` |
| `dirty` | ckpt at HEAD, open routine but dirty tree | `surfaced:dirty` |

`hard-gated` is the fixture most at risk from prompt thinning — it requires the model to
apply the full EXECUTABLE-HARD test and NOT dispatch a gated item. Extend the corpus
(diverged, stale-worktree, parked-orphan, handoff-no-tag) as those guards get thinned.

## Agent override

`CANARY_AGENT="<cmd>"` — a command reading the prompt on STDIN and printing the shard
JSON (`{units,surfaced,skipped}`) on STDOUT. Used for the hermetic plumbing self-test;
default is `claude -p --output-format json`.
