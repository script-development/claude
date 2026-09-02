#!/usr/bin/env node
// context-audit — measure where a Claude Code session's tokens actually went.
//
// Project-agnostic by construction: it reads Claude Code's own transcript store
// (~/.claude/projects/**/*.jsonl), whose location and schema belong to the harness,
// not to any project. Nothing here knows what language or framework you are in.
//
// WHY THIS EXISTS: a session cannot see its own token growth, so every claim about
// "what was expensive" is otherwise a guess. The transcripts carry a full per-request
// `usage` object. This reads it.
//
// FOUR THINGS THAT WILL BURN ANYONE WHO REIMPLEMENTS THIS:
//
//   1. DEDUPE BY requestId. One API response is written as several transcript lines
//      (one per content block: text, thinking, each tool_use) and EVERY line repeats
//      the same `usage` object. Summing lines double-counts — measured 18,500 lines
//      for 8,865 real requests, a 2.1x inflation.
//
//   2. SUBAGENTS LIVE IN THEIR OWN DIRECTORY. `isSidechain` is not sufficient;
//      subagent transcripts are written under <project>/<parent-session-id>/subagents/.
//      Classify on the path too, or subagent spend is reported as main-loop spend.
//
//   3. sessionId IS NOT A CONTEXT BOUNDARY. A subagent transcript carries its PARENT's
//      sessionId. Group by it and you merge a parent context with every child context
//      into one imaginary session -- which then reports a file read once per agent as
//      a "repeat read", when separate contexts is the entire point of a subagent.
//      The unit of context is the TRANSCRIPT FILE. Group on that.
//
//   4. MEASURE THE PAYLOAD, NOT THE RECORD. `textLen(r)` on a whole transcript line
//      counts parentUuid/uuid/timestamp/cwd/sessionId/version/gitBranch -- ~459 chars
//      per record that were never sent to the model. Worse for `system` lines: 84% of
//      them have no `content` field at all, only durationMs/messageCount/subtype
//      bookkeeping, so the old measure scored ~474 chars for a 2-char payload. Fixed
//      below (measure `r.attachment` / `r.content`); corpus-wide this removed 3.55M
//      phantom characters, 7.4% of the old total, and `system notices` all but
//      vanished as a category. Measured and cross-checked in
//      docs/calibration.md, correction 1.
//
//   5. OUTPUT IS NOT A SEPARATE SOURCE OF NEW MATERIAL. It is tempting to write
//      newMaterial = inp + cc + out, because output does enter context and is not
//      cache creation. That double-counts: an assistant turn is re-sent as INPUT on
//      the very next request, where it is billed inside `cache_creation_input_tokens`.
//      Measured with tools/context-billing.js -- across 1,698 warm consecutive request
//      pairs, cache creation on request t+1 equals the FULL prefix increment, output
//      included, in 97.1% of cases. So output already sits in `cc`, and adding it again
//      inflates the denominator and UNDERSTATES amplification. The 2026-08-21 report
//      shipped with that defect; see docs/measured.md, correction 2026-09-02.
//
// Token counts from `usage` are exact. Character-derived sizes (composition, tool
// volume) are approximations at CHARS_PER_TOKEN and are labelled as such.
//
// STILL APPROXIMATE, DELIBERATELY: CHARS_PER_TOKEN stays at 4 so figures remain
// comparable with the 2026-08-21 run. It is wrong per category (measured: 2.15 for
// tool results, 1.89 for user messages, 4.35 for injected) and it cannot see thinking
// at all -- `thinking.display` defaults to "omitted", so all 5,660 thinking blocks in
// the corpus carry ZERO characters while still being billed and still sitting in
// context. Any composition figure here therefore UNDER-counts the assistant side:
// measured directly from `usage.output_tokens_details.thinking_tokens` (Claude Code
// 2.1.229+, present on 29% of this corpus), thinking is 36.4% of assistant output,
// so visible assistant output runs at 2.20 chars/token rather than the 1.40 a naive
// count implies. `tools/context-calibrate.js` is the tool that measures these
// properly; do not fix it here without re-baselining the published report.

const fs = require('fs');
const path = require('path');
const os = require('os');

const CHARS_PER_TOKEN = 4;

// Public per-Mtok list prices, used only for the cost split — never for token
// figures. Override with --rate-in / --rate-out if you are on different terms.
let RATE_IN = 15, RATE_OUT = 75;
const CACHE_WRITE_MULT = 1.25, CACHE_READ_MULT = 0.10;

const argv = process.argv.slice(2);
const flag = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const has = n => argv.includes(n);

