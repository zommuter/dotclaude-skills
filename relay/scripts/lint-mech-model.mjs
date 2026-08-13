#!/usr/bin/env node
// lint-mech-model.mjs (id:4313) — every dispatch call (`agent()`, or its guarded
// wrapper `dispatchGuarded`, id:ed3f — the only one in the tree, id:3d78) in a Workflow JS script
// that carries a ```relay-mech fenced command must dispatch with `model: MECH_MODEL`, never a
// literal model name ('bash', 'haiku', …). MECH_MODEL resolves to 'bash' under a healthy proxy
// and 'haiku' under probe mode-a (id:4239) — a hop hardcoding either literal breaks the OTHER
// mode. Three real hops (discover-prelude, the discover-run shard, releaseLease) missed the
// id:4239 indirection and were fixed by loderite in 490ac6e; because discover-prelude is
// round-1's FIRST hop, probe mode-a killed the whole pool with zero units dispatched (run
// relay-20260730-115757-3504). This lint makes the invariant durable instead of relying on
// each future hop's author remembering it.
//
// id:ed3f — `releaseLease`'s fence dispatch was later routed through `dispatchGuarded` (id:3222,
// so a blocked/empty guarded call is recorded instead of silently vanishing), which moved the
// real dispatch out of a bare `agent(` call site: the literal text at the fence is now
// `dispatchGuarded({ ..., model: MECH_MODEL }, repo, fenceText)`, not `agent(fenceText, {...})`.
// A linter matching only the identifier `agent` stopped covering that hop — invisibly, since the
// coverage gap itself produces no test failure (a second route, the `model: MECH_MODEL` label
// line, happened to still hold the invariant for THIS hop). The next hop routed through a guard
// wrapper would lose coverage the same way. Matching the wrapper identifiers too closes that gap.
//
// SAME LEXER SHAPE AS lint-workflow-templates.mjs (id:71f2) — a single-pass character state
// machine tracking JS context (code / line-comment / block-comment / '…' / "…" / `…`
// template, with `${…}` substitution nesting), because a naive grep for `agent(` cannot
// tell a real call from the same text inside a comment or a string, and cannot correctly
// find the MATCHING close-paren of a call whose argument itself contains nested parens
// (e.g. a fenced shell command with `$(...)`).
//
// Non-fence `agent()` calls (handback-followup, integrate, gaming-log — real inference
// calls) are explicitly OUT of scope: they legitimately hardcode 'haiku'/'sonnet' and must
// not be swept up.
//
// Usage: lint-mech-model.mjs [file-or-repo-root ...]
//   no args  → repo root via the script's own location (../.. of relay/scripts)
//   a dir    → scan its relay/scripts for workflow scripts
//   a file   → lint exactly that file
// Exit 0 = clean; exit 1 = one or more violations (each printed as file:line:col);
// exit 2 = misuse (no such path).

import { readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, join, resolve, basename } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))           // …/relay/scripts
const DEFAULT_ROOT = resolve(HERE, '..', '..')                 // repo root

const isWordChar = (c) => c !== undefined && /[A-Za-z0-9_$]/.test(c)
const DIVISION_AFTER = (c) => isWordChar(c) || c === ')' || c === ']'
const regexAllowed = (prevSig) => prevSig === '' || !DIVISION_AFTER(prevSig)

// Call identifiers that dispatch a hop and so are in scope for this lint: the bare `agent`
// call, plus the guarded wrapper that routes a fence-carrying prompt through `agent()`
// internally without the literal text `agent(` at the call site itself (id:ed3f —
// `dispatchGuarded` moved `releaseLease`'s fence dispatch out of a bare `agent(` call, and a
// linter matching only `agent` silently stopped covering that hop). Both share the same
// (opts-ish-first-or-last, prompt) shape closely enough that substring-searching the raw call
// text for the fence marker and the `model:` property (below) works unchanged regardless of
// argument order.
//
// id:3d78 — this set TRACKS THE TREE; it does not speculate. The ratified id:ed3f spec says
// verbatim: "`dispatchGuarded` is the ONLY such wrapper in the tree today
// (`agentGuarded`/`safeAgent` do not exist — do not invent matchers for them)". `5c425fc`
// shipped them anyway — inert (they match nothing), so a green suite never surfaced it, but a
// derived implementation contradicting its ratified source in the permissive direction. A new
// wrapper earns a matcher when it EXISTS, added together with the spec amendment.
// Pinned by tests/test_mech_model_lint_identifier_set_3d78.sh in BOTH directions.
const AGENT_CALL_IDENTIFIERS = new Set(['agent', 'dispatchGuarded'])

