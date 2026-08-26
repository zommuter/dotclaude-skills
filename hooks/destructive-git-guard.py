#!/usr/bin/env python3
"""
PreToolUse(Bash) hook: TREE-WIDE destructive-git guard (TODO id:3a09).

WHY
---
`git checkout -- .` / `git restore .` / `git reset --hard` / `git clean -fd` are
TREE-WIDE and blind to WHOSE uncommitted changes they discard.  Uncommitted
content has NO reflog, so a partially-good transform plus one unaccounted modified
file destroys work irrecoverably — and in a main checkout it can take out a human's
or a parallel session's in-flight edits.  Observed live 2026-08-21: an executor
mid-transform (427 sites / 162 files) reached for `git checkout -- .`.

`~/.claude/settings.json` already lists these under `permissions.ask`, which PROMPTS
in every mode — so under an unattended `--afk` pool run each one is a STALL by
construction (nobody is there to answer).

OWNER RULING 2026-08-22 — UNCONDITIONAL DENY.  DO NOT RE-LITIGATE.
------------------------------------------------------------------
All five guarded ops are now DENIED in every context.  There is no context branch and
no defer-to-`permissions.ask`.  The argument, in full, so nobody reopens it:

  This is a PreToolUse hook on **Claude's Bash tool**.  It governs what the AGENT may
  run — it does not govern the human.  A human who genuinely needs `git reset --hard`
  types it in their own terminal, where this hook does not exist and never fires.

  Therefore the "interactive escape a human legitimately wants" that this header used
  to cite as the reason not to use `permissions.deny` was never an escape for the
  human at all.  It was an escape for the AGENT — and there is no case in which an
  agent should perform an unrecoverable, tree-wide revert on the owner's repository.
  Denying costs the human exactly nothing.

  This also disposes of the old note that "`deny` is worse than `ask` because it
  cannot be approved".  That objection was written about a FALSE deny produced by the
  id:6f62 heartbeat bug (every interactive session hard-denied).  A CORRECT deny being
  un-approvable is not a defect; it is the entire point.

  Motivating incident (2026-08-22): a delegated review agent ran `git reset --hard`.
  The guard classified the session INTERACTIVE and deferred, so `permissions.ask`
  fired a prompt at ~02:00 with the owner asleep — the agent stalled and the owner
  woke to an unanswerable request.  The guard behaved exactly as designed; the design
  was wrong.

  NOT in scope, deliberately (TODO id:6a6b): no whitelist/exemption for disposable
  worktrees.  Owner ruled: ship the deny first, relax later ONLY for a context the
  guard can PROVE.  A premature exemption reopens the hole.

WHAT IT BLOCKS  (tree-wide only)
--------------------------------
  git checkout -- .        git checkout .          git checkout HEAD -- <dir>
  git restore .            git restore --staged .  git restore <dir>
  git reset --hard [...]
  git clean -f / -d / -fd / -fdx / --force
  git stash drop           git stash clear

WHAT IT ALLOWS  (this is the point — a guard that makes the safe form painful
gets routed around into the tree-wide form)
  git checkout -- path/to/one/file.sh      git checkout -- a.sh b.sh
  git restore path/to/file.py              git restore --staged path/to/file.py
  git checkout <branch> / -b <branch>      git reset / git reset --soft / --mixed
  git clean -n / --dry-run                 git stash / pop / list / show

CONTEXT DETECTION  (REPORT-ONLY since the 2026-08-22 ruling)
------------------------------------------------------------
`detect_context()` NO LONGER DECIDES ANYTHING.  Nothing in this file branches on its
result; the deny is unconditional.  It survives for one purpose only: so the refusal
message can NAME the situation it fired in, which is what made the id:6f62 and id:8987
defects diagnosable.  Keep that in mind before wiring it into a new decision.

WHAT WAS DONE WITH THE NOW-DEAD `interactive` BRANCH, AND WHY
------------------------------------------------------------
It was REMOVED, not merely left unreferenced.  The branch read: `CLAUDE_CODE_ENTRYPOINT
== "cli"` and no unattended signal ⇒ "interactive" ⇒ a human is present.  That claim is
FALSE, and not only because the deny is now unconditional: a human-launched CLI session
keeps the same `CLAUDE_CODE_ENTRYPOINT=cli` after the human walks away, which is exactly
what happened at ~02:00 on 2026-08-22.  The entrypoint records HOW the session was
started, never WHO is currently watching it; no environment variable available here can
establish presence.  Leaving a function that asserts presence on evidence that cannot
establish it is a trap for the next reader who reuses it — so the verdict is gone.

`detect_context()` is therefore TWO-WAY now: 'unattended' (a positive unattended signal
fired) or 'ambiguous' (none did).  `CLAUDE_CODE_ENTRYPOINT` is still REPORTED in the
trigger string — it is useful diagnostics — but it no longer produces a verdict.

  UNATTENDED  (reported).  Signalled by ANY of:
                  * env RELAY_RUN_ID or CLAUDE_RELAY_RUN_ID non-empty
                    (the relay loop's own run marker — relay/scripts/discover-prelude.sh)
                  * env RELAY_AFK / CLAUDE_UNATTENDED truthy
                  * a LIVE relay POOL heartbeat (id:e149) — i.e. at least one
                    `heartbeats/<runId>.json` under $HEARTBEAT_BASE
                    (default ~/.config/relay/heartbeats) whose heartbeat_ts is
                    within HEARTBEAT_TTL (default 3600s) AND whose runId names a
                    real pool.  "Names a real pool" is NOT re-derived here: it is
                    `relay/scripts/lib-pool-runs.py::is_pool_run`, the same predicate
                    `stop-request.sh` uses (id:6f62).  Before that fix this probe
                    accepted ANY live marker, and the always-beating non-pool
                    `discovery-producer` daemon (fixed runId, 2100s TTL, id:54fc)
                    therefore hard-DENIED every interactive session.

  AMBIGUOUS   (reported).  No positive unattended signal was identified.  The trigger
                string still distinguishes the interesting sub-cases:
                  * `CLAUDE_CODE_ENTRYPOINT=cli` — reported, explicitly annotated as
                    NOT evidence that a human is present (see above)
                  * an unrecognised CLAUDE_CODE_ENTRYPOINT value (e.g. an sdk/print
                    headless entrypoint)
                  * no entrypoint signal at all (env not propagated / unknown harness)
                  * the heartbeat probe ERRORED (directory present but unreadable, a
                    marker file that will not parse, a LIVE marker whose runId is empty
                    or not a string (id:8987), or the shared pool-run predicate could
                    not be loaded)
                An ABSENT heartbeat directory is NOT an error — it just means the relay
                is not installed/running here, and contributes no signal.

  DESTRUCTIVE_GIT_GUARD_CONTEXT=unattended|ambiguous forces the REPORTED label.  It is
  no longer an escape hatch and CANNOT unblock anything — in particular the historical
  value `interactive` is accepted on input but IGNORED (reported as such), because
  honouring it would reintroduce the 2026-08-22 incident verbatim.

PARSE AMBIGUITY also resolves to BLOCK: if the command cannot be tokenised (shlex
error, command substitution, heredoc), a conservative regex scan for the unmistakable
tree-wide forms runs instead.  A false block is recoverable (commit first, or scope the
paths); a false allow destroys work.

That fallback scan is ANCHORED to command start and SPELLING-INSENSITIVE (id:221f,
2026-08-26 — parity with hooks/rm-force-guard.sh).  It no longer fires on a guarded
command that a heredoc payload or a quoted argument merely MENTIONS, and `git clean
--force` / `git checkout -f .` now reach the same verdict there as their other
spellings already reached on the tokenised path.  Full rationale sits above
`_CMD_START`; the spelling table and the mention negative-control live in
tests/test_destructive_git_guard_spelling_anchor_221f.sh.

NOT fixed here, and NOT fixable here: the guard covers only the five tree-wide forms.
`git worktree remove -f`, `git branch -D`, `git push -f` are gated (or not) by
`~/.claude/settings.json` `permissions`, which is the OWNER's file and is never
agent-edited.  The short-form/long-form asymmetry there is recorded in TODO id:221f.

WIRING
------
WIRED.  The owner activated it in `~/.claude/settings.json` (PreToolUse/Bash matcher) on
2026-08-21, and on 2026-08-22 it demonstrably stopped an agent's `git reset --hard`.
`make install-hooks` symlinks it into ~/.claude/hooks/.  The `permissions.ask` entries
for these five forms are now redundant — this hook denies first — but they are harmless
and are left alone.

Output
------
A PreToolUse deny object on stdout whenever one of the five forms is present; nothing
(exit 0) otherwise.
"""
import importlib.util
import json
import os
import re
import shlex
import sys
import time
from typing import Optional, Tuple

