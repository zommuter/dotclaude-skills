#!/usr/bin/env bash
# roadmap:5bbb — completeness guard: every ```relay-mech fenced command that
# relay-loop.js can dispatch as model:'bash' must name a script present in
# mechanical-proxy.py's ALLOWED_RELAY_SCRIPTS. A non-allowlisted command fails
# neither at authoring time nor in the ordinary suite — it fails at RUNTIME,
# in exactly the rare path (a dying child) where nobody is watching and the
# cost is highest (fail-open to the real API: "There's an issue with the
# selected model (bash)"). Shipped THREE times: id:86a2's discover-prelude.sh,
# the same class again, and 2026-07-29's worktree-retire.sh (id:4df8/1f8e —
# an execute child's uncommitted work was one `git worktree prune` from
# deletion, hand-salvaged as 06cffba).
#
# This is a READ-ONLY completeness test over the live relay-loop.js +
# mechanical-proxy.py source (that is the point — a hermetic fixture would
# only guard itself). It writes nothing, needs no network and no ~/.claude.
#
# WHY THIS IS HARDER THAN A BLOCK REGEX: the fences are not statically
# greppable as ```...``` blocks. relay-loop.js builds them by string
# concatenation ('```relay-mech\n' + cmd + '\n```'), and in one style
# (id:6176's quota hop) inside a template literal with escaped backticks
# (\`\`\`relay-mech). Two fences (id:907e/8123's mechVerdictHop, and
# releaseLease's per-call dispatch helper) carry a bare PARAMETER, not a
# literal script path — the actual script only appears at the function's
# call sites, one level of indirection up. An unresolvable fence (beyond that
# one level) MUST fail LOUDLY, never be skipped — a skip reproduces the exact
# silent hole this test exists to close.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JS="$SRC_DIR/relay/scripts/relay-loop.js"
PROXY="$SRC_DIR/relay/scripts/mechanical-proxy.py"

[[ -f "$JS" ]] || { echo "FAIL: relay-loop.js not found at $JS"; exit 1; }
[[ -f "$PROXY" ]] || { echo "FAIL: mechanical-proxy.py not found at $PROXY"; exit 1; }
echo "PASS: relay-loop.js and mechanical-proxy.py both exist"

python3 - "$JS" "$PROXY" <<'PYEOF'
import re, sys

JS, PROXY = sys.argv[1], sys.argv[2]

raw_src = open(JS).read()
raw_lines = raw_src.split("\n")

# Comment-blanked view: everything from the first unescaped `//` on a line to
# end-of-line is replaced with spaces (offsets preserved) so every downstream
# regex/paren-match only ever sees real code, never prose. (A `//` inside a
# string literal would defeat this — none of relay-loop.js's fence-adjacent
# strings contain one; verified by the negative control below never firing
# on a false split.)
code_lines = []
for line in raw_lines:
    cstart = line.find('//')
    code_lines.append(line if cstart == -1 else line[:cstart] + ' ' * (len(line) - cstart))
src = "\n".join(code_lines)

line_offsets = []
off = 0
for l in raw_lines:
    line_offsets.append(off)
    off += len(l) + 1


def line_of(pos):
    lo, hi = 0, len(line_offsets) - 1
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if line_offsets[mid] <= pos:
            lo = mid
        else:
            hi = mid - 1
    return lo + 1


# (1) Classify every "relay-mech" mention in the file as either a REAL fence
# marker (immediately preceded by ``` or the escaped \`\`\` — the two valid
# JS-source forms of a fence delimiter, per test_relay_loop_mech_emitter.sh's
# id:6176 fix) or a comment-only mention (negative control, acceptance #5).
# Anything that is neither is UNCLASSIFIED and fails loudly — that is the
# guard against the extractor silently missing a future fence shape.
mention_re = re.compile(r"relay-mech")
markers = []
stdin_markers = []
comment_mentions = []
unclassified = []