// Find every top-level guarded-dispatch CALL in `src` — i.e. one of AGENT_CALL_IDENTIFIERS, not
// preceded by a word char or `.` (so `someAgent(` / `x.agent(` never match), immediately
// followed (modulo whitespace) by `(`, whose ARGUMENT LIST is captured with correct
// paren-depth tracking through nested strings/comments/templates/regex/parens.
// Returns [{ raw, startIdx, line }] — raw includes the outer parens.
function findAgentCalls(src) {
  const calls = []
  let line = 1
  let state = 'code' // 'code' | 'line' | 'block' | 'sq' | 'dq' | 'tmpl' | 'regex'
  const tmplStack = []
  let braceDepth = 0
  let prevSig = ''
  let inRegexClass = false
  let parenDepth = 0
  const callStack = [] // { depth, startIdx, startLine }
  const lineAt = [] // lineAt[idx] = line number of char at idx (built lazily via a running counter)

  const n = src.length
  let i = 0
  while (i < n) {
    const c = src[i]
    const next = src[i + 1]
    lineAt[i] = line
    if (c === '\n') line++

    if (state === 'code') {
      if (c === '/' && next === '/') { state = 'line'; i += 2; continue }
      if (c === '/' && next === '*') { state = 'block'; i += 2; continue }
      if (c === '/' && regexAllowed(prevSig)) {
        state = 'regex'; inRegexClass = false; prevSig = '/'; i++; continue
      }
      if (c === "'") { state = 'sq'; prevSig = "'"; i++; continue }
      if (c === '"') { state = 'dq'; prevSig = '"'; i++; continue }
      if (c === '`') { state = 'tmpl'; prevSig = '`'; i++; continue }
      if (c === '(') {
        parenDepth++
        // was this exact '(' preceded (mod whitespace) by the bare word "agent"?
        let k = i - 1
        while (k >= 0 && /\s/.test(src[k])) k--
        const wEnd = k + 1
        let wStart = wEnd
        while (wStart > 0 && isWordChar(src[wStart - 1])) wStart--
        const word = src.slice(wStart, wEnd)
        const preWord = src[wStart - 1]
        if (AGENT_CALL_IDENTIFIERS.has(word) && !isWordChar(preWord) && preWord !== '.') {
          callStack.push({ depth: parenDepth, startIdx: wStart, startLine: lineAt[wStart] })
        }
        prevSig = '('
        i++; continue
      }
      if (c === ')') {
        const closingDepth = parenDepth
        parenDepth--
        if (callStack.length && callStack[callStack.length - 1].depth === closingDepth) {
          const call = callStack.pop()
          calls.push({ raw: src.slice(call.startIdx, i + 1), startIdx: call.startIdx, line: call.startLine })
        }
        prevSig = ')'
        i++; continue
      }
      if (c === '{') { braceDepth++; prevSig = '{'; i++; continue }
      if (c === '}') {
        braceDepth--
        if (tmplStack.length && tmplStack[tmplStack.length - 1].braceDepth === braceDepth) {
          tmplStack.pop(); state = 'tmpl'; prevSig = '`'; i++; continue
        }
        prevSig = '}'; i++; continue
      }
      if (!/\s/.test(c)) prevSig = c
      i++; continue
    }

    switch (state) {
      case 'regex': {
        if (c === '\\') { i += 2; continue }
        if (c === '[') { inRegexClass = true; i++; continue }
        if (c === ']') { inRegexClass = false; i++; continue }
        if (c === '/' && !inRegexClass) { state = 'code'; prevSig = '/'; i++; continue }
        i++; continue
      }
      case 'line': {
        if (c === '\n') state = 'code'
        i++; continue
      }
      case 'block': {
        if (c === '*' && next === '/') { state = 'code'; i += 2; continue }
        i++; continue
      }
      case 'sq': {
        if (c === '\\') { i += 2; continue }
        if (c === "'") { state = 'code'; prevSig = "'" }
        i++; continue
      }
      case 'dq': {
        if (c === '\\') { i += 2; continue }
        if (c === '"') { state = 'code'; prevSig = '"' }
        i++; continue
      }
      case 'tmpl': {
        if (c === '\\') { i += 2; continue }
        if (c === '$' && next === '{') {
          tmplStack.push({ braceDepth })
          braceDepth++
          state = 'code'
          i += 2; continue
        }
        if (c === '`') { state = 'code'; prevSig = '`'; i++; continue }
        i++; continue
      }
    }
  }
  return calls
}

// Does the call's argument text carry a ```relay-mech fence? Fence-open text is always a
// literal source substring (even when the command body is concatenated from variables), so
// a direct substring search over the raw call text is reliable.
const FENCE_MARKER = 'relay-mech'

