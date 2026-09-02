#!/usr/bin/env node
// context-billing — how one token is actually charged over its lifetime in a context.
//
// Companion to context-audit.js, which answers "where did the tokens go". This answers
// the question underneath it: a token is not billed once, and the number of times it is
// billed is not a property of the token. Both facts are measurable from the same
// transcript store, and both were assumed rather than measured in the 2026-08-21 report.
//
// WHY THIS EXISTS. docs/design.md asserted that an output token is "billed twice" — 5x
// as output, then 0.1x on replay. That is wrong in a way that matters: it implies the
// cache WRITE is folded into the output rate. It is not. The assistant turn arrives as
// ordinary input material on the very next request and is written like any other, so the
// real shape is three phases: 5x once, 1.25x once, 0.1x many times. That claim needed a
// measurement rather than an argument, because the alternative is genuinely plausible —
// the server computed the KV for those tokens during generation, so it COULD retain them
// and serve the next request's prefix as a pure read. This tool decides which happens.
//
// THE TEST, AND WHY IT NEEDS NO CHARACTER ESTIMATES. Token conservation in the prefix is
// exact. The tokens sent on a request are cr + cc + inp, and between consecutive requests
// in one context:
//
//     delta = (cr + cc + inp)[t+1] - (cr + cc + inp)[t] = out(t) + newInput(t+1)
//
// The two hypotheses then separate cleanly on cc(t+1):
//
//     cc(t+1) ~ delta            -> the whole increment was written, output included
//     cc(t+1) ~ delta - out(t)   -> only fresh input was written; output rode in free
//
// No CHARS_PER_TOKEN anywhere, which is what makes this stronger than the composition
// figures in context-audit.js. Everything below reads `usage` only.
//
// FOUR THINGS THAT WILL BURN ANYONE WHO REIMPLEMENTS THIS. The first three are the same
// burns context-audit.js documents, and they bite here for the same reasons:
//
//   1. DEDUPE BY requestId. One API response is written as several transcript lines, each
//      repeating the same `usage` object. Summing lines double-counts ~2.1x. Worse here
//      than in the audit: undeduped lines would fabricate consecutive "pairs" whose delta
//      is zero, which is not a measurement of anything.
//
//   2. THE UNIT OF CONTEXT IS THE TRANSCRIPT FILE, not sessionId — a subagent transcript
//      carries its PARENT's sessionId. Pairing across that boundary would compare two
//      unrelated prefixes and report the difference as an increment.
//
//   3. ORDER BY TIMESTAMP WITHIN THE FILE. The pairing is the whole measurement; a
//      readdir-order or line-order pass produces deltas of arbitrary sign.
//
//   4. FILTER TO WARM, FORWARD-GROWING PAIRS. Three cases must be excluded or they swamp
//      the signal: cr == 0 (cold start or expired entry — nothing was cached to extend),
//      delta <= 0 (compaction, /clear, or a rewritten history — the prefix shrank), and
//      small out(t), where the two hypotheses are only a few hundred tokens apart and
//      ordinary breakpoint jitter decides the verdict. --min-out sets the last threshold.
//
// WHAT THE RESIDUE IS -- and it is not what this tool first claimed. A minority of pairs
// (~2.4%) match `delta - out(t)`. The obvious explanation is that the increment landed in
// `inp` as uncached input because the breakpoint had not advanced. THAT IS WRONG, and the
// decomposition printed below is what refutes it: in those pairs `inp` averages 2 tokens
// while `cr` grows by MORE than the whole previous prefix, by very nearly exactly out(t)
// (measured: 52 of 67 such pairs). The previous turn's output was genuinely served as a
// READ. So the server does sometimes retain the KV it computed while generating and extend
// the cache entry with it at no write charge -- rarely, and for reasons not established
// here. Two facts about it are established: it does not disturb the 97% three-phase
// account, and it clusters oddly in the 1-5 minute gap band (16% of pairs there, 0.8%
// under a minute), which is why that band's cc/delta reads 0.71 while every other band is
// at or above 1.0. Do not explain a sub-1.0 ratio by breakpoint placement without running
// the decomposition -- that is the mistake this comment exists to stop being repeated.
//
// Run it as:
//
//   node tools/context-billing.js                        # both reports, whole store
//   node tools/context-billing.js --since 2026-08-01     # windowed, per-record
//   node tools/context-billing.js --min-out 1000         # stricter separation
//   node tools/context-billing.js --json                 # machine-readable

