#!/usr/bin/env node
// measure-large-request — corpus-mine the distribution of `large_request`, the bound
// Route 5 (docs/design.md O10) needs in place of `fat_turn`.
//
// WHY THIS EXISTS: finding #18 (docs/measured.md) shows `fat_turn` is not a real bound for
// an unattended "run to completion" turn -- one `/implement-plan` turn added ~549k resident
// tokens with no `Stop` event to observe any of it. O10's proposal moves the write-trigger's
// arming check off `Stop` (which only observes at true turn boundaries) onto `PostToolUse`
// (which fires after every tool call), substituting `large_request` -- the max resident
// delta a SINGLE tool-call round trip can add -- for `fat_turn`, on the theory that a single
// round trip is plausibly an actually-bounded quantity where a whole uninterrupted turn is
// not. This measures that distribution the same way findings #14/#15 measured
// `authoring_turn`/`fat_turn`: corpus-mined from real transcripts, not a fresh live probe.
//
// NO SCRIPT SURVIVED FROM #14/#15 TO EXTEND. Both findings say so explicitly ("no script was
// saved... re-derive with the method above"), and O10 itself points at tooling in
// `mission_control` that turns out not to exist there either. This is a fresh implementation
// of the same method at finer (per-request, not per-turn) granularity -- see docs/design.md
// O10 and the conversation that authorized writing it new rather than tracking down a copy on
// another machine.
//
// WHAT COUNTS AS "ONE TOOL-CALL ROUND TRIP": `PostToolUse` fires after a tool executes, i.e.
// only after an assistant API response that itself contained a `tool_use` block. An assistant
// response with no tool call (a plain reply that ends a turn) is not an observation point --
// the NEXT observation point is the next response anywhere in the transcript that does contain
// a tool_use, however far away that is. So the candidate delta is the resident growth between
// two consecutive TOOL-CALL-BEARING assistant responses, not between every assistant response.
// This can span a turn boundary (a whole user message plus the new turn's first tool call) if
// the intervening response had no tool call -- and that IS the shape `large_request` has to
// bound if Route 5 ever fully replaces the `Stop` trigger rather than merely supplementing it
// (O10's still-open decision, item 3). Every delta is therefore tagged `crossedTurn` so the
// distribution can be read either way.
//
// TRAPS INHERITED FROM tools/context-audit.js, all apply here unchanged:
//   1. DEDUPE BY requestId -- one API response is written as several transcript lines (one per
//      content block), each repeating the SAME usage object, so summing lines double-counts.
//      Unlike a streaming partial-usage worry, first-vs-last occurrence doesn't matter here --
//      the object is identical across every line sharing a requestId -- so this keeps the FIRST
//      (cheaper, and preserves file order without a second pass).
//   2. SUBAGENTS LIVE IN THEIR OWN DIRECTORY and carry their PARENT's sessionId. Excluded
//      entirely here (not merely flagged): Route 5 arms the MAIN loop's hook registration, and
//      the existing authoring_turn/fat_turn corpus (#14/#15) was gathered from session-level
//      turns, not subagent-internal ones -- pooling them would compare a different population.
//   3. THE UNIT OF CONTEXT IS THE TRANSCRIPT FILE, not sessionId (same reason as #2). One file,
//      one context, deltas never computed across a file boundary.
//   4. RESIDENT = input + cache_creation + cache_read (never + output -- see context-audit.js's
//      burn #5). This is exactly what hooks/handoff-write.sh reads out of the transcript.
//
// A NEGATIVE DELTA IS NOT A SMALL large_request, IT IS A COMPACTION OR REWIND. Both shrink the
// prefix; pooling that with genuine growth would silently narrow the distribution's tail on
// the (wrong) theory that a drop offsets a spike. Counted and reported separately, excluded
// from every percentile, same treatment finding #15 gave its 2 post-compaction-boundary turns.

'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');

const argv = process.argv.slice(2);
const flag = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const has = n => argv.includes(n);