// Blank out // and /* */ comment content (preserving newlines, so line math elsewhere
// stays valid) — WITHOUT touching string/template content, so a doc-comment that mentions
// `model:"bash"` as prose (id:6176's convention throughout this file) is never mistaken for
// the call's real options object. Assumes `text` is itself syntactically well-formed (it is
// always a balanced-paren call slice from findAgentCalls), so no separate paren tracking
// is needed here — just comment/string state.
function stripComments(text) {
  let out = ''
  let state = 'code' // 'code' | 'line' | 'block' | 'sq' | 'dq' | 'tmpl'
  const n = text.length
  let i = 0
  while (i < n) {
    const c = text[i]
    const next = text[i + 1]
    if (state === 'code') {
      if (c === '/' && next === '/') { state = 'line'; out += '  '; i += 2; continue }
      if (c === '/' && next === '*') { state = 'block'; out += '  '; i += 2; continue }
      if (c === "'") { state = 'sq'; out += c; i++; continue }
      if (c === '"') { state = 'dq'; out += c; i++; continue }
      if (c === '`') { state = 'tmpl'; out += c; i++; continue }
      out += c; i++; continue
    }
    if (state === 'line') {
      if (c === '\n') { state = 'code'; out += '\n'; i++; continue }
      out += ' '; i++; continue
    }
    if (state === 'block') {
      if (c === '*' && next === '/') { state = 'code'; out += '  '; i += 2; continue }
      out += (c === '\n' ? '\n' : ' '); i++; continue
    }
    if (state === 'sq') {
      if (c === '\\') { out += text.slice(i, i + 2); i += 2; continue }
      if (c === "'") state = 'code'
      out += c; i++; continue
    }
    if (state === 'dq') {
      if (c === '\\') { out += text.slice(i, i + 2); i += 2; continue }
      if (c === '"') state = 'code'
      out += c; i++; continue
    }
    if (state === 'tmpl') {
      if (c === '\\') { out += text.slice(i, i + 2); i += 2; continue }
      if (c === '`') state = 'code'
      out += c; i++; continue
    }
  }
  return out
}

// Extract the `model:` property's value token from a call's raw text, or null if absent.
// Handles: bare identifier (MECH_MODEL), single/double/template-quoted string literals.
// Comments are stripped first so a doc-comment mentioning `model:"bash"` as PROSE (this
// file's own id:6176 convention) is never mistaken for the real options object.
function extractModel(raw) {
  const code = stripComments(raw)
  const m = code.match(/model\s*:\s*(MECH_MODEL|'[^']*'|"[^"]*"|`[^`]*`|[A-Za-z_$][A-Za-z0-9_$]*)/)
  return m ? m[1] : null
}

function lintSource(src) {
  const violations = []
  for (const call of findAgentCalls(src)) {
    const code = stripComments(call.raw)
    if (!code.includes(FENCE_MARKER)) continue // non-fence call (a comment MENTIONING the
    // fence, with no real fence in the prompt, does not count): out of scope
    const model = extractModel(call.raw)
    if (model === 'MECH_MODEL') continue // clean
    const col = 0
    if (model === null) {
      violations.push({ line: call.line, col, msg: 'fence-carrying agent() call has no model: property (expected model: MECH_MODEL)' })
    } else {
      violations.push({ line: call.line, col, msg: `fence-carrying agent() call hardcodes model: ${model} (expected model: MECH_MODEL) — breaks under probe mode-a or a healthy proxy, whichever ${model} doesn't match` })
    }
  }
  return violations
}

function isWorkflowScript(file) {
  const bn = basename(file)
  if (!/\.(mjs|js)$/.test(bn)) return false
  if (bn === basename(fileURLToPath(import.meta.url))) return false // never lint self
  if (/\.workflow\.js$/.test(bn)) return true
  try {
    return readFileSync(file, 'utf8').includes('export const meta')
  } catch { return false }
}

function collectFromDir(root) {
  const scriptsDir = join(root, 'relay', 'scripts')
  let entries
  try { entries = readdirSync(scriptsDir) } catch { return [] }
  return entries
    .map((e) => join(scriptsDir, e))
    .filter((p) => { try { return statSync(p).isFile() } catch { return false } })
    .filter(isWorkflowScript)
    .sort()
}

function main(argv) {
  const args = argv.slice(2)
  const paths = args.length ? args : [DEFAULT_ROOT]
  const files = []
  for (const p of paths) {
    const abs = resolve(p)
    let st
    try { st = statSync(abs) } catch {
      process.stderr.write(`lint-mech-model: no such path: ${p}\n`)
      return 2
    }
    if (st.isDirectory()) files.push(...collectFromDir(abs))
    else files.push(abs)
  }

  if (files.length === 0) {
    process.stderr.write('lint-mech-model: no workflow JS scripts found\n')
    return 2
  }

  let total = 0
  for (const f of files) {
    let src
    try { src = readFileSync(f, 'utf8') } catch {
      process.stderr.write(`lint-mech-model: cannot read ${f}\n`)
      return 2
    }
    const vs = lintSource(src)
    for (const v of vs) {
      total++
      process.stdout.write(`${f}:${v.line}:${v.col}: ${v.msg}\n`)
    }
  }

  if (total > 0) {
    process.stdout.write(`lint-mech-model: ${total} violation(s) — a fenced mechanical hop must dispatch model: MECH_MODEL, never a literal.\n`)
    return 1
  }
  process.stdout.write(`lint-mech-model: ${files.length} workflow script(s) clean.\n`)
  return 0
}

process.exit(main(process.argv))
