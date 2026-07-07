#!/usr/bin/env node
// lint-workflow-templates.mjs (id:71f2) — a parser/lexer-aware lint that flags an
// UNESCAPED backtick used as literal text INSIDE a template literal in a Workflow JS
// script (the relay pool's live engine). `node --check` is NOT sufficient: the buggy
// relay-loop.js (commit 178b8db^) added `hard` (backtick-wrapped) inside the shardPrompt
// template literal WITHOUT escaping; `node --check` AND `make test` both PASSED, yet the
// Workflow tool's stricter template-literal parser rejected the whole script
// ("Unexpected token (763:1527)") so `/relay --afk` could not launch the pool at all.
//
// WHY A REAL LEXER, NOT A GREP: the same `` `word` `` text is BENIGN when escaped
// (`` \`word\` `` — the relay shard prompt is full of these) or when it appears in a
// `//` / `/* */` comment or an ordinary '…'/"…" string. A line grep cannot tell those
// apart from the unescaped bug. This script runs a single-pass character lexer that
// tracks JS context (code / line-comment / block-comment / '…' / "…" / `…` template,
// with `${…}` substitution nesting) and flags ONLY an unescaped backtick that, while in
// template-literal *content*, is immediately followed by an identifier char
// (`[A-Za-z0-9_$]`) — the `` `hard`` desync signature. A legitimate template CLOSE is
// always followed by an operator / punctuator / whitespace / EOF, never a glued word
// char; an escaped `` \` `` is consumed by the escape rule and never seen as a close; a
// backtick inside a comment/string is in the wrong state and never reaches the rule.
//
// Targets every workflow JS script: relay-loop.js plus any *.js/*.mjs under relay/scripts
// containing `export const meta` (the Workflow entry marker) or named `*.workflow.js`.
//
// Usage: lint-workflow-templates.mjs [file-or-repo-root ...]
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

// A `/` starts a regex literal (vs division) when the previous significant code char is
// empty/start-of-input or an operator/opening context expecting a value — i.e. NOT after
// an identifier char, a number, `)`, or `]` (those are division). Conservative: anything
// not clearly a "division-after-value" context is treated as regex-start.
const DIVISION_AFTER = (c) => isWordChar(c) || c === ')' || c === ']'
const regexAllowed = (prevSig) => prevSig === '' || !DIVISION_AFTER(prevSig)

// Lex `src` and return an array of violations {line, col, ctx}.
// Single forward pass, no regex over the whole file (regex can't track nesting).
function lintSource(src) {
  const violations = []
  let line = 1, col = 0
  // template-substitution stack: each entry is the brace depth at which we re-enter
  // template context. While inside a `${ … }` we are in CODE state but must pop back to
  // TEMPLATE on the matching `}`.
  const tmplStack = [] // each = { braceDepth }
  let braceDepth = 0
  // state: 'code' | 'line' | 'block' | 'sq' | 'dq' | 'tmpl' | 'regex'
  let state = 'code'
  // To tell a regex literal `/…/` from a division `/`, track the previous SIGNIFICANT
  // (non-whitespace, non-comment) code char. A `/` begins a regex when the prior
  // significant char is empty or one of the operator/opening contexts where a value is
  // expected (not after an identifier/number/`)`/`]` — those mean division). Keyword
  // forms like `return /re/` end in a word char but are rare in this codebase and a
  // mis-classification there only risks a false negative on a backtick INSIDE that
  // regex (no false positive on real code), so the simple char rule is safe here.
  let prevSig = ''
  let inRegexClass = false // inside a [...] char class, where `/` does not end the regex

  const n = src.length
  let i = 0
  while (i < n) {
    const c = src[i]
    const next = src[i + 1]
    // track position
    if (c === '\n') { line++; col = 0 } else { col++ }

    switch (state) {
      case 'code': {
        if (c === '/' && next === '/') { state = 'line'; i += 2; col++; continue }
        if (c === '/' && next === '*') { state = 'block'; i += 2; col++; continue }
        if (c === '/' && regexAllowed(prevSig)) {
          state = 'regex'; inRegexClass = false; prevSig = '/'; i++; continue
        }
        if (c === "'") { state = 'sq'; prevSig = "'"; i++; continue }
        if (c === '"') { state = 'dq'; prevSig = '"'; i++; continue }
        if (c === '`') { state = 'tmpl'; prevSig = '`'; i++; continue }
        if (c === '{') { braceDepth++; prevSig = '{'; i++; continue }
        if (c === '}') {
          braceDepth--
          // closing a `${ … }` substitution → back to its template literal
          if (tmplStack.length && tmplStack[tmplStack.length - 1].braceDepth === braceDepth) {
            tmplStack.pop()
            state = 'tmpl'
            prevSig = '`'
            i++; continue
          }
          prevSig = '}'
          i++; continue
        }
        if (!/\s/.test(c)) prevSig = c
        i++; continue
      }
      case 'regex': {
        if (c === '\\') { i += 2; col++; continue }   // escaped regex char
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
        if (c === '*' && next === '/') { state = 'code'; i += 2; col++; continue }
        i++; continue
      }
      case 'sq': {
        if (c === '\\') { i += 2; col++; continue }   // escape: skip next char
        if (c === "'") { state = 'code'; prevSig = "'" }  // closed string = a value
        i++; continue
      }
      case 'dq': {
        if (c === '\\') { i += 2; col++; continue }
        if (c === '"') { state = 'code'; prevSig = '"' }
        i++; continue
      }
      case 'tmpl': {
        if (c === '\\') { i += 2; col++; continue }   // escaped char (incl. \` and \$) — skip
        if (c === '$' && next === '{') {
          // enter a substitution: CODE context until the matching brace
          tmplStack.push({ braceDepth })
          braceDepth++
          state = 'code'
          i += 2; col++; continue
        }
        if (c === '`') {
          // An unescaped backtick in template content. In valid JS this CLOSES the
          // literal. The id:71f2 bug is an UNINTENDED close with two desync signatures:
          //
          //  (a) `…`word`…`  — the backtick is glued to a following identifier char.
          //      This is a PARSE error in the strict Workflow parser (the original 178b8db
          //      `` `hard`` incident). Caught by isWordChar(next).
          //
          //  (b) `…`.member`…` — the backtick is followed by a `.identifier` chain that is
          //      itself followed by ANOTHER backtick. That parses as a TAGGED TEMPLATE
          //      `(…).member`…`` — VALID grammar, so `node --check` AND the Workflow parser
          //      both pass, but `.member` is undefined at runtime → "undefined is not a
          //      function", thrown synchronously → whole pool crash (the `.timer` incident,
          //      2026-07-07, id:5bac). A LEGITIMATE method-call close (`\`text\`.trim()`) is
          //      followed by `(`, never a backtick, so this does not false-positive on it.
          if (isWordChar(next)) {
            violations.push({ line, col, ctx: snippet(src, i) })
            // stay in tmpl so we keep scanning the rest of the (malformed) literal for
            // further violations rather than mis-tracking state from this point.
            i++; continue
          }
          if (next === '.' && isTaggedMemberClose(src, i, n)) {
            violations.push({ line, col, ctx: snippet(src, i) })
            i++; continue   // stay in tmpl (as above) to keep scanning
          }
          state = 'code'
          prevSig = '`'   // closed template = a value
          i++; continue
        }
        i++; continue
      }
    }
    i++
  }
  return violations
}