for i, line in enumerate(raw_lines):
    for m in mention_re.finditer(line):
        col = m.start()
        cstart = line.find('//')
        if cstart != -1 and cstart < col:
            comment_mentions.append((i + 1, col))
            continue
        before = line[:col]
        if before.endswith('```') or before.endswith('\\`\\`\\`'):
            # id:b0ce — a ```relay-mech-stdin opener is the DATA-plane fence, NOT a command
            # fence: its body is a payload piped to the child's stdin and is NEVER handed to a
            # shell (mechanical-proxy.py `_MECH_STDIN_FENCE_RE` / `_run_mechanical`'s `input=`).
            # Resolving it against the script allowlist is a category error — the payload is
            # arbitrary markdown by construction. This mirrors the proxy's own disjointness rule:
            # its COMMAND regex requires `[ \t]*\r?\n` right after `relay-mech`, so it never
            # matches this opener. Counted separately rather than skipped, so a data fence still
            # cannot slip past the classifier unnoticed (acceptance #5's spirit).
            if line[col + len('relay-mech'):].startswith('-stdin'):
                stdin_markers.append((i + 1, col))
            else:
                markers.append((i + 1, line_offsets[i] + col))
        else:
            unclassified.append((i + 1, col, line))

if unclassified:
    for ln, col, line in unclassified:
        print(f"FAIL: unclassified 'relay-mech' mention at line {ln} (neither a real fence marker nor inside a // comment): {line!r}")
    sys.exit(1)

if not markers:
    print("FAIL: zero real relay-mech fence markers found — the proxy has nothing to dispatch, or the extractor is broken")
    sys.exit(1)

print(f"PASS: {len(markers)} real relay-mech COMMAND fence markers found (acceptance #1 count), {len(stdin_markers)} relay-mech-stdin DATA fence(s) correctly excluded from allowlist resolution, {len(comment_mentions)} comment-only mentions correctly excluded (acceptance #5 negative control), 0 unclassified")

close_re = re.compile(r"```|\\`\\`\\`")
script_re = re.compile(r"relay/scripts/([A-Za-z0-9_.-]+\.sh)")
bare_ident_re = re.compile(r"^[A-Za-z_$][A-Za-z0-9_$]*$")


def enclosing_func(marker_line):
    """Nearest function/arrow definition strictly above `marker_line`, for
    resolving a fence whose body is a bare parameter (one level of
    indirection — acceptance #3)."""
    func_def_re = re.compile(r"(?:async\s+)?function\s+([A-Za-z_$][\w$]*)\s*\(([^)]*)\)")
    arrow_def_re = re.compile(r"const\s+([A-Za-z_$][\w$]*)\s*=\s*\(([^)]*)\)\s*=>")
    for i in range(marker_line - 1, 0, -1):
        line = code_lines[i - 1]
        m = func_def_re.search(line) or arrow_def_re.search(line)
        if m:
            return m.group(1), i
    return None


def split_top_level_args(text):
    """Split on top-level commas only, skipping commas nested inside (),
    [], {}, or inside '...'/"..."/`...` string literals (backslash-escape
    aware)."""
    args, depth, quote, start, i, n = [], 0, None, 0, 0, len(text)
    while i < n:
        c = text[i]
        if quote:
            if c == '\\':
                i += 2
                continue
            if c == quote:
                quote = None
        else:
            if c in ("'", '"', '`'):
                quote = c
            elif c in '([{':
                depth += 1
            elif c in ')]}':
                depth -= 1
            elif c == ',' and depth == 0:
                args.append(text[start:i])
                start = i + 1
        i += 1
    args.append(text[start:])
    return [a.strip() for a in args]


def find_call_args(fname, def_line):
    """Every call site `fname(...)` in the comment-blanked source other than
    the definition line itself, as [(line_no, [arg_texts])]."""
    results = []
    call_re = re.compile(r"\b" + re.escape(fname) + r"\(")
    for m in call_re.finditer(src):
        ln = line_of(m.start())
        if ln == def_line:
            continue
        start = m.end()
        depth, quote, i = 1, None, start
        while i < len(src) and depth > 0:
            c = src[i]
            if quote:
                if c == '\\':
                    i += 2
                    continue
                if c == quote:
                    quote = None
            else:
                if c in ("'", '"', '`'):
                    quote = c
                elif c in '([{':
                    depth += 1
                elif c in ')]}':
                    depth -= 1
                    if depth == 0:
                        break
            i += 1
        results.append((ln, split_top_level_args(src[start:i])))
    return results