const fs = require('fs');
const path = require('path');
const os = require('os');

const NL = String.fromCharCode(10);

// Public per-Mtok list prices, used only for the lifetime table. Every current model
// prices output at exactly 5x input ($10/$50, $5/$25, $2/$10, $3/$15, $1/$5), so the
// multiple below is model-independent in practice; override if your terms differ.
let RATE_IN = 15, RATE_OUT = 75;
const CACHE_WRITE_MULT = 1.25, CACHE_READ_MULT = 0.10;

const argv = process.argv.slice(2);
const flag = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const has = n => argv.includes(n);

const ROOT = flag('--root', path.join(os.homedir(), '.claude', 'projects'));
const SINCE = flag('--since', null);
const UNTIL = flag('--until', null);
const MIN_OUT = parseInt(flag('--min-out', '300'), 10);
const TOLERANCE = parseFloat(flag('--tolerance', '0.02'));
const AS_JSON = has('--json');
RATE_IN = parseFloat(flag('--rate-in', RATE_IN));
RATE_OUT = parseFloat(flag('--rate-out', RATE_OUT));

if (has('--help')) {
  console.log([
    'context-billing — how one token is charged over its lifetime',
    '',
    '  --root DIR        transcript store (default ~/.claude/projects)',
    '  --since ISO       only records at or after this timestamp',
    '  --until ISO       only records before this timestamp',
    '  --min-out N       minimum out(t) for a pair to be counted (default 300)',
    '  --tolerance F     relative match tolerance, default 0.02',
    '  --rate-in N       $/Mtok input, for the lifetime table only (default 15)',
    '  --rate-out N      $/Mtok output, for the lifetime table only (default 75)',
    '  --json            machine-readable output',
  ].join(NL));
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

const inWindow = ts => !ts || ((!SINCE || ts >= SINCE) && (!UNTIL || ts < UNTIL));

// ---------------------------------------------------------------- collect
// One entry per (context, requestId). Burn #1 and burn #2.
const contexts = new Map();
let totalRequests = 0;
const T = { inp: 0, cc: 0, cr: 0, out: 0 };

for (const file of walk(ROOT)) {
  const ctxId = path.relative(ROOT, file).split(path.sep).join('/');
  let lines;
  try { lines = fs.readFileSync(file, 'utf8').split(NL); } catch (e) { continue; }
  const seen = new Map();
  for (const line of lines) {
    if (!line.trim()) continue;
    let r; try { r = JSON.parse(line); } catch (e) { continue; }
    if (!inWindow(r.timestamp)) continue;
    const u = r.type === 'assistant' && r.message && r.message.usage;
    if (!u || !r.requestId || seen.has(r.requestId)) continue;
    seen.set(r.requestId, {
      ts: r.timestamp || '',
      inp: u.input_tokens || 0,
      cc: u.cache_creation_input_tokens || 0,
      cr: u.cache_read_input_tokens || 0,
      out: u.output_tokens || 0,
    });
  }
  if (!seen.size) continue;
  // Burn #3.
  const rs = Array.from(seen.values()).sort((a, b) => (a.ts < b.ts ? -1 : a.ts > b.ts ? 1 : 0));
  contexts.set(ctxId, rs);
  totalRequests += rs.length;
  for (const r of rs) { T.inp += r.inp; T.cc += r.cc; T.cr += r.cr; T.out += r.out; }
}

if (!totalRequests) { console.error('No usage records found under ' + ROOT); process.exit(1); }

// ---------------------------------------------------------------- pair up
const prefixOf = r => r.cr + r.cc + r.inp;

const phase = { pairs: 0, write: 0, free: 0, neither: 0, sumCC: 0, sumDelta: 0, sumOut: 0 };
// Where the shortfall goes in sub-1.0 pairs. inp -> deferred write (breakpoint lagging);
// cr growth beyond the previous prefix -> the tokens were served free. Measured, not assumed.
const residue = { pairs: 0, sumShortfall: 0, sumInp: 0, sumCrOverrun: 0, crServed: 0 };
const GAPS = ['<1m', '1-5m', '5-60m', '>60m'];
const gapKey = m => (m < 1 ? '<1m' : m < 5 ? '1-5m' : m < 60 ? '5-60m' : '>60m');
const gaps = {};
for (const g of GAPS) gaps[g] = { pairs: 0, cc: 0, delta: 0 };

for (const rs of contexts.values()) {
  for (let i = 1; i < rs.length; i++) {
    const a = rs[i - 1], b = rs[i];
    const delta = prefixOf(b) - prefixOf(a);
    if (b.cr <= 0 || delta <= 0) continue;      // burn #4

    // Gap table: every warm growing pair, regardless of out(t).
    if (a.ts && b.ts) {
      const mins = (new Date(b.ts) - new Date(a.ts)) / 60000;
      if (mins >= 0) {
        const g = gaps[gapKey(mins)];
        g.pairs++; g.cc += b.cc; g.delta += delta;
      }
    }

    // Phase test: only pairs where the hypotheses are far enough apart to decide.
    if (a.out < MIN_OUT) continue;
    const hWrite = Math.abs(b.cc - delta) / delta;
    const hFree = Math.abs(b.cc - (delta - a.out)) / delta;
    phase.pairs++;
    phase.sumCC += b.cc; phase.sumDelta += delta; phase.sumOut += a.out;
    if (hWrite < TOLERANCE && hWrite < hFree) phase.write++;
    else if (hFree < TOLERANCE && hFree < hWrite) phase.free++;
    else phase.neither++;

    if (b.cc < delta * (1 - TOLERANCE)) {
      const crOverrun = b.cr - prefixOf(a);   // cache read beyond everything sent last time
      residue.pairs++;
      residue.sumShortfall += delta - b.cc;
      residue.sumInp += b.inp;
      residue.sumCrOverrun += Math.max(0, crOverrun);
      if (crOverrun > 50) residue.crServed++;
    }
  }
}

// Amplification on the corrected denominator — output is NOT new material, because the
// phase test above is precisely the proof that it reappears inside cc. See burn #5 in
// context-audit.js.
const newMaterial = T.inp + T.cc;
const R = T.cr / Math.max(1, newMaterial);
const OUT_MULT = RATE_OUT / RATE_IN;
const lifetimeIn = CACHE_WRITE_MULT + CACHE_READ_MULT * R;
const lifetimeOut = OUT_MULT + CACHE_WRITE_MULT + CACHE_READ_MULT * R;

if (AS_JSON) {
  console.log(JSON.stringify({
    root: ROOT, since: SINCE, until: UNTIL, requests: totalRequests, contexts: contexts.size,
    totals: T, minOut: MIN_OUT, tolerance: TOLERANCE,
    phaseTest: phase, residue: residue,
    phaseVerdict: phase.write > phase.free ? 'output re-billed as cache write' : 'output rides in as cache read',
    gapTable: GAPS.map(g => ({ gap: g, pairs: gaps[g].pairs, cc: gaps[g].cc, delta: gaps[g].delta,
      ratio: gaps[g].delta ? gaps[g].cc / gaps[g].delta : null })),
    amplification: R, newMaterial: newMaterial,
    lifetime: { inputToken: lifetimeIn, outputToken: lifetimeOut, outputMultiple: OUT_MULT },
  }, null, 2));
  process.exit(0);
}

const pc = (a, b) => (b ? (100 * a / b).toFixed(1) + '%' : '-');
const M = n => (n / 1e6).toFixed(2) + 'M';

console.log('');
console.log('  CONTEXT BILLING  —  how one token is charged over its lifetime');
console.log('  ' + ROOT + (SINCE || UNTIL ? '   ' + (SINCE ? 'since ' + SINCE + ' ' : '') + (UNTIL ? 'until ' + UNTIL : '') : ''));
console.log('  ' + totalRequests + ' API requests across ' + contexts.size + ' contexts');

console.log('');
console.log('  -- PHASE 2: IS OUTPUT RE-BILLED AS A CACHE WRITE? -----------------');
console.log('     delta = change in (cr + cc + inp) between consecutive requests');
console.log('           = out(t) + newInput(t+1)          [token conservation, exact]');
console.log('');
console.log('     pairs examined (warm, growing, out(t) >= ' + MIN_OUT + '):  ' + phase.pairs);
if (phase.pairs) {
  const rows = [
    ['cc(t+1) == delta          output re-billed as a WRITE', phase.write],
    ['cc(t+1) == delta - out(t) output rode in as a READ', phase.free],
    ['neither, within ' + (TOLERANCE * 100).toFixed(0) + '%', phase.neither],
  ];
  for (const row of rows)
    console.log('       ' + row[0].padEnd(54) + String(row[1]).padStart(6) + '  ' + pc(row[1], phase.pairs).padStart(7));
  console.log('');
  console.log('     aggregate  sum cc(t+1) ' + M(phase.sumCC) + '   sum delta ' + M(phase.sumDelta)
    + '   sum out(t) ' + M(phase.sumOut));
  console.log('       cc / delta         ' + (phase.sumCC / Math.max(1, phase.sumDelta)).toFixed(3)
    + '     (1.0 => write hypothesis)');
  console.log('       cc / (delta - out) ' + (phase.sumCC / Math.max(1, phase.sumDelta - phase.sumOut)).toFixed(3)
    + '     (1.0 => free-read hypothesis)');
  console.log('');
  console.log('     VERDICT: ' + (phase.write > phase.free
    ? 'output IS re-billed as a cache write on the next request.'
    : 'output rides in as a cache read — the write is NOT charged again.'));
  console.log('              An output token therefore costs ' + OUT_MULT + 'x once, then '
    + CACHE_WRITE_MULT + 'x once, then ' + CACHE_READ_MULT + 'x per replay.');
} else {
  console.log('     No pairs met the filter. Lower --min-out, or widen the window.');
}

console.log('');
console.log('  -- DOES PHASE 2 REPEAT? CACHE WRITES VS IDLE TIME -----------------');
console.log('     A write is once per cache ENTRY, not once per token. Above the TTL the');
console.log('     prefix is written again — so cc/delta should climb with the gap.');
console.log('');
console.log('     ' + 'gap'.padEnd(8) + 'pairs'.padStart(7) + 'sum cc'.padStart(10)
  + 'sum delta'.padStart(11) + 'cc/delta'.padStart(10));
for (const g of GAPS) {
  const b = gaps[g];
  console.log('     ' + g.padEnd(8) + String(b.pairs).padStart(7) + M(b.cc).padStart(10)
    + M(b.delta).padStart(11) + (b.delta ? (b.cc / b.delta).toFixed(2) : '-').padStart(10));
}
console.log('');
console.log('');
console.log('     WHERE A SUB-1.0 RATIO COMES FROM (' + residue.pairs + ' pairs short of their delta):');
if (residue.pairs) {
  console.log('       shortfall, tokens not written   ' + residue.sumShortfall);
  console.log('         of which landed in inp        ' + residue.sumInp
    + '   (deferred write, breakpoint lagging)');
  console.log('         of which served as cr         ' + residue.sumCrOverrun
    + '   (read beyond the whole prior prefix)');
  console.log('       pairs where cr overran the prior prefix: ' + residue.crServed + ' of ' + residue.pairs);
  console.log('');
  console.log('     If the second row dominates, the output was genuinely served FREE and no');
  console.log('     write was charged for it. Do not attribute a sub-1.0 ratio to breakpoint');
  console.log('     placement without reading these two rows.');
}

console.log('');
console.log('  -- LIFETIME COST OF ONE TOKEN -------------------------------------');
console.log('     R is not a constant. It is the number of requests that FOLLOW the one a');
console.log('     token arrives on, so it is a property of position, not of the token.');
console.log('');
console.log('     measured amplification  R = ' + R.toFixed(1)
  + '   (cache read / new material, new material = ' + M(newMaterial) + ')');
console.log('');
console.log('       an input token    ' + CACHE_WRITE_MULT + ' + ' + CACHE_READ_MULT + 'R  = '
  + lifetimeIn.toFixed(2) + 'x base input');
console.log('       an output token   ' + OUT_MULT + ' + ' + CACHE_WRITE_MULT + ' + ' + CACHE_READ_MULT + 'R  = '
  + lifetimeOut.toFixed(2) + 'x base input      (' + (lifetimeOut / lifetimeIn).toFixed(2) + 'x an input token)');
console.log('');
console.log('     The ratio falls towards 1.0 as R grows: deep in a context, position');
console.log('     dominates provenance and it stops mattering how a token got there.');
console.log('');