GUARD_ID = "id:3a09"

# ── the SHARED pool-run predicate (id:6f62) ──────────────────────────────────
# Single definition, in relay/scripts/lib-pool-runs.py, also used by
# relay/scripts/stop-request.sh.  Never re-derive the rule here: a second copy is
# exactly how this guard came to treat the non-pool `discovery-producer` daemon as
# proof of an unattended run.  Resolved through realpath() so it works both from the
# repo and from the ~/.claude/hooks/ symlink that `make install-hooks` creates.
_POOL_RUNS_LIB = os.path.join(
    os.path.dirname(os.path.dirname(os.path.realpath(__file__))),
    "relay", "scripts", "lib-pool-runs.py",
)


def _load_is_pool_run():
    """Return lib-pool-runs.py's is_pool_run, or None if it cannot be loaded."""
    try:
        spec = importlib.util.spec_from_file_location("relay_lib_pool_runs", _POOL_RUNS_LIB)
        if spec is None or spec.loader is None:
            return None
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod.is_pool_run
    except Exception:
        return None  # caller turns this into a heartbeat-probe ERROR ⇒ ambiguous ⇒ block

# ── shell operators that terminate one simple command in the token stream ─────
_OPERATORS = frozenset({";", "&&", "||", "|", "&", "\n"})