# (2) Resolve every marker to the concrete relay-script(s) it dispatches.
resolved = {}
fail = False

for ln, off_ in markers:
    marker_end = off_ + len("relay-mech")
    close_m = close_re.search(src, marker_end)
    if not close_m:
        print(f"FAIL: line {ln} — no closing fence marker found after the open marker (unresolvable)")
        fail = True
        continue
    cmd_src = src[marker_end:close_m.start()]
    scripts = set(script_re.findall(cmd_src))
    if scripts:
        resolved[ln] = scripts
        continue
    # No literal script path in the fence body — is it a single bare
    # identifier (a parameter), i.e. one level of indirection?
    stripped = " ".join(cmd_src.replace("\\n", " ").replace("'", " ").replace("+", " ").split())
    if not bare_ident_re.match(stripped):
        print(f"FAIL: line {ln} — fence body resolves to neither a literal relay script nor a single bare-identifier parameter (unresolvable): {cmd_src!r}")
        fail = True
        continue
    ident = stripped
    fe = enclosing_func(ln)
    if not fe:
        print(f"FAIL: line {ln} — fence body is bare identifier {ident!r} but no enclosing function/arrow definition was found above it (unresolvable indirection)")
        fail = True
        continue
    fname, def_line = fe
    func_def_re = re.compile(r"(?:async\s+)?function\s+" + re.escape(fname) + r"\s*\(([^)]*)\)")
    arrow_def_re = re.compile(r"const\s+" + re.escape(fname) + r"\s*=\s*\(([^)]*)\)\s*=>")
    mm = func_def_re.search(code_lines[def_line - 1]) or arrow_def_re.search(code_lines[def_line - 1])
    params = [p.strip() for p in mm.group(1).split(",") if p.strip()]
    if ident not in params:
        print(f"FAIL: line {ln} — fence body identifier {ident!r} is not a parameter of enclosing {fname}({', '.join(params)}) (unresolvable indirection)")
        fail = True
        continue
    idx = params.index(ident)
    call_arg_lists = find_call_args(fname, def_line)
    if not call_arg_lists:
        print(f"FAIL: line {ln} — fence body is parameter {ident!r} of {fname}() but no call sites were found (unresolvable indirection — beyond one level)")
        fail = True
        continue
    union_scripts, unresolved_call = set(), False
    for cln, args in call_arg_lists:
        if idx >= len(args) or not (arg_scripts := set(script_re.findall(args[idx]))):
            unresolved_call = True
            continue
        union_scripts |= arg_scripts
    if unresolved_call or not union_scripts:
        print(f"FAIL: line {ln} — one-level indirection via {fname}()'s call sites did not resolve parameter {ident!r} to a literal relay script at every call site (unresolvable beyond one level)")
        fail = True
        continue
    resolved[ln] = union_scripts

if fail:
    sys.exit(1)

print(f"PASS: resolved all {len(markers)} fences to concrete relay script(s) (acceptance #2/#3)")
for ln in sorted(resolved):
    print(f"  line {ln}: {sorted(resolved[ln])}")

# (3) Every resolved script must be in mechanical-proxy.py's
# ALLOWED_RELAY_SCRIPTS (acceptance #2 — the whole point of this test).
proxy_src = open(PROXY).read()
alw_m = re.search(r"ALLOWED_RELAY_SCRIPTS\s*=\s*frozenset\(\[(.*?)\]\)", proxy_src, re.S)
if not alw_m:
    print("FAIL: could not locate ALLOWED_RELAY_SCRIPTS frozenset in mechanical-proxy.py")
    sys.exit(1)
allowed = set(re.findall(r'"([^"]+\.sh)"', alw_m.group(1)))
print(f"PASS: parsed {len(allowed)} entries from ALLOWED_RELAY_SCRIPTS")

missing = False
for ln, scripts in sorted(resolved.items()):
    for s in sorted(scripts):
        if s not in allowed:
            print(f"FAIL: line {ln} dispatches {s!r} which is NOT in ALLOWED_RELAY_SCRIPTS (acceptance #2 — this is the runtime trap id:5bbb exists to close)")
            missing = True

if missing:
    sys.exit(1)

print("ALL PASS")
PYEOF
