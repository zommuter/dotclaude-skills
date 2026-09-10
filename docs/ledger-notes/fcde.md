# id:fcde -- `/relay --once` and `--after N` gain nothing from the `id:4e84` chain-end widening: the wave budget refuses every chain-pushed follow-on

Measured 2026-09-10 during the `id:4e84` implementation, by reading the gate rather than inferring
from behaviour. Filed at the owner's instruction so the limit is tracked rather than living only in
a commit message.

## The mechanism

`waveDispatchBudget` is snapshotted from `queue.length` BEFORE the parallel wave starts
(`relay-loop.js:4759` region; the gate is at `:2924`). The chain-end re-ask's `queue.push` happens
DURING a unit's own dispatch processing -- i.e. after that snapshot. So the newly enqueued unit
lands above the budget and is refused-and-surfaced rather than dispatched.

This is not a bug in `id:4e84`. The gate's own comment states the behaviour explicitly and cites
the `id:8123` chain-end re-ask BY NAME: "chained follow-ons beyond this are surfaced, not
dispatched". It was deliberate before `4e84` existed, and `4e84` deliberately did not touch it.

## So the practical shape, stated plainly

| invocation | benefits from id:4e84 |
|---|---|
| unbounded `/relay --afk` | YES -- `hard`/`handoff` become reachable |
| `/relay --once` | NO |
| `/relay --after N` | NO |

The `id:4e84` spec therefore runs with that bound disarmed (its rounds are bounded by the discovery
stub going empty instead), and its harness says so in a comment. Worth knowing when reading that
spec: it does not exercise the `--once` path, by design.

## The question, which is the owner's

Should a chain-pushed follow-on be exempt from the wave budget under `--once`/`--after N`?

**Case for leaving it as is (my recommendation):** `--once` means "do one wave", and a
chain-pushed unit is by definition a SECOND wave's worth of work appearing mid-wave. Exempting it
makes `--once` mean "one wave, plus however many follow-ons the chain generates", which is no longer
a bound -- and the bound is the entire point of the flag. An operator using `--once` to take a
single controlled step would silently get two or three.

**Case for changing it:** a human running `--once` specifically to drain a starved `[HARD]` backlog
now cannot, and the failure is silent-ish -- the unit is surfaced, not dispatched, so the operator
sees it named but not worked and may not connect that to the budget.

**A middle option, recorded but not recommended:** make the refusal LOUDER under `--once`
specifically, naming the budget as the reason and pointing at the unbounded invocation. That keeps
the bound honest and removes the confusion, without changing dispatch semantics. Cheaper than
either branch above and it does not touch the gate's behaviour.

## Acceptance (if the owner chooses to act)

* Whatever is decided, `--once` must still mean a BOUNDED number of dispatches -- the flag's
  contract -- or the change is a different feature wearing the same name.
* A refused chain-pushed follow-on names the budget as its reason.
* The `id:a615` gate's existing comment stays true, or is amended in the same commit.

## Related

`id:4e84` (the widening), `id:a615` (the wave dispatch budget / stop-sentinel work), `id:8123` (the
chain-end re-ask the gate's comment already names), `dc5b` C2 (one unit per repo per round, the
reason nothing faster is wanted anyway).