# Constructs shlex cannot tokenise faithfully → fall back to the regex scan.
_UNPARSEABLE_CONSTRUCT = re.compile(r"\$\(|`|<<|<\(")

# git global options that consume the NEXT token as their value.
_GIT_GLOBAL_WITH_VALUE = frozenset({"-C", "--git-dir", "--work-tree", "-c", "--exec-path", "--namespace"})

# ── raw-text fallback scan (id:221f) ─────────────────────────────────────────
# PARITY WITH hooks/rm-force-guard.sh.  That guard is (1) ANCHORED to command start
# and (2) SPELLING-INSENSITIVE about the force flag.  This scan used to be neither.
#
# (b) ANCHORING.  These patterns are reached only when tokenisation is impossible —
# in practice a heredoc, which is exactly how a TODO item, commit message, meeting
# note or test fixture that QUOTES a guarded command gets written.  Unanchored, the
# guard fired on the mention: filing id:221f itself was refused because the item's
# prose quoted a tree-wide discard inside a heredoc payload to md-merge.py.  A guard
# that cannot be written about trains the route-around reflex it exists to prevent.
# Two mechanisms, both of which make the scan fire STRICTLY LESS (no op that merely
# prompted before can newly deny):
#   * `_strip_noncommand_text()` blanks heredoc BODIES and the interior of balanced
#     quoted spans, so a command named inside a payload or an argument is not text
#     this scan ever sees;
#   * every pattern is anchored to `_CMD_START` — string start or immediately after a
#     shell operator that terminates the previous simple command.
# The tokenised path (`classify_git_argv`) is unchanged and remains the primary
# analysis; it was already quoting-aware, which is why `git commit -m "git reset
# --hard"` never fired there.
#
# (a) SPELLING.  `git clean --force` did NOT match the old clean pattern
# (`-{1,2}[A-Za-z]*(?:f|d)\b` cannot reach the `f` in `force` — the following `o` is
# not a word boundary), and `git checkout -f .` / `git restore -s HEAD .` did not
# match either, though the tokenised path denies all three.  A destructive op must
# not reach a different verdict because of which spelling was typed.  `--dry-run`
# and `-n` still do NOT match (verified by the spelling table in
# tests/test_destructive_git_guard_spelling_anchor_221f.sh).