const ROOT = flag('--root', path.join(os.homedir(), '.claude', 'projects'));
const DEFAULT_PROJECTS = [
  'C--Users-Bart-Documents-GitHub-context-economy',
  'C--Users-Bart-Documents-GitHub-kendo',
  'C--Users-Bart-Documents-GitHub-kendo-2',
  'C--Users-Bart-Documents-GitHub-mission-control',
];
const PROJECTS = (flag('--projects', '') || '').split(',').filter(Boolean);
const projectDirs = (PROJECTS.length ? PROJECTS : DEFAULT_PROJECTS);
const SESSIONS_PER_PROJECT = parseInt(flag('--sessions-per-project', '12'), 10);
const ALL = has('--all');
const TOP_N = parseInt(flag('--top', '10'), 10);
const AS_JSON = has('--json');

if (has('--help')) {
  console.log([
    'measure-large-request — corpus-mine the per-tool-call-round-trip resident delta',
    '(docs/design.md O10, prerequisite 2 for Route 5)',
    '',
    '  node tools/measure-large-request.js [options]',
    '',
    '  --root <dir>              transcript store (default ~/.claude/projects)',
    '  --projects <a,b,c>        project dirs under --root (default: the same 4 findings',
    '                            #14/#15/#18 used -- context-economy, kendo, kendo-2,',
    '                            mission-control)',
    '  --sessions-per-project <n> largest-by-size transcripts sampled per project (default 12,',
    '                             matching finding #15\'s method)',
    '  --all                     ignore the per-project cap and use every transcript found',
    '  --top <n>                 rows in the largest-deltas table (default 10)',
    '  --json                    machine-readable output',
  ].join('\n'));
  process.exit(0);
}

const isSubagentPath = p => /[\\/]subagents[\\/]/.test(p);

function listTranscripts(projectDir) {
  const dir = path.join(ROOT, projectDir);
  let ents;
  try { ents = fs.readdirSync(dir, { withFileTypes: true }); } catch (e) { return []; }
  const files = [];
  for (const e of ents) {
    if (e.isDirectory()) continue; // subagents/ and similar -- excluded by construction
    if (!e.name.endsWith('.jsonl')) continue;
    const p = path.join(dir, e.name);
    let size = 0;
    try { size = fs.statSync(p).size; } catch (err) { /* ignore */ }
    files.push({ path: p, size });
  }
  files.sort((a, b) => b.size - a.size);
  return ALL ? files : files.slice(0, SESSIONS_PER_PROJECT);
}

// A "real" user message: type:"user" whose content is a plain string, or an array containing
// at least one non-tool_result block (text/image). A tool_result-only array is the harness
// handing a tool's output back, not a human turn boundary.
function isRealUserMessage(r) {
  if (r.type !== 'user' || !r.message) return false;
  const c = r.message.content;
  if (typeof c === 'string') return c.trim().length > 0;
  if (Array.isArray(c)) return c.some(b => b && b.type !== 'tool_result');
  return false;
}

const withinTurn = [];   // deltas where no real user message intervened
const crossTurn = [];    // deltas where the gap crossed at least one turn boundary
const negatives = [];    // compaction/rewind artifacts, reported not pooled
const allEvents = [];    // for the top-N table: {delta, crossedTurn, project, file, ts, tools}

let sessionsProcessed = 0;
let requestsTotal = 0;
let toolCallEventsTotal = 0;