const ROOT = flag('--root', path.join(os.homedir(), '.claude', 'projects'));
const ONLY_SESSION = flag('--session', null);
const SINCE = flag('--since', null);
const UNTIL = flag('--until', null);
const TOP = parseInt(flag('--top', '12'), 10);
const AS_JSON = has('--json');
RATE_IN = parseFloat(flag('--rate-in', RATE_IN));
RATE_OUT = parseFloat(flag('--rate-out', RATE_OUT));

if (has('--help')) {
  console.log([
    'context-audit — where a Claude Code session\'s tokens went',
    '',
    '  node tools/context-audit.js [options]',
    '',
    '  --root <dir>       transcript store (default ~/.claude/projects)',
    '  --session <id>     drill into one session or context (adds a composition breakdown)',
    '  --since <date>     only records on/after YYYY-MM-DD',
    '  --until <date>     only records strictly before YYYY-MM-DD',
    '                     (window applies to EVERY section, so a re-run can be made',
    '                      comparable with an older one over the same request set)',
    '  --top <n>          rows in the session table (default 12)',
    '  --json             machine-readable output',
    '  --rate-in <n>      $/Mtok input  (default 15)',
    '  --rate-out <n>     $/Mtok output (default 75)',
  ].join('\n'));
  process.exit(0);
}

function walk(dir, out) {
  out = out || [];
  let ents;
  try { ents = fs.readdirSync(dir, { withFileTypes: true }); } catch (e) { return out; }
  for (const e of ents) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.jsonl')) out.push(p);
  }
  return out;
}

const isSubagentPath = p => /[\\/]subagents[\\/]/.test(p);
const textLen = v => (v == null ? 0 : (typeof v === 'string' ? v : JSON.stringify(v)).length);
// Applied per RECORD, so every section below shares one window. Records with no
// timestamp are kept: they carry no date to judge and dropping them would silently
// shrink the character sections relative to the token table.
const inWindow = ts => !ts || ((!SINCE || ts >= SINCE) && (!UNTIL || ts < UNTIL));

// ---------------------------------------------------------------- collect
const requests = new Map();    // requestId -> deduped usage record
const toolCalls = new Map();   // tool_use id -> {name, inChars}
const toolResults = new Map(); // tool_use id -> chars
const composition = {};        // session -> bucket -> chars
const readsBySession = {};
const shellCalls = [];

for (const file of walk(ROOT)) {
  const sub = isSubagentPath(file);
  const rel = path.relative(ROOT, file);
  const ctxId = rel.split(path.sep).join('/');     // one transcript file == one context
  const project = rel.split(path.sep)[0] || '(root)';
  let lines;
  try { lines = fs.readFileSync(file, 'utf8').split('\n'); } catch (e) { continue; }

  for (const line of lines) {
    if (!line.trim()) continue;
    let r; try { r = JSON.parse(line); } catch (e) { continue; }
    if (!inWindow(r.timestamp)) continue;
    const sid = ctxId;
    if (ONLY_SESSION && !(r.sessionId === ONLY_SESSION || ctxId.indexOf(ONLY_SESSION) >= 0)) continue;

    const u = r.type === 'assistant' && r.message && r.message.usage;
    if (u && r.requestId && !requests.has(r.requestId)) {
      requests.set(r.requestId, {
        ctx: ctxId, session: r.sessionId || ctxId, project: project, sub: sub, ts: r.timestamp || '',
        model: r.message.model || '?', skill: r.attributionSkill || '',
        inp: u.input_tokens || 0,
        cc: u.cache_creation_input_tokens || 0,
        cr: u.cache_read_input_tokens || 0,
        out: u.output_tokens || 0,
      });
    }

    const comp = composition[sid] || (composition[sid] = {});
    const add = (k, n) => { if (n) comp[k] = (comp[k] || 0) + n; };

    if (r.type === 'assistant' && r.message && Array.isArray(r.message.content)) {
      for (const c of r.message.content) {
        if (c.type === 'text') add('assistant text', textLen(c.text));
        else if (c.type === 'thinking') add('assistant thinking', textLen(c.thinking));
        else if (c.type === 'tool_use') {
          const n = textLen(c.input);
          add('tool CALL inputs', n);
          if (!toolCalls.has(c.id)) toolCalls.set(c.id, { name: c.name, inChars: n });
          const inp = c.input || {};
          const fp = inp.file_path || inp.notebook_path;
          if (c.name === 'Read' && fp) {
            (readsBySession[sid] || (readsBySession[sid] = []))
              .push({ file: String(fp), scoped: !!(inp.offset || inp.limit) });
          }
          if ((c.name === 'Bash' || c.name === 'PowerShell') && inp.command) shellCalls.push(String(inp.command));
        }
      }
    } else if (r.type === 'user' && r.message && Array.isArray(r.message.content)) {
      for (const c of r.message.content) {
        if (c.type === 'tool_result') {
          const n = Array.isArray(c.content)
            ? c.content.reduce((a, b) => a + textLen(b && b.text != null ? b.text : b), 0)
            : textLen(c.content);
          add('tool RESULTS', n);
          if (!toolResults.has(c.tool_use_id)) toolResults.set(c.tool_use_id, n);
        } else if (c.type === 'text') add('user messages', textLen(c.text));
      }
    } else if (r.type === 'user') {
      add('user messages', textLen(r.message && r.message.content));
    } else if (r.type === 'attachment') {
      // Harness-injected context: skill listings, IDE diagnostics, reminders, file echoes.
      add('injected: ' + ((r.attachment && r.attachment.type) || '?'), textLen(r.attachment));
    } else if (r.type === 'system') {
      add('system notices', textLen(r.content));   // burn #4: most have no content
    }
    // file-history-* / mode / last-prompt are transcript bookkeeping and are NOT sent
    // to the model. Deliberately excluded — counting them overstates context by ~a third.
  }
}