# Start of a simple command: string start, or right after an operator/grouping
# character that ends the previous one.  Tolerates `sudo`, shell keywords, and
# leading VAR=value assignments.
_CMD_START = (
    r"(?:^|[\n;&|(){}])[ \t]*"
    r"(?:(?:then|do|else|elif|!)[ \t]+)*"
    r"(?:sudo[ \t]+)?"
    r"(?:[A-Za-z_][A-Za-z0-9_]*=(?:\"[^\"]*\"|'[^']*'|[^\s;&|]*)[ \t]+)*"
)

# git's own global options (and their values) sitting between `git` and the
# subcommand: `-C <dir>`, `-c k=v`, `--git-dir=…`, `--no-pager`, …  Deliberately
# unable to consume a bare word, so it can never swallow a subcommand.
_GIT_GLOBALS = (
    r"(?:[ \t]+(?:"
    r"-{1,2}[^\s;&|]*"           # any option, short or long, with or without =value
    r"|[^\s;&|]*[=/][^\s;&|]*"   # a value that looks like a path or key=value
    r"|\.{1,2}"                  # `-C .` / `-C ..`
    r"|~[^\s;&|]*"               # `-C ~/src/x`
    r"))*"
)

_GIT_HEAD = _CMD_START + r"(?:[^\s;&|]*/)?git" + _GIT_GLOBALS + r"[ \t]+"

# Options and tree-ish/pathspec words a subcommand may carry before the tree-wide
# pathspec (`-f`, `--staged`, `HEAD`, a branch name, …).
_SUB_ARGS = r"(?:[ \t]+(?:-{1,2}[^\s;&|]*|[A-Za-z0-9_][^\s;&|]*))*"

# A pathspec of exactly `.` — end of token, not the start of `./foo.sh`.
_DOT = r"\.(?=[\s;&|]|$)"

_RAW_PATTERNS = (
    (re.compile(_GIT_HEAD + r"checkout" + _SUB_ARGS + r"[ \t]+(?:--[ \t]+)?" + _DOT),
     "git checkout -- ."),
    (re.compile(_GIT_HEAD + r"restore" + _SUB_ARGS + r"[ \t]+(?:--[ \t]+)?" + _DOT),
     "git restore ."),
    (re.compile(_GIT_HEAD + r"reset\b(?:[ \t]+[^\s;&|]+)*?[ \t]+--hard\b"),
     "git reset --hard"),
    # Spelling-insensitive, the way rm-force-guard.sh is: `--force`, and any short
    # cluster containing f or d (`-f`, `-d`, `-fd`, `-df`, `-xdf`, `-dfx`).  `-n` and
    # `--dry-run` are excluded — a long option can only match via the literal
    # `--force`, so `--dry-run` cannot reach the `d`.
    (re.compile(_GIT_HEAD + r"clean\b[^;&|]*?[ \t](?:--force\b|-[A-Za-z]*[fd][A-Za-z]*(?=[\s;&|]|$))"),
     "git clean -f/-d"),
    (re.compile(_GIT_HEAD + r"stash[ \t]+(?:drop|clear)\b"),
     "git stash drop/clear"),
)

# `<<TAG`, `<<-TAG`, `<<'TAG'`, `<<"TAG"`
_HEREDOC_START = re.compile(r"<<-?[ \t]*(?P<q>['\"]?)(?P<tag>[A-Za-z_][A-Za-z0-9_]*)(?P=q)")

# A balanced single- or double-quoted span.
_QUOTED_SPAN = re.compile(r"'[^']*'|\"(?:[^\"\\]|\\.)*\"")


def _strip_heredoc_bodies(command: str) -> str:
    """Blank the BODY of every heredoc, keeping line structure.

    A heredoc body is a PAYLOAD, not a command — it is where a commit message, a
    ledger line or a test fixture quotes the very command this guard blocks.  The
    delimiter line and everything outside the body are left untouched, so a real
    `... <<EOF ... EOF ; git reset --hard` is still scanned.
    """
    lines = command.split("\n")
    out: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        tags = [m.group("tag") for m in _HEREDOC_START.finditer(line)]
        i += 1
        for tag in tags:
            while i < len(lines):
                body = lines[i]
                i += 1
                if body.strip() == tag:
                    out.append(body)
                    break
                out.append("")
    return "\n".join(out)