for (const projectDir of projectDirs) {
  for (const f of listTranscripts(projectDir)) {
    if (isSubagentPath(f.path)) continue;
    let lines;
    try { lines = fs.readFileSync(f.path, 'utf8').split('\n'); } catch (e) { continue; }

    const seenRequestIds = new Set();
    const events = []; // ordered: {resident, ts, tools:[names]}
    let sawTurnBoundarySincePrev = false;
    let anyRecord = false;

    for (const line of lines) {
      if (!line.trim()) continue;
      let r; try { r = JSON.parse(line); } catch (e) { continue; }
      anyRecord = true;

      if (isRealUserMessage(r)) { sawTurnBoundarySincePrev = true; continue; }

      if (r.type !== 'assistant' || !r.message || !r.message.usage) continue;
      requestsTotal++;
      const rid = r.requestId;
      if (rid && seenRequestIds.has(rid)) continue; // burn #1: same object, keep first
      if (rid) seenRequestIds.add(rid);

      const content = Array.isArray(r.message.content) ? r.message.content : [];
      const toolNames = content.filter(c => c && c.type === 'tool_use').map(c => c.name);
      if (toolNames.length === 0) continue; // not a PostToolUse observation point

      const u = r.message.usage;
      const resident = (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0)
        + (u.cache_read_input_tokens || 0);

      events.push({
        resident, ts: r.timestamp || '', tools: toolNames,
        crossedTurn: sawTurnBoundarySincePrev,
      });
      sawTurnBoundarySincePrev = false;
    }

    if (!anyRecord) continue;
    sessionsProcessed++;
    toolCallEventsTotal += events.length;

    for (let i = 1; i < events.length; i++) {
      const delta = events[i].resident - events[i - 1].resident;
      const rec = {
        delta, crossedTurn: events[i].crossedTurn, project: projectDir,
        file: path.basename(f.path), ts: events[i].ts, tools: events[i].tools,
      };
      if (delta < 0) { negatives.push(rec); continue; }
      (events[i].crossedTurn ? crossTurn : withinTurn).push(delta);
      allEvents.push(rec);
    }
  }
}

// ---------------------------------------------------------------- percentiles
// Nearest-rank, sorted ascending. Documented rather than borrowed, since no percentile
// helper exists elsewhere in this repo's tools to stay consistent with.
function pct(sorted, p) {
  if (!sorted.length) return null;
  const idx = Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1);
  return sorted[Math.max(0, idx)];
}
function stats(arr) {
  const sorted = arr.slice().sort((a, b) => a - b);
  if (!sorted.length) return { n: 0 };
  return {
    n: sorted.length,
    min: sorted[0],
    median: pct(sorted, 50),
    p90: pct(sorted, 90),
    p95: pct(sorted, 95),
    p99: pct(sorted, 99),
    max: sorted[sorted.length - 1],
  };
}

const combined = withinTurn.concat(crossTurn);
const result = {
  sessionsProcessed, requestsTotal, toolCallEventsTotal,
  negativeDeltasExcluded: negatives.length,
  withinTurn: stats(withinTurn),
  crossTurn: stats(crossTurn),
  combined: stats(combined),
  top: allEvents.slice().sort((a, b) => b.delta - a.delta).slice(0, TOP_N),
};

if (AS_JSON) {
  console.log(JSON.stringify(result, null, 2));
  process.exit(0);
}

const fmt = n => n == null ? '—' : n.toLocaleString('en-US');
function printBlock(title, s) {
  console.log(`\n${title}  (n=${s.n})`);
  if (!s.n) { console.log('  (no data)'); return; }
  console.log(`  min ${fmt(s.min)}   median ${fmt(s.median)}   p90 ${fmt(s.p90)}   p95 ${fmt(s.p95)}   p99 ${fmt(s.p99)}   max ${fmt(s.max)}`);
}

console.log('measure-large-request — docs/design.md O10, prerequisite 2');
console.log(`projects: ${projectDirs.join(', ')}`);
console.log(`sessions processed: ${sessionsProcessed}  (${ALL ? 'all found' : `top ${SESSIONS_PER_PROJECT} by size per project`})`);
console.log(`assistant records with usage: ${requestsTotal}   tool-call-bearing (observation points): ${toolCallEventsTotal}`);
console.log(`negative deltas excluded (compaction/rewind, not pooled): ${negatives.length}`);

printBlock('WITHIN-TURN deltas (no real user message intervened — what large_request needs if Stop keeps handling turn boundaries)', result.withinTurn);
printBlock('CROSS-TURN deltas (a real user message intervened — the shape Route 5 must bound if it replaces Stop entirely)', result.crossTurn);
printBlock('COMBINED (both pooled — the conservative bound if PostToolUse is the only observation mechanism)', result.combined);

console.log(`\nTop ${TOP_N} single deltas:`);
console.log('  delta        project                                          file                                     crossedTurn  tools');
for (const e of result.top) {
  console.log(
    '  ' + fmt(e.delta).padStart(10) +
    '   ' + e.project.padEnd(46) +
    ' ' + e.file.slice(0, 8).padEnd(10) +
    ' ' + String(e.crossedTurn).padEnd(12) +
    ' ' + e.tools.join(',')
  );
}
