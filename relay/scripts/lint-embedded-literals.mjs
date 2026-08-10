#!/usr/bin/env node
// lint-embedded-literals.mjs (id:ef9e) — a lexer-aware lint that extracts a Python or awk
// program embedded in a bash single-quoted CLI argument (`python3 -c '…'` / `awk '…'`) and
// runs the GUEST language's own syntax checker against it, so a quoting hazard that
// corrupts the embedded body is caught at lint time instead of at whichever runtime path
// happens to execute it.
//
// WHY THIS EXISTS (id:ef9e): `discover-repo.sh` embeds a ~90-line Python program in a
// single-quoted `python3 -c '...'`. Adding a comment containing `lib-state-claim.sh's`
// closed the bash single-quote at that apostrophe — bash single-quotes have NO escaping,
// so the FIRST `'` after the opening one ends the string, full stop. `bash -n` stayed
// clean (the truncated remainder was still syntactically valid bash — just a shorter
// string, followed by stray bareword tokens), and the corruption surfaced only at RUNTIME
// as a Python `IndentationError`, in a traceback pointing at a line the author never wrote.
// This is the THIRD instance of one class — a foreign language embedded in a host
// literal, where the host's syntax checker cannot see the guest (see broker-curl.sh's
// apostrophe gotcha and id:5bac/aec5's relay-loop.js template-literal desyncs) — which is
// what lifts it over the id:415b determinism gate.
//
// SCOPE: only the single-quoted `python3 -c '…'` / `awk '…'` CLI-argument form is
// vulnerable to this bug (single quotes have no escaping — an apostrophe anywhere inside
// silently truncates the string early). A HEREDOC body (`python3 - <<'PYEOF' … PYEOF`,
// the dominant pattern in this repo) is NOT vulnerable: the shell takes everything
// verbatim up to the delimiter LINE, with no quote-parsing inside at all — so heredoc
// bodies are skipped by this lint (out of scope; not the failure mode being guarded), but
// their content is scanned character-for-character to correctly maintain lexer state
// (an apostrophe inside a heredoc body must NOT be mistaken for a bash quote toggle,
// or every subsequent quote in the file mis-parses).
//
// HONEST LIMIT: extraction is heuristic, not a real bash parser. A body built by string
// CONCATENATION (`'foo'"$bar"`, `'foo'\''bar'`) or carrying shell INTERPOLATION (a
// double-quoted argument, which may contain `$…`) cannot be isolated as a literal guest
// program — such cases are reported UNCHECKED and counted, never silently treated as
// clean (the no-silent-swallow rule: a lint that quietly skips what it cannot parse is a
// vacuous guard).
//
// Usage: lint-embedded-literals.mjs [file-or-repo-root ...]
//   no args  → repo root via the script's own location (../.. of relay/scripts)
//   a dir    → scan its relay/scripts/*.sh
//   a file   → lint exactly that file
// Exit 0 = clean (UNCHECKED bodies do not fail the run — they're reported, not hidden);
// exit 1 = one or more REJECTED (syntactically invalid) embedded bodies;
// exit 2 = misuse (no such path).

import { readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, join, resolve, basename } from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawnSync } from 'node:child_process'

const HERE = dirname(fileURLToPath(import.meta.url))           // …/relay/scripts
const DEFAULT_ROOT = resolve(HERE, '..', '..')                 // repo root

const isWS = (c) => c === ' ' || c === '\t' || c === '\r'