def _blank_quoted_spans(command: str) -> str:
    """Replace the INTERIOR of balanced quoted spans with spaces.

    Length and quote characters are preserved so no new token adjacency or shell
    operator can be manufactured.  An UNbalanced quote simply does not match and is
    left alone — that direction only ever scans more text, never less.
    """
    return _QUOTED_SPAN.sub(lambda m: m.group(0)[0] + " " * (len(m.group(0)) - 2) + m.group(0)[-1],
                            command)


def _strip_noncommand_text(command: str) -> str:
    """Remove the regions of `command` that are payload/argument text, not commands."""
    return _blank_quoted_spans(_strip_heredoc_bodies(command))


# ── context detection ────────────────────────────────────────────────────────

def _truthy(val: Optional[str]) -> bool:
    return bool(val) and val.strip().lower() not in ("0", "false", "no", "")


def _heartbeat_signal(env) -> Tuple[str, str]:
    """
    Probe the id:e149 relay run heartbeat.

    Returns (status, detail) where status is one of:
      "live"    — at least one POOL run marker beat within TTL (⇒ unattended);
                  detail is that runId
      "none"    — no heartbeat dir / no live POOL marker        (⇒ no signal)
      "error"   — the probe itself failed                        (⇒ ambiguous);
                  detail says what failed
    Markers whose runId is NOT a pool (is_pool_run ⇒ False, e.g. the
    `discovery-producer` daemon) contribute NO signal, however fresh they are.
    """
    is_pool_run = _load_is_pool_run()
    if is_pool_run is None:
        return "error", f"cannot load the shared pool-run predicate ({_POOL_RUNS_LIB})"

    base = env.get("HEARTBEAT_BASE") or os.path.join(
        env.get("HOME", os.path.expanduser("~")), ".config", "relay", "heartbeats"
    )
    if not os.path.isdir(base):
        return "none", ""  # relay not installed/running here — not an error
    try:
        ttl = int(env.get("HEARTBEAT_TTL", "3600"))
    except ValueError:
        return "error", "HEARTBEAT_TTL is not an integer"
    now = time.time()
    try:
        names = os.listdir(base)
    except OSError:
        return "error", f"heartbeat dir present but unreadable ({base})"
    for name in names:
        if not name.endswith(".json"):
            continue
        path = os.path.join(base, name)
        try:
            with open(path, "r", encoding="utf-8") as fh:
                marker = json.load(fh)
            if not isinstance(marker, dict):
                return "error", f"unparseable heartbeat marker ({name})"
            ts = float(marker.get("heartbeat_ts", 0))
            run_id = marker.get("runId", "")
        except (OSError, ValueError, TypeError, AttributeError):
            return "error", f"unparseable heartbeat marker ({name})"
        if now - ts > ttl:
            continue  # stale — not a live run
        # A FRESH marker we cannot classify is a probe ERROR, not a non-signal (id:8987).
        # `is_pool_run` answers False for "" / None just as it does for a known non-pool
        # daemon, and collapsing the two inverted this guard's own "cannot tell ⇒ block"
        # doctrine: an unnameable-but-live run would have let an interactive session
        # DEFER. The split belongs here, in the caller — lib-pool-runs.py stays as is,
        # because stop-request.sh genuinely cannot address an unnamed run.
        if not isinstance(run_id, str) or not run_id.strip():
            return "error", f"live heartbeat marker with an empty or non-string runId ({name})"
        if not is_pool_run(run_id):
            continue  # a non-pool daemon (id:54fc) is NOT evidence of an unattended run
        return "live", str(run_id).strip()
    return "none", ""