let reqs = Array.from(requests.values());   // already windowed by inWindow()
if (!reqs.length) { console.error('No usage records found under ' + ROOT); process.exit(1); }

// ---------------------------------------------------------------- aggregate
const T = { inp: 0, cc: 0, cr: 0, out: 0 };
for (const r of reqs) { T.inp += r.inp; T.cc += r.cc; T.cr += r.cr; T.out += r.out; }
const total = T.inp + T.cc + T.cr + T.out;
const newMaterial = T.inp + T.cc;          // NOT + T.out -- see burn #5
const amplification = T.cr / Math.max(1, newMaterial);
const cost = (T.inp * RATE_IN + T.cc * RATE_IN * CACHE_WRITE_MULT
  + T.cr * RATE_IN * CACHE_READ_MULT + T.out * RATE_OUT) / 1e6;

const sessions = {};
for (const r of reqs) {
  const s = sessions[r.ctx] || (sessions[r.ctx] = {
    id: r.ctx, session: r.session, project: r.project, sub: r.sub, n: 0,
    cr: 0, cc: 0, out: 0, inp: 0, t0: r.ts, t1: r.ts, depths: [],
  });
  s.n++; s.cr += r.cr; s.cc += r.cc; s.out += r.out; s.inp += r.inp;
  s.depths.push(r.cr + r.cc);
  if (r.ts && r.ts < s.t0) s.t0 = r.ts;
  if (r.ts && r.ts > s.t1) s.t1 = r.ts;
}
for (const s of Object.values(sessions)) {
  s.total = s.cr + s.cc + s.out + s.inp;
  s.newTok = s.cc + s.inp;                  // NOT + s.out -- see burn #5
  s.amp = s.cr / Math.max(1, s.newTok);
  s.peak = Math.max.apply(null, s.depths);
}
const ranked = Object.values(sessions).sort((a, b) => b.total - a.total);

// Spend by context depth — the load-bearing chart. Cost is quadratic in session
// length, so this answers "how deep was the context when the money was spent".
const depth = {};
for (const r of reqs) {
  const d = r.cr + r.cc;
  const b = Math.floor(d / 100000) * 100;
  depth[b] = (depth[b] || 0) + d;
}

// Counterfactual: what a reset-at-threshold discipline would have cost. Assumes a
// reset lands at HANDOFF tokens (a written brief re-read by a fresh session) and
// context then regrows at the same per-turn rate the real session actually showed.
const HANDOFF = 25000;
function simulate(threshold) {
  let real = 0, sim = 0;
  for (const s of ranked) {
    const ctx = s.depths;
    const incs = [];
    for (let i = 1; i < ctx.length; i++) {
      const d = ctx[i] - ctx[i - 1];
      if (d > 0 && d < 50000) incs.push(d);
    }
    incs.sort((a, b) => a - b);
    const rate = incs[Math.floor(incs.length / 2)] || 1500;
    real += ctx.reduce((a, b) => a + b, 0);
    let c = Math.min(HANDOFF, ctx[0] || HANDOFF);
    for (let i = 0; i < ctx.length; i++) { if (c > threshold) c = HANDOFF; sim += c; c += rate; }
  }
  return { real: real, sim: sim, saved: 1 - sim / real };
}