// ---------------------------------------------------------------------------
// A small recursive-descent bash lexer. Bash quoting nests: a `$( … )` command
// substitution opens a fresh CODE region with its OWN independent quoting (its quotes
// do not interact with an enclosing double-quote's terminator), and single quotes
// suppress ALL expansion (including `$(...)`) — this repo's real vulnerable pattern,
// `rec_disposition="$(printf '%s' "$x" | python3 -c '…')"`, requires exactly this
// nesting to parse correctly: a NAIVE scan that just hunts for the next unescaped `"`
// closes on the inner `"$x"` and mis-locates everything downstream.
//
// scanCode(src, i, n, mode, candidates) scans a CODE region (top-level, or inside a
// `$( … )`) starting at index i and returns the index just past where this region
// ends (EOF for 'top'; just past the matching ')' for 'cmdsub'). It pushes a
// candidate for every `python3 -c '…'` / `awk '…'` (or "…") CLI-argument it finds
// directly in this region — nested `$(...)` regions are scanned recursively so a
// candidate embedded inside one is still found, independent of any enclosing quote.
// ---------------------------------------------------------------------------
function scanCode(src, i, n, mode, candidates) {
  let parenDepth = 0 // only meaningful for mode==='cmdsub': depth of '(' opened WITHIN this region
  let pendingWords = []
  let curWordStart = -1

  const flushWord = (end) => {
    if (curWordStart >= 0 && end > curWordStart) {
      pendingWords.push(src.slice(curWordStart, end))
      if (pendingWords.length > 4) pendingWords.shift()
    }
    curWordStart = -1
  }
  const resetWords = () => { pendingWords = []; curWordStart = -1 }
  function detectLang() {
    if (pendingWords.length >= 2) {
      const last2 = pendingWords.slice(-2)
      if (/^python3(\.\d+)?$/.test(last2[0]) && last2[1] === '-c') return 'python3'
    }
    if (pendingWords.length >= 1) {
      let k = pendingWords.length - 1
      while (k >= 0 && /^-/.test(pendingWords[k])) k--
      if (k >= 0 && pendingWords[k] === 'awk') return 'awk'
    }
    return null
  }

  while (i < n) {
    const c = src[i]

    if (c === '\n') { flushWord(i); resetWords(); i++; continue }

    // comment: `#` at start-of-region, or preceded by whitespace/an operator char.
    if (c === '#' && (i === 0 || isWS(src[i - 1]) || src[i - 1] === '\n' || ';&|(){}'.includes(src[i - 1]))) {
      flushWord(i)
      while (i < n && src[i] !== '\n') i++
      continue
    }

    // heredoc: `<<`/`<<-` then optional quote + delimiter word; skip the body verbatim
    // (an apostrophe inside it must NOT toggle our quote state — it is genuinely inert
    // to bash there, and this repo's dominant `python3 - <<'PYEOF'` pattern is exactly
    // the SAFE form this lint does not need to check).
    if (c === '<' && src[i + 1] === '<') {
      let j = i + 2
      let dashed = false
      if (src[j] === '-') { dashed = true; j++ }
      while (isWS(src[j])) j++
      let delim = ''
      if (src[j] === "'" || src[j] === '"') {
        const q = src[j]; j++
        const start = j
        while (j < n && src[j] !== q) j++
        delim = src.slice(start, j)
        if (src[j] === q) j++
      } else if (/[A-Za-z0-9_]/.test(src[j] || '')) {
        const start = j
        while (j < n && /[A-Za-z0-9_]/.test(src[j])) j++
        delim = src.slice(start, j)
      }
      if (delim) {
        let k = j
        while (k < n && src[k] !== '\n') k++
        let scan = k + 1
        for (;;) {
          let lineEnd = src.indexOf('\n', scan)
          if (lineEnd === -1) lineEnd = n
          const rawLine = src.slice(scan, lineEnd)
          const testLine = dashed ? rawLine.replace(/^\t+/, '') : rawLine
          if (testLine === delim) { i = lineEnd < n ? lineEnd + 1 : n; break }
          if (lineEnd >= n) { i = n; break }
          scan = lineEnd + 1
        }
        resetWords()
        continue
      }
      flushWord(i); i += 2; continue
    }

    if (c === '\\') { flushWord(i); i += 2; continue }

    // old-style backtick command substitution: opaque hop to the next unescaped
    // backtick. Rare in this codebase (modern scripts use `$(...)`) and NOT recursed
    // into for candidates — an honest, documented limitation, not silent corruption of
    // surrounding state (the backtick pair is fully consumed so nothing downstream
    // desyncs).
    if (c === '`') {
      flushWord(i)
      let j = i + 1
      while (j < n && src[j] !== '`') { if (src[j] === '\\') j++; j++ }
      i = j < n ? j + 1 : n
      resetWords()
      continue
    }

    if (c === "'") {
      // A quote GLUED to an in-progress bareword (curWordStart already active, no
      // whitespace between them — e.g. `-F'\t'`) is a CONTINUATION of that word (the
      // flag's own value), never the command's program argument, even if pendingWords
      // currently ends in `awk`/`python3 -c` from an EARLIER, already-flushed token.
      // Only a quote starting a fresh word (immediately preceded by whitespace/operator)
      // can be the program position.
      const glued = curWordStart >= 0
      const lang = glued ? null : detectLang()
      flushWord(i)
      const openIdx = i
      let j = i + 1
      while (j < n && src[j] !== "'") j++ // NO escaping inside '...' — this is the real rule
      const closeIdx = j
      if (lang) pushCandidate(candidates, src, lang, "'", openIdx, closeIdx, n,
        closeIdx < n ? src.slice(openIdx + 1, closeIdx) : null,
        closeIdx >= n ? 'unterminated single-quoted string' : null)
      i = closeIdx < n ? closeIdx + 1 : n
      // A glued quote (flag value) keeps the command context alive (e.g. `awk` must
      // still be recognized for the REAL program that follows `-F'\t'`); only a
      // free-standing quote resets it.
      if (!glued) resetWords()
      continue
    }

    if (c === '"') {
      const glued = curWordStart >= 0
      const lang = glued ? null : detectLang()
      flushWord(i)
      const openIdx = i
      const { end, hasInterp } = scanDquote(src, i + 1, n, candidates)
      if (lang) {
        const raw = end - 1 > openIdx + 1 ? src.slice(openIdx + 1, end - 1) : ''
        pushCandidate(candidates, src, lang, '"', openIdx, end - 1, n,
          (!hasInterp && end <= n) ? raw.replace(/\\(["\\$`])/g, '$1') : null,
          end > n ? 'unterminated double-quoted string' : (hasInterp ? 'double-quoted body carries $/` interpolation' : null))
      }
      i = end
      if (!glued) resetWords()
      continue
    }

    if (c === '$' && src[i + 1] === '(') {
      flushWord(i)
      i = scanCode(src, i + 2, n, 'cmdsub', candidates)
      resetWords()
      continue
    }

    if (mode === 'cmdsub') {
      if (c === '(') { parenDepth++; flushWord(i); i++; continue }
      if (c === ')') {
        if (parenDepth === 0) { flushWord(i); return i + 1 } // closes THIS $(...)
        parenDepth--; flushWord(i); i++; continue
      }
    }

    if (isWS(c)) flushWord(i)
    else if (curWordStart < 0 && /[A-Za-z0-9_.\/-]/.test(c)) curWordStart = i
    i++
  }
  flushWord(n)
  return n
}

// Scans double-quote CONTENT starting just after the opening `"`. Recognizes `\X`
// escapes and recurses into `$( … )` (double quotes still allow command substitution,
// with its own independent quoting — same recursion as top-level). Returns the index
// just PAST the closing `"` (== n+1 sentinel-safe if unterminated: caller checks
// end > n) and whether any `$`/backtick interpolation was seen directly in this
// dquote's own text (nested `$(...)` content doesn't count against the OUTER body —
// it is scanned and reported on its own, via the shared `candidates` array).
function scanDquote(src, i, n, candidates) {
  let hasInterp = false
  while (i < n) {
    const c = src[i]
    if (c === '\\') { i += 2; continue }
    if (c === '"') return { end: i + 1, hasInterp }
    if (c === '$' && src[i + 1] === '(') {
      hasInterp = true
      i = scanCode(src, i + 2, n, 'cmdsub', candidates)
      continue
    }
    if (c === '$' || c === '`') hasInterp = true
    i++
  }
  return { end: n + 1, hasInterp } // unterminated
}

// A closing quote is glued to more of the SAME shell word — i.e. the value is built by
// CONCATENATION, e.g. `'BIG...' ... 'more'` with the "..." glued on with no whitespace —
// unless the immediately-following char is undefined (EOF/last char) or one of the
// characters that genuinely end a shell word: whitespace, newline, or a metacharacter
// (`;|&<>)}`, or a `#` starting a NEW comment — a `#` is only a comment-starter when
// preceded by whitespace, which glued-immediately-after never is). ANY other character —
// including one as unremarkable as a literal `.` — continues the same word and must be
// treated as concatenation, not a clean close (the real-world case this must catch: two
// single-quoted spans separated only by a literal `...` ellipsis).
const WORD_TERMINATOR = new Set([' ', '\t', '\r', '\n', ';', '|', '&', '<', '>', ')', '}'])
function pushCandidate(candidates, src, lang, quote, openIdx, closeIdx, n, body, forcedReason) {
  let isolable = body !== null && !forcedReason
  let reason = forcedReason
  if (isolable) {
    const after = src[closeIdx + 1]
    if (after !== undefined && !WORD_TERMINATOR.has(after)) {
      isolable = false
      reason = 'concatenated with adjacent shell word (cannot isolate)'
    }
  }
  candidates.push({
    lang, quote, openIdx, closeIdx,
    line: 1 + (src.slice(0, openIdx).match(/\n/g) || []).length,
    body: isolable ? body : null,
    isolable, reason,
  })
}

function scanBash(src) {
  const candidates = []
  scanCode(src, 0, src.length, 'top', candidates)
  return candidates
}

// ---------------------------------------------------------------------------
// Guest syntax checkers — compile-only, never execute the embedded body.
// ---------------------------------------------------------------------------
let _gawkChecked = false
let _gawkAvailable = false
function gawkAvailable() {
  if (_gawkChecked) return _gawkAvailable
  _gawkChecked = true
  try {
    const r = spawnSync('awk', ['--version'], { encoding: 'utf8' })
    _gawkAvailable = r.status === 0 && /GNU Awk/.test(r.stdout || '')
  } catch { _gawkAvailable = false }
  return _gawkAvailable
}

function checkPython(body) {
  const py = `
import sys, ast
try:
    ast.parse(sys.stdin.read())
except SyntaxError as e:
    sys.stderr.write(f"{e.__class__.__name__}: {e.msg} (line {e.lineno})")
    sys.exit(1)
`
  const r = spawnSync('python3', ['-c', py], { input: body, encoding: 'utf8' })
  if (r.error) return { ok: null, detail: `python3 unavailable: ${r.error.message}` }
  if (r.status !== 0) return { ok: false, detail: (r.stderr || '').trim() || 'syntax error' }
  return { ok: true }
}

function checkAwk(body) {
  if (!gawkAvailable()) return { ok: null, detail: 'gawk --pretty-print unavailable on this host' }
  // --pretty-print parses (and reformats) the program WITHOUT executing it (gawk 4+).
  const r = spawnSync('awk', ['--pretty-print=/dev/null', '--', body], { input: '', encoding: 'utf8' })
  if (r.error) return { ok: null, detail: `awk unavailable: ${r.error.message}` }
  if (r.status !== 0) return { ok: false, detail: (r.stderr || '').trim() || 'syntax error' }
  return { ok: true }
}

// ---------------------------------------------------------------------------
// File / directory collection.
// ---------------------------------------------------------------------------
function collectFromDir(root) {
  const scriptsDir = join(root, 'relay', 'scripts')
  let entries
  try { entries = readdirSync(scriptsDir) } catch { return [] }
  return entries
    .map((e) => join(scriptsDir, e))
    .filter((p) => { try { return statSync(p).isFile() } catch { return false } })
    .filter((p) => basename(p).endsWith('.sh'))
    .sort()
}

function lintFile(file) {
  let src
  try { src = readFileSync(file, 'utf8') } catch (e) {
    return { rejected: [], unchecked: 0, error: `cannot read ${file}: ${e.message}` }
  }
  const candidates = scanBash(src)
  const rejected = []
  let unchecked = 0
  for (const cand of candidates) {
    if (!cand.isolable) {
      unchecked++
      continue
    }
    const checker = cand.lang === 'python3' ? checkPython : checkAwk
    const res = checker(cand.body)
    if (res.ok === null) {
      unchecked++
      continue
    }
    if (!res.ok) {
      rejected.push({ file, line: cand.line, lang: cand.lang, detail: res.detail })
    }
  }
  return { rejected, unchecked }
}

function main(argv) {
  const args = argv.slice(2)
  const paths = args.length ? args : [DEFAULT_ROOT]
  const files = []
  for (const p of paths) {
    const abs = resolve(p)
    let st
    try { st = statSync(abs) } catch {
      process.stderr.write(`lint-embedded-literals: no such path: ${p}\n`)
      return 2
    }
    if (st.isDirectory()) files.push(...collectFromDir(abs))
    else files.push(abs)
  }

  if (files.length === 0) {
    process.stderr.write('lint-embedded-literals: no *.sh scripts found\n')
    return 2
  }

  let totalRejected = 0
  let totalUnchecked = 0
  for (const f of files) {
    const { rejected, unchecked, error } = lintFile(f)
    if (error) {
      process.stderr.write(`lint-embedded-literals: ${error}\n`)
      continue
    }
    for (const v of rejected) {
      totalRejected++
      process.stdout.write(`${v.file}:${v.line}: embedded ${v.lang} body is syntactically invalid — ${v.detail}\n`)
    }
    totalUnchecked += unchecked
  }

  if (totalUnchecked > 0) {
    process.stdout.write(`lint-embedded-literals: ${totalUnchecked} embedded body/bodies UNCHECKED (concatenation/interpolation/unavailable guest checker — not verified, not assumed clean).\n`)
  }

  if (totalRejected > 0) {
    process.stdout.write(`lint-embedded-literals: ${totalRejected} violation(s) — a corrupted embedded body would only surface at runtime otherwise.\n`)
    return 1
  }
  process.stdout.write(`lint-embedded-literals: ${files.length} script(s) checked, clean.\n`)
  return 0
}

process.exit(main(process.argv))