def detect_context(env=None) -> Tuple[str, str]:
    """
    REPORT-ONLY (owner ruling 2026-08-22).  Return (context, trigger) where context is
    'unattended' | 'ambiguous' and `trigger` names the CONCRETE signal observed (id:6f62
    — the refusal must report what actually fired, not assert a compound reason).

    NOTHING BRANCHES ON THIS.  All five guarded forms deny unconditionally; this only
    annotates the refusal.  Do not reintroduce a decision here without re-reading the
    ruling in the module docstring.

    The third verdict 'interactive' is DELETED.  `CLAUDE_CODE_ENTRYPOINT=cli` records how
    the session was STARTED, not whether a human is watching it now — a human-launched
    session that keeps working after the human walks away carries the identical value, and
    that is precisely the 2026-08-22 incident.  Nothing readable from this process can
    establish presence, so no verdict here claims it.
    """
    env = os.environ if env is None else env

    forced = (env.get("DESTRUCTIVE_GIT_GUARD_CONTEXT") or "").strip().lower()
    if forced in ("unattended", "ambiguous"):
        return forced, f"DESTRUCTIVE_GIT_GUARD_CONTEXT={forced} (forced label)"
    ignored_force = ""
    if forced:
        # Historically 'interactive' selected the defer branch.  Accepted on input so an
        # old caller does not error, but it decides NOTHING — honouring it would
        # reintroduce the incident this guard was re-specified to prevent.
        ignored_force = (
            f"DESTRUCTIVE_GIT_GUARD_CONTEXT={forced} (IGNORED — no context can "
            f"unblock these forms); "
        )

    for var in ("RELAY_RUN_ID", "CLAUDE_RELAY_RUN_ID"):
        val = env.get(var, "").strip()
        if val:
            return "unattended", f"{ignored_force}{var}={val}"
    for var in ("RELAY_AFK", "CLAUDE_UNATTENDED"):
        if _truthy(env.get(var)):
            return "unattended", f"{ignored_force}{var}={env.get(var, '').strip()}"

    hb, detail = _heartbeat_signal(env)
    if hb == "live":
        return "unattended", f"{ignored_force}live pool heartbeat: {detail}"
    if hb == "error":
        return "ambiguous", f"{ignored_force}heartbeat probe ERRORED: {detail}"

    entrypoint = env.get("CLAUDE_CODE_ENTRYPOINT", "").strip()
    if entrypoint == "cli":
        # REPORTED, never a verdict: this says the session was STARTED from the CLI, which
        # is NOT evidence that a human is present at it now (2026-08-22 incident).
        return "ambiguous", (
            f"{ignored_force}no unattended signal identified; "
            f"CLAUDE_CODE_ENTRYPOINT=cli (how the session STARTED — NOT evidence "
            f"a human is present)"
        )
    if entrypoint:
        return "ambiguous", f"{ignored_force}unrecognised CLAUDE_CODE_ENTRYPOINT={entrypoint}"

    return "ambiguous", f"{ignored_force}no CLAUDE_CODE_ENTRYPOINT signal at all"


# ── command classification ───────────────────────────────────────────────────

def _is_tree_wide_pathspec(arg: str) -> bool:
    """True if this pathspec names the tree / a directory rather than a single file."""
    if arg in (".", "..", "/", "*", ":/", "./", "*/*"):
        return True
    if arg.endswith("/"):
        return True
    if arg.startswith(":/") or arg.startswith(":("):  # git magic pathspecs are tree-rooted
        return True
    try:
        if os.path.isdir(arg):
            return True
    except OSError:
        return True  # cannot tell ⇒ safe side
    return False


def _split_git_commands(tokens: list[str]) -> list[list[str]]:
    """Split a token stream into the argv of each `git ...` simple command."""
    cmds: list[list[str]] = []
    cur: Optional[list[str]] = None
    for tok in tokens:
        if tok in _OPERATORS:
            if cur:
                cmds.append(cur)
            cur = None
            continue
        if cur is not None:
            cur.append(tok)
        elif tok == "git" or tok.endswith("/git"):
            cur = []
    if cur:
        cmds.append(cur)
    return cmds