// Hygiene — real, but small. Reported so nobody mistakes it for the main lever.
let repeatReads = 0, totalReads = 0, scopedReads = 0;
const repeatDetail = [];
for (const list of Object.values(readsBySession)) {
  const seen = {};
  for (const r of list) {
    totalReads++; if (r.scoped) scopedReads++;
    seen[r.file] = (seen[r.file] || 0) + 1;
  }
  for (const f of Object.keys(seen)) if (seen[f] > 1) { repeatReads += seen[f] - 1; repeatDetail.push({ file: f, n: seen[f] }); }
}
const BIG = /\b(git log|git diff|git show|cat |ls -R|find |grep -r|rg )/;
const CAP = /\|\s*(head|tail)\b|\s-n\s*\d|\shead\s|-m\s*\d|--max-count/;
const bigShell = shellCalls.filter(c => BIG.test(c));
const cappedShell = bigShell.filter(c => CAP.test(c));

const toolVolume = {};
for (const entry of toolCalls) {
  const id = entry[0], c = entry[1];
  const o = toolVolume[c.name] || (toolVolume[c.name] = { n: 0, inChars: 0, outChars: 0 });
  o.n++; o.inChars += c.inChars; o.outChars += toolResults.get(id) || 0;
}

// ---------------------------------------------------------------- report
const M = n => (n / 1e6).toFixed(2) + 'M';
const K = n => (n / 1000).toFixed(0) + 'k';
const pc = (a, b) => (100 * a / b).toFixed(1) + '%';

if (AS_JSON) {
  console.log(JSON.stringify({
    totals: T, total: total, newMaterial: newMaterial, amplification: amplification, cost: cost,
    sessions: ranked.map(s => ({
      context: s.id, session: s.session, project: s.project, subagent: s.sub, requests: s.n,
      total: s.total, newTokens: s.newTok, amplification: s.amp, peakContext: s.peak, start: s.t0, end: s.t1,
    })),
    spendByDepth: depth,
    simulations: [120000, 200000, 300000, 400000].map(t => Object.assign({ threshold: t }, simulate(t))),
    hygiene: { totalReads: totalReads, repeatReads: repeatReads, scopedReads: scopedReads,
      largeShellCalls: bigShell.length, cappedShellCalls: cappedShell.length },
  }, null, 2));
  process.exit(0);
}

console.log('\n  CONTEXT AUDIT  —  ' + reqs.length + ' API requests across ' + ranked.length + ' contexts (main loops + subagents)');
console.log('  ' + ROOT + (SINCE ? '   since ' + SINCE : '') + (UNTIL ? '   until ' + UNTIL : '')
  + (ONLY_SESSION ? '   session ' + ONLY_SESSION : ''));
console.log('  payload-measure fix applied (see header burn #4) — character sections are NOT'
  + ' comparable\n  with output from before 2026-08-24; token sections are unaffected.');

console.log('\n  -- WHERE THE TOKENS WENT ------------------------------------------');
const rowsT = [['uncached input', T.inp], ['cache creation (new material)', T.cc],
  ['cache read (CONTEXT REPLAY)', T.cr], ['output', T.out]];
for (const row of rowsT) console.log('    ' + row[0].padEnd(32) + M(row[1]).padStart(9) + '  ' + pc(row[1], total).padStart(7));
console.log('    ' + 'TOTAL'.padEnd(32) + M(total).padStart(9));
console.log('\n    amplification  ' + amplification.toFixed(1) + 'x   - every token of new material is re-sent ~' + amplification.toFixed(0) + ' times');
console.log('                   (new material = uncached input + cache creation; output is NOT added - burn #5)');
console.log('    est. spend     $' + cost.toFixed(2) + '   (@ $' + RATE_IN + '/$' + RATE_OUT + ' per Mtok)');
const costs = {
  'uncached input': T.inp * RATE_IN, 'cache creation': T.cc * RATE_IN * CACHE_WRITE_MULT,
  'cache read': T.cr * RATE_IN * CACHE_READ_MULT, 'output': T.out * RATE_OUT,
};
for (const k of Object.keys(costs))
  console.log('      ' + k.padEnd(16) + '$' + (costs[k] / 1e6).toFixed(2).padStart(9) + '  ' + pc(costs[k] / 1e6, cost).padStart(7) + ' of spend');

console.log('\n  -- SPEND BY CONTEXT DEPTH  (the load-bearing number) --------------');
const dTot = Object.values(depth).reduce((a, b) => a + b, 0);
let cum = 0;
for (const e of Object.entries(depth).sort((a, b) => (+a[0]) - (+b[0]))) {
  cum += e[1];
  const bar = '#'.repeat(Math.round(38 * e[1] / dTot));
  console.log('    ' + String(e[0]).padStart(4) + '-' + String(+e[0] + 100).padStart(4) + 'k  ' + M(e[1]).padStart(8) + ' ' + pc(e[1], dTot).padStart(6) + '  ' + bar.padEnd(38) + ' cum ' + (100 * cum / dTot).toFixed(0) + '%');
}

