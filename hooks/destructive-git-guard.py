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
construction (nobody is there to answer).  `permissions.deny` fails closed but is
mode-blind: it would also remove the interactive escape a human legitimately wants.
A PreToolUse hook is the lever because it fails closed AND can be context-aware.

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

CONTEXT DETECTION  (acceptance clause 3)
----------------------------------------
Three-way, positive-signal based, ambiguity resolving to BLOCK:

  UNATTENDED  → BLOCK (deny, fails closed).  Signalled by ANY of:
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

  INTERACTIVE → DEFER (stay silent; the existing `permissions.ask` entry prompts a
                human, who can approve exactly as the owner did on 2026-08-21).
                Requires the POSITIVE signal CLAUDE_CODE_ENTRYPOINT == "cli"
                AND no unattended signal above.

  AMBIGUOUS   → BLOCK.  Anything else is ambiguous and resolves to the SAFE side:
                  * no entrypoint signal at all (env not propagated / unknown harness)
                  * an unrecognised CLAUDE_CODE_ENTRYPOINT value (e.g. an sdk/print
                    headless entrypoint — those are unattended by nature)
                  * the heartbeat probe ERRORED (directory present but unreadable, a
                    marker file that will not parse, or the shared pool-run predicate
                    could not be loaded) — we cannot tell whether a pool run is live,
                    so we assume it is
                An ABSENT heartbeat directory is NOT an error — it just means the relay
                is not installed/running here, and contributes no signal.

  Set DESTRUCTIVE_GIT_GUARD_CONTEXT=unattended|interactive to force a branch (used by
  the tests; also an owner escape hatch).

PARSE AMBIGUITY also resolves to BLOCK: if the command cannot be tokenised (shlex
error, command substitution, heredoc), a conservative regex scan for the unmistakable
tree-wide forms runs instead.  A false block is recoverable (commit first, or scope the
paths); a false allow destroys work.

WIRING
------
DELIBERATELY NOT wired into settings.json by this change (id:3a09 acceptance 5) —
wiring changes behaviour for every session at once and an over-blocking guard is worse
than none.  `make install-hooks` symlinks it into ~/.claude/hooks/; activation is the
owner's, by adding it to the PreToolUse/Bash matcher.

Output
------
A PreToolUse deny object on stdout when blocking; nothing (exit 0) otherwise.
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

# Conservative raw-text patterns for the unmistakable tree-wide forms, used only
# when tokenisation is impossible.  Deliberately narrow: they must not fire on a
# path-scoped revert mentioned inside a commit message.
_RAW_PATTERNS = (
    (re.compile(r"\bgit\s+(?:\S+\s+)*?checkout\s+(?:--\s+)?\.(?:\s|$)"), "git checkout -- ."),
    (re.compile(r"\bgit\s+(?:\S+\s+)*?restore\s+(?:--staged\s+)?\.(?:\s|$)"), "git restore ."),
    (re.compile(r"\bgit\s+(?:\S+\s+)*?reset\s+(?:\S+\s+)*?--hard\b"), "git reset --hard"),
    (re.compile(r"\bgit\s+(?:\S+\s+)*?clean\b[^;&|]*\s-{1,2}[A-Za-z]*(?:f|d)\b"), "git clean -f/-d"),
    (re.compile(r"\bgit\s+(?:\S+\s+)*?stash\s+(?:drop|clear)\b"), "git stash drop/clear"),
)


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
            ts = float(marker.get("heartbeat_ts", 0))
            run_id = marker.get("runId", "")
        except (OSError, ValueError, TypeError):
            return "error", f"unparseable heartbeat marker ({name})"
        if now - ts > ttl:
            continue  # stale — not a live run
        if not is_pool_run(run_id):
            continue  # a non-pool daemon (id:54fc) is NOT evidence of an unattended run
        return "live", str(run_id).strip()
    return "none", ""


def detect_context(env=None) -> Tuple[str, str]:
    """
    Return (context, trigger) where context is
    'unattended' | 'interactive' | 'ambiguous' and `trigger` names the CONCRETE
    signal that decided it (id:6f62 — the refusal must report what actually fired,
    not assert a compound reason).
    """
    env = os.environ if env is None else env

    forced = (env.get("DESTRUCTIVE_GIT_GUARD_CONTEXT") or "").strip().lower()
    if forced in ("unattended", "interactive", "ambiguous"):
        return forced, f"DESTRUCTIVE_GIT_GUARD_CONTEXT={forced} (forced)"

    for var in ("RELAY_RUN_ID", "CLAUDE_RELAY_RUN_ID"):
        val = env.get(var, "").strip()
        if val:
            return "unattended", f"{var}={val}"
    for var in ("RELAY_AFK", "CLAUDE_UNATTENDED"):
        if _truthy(env.get(var)):
            return "unattended", f"{var}={env.get(var, '').strip()}"

    hb, detail = _heartbeat_signal(env)
    if hb == "live":
        return "unattended", f"live pool heartbeat: {detail}"
    if hb == "error":
        return "ambiguous", f"heartbeat probe ERRORED: {detail}"

    entrypoint = env.get("CLAUDE_CODE_ENTRYPOINT", "").strip()
    if entrypoint == "cli":
        return "interactive", "CLAUDE_CODE_ENTRYPOINT=cli, no unattended signal"
    if entrypoint:
        return "ambiguous", f"unrecognised CLAUDE_CODE_ENTRYPOINT={entrypoint}"

    return "ambiguous", "no CLAUDE_CODE_ENTRYPOINT signal at all"


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


def find_violation(command: str) -> Optional[str]:
    """Return a description of the banned form in `command`, or None."""
    if "git" not in command:
        return None

    tokens: Optional[list[str]] = None
    if not _UNPARSEABLE_CONSTRUCT.search(command):
        try:
            tokens = shlex.split(command, comments=False)
        except ValueError:
            tokens = None

    if tokens is None:
        # Parse ambiguity → conservative raw scan (safe side).
        for pat, label in _RAW_PATTERNS:
            if pat.search(command):
                return label
        return None

    for argv in _split_git_commands(tokens):
        hit = classify_git_argv(argv)
        if hit:
            return hit
    return None


# ── refusal message ──────────────────────────────────────────────────────────

# The context line REPORTS the signal that actually fired (id:6f62) rather than
# asserting a compound "relay run id / live heartbeat detected", which read as fact
# even when neither applied.
_CONTEXT_LINE = {
    "unattended": (
        "Context: UNATTENDED — trigger: {trigger}. No human is here to answer the "
        "permissions.ask prompt, so this guard fails closed."
    ),
    "ambiguous": (
        "Context: AMBIGUOUS — trigger: {trigger}. Ambiguity resolves to the safe side, so "
        "this guard blocks. Re-run in a confirmed interactive session, or set "
        "DESTRUCTIVE_GIT_GUARD_CONTEXT=interactive if you are certain a human is watching."
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


def main() -> None:
    try:
        payload = json.loads(sys.stdin.read())
    except Exception:
        return  # not our payload — stay silent
    if payload.get("tool_name") != "Bash":
        return
    command = (payload.get("tool_input") or {}).get("command", "")
    if not command:
        return

    form = find_violation(command)
    if form is None:
        return

    context, trigger = detect_context()
    if context == "interactive":
        # Defer to the existing permissions.ask prompt — a human can approve.
        return

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": refusal_reason(form, context, trigger),
        }
    }))


if __name__ == "__main__":
    main()