def classify_git_argv(argv: list[str]) -> Optional[str]:
    """
    argv = the tokens AFTER `git`.  Return a short description of the banned
    tree-wide form, or None if this invocation is allowed.
    """
    i = 0
    while i < len(argv) and argv[i].startswith("-"):
        if argv[i] in _GIT_GLOBAL_WITH_VALUE:
            i += 2
        else:
            i += 1
    if i >= len(argv):
        return None
    sub = argv[i]
    rest = argv[i + 1:]

    if sub == "reset":
        return "git reset --hard" if "--hard" in rest else None

    if sub == "clean":
        for tok in rest:
            if tok == "--force":
                return "git clean --force"
            if tok in ("-n", "--dry-run"):
                return None
            if re.fullmatch(r"-[A-Za-z]+", tok) and ("f" in tok or "d" in tok):
                return f"git clean {tok}"
        return None

    if sub == "stash":
        for tok in rest:
            if tok in ("drop", "clear"):
                return f"git stash {tok}"
            if not tok.startswith("-"):
                break
        return None

    if sub in ("checkout", "restore"):
        # Collect the pathspec arguments.
        paths: list[str] = []
        after_dashdash = False
        seen_nonflag = False
        for tok in rest:
            if after_dashdash:
                paths.append(tok)
                continue
            if tok == "--":
                after_dashdash = True
                continue
            if tok.startswith("-"):
                continue
            if sub == "checkout" and not seen_nonflag:
                # First bare token of `git checkout X` is a tree-ish (branch/commit)
                # UNLESS it is itself a tree-wide pathspec — `git checkout .` is the
                # blind form the hazard report names explicitly.
                seen_nonflag = True
                if _is_tree_wide_pathspec(tok):
                    paths.append(tok)
                continue
            paths.append(tok)
        for p in paths:
            if _is_tree_wide_pathspec(p):
                return f"git {sub} {'-- ' if after_dashdash else ''}{p}"
        return None

    return None


def _raw_scan(command: str) -> Optional[str]:
    """Conservative raw-text scan, used when tokenised analysis is unavailable.

    ANCHORED to command start and blind to payload/argument text (id:221f) — see the
    long note above `_CMD_START`.
    """
    scanned = _strip_noncommand_text(command)
    for pat, label in _RAW_PATTERNS:
        if pat.search(scanned):
            return label
    return None


def _find_violation_tokenised(command: str) -> Optional[str]:
    tokens: Optional[list[str]] = None
    if not _UNPARSEABLE_CONSTRUCT.search(command):
        try:
            tokens = shlex.split(command, comments=False)
        except ValueError:
            tokens = None

    if tokens is None:
        # Parse ambiguity → conservative raw scan (safe side).
        return _raw_scan(command)

    for argv in _split_git_commands(tokens):
        hit = classify_git_argv(argv)
        if hit:
            return hit
    return None


def find_violation(command: str) -> Optional[str]:
    """
    Return a description of the banned form in `command`, or None.

    NEVER raises (id:3866).  An uncaught exception here would exit the hook 1, and a
    PreToolUse hook that exits non-zero is a NON-BLOCKING error — Claude Code prints
    stderr and RUNS the command, i.e. the guard would fail OPEN.  Any unexpected
    failure of the tokenised analysis therefore routes to the conservative regex scan
    (the same safe side a shlex parse failure takes), not to a traceback.
    """
    if not isinstance(command, str) or "git" not in command:
        return None
    try:
        return _find_violation_tokenised(command)
    except Exception as exc:  # noqa: BLE001 — deliberate: fail SAFE, never fail open
        print(
            f"destructive-git-guard ({GUARD_ID}): tokenised analysis failed "
            f"({type(exc).__name__}: {exc}); falling back to the conservative scan",
            file=sys.stderr,
        )
        try:
            return _raw_scan(command)
        except Exception:  # noqa: BLE001 — a regex cannot realistically fail; still never raise
            return None


# ── refusal message ──────────────────────────────────────────────────────────

# The context line REPORTS the signal that actually fired (id:6f62) rather than
# asserting a compound "relay run id / live heartbeat detected", which read as fact
# even when neither applied.
# Since the 2026-08-22 ruling the context is REPORTED, never decisive — both lines say so
# explicitly, so nobody reads the refusal as "this would have been allowed elsewhere".
_CONTEXT_LINE = {
    "unattended": (
        "Context: UNATTENDED — trigger: {trigger}. Reported for diagnosis only: this "
        "refusal is UNCONDITIONAL and does not depend on the context."
    ),
    "ambiguous": (
        "Context: AMBIGUOUS (no positive unattended signal identified) — trigger: "
        "{trigger}. Reported for diagnosis only: this refusal is UNCONDITIONAL and does "
        "not depend on the context. There is no interactive escape — this hook governs "
        "the AGENT's Bash tool, not your terminal; run it there if you really mean it."
    ),
}