console.log('\n  -- COUNTERFACTUAL: reset-at-threshold discipline ------------------');
console.log('     (reset = write a ' + K(HANDOFF) + ' handoff brief, /clear, resume in a fresh session)');
for (const t of [120000, 200000, 300000, 400000]) {
  const r = simulate(t);
  console.log('    reset at ' + K(t).padStart(5) + ':  ' + M(r.sim).padStart(8) + ' vs ' + M(r.real).padStart(8) + ' actual   ->  ' + (100 * r.saved).toFixed(0).padStart(3) + '% saved');
}

console.log('\n  -- CONTEXTS  (one transcript file = one context) -------------------');
console.log('    reqs    total      new      amp    peak ctx  kind      project / start');
for (const s of ranked.slice(0, TOP))
  console.log('    ' + String(s.n).padStart(4) + '  ' + M(s.total).padStart(8) + '  ' + K(s.newTok).padStart(7) + '  ' + (s.amp.toFixed(0) + 'x').padStart(5) + '  ' + K(s.peak).padStart(8) + '  ' + (s.sub ? 'subagent' : 'main').padEnd(8) + '  ' + s.project.replace(/^[Cc]--Users-[^-]+-/, '').slice(0, 34) + ' ' + s.t0.slice(0, 10));
let c80 = 0, n80 = 0;
for (const s of ranked) { c80 += s.total; n80++; if (c80 > total * 0.8) break; }
console.log('    -> top ' + n80 + ' of ' + ranked.length + ' contexts (' + (100 * n80 / ranked.length).toFixed(0) + '%) account for 80% of all tokens');

if (ONLY_SESSION || ranked.length === 1) {
  const comp = composition[ranked[0].id] || {};
  const cTot = Object.values(comp).reduce((a, b) => a + b, 0) || 1;
  console.log('\n  -- WHAT FILLED THE CONTEXT  (~tok, chars/' + CHARS_PER_TOKEN + ') -------------------');
  for (const e of Object.entries(comp).sort((a, b) => b[1] - a[1]))
    if (e[1] / CHARS_PER_TOKEN > 500) console.log('    ' + K(e[1] / CHARS_PER_TOKEN).padStart(7) + '  ' + pc(e[1], cTot).padStart(6) + '  ' + e[0]);
}

console.log('\n  -- TOOL TRAFFIC  (~tok, chars/' + CHARS_PER_TOKEN + ') -----------------------------');
console.log('    calls    call inputs    results     tool');
const tv = Object.entries(toolVolume).sort((a, b) => (b[1].inChars + b[1].outChars) - (a[1].inChars + a[1].outChars));
let tvIn = 0, tvOut = 0;
tv.forEach(e => { tvIn += e[1].inChars; tvOut += e[1].outChars; });
for (const e of tv.slice(0, 10))
  console.log('    ' + String(e[1].n).padStart(5) + '  ' + K(e[1].inChars / CHARS_PER_TOKEN).padStart(12) + '  ' + K(e[1].outChars / CHARS_PER_TOKEN).padStart(10) + '     ' + e[0]);
console.log('    all tool traffic ~' + M((tvIn + tvOut) / CHARS_PER_TOKEN) + ' tok = ' + pc((tvIn + tvOut) / CHARS_PER_TOKEN, newMaterial) + ' of new material');

console.log('\n  -- HYGIENE  (real, but small - do not mistake it for the lever) ---');
console.log('    repeat reads     ' + repeatReads + '/' + totalReads + ' (' + pc(repeatReads, totalReads || 1) + ') - same file re-read within one context');
console.log('    unscoped reads   ' + (totalReads - scopedReads) + '/' + totalReads + ' (' + pc(totalReads - scopedReads, totalReads || 1) + ') - whole file, no offset/limit');
console.log('    uncapped shell   ' + (bigShell.length - cappedShell.length) + '/' + bigShell.length + ' (' + pc(bigShell.length - cappedShell.length, bigShell.length || 1) + ') - git log/diff/find/grep with no head/tail');
if (repeatDetail.length) {
  console.log('    most re-read:');
  for (const d of repeatDetail.sort((a, b) => b.n - a.n).slice(0, 5))
    console.log('      ' + String(d.n).padStart(3) + 'x  ' + d.file.split(/[\\/]/).slice(-3).join('/'));
}
console.log('');