// From a backtick at index `i` (whose next char is `.`), is the tail a tagged-template
// desync `(…).ident(.ident)*`…` ? True iff a `.identifier` member chain is immediately
// followed by another backtick (the reopened template that makes it a tagged call). A real
// `.method()` close is followed by `(` and returns false, so legitimate `\`text\`.trim()`
// chaining is never flagged.
function isTaggedMemberClose(src, i, n) {
  let j = i + 1
  let sawMember = false
  while (j < n && src[j] === '.') {
    j++
    const start = j
    while (j < n && isWordChar(src[j])) j++
    if (j === start) return false   // a bare `.` with no identifier → not a member chain
    sawMember = true
  }
  return sawMember && src[j] === '`'
}

// A short single-line snippet around index i for the diagnostic.
function snippet(src, i) {
  let a = i, b = i
  while (a > 0 && src[a - 1] !== '\n' && i - a < 30) a--
  while (b < src.length && src[b] !== '\n' && b - i < 30) b++
  return src.slice(a, b).replace(/\s+/g, ' ').trim()
}

// Is `file` a workflow JS script? (contains `export const meta`, or *.workflow.js)
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
      process.stderr.write(`lint-workflow-templates: no such path: ${p}\n`)
      return 2
    }
    if (st.isDirectory()) files.push(...collectFromDir(abs))
    else files.push(abs)   // explicit file: lint as-is even without the meta marker
  }

  if (files.length === 0) {
    process.stderr.write('lint-workflow-templates: no workflow JS scripts found\n')
    return 2
  }

  let total = 0
  for (const f of files) {
    let src
    try { src = readFileSync(f, 'utf8') } catch {
      process.stderr.write(`lint-workflow-templates: cannot read ${f}\n`)
      return 2
    }
    const vs = lintSource(src)
    for (const v of vs) {
      total++
      process.stdout.write(`${f}:${v.line}:${v.col}: unescaped backtick inside a template literal (escape it as \\\` or use \${…}) — "${v.ctx}"\n`)
    }
  }

  if (total > 0) {
    process.stdout.write(`lint-workflow-templates: ${total} violation(s) — these crash the live Workflow parser even though node --check passes.\n`)
    return 1
  }
  process.stdout.write(`lint-workflow-templates: ${files.length} workflow script(s) clean.\n`)
  return 0
}

process.exit(main(process.argv))
