# Strong-model audit — Run 71 (2026-08-11-2145)

**Item:** ROADMAP id:401c (recurring `[HARD]` strong-model audit), dispatched as an
Opus-apex HARD-execute child (run `relay-20260811-144639-28608`, model `claude-opus-4-8`).

**Window.** Run 70 (2026-08-11-2039) filed id:da95: a strong-EXECUTE checkpoint advances
`last_strong_ckpt`, so the mechanical watermark falsely reads a 0-commit window. That defect
is real and still open — but it does NOT mean "nothing to audit". The genuine first-seen code
since Run 70's own audit merge (`2c989a9..HEAD`) is exactly **one feature**: the id:33b2 /
id:a05c-option-B **opt-in proxy stdin channel**, merged at `66f3a16`/`c7a7ac4`. That is a
bounded, self-contained, security-sensitive diff — an ideal single-turn audit target — so this
run audits it properly rather than re-declining on the watermark. Diff surface:

| File | Δ |
|---|---|
| `relay/scripts/mechanical-proxy.py` | +133 / −8 (the channel) |
| `tests/test_mech_stdin_channel_33b2.sh` | +78 (its spec) |

Baseline verified green on arrival: `tests/run-tests.sh` → **383 passed, 0 failed, 1
expected-red**. The id:33b2 code itself is **clean** — no correctness or security defect was
found in it. One **latent LOW forward-robustness finding** is filed (F1, id:09e4). Two nits
are explicitly accepted (below). No inline fix was applied (rationale in F1).

---

## What the id:33b2 stdin channel does (the thing audited)

Before id:33b2 a mechanical hop could only carry a command in a ```` ```relay-mech ````
fence; a payload embedding heredocs / JSON / `$(…)` / newlines could not be passed because
`_command_allowed()` refuses those metacharacters. id:33b2 adds a **second, disjoint** fence
— ```` ```relay-mech-stdin ```` — whose contents are piped to the child's **stdin** as inert
DATA via `subprocess.run([bash,'-c',command], input=stdin)`, never placed on the command
line. Admission is **opt-in and AND-gated**:

- the command still passes the full unchanged `_command_allowed()` gate (`_mechanical_command`);
- AND the command's pinned last-stage script must be an explicit member of a **separate**
  `STDIN_ALLOWED_SCRIPTS` frozenset (currently just `relay-status-publish.sh`), never derived
  from / aliased to `ALLOWED_RELAY_SCRIPTS` (the owner's 2026-07-28 option-B ruling).

## Pass 1 — Code review  [clean]

- `_last_stage_relay_script()` **correctly mirrors** `_command_allowed()`'s last-stage
  identification: identical `_SEG_SPLIT_RE.split` → `_segment_leader` → `_token_is_relay_script`
  chain, applied to `segments[-1]`. So the script keyed for stdin-admission is provably the same
  script whose stdout the proxy returns. No drift between the two code paths.
- The two fences are **disjoint by construction** (verified against the regexes): the command
  regex requires `relay-mech[ \t]*\r?\n` — the char after `relay-mech` in a `-stdin` opener is
  `-`, not whitespace/newline, so the command regex cannot match a stdin opener; the stdin regex
  requires the literal `-stdin` suffix, so it cannot match a plain command fence. The in-code
  comment's disjointness claim holds.
- `_run_mechanical(command, stdin=None)`: `input=stdin` with `stdin=None` leaves the child's
  stdin inherited — **byte-identical** to the pre-channel behaviour on the legacy path. The
  `_mechanical_dispatch` return contract `(command, None)` for the no-fence case preserves this.
- `extract_stdin_payload()` returns `m.group(1)` verbatim (never `.strip()`) — correct, since
  the payload is data that must round-trip exactly; the regex already excludes only the single
  framing newline on each side.

## Pass 2 — Security audit  [clean]

- **The core property holds**: the payload reaches `subprocess.run(input=…)`, i.e. the child
  process's stdin — it is **never** interpolated into the `-c` command string, so it cannot be
  word-split, glob-expanded, or command-substituted. The end-to-end test proves this: a payload
  of `$(touch $CANARY)` / backticks / `;` / `&&` round-trips byte-identical AND the canary file
  is never created (stdin stayed inert).
- **AND-gate is genuinely AND, not OR**: `_mechanical_dispatch` returns None (fail open) if
  `_mechanical_command` refuses the command, regardless of the stdin fence. Test (3/AND) proves
  `cat /etc/passwd ; relay-status-publish.sh` + a stdin fence is refused — the command gate's
  id:f9cd sequence-operator refusal is not bypassed by the new channel.
- **Opt-in is enforced**: test (2) proves a stdin fence for `claim.sh` (allowlisted but NOT in
  `STDIN_ALLOWED_SCRIPTS`) is refused. A future `ALLOWED_RELAY_SCRIPTS` addition does not
  silently inherit the data plane.
- **STANDING-OBLIGATION check on the single admitted member.** I read
  `relay-status-publish.sh`: it consumes stdin as `raw="$(cat)"`, splits it at a fixed literal
  `SENTINEL` into `content`/`events`, and pipes those to `relay-state-write.sh status-write`
  (an atomic file writer) — it never `eval`s, `source`s, or shell-interpolates the bytes. The
  member honours the obligation the in-code comment imposes; admitting it is safe.

## Pass 3 — Design coherence  [clean]

- Consistent with the owner's 2026-07-28 option-B ruling: `STDIN_ALLOWED_SCRIPTS` is a separate,
  hand-maintained frozenset with an explicit in-code prohibition against defaulting to /
  aliasing / deriving from `ALLOWED_RELAY_SCRIPTS`, and a STANDING OBLIGATION comment that a
  future admitter will actually meet at the point of editing. This is the "admission stays a
  deliberate, reviewable act" property the ruling exists to preserve, encoded where it bites.
- The `stdin_bytes` log field and `mechanical_stdin_refused` log event give the channel its own
  observability, consistent with the proxy's existing event-logging discipline.

---

## F1 — the stdin channel silently misdirects its payload for a non-leading pipeline stage  [CONFIRMED · correctness/robustness · LOW]  <!-- id:09e4 -->

**Mechanism.** `_mechanical_dispatch` admits a stdin fence whenever
`_last_stage_relay_script(command)` — the LAST pipeline stage's pinned script — is in
`STDIN_ALLOWED_SCRIPTS`. But `_run_mechanical` delivers the payload via
`subprocess.run([bash,'-c',command], input=stdin)`, which reaches the **shell process's**
stdin, i.e. the **first** stage of any pipeline, not the last. So for a command such as

```
echo x | relay-status-publish.sh
```

(`echo` is `_SAFE_PLUMBING`, `relay-status-publish.sh` is the admitted last stage — both pass
`_command_allowed`), a `relay-mech-stdin` payload would be handed to `echo` (which ignores its
stdin) while `relay-status-publish.sh` reads the pipe (`x`) instead of the payload. The payload
is **silently lost / wrong-bytes-delivered**.

**Severity — LOW, not an active vulnerability.** Nothing dangerous runs and no data leaks: the
command is caller-constructed by `relay-loop.js` (trusted), and the only admitted member is
invoked bare (never piped) today. The failure mode is a lost payload, not code execution or
exfiltration. It is filed because it is **latent**: the design intent is documented in-code as
"the command stays a single bare allowlisted script invocation", but the gate never enforces
that shape — the first time an admitted script is placed downstream of a pipe, its stdin
silently receives the wrong bytes, and the symptom (a mangled `RELAY_STATUS.md`) would be far
from the cause.

**Recommended fix** (tracked, not applied inline): when a `relay-mech-stdin` fence is present,
require the command to be a **single stage** — refuse (fail open, log `mechanical_stdin_refused`
with reason `stdin fence on a multi-stage pipeline`) if it contains an unquoted `|`. A bare
admitted invocation is the only shape that delivers stdin correctly, so this narrowing matches
the documented intent exactly and closes the gap fail-closed. RED spec: a stdin fence on
`echo x | relay-status-publish.sh` → `_mechanical_dispatch` returns None; the bare-invocation
case stays green.

**Not fixed inline in this run** — consistent with the id:401c discipline that a finding in
freshly-landed code becomes a tracked item unless the fix is trivial and self-evident: this fix
needs a small design choice (single-stage-only vs. feed-stdin-to-last-stage-only, which is not
expressible through `bash -c`) plus its own red-green test, so it is a proper `[ROUTINE]` item,
not a drive-by edit inside an audit.

## Accepted (no action)

- **`_extract_mechanical_stdin` re-parses the body JSON and re-derives `_last_user_text`**,
  work already done inside `_mechanical_command` on the same request — up to ~3 JSON parses per
  request. Accepted: the proxy handles one request at a time, bodies are small (a single agent
  message), and the duplication keeps each extractor a clean standalone guard. Zero correctness
  or security impact.
- **`_run_mechanical(command, stdin: str = None)`** type-hints `str` while defaulting to `None`
  — should read `Optional[str]`. Cosmetic; the default `None` is not a mutable-default hazard.

---

## Ledger coherence

Cross-ledger state after this run: id:33b2 is `[x]` in both ROADMAP.archive.md and closed in
TODO; the id:401c recurring item stays OPEN by design. The new finding id:09e4 is filed as a
`[ROUTINE]` TODO item under a Run 71 section. The id:da95 watermark-starvation defect from Run
70 remains OPEN and un-fixed (owner/reviewer's call, per Run 70's rationale) — this run did not
touch it. Suite remains **383/0/1-xred** (audit-only; no test changes).