def refusal_reason(form: str, context: str, trigger: str = "") -> str:
    line = _CONTEXT_LINE.get(context, _CONTEXT_LINE["ambiguous"])
    return (
        f"Destructive-git guard ({GUARD_ID}): refusing `{form}` — this is TREE-WIDE. It "
        f"discards EVERY uncommitted change in the worktree, including files you did not "
        f"touch (a parallel session's or a human's in-flight edits). Uncommitted content "
        f"has no reflog, so it is UNRECOVERABLE.\n"
        f"Do one of these instead:\n"
        f"  1. COMMIT FIRST — worktree commits are free and squashable: stage the exact "
        f"paths you changed and commit them, "
        f"`git add -- path/to/changed.sh path/to/other.py && git commit -m 'wip: before "
        f"transform'`, then revert or squash whatever you don't keep. (Stage named paths, "
        f"never the whole tree — this repo's convention, id:debf.)\n"
        f"  2. SCOPE THE REVERT to enumerated paths — this guard ALLOWS that: "
        f"`git checkout -- path/to/one/file.sh path/to/other.sh`.\n"
        f"  3. Run the exploratory pass on a `tar`-copy of the tree and throw the copy away.\n"
        f"{line.format(trigger=trigger or 'unspecified')}"
    )


def _defer(note: str) -> None:
    """
    Unreadable payload ⇒ DEFER, observably (id:3866, acceptance clause 2).

    Disposition: a payload this hook cannot parse carries no command, so there is
    nothing destructive to block — exit 0 with EMPTY stdout.  Blocking instead would
    turn any future hook-protocol change into a fleet-wide outage in front of every
    single Bash call, which is a far larger hazard than the one this guard removes.
    But the deferral is never SILENT: one line to stderr so a malformed-payload
    regression is visible rather than an invisible hole in the guard.
    """
    print(f"destructive-git-guard ({GUARD_ID}): {note}; deferring", file=sys.stderr)


def main() -> None:
    # Every branch below must exit 0.  A PreToolUse hook exiting non-zero is a
    # NON-BLOCKING error: Claude Code surfaces stderr and RUNS the command, so a crash
    # here silently BYPASSES the guard (id:3866).  No stdin shape may reach a traceback.
    try:
        raw = sys.stdin.read()
    except Exception as exc:  # noqa: BLE001
        return _defer(f"stdin unreadable ({type(exc).__name__})")
    if not raw.strip():
        return _defer("empty stdin")
    try:
        payload = json.loads(raw)
    except Exception:
        return _defer("stdin is not valid JSON")
    if not isinstance(payload, dict):
        return _defer(f"payload is a {type(payload).__name__}, not an object")
    if payload.get("tool_name") != "Bash":
        return
    tool_input = payload.get("tool_input")
    if tool_input is None:
        return _defer("payload has no tool_input")
    if not isinstance(tool_input, dict):
        return _defer(f"tool_input is a {type(tool_input).__name__}, not an object")
    command = tool_input.get("command")
    if command is None or command == "":
        return
    if not isinstance(command, str):
        return _defer(f"tool_input.command is a {type(command).__name__}, not a string")

    form = find_violation(command)
    if form is None:
        return

    # UNCONDITIONAL DENY (owner ruling 2026-08-22 — see the module docstring).  There is
    # deliberately NO context branch here: `detect_context()` is called only to annotate
    # the refusal.  A PreToolUse hook governs the AGENT's Bash tool, not the human's
    # terminal, so there is no legitimate escape to preserve.
    context, trigger = detect_context()

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": refusal_reason(form, context, trigger),
        }
    }))


if __name__ == "__main__":
    # Outermost net (id:3866): even a bug OUTSIDE the payload-shape checks must not
    # exit non-zero, because a non-zero PreToolUse hook fails OPEN.
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        try:
            print(
                f"destructive-git-guard ({GUARD_ID}): unexpected "
                f"{type(exc).__name__}: {exc}; deferring",
                file=sys.stderr,
            )
        except Exception:  # noqa: BLE001
            pass
    sys.exit(0)
