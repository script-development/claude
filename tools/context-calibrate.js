#!/usr/bin/env node
// context-calibrate — measure chars-per-token PER CATEGORY, from the corpus itself.
//
// WHY THIS EXISTS: `context-audit.js` divides character counts by a single constant
// (CHARS_PER_TOKEN = 4) to report composition and tool volume, and
// `plugins/context-economy/lib/context-economy/context-thresholds.sh` carries a calibrated 2.68 for the
// handoff budget. Both are single ratios. A single ratio is invariant under a
// PROPORTIONAL split — which is why finding #4's attribution table survives the
// 4-vs-2.68 discrepancy unharmed — but it is NOT invariant to the ratio VARYING
// between the categories being split. JSON tool calls, English prose and markdown
// preamble tokenize very differently, so one ratio silently transfers share from the
// badly-tokenizing categories to the well-tokenizing ones.
//
// HOW IT MEASURES RATHER THAN ESTIMATES: no tokenizer, no API call, no tiktoken
// (which is OpenAI's and wrong for Claude by 15–20% on prose, more on code). Each
// request's transcript records EXACT resident input tokens as
// input_tokens + cache_creation_input_tokens + cache_read_input_tokens. Rebuild the
// cumulative per-category character composition of the context at that same request
// and every request becomes one equation:
//
//     resident_tokens_i = preamble + SUM_c beta_c * chars_(i,c),   beta_c = 1/(chars per token)_c
//
// Fit by non-negative least squares. The intercept measures the harness preamble
// (system prompt + tool definitions), which is resident from turn 1 but appears
// NOWHERE in the transcript — so it doubles as a free cross-check against finding
// #4's "median 55k for a main-loop context".
//
// FOUR THINGS THAT WILL BURN ANYONE WHO REIMPLEMENTS THIS:
//
//   1. SNAPSHOT BEFORE, NOT AFTER. A response's own content is output, not input.
//      Record the observation on FIRST sight of a requestId, then add that line's
//      characters. Adding first inflates every ratio by one turn of assistant text.
//
//   2. A RESET BREAKS THE CUMULATIVE SUM. Compaction (and context editing) drops
//      resident tokens while the character tally keeps climbing, so every later
//      observation in that file is nonsense. Detect the drop and stop using the file —
//      do not try to rebase: the post-reset context is a SUMMARY whose characters
//      were never in the transcript.
//
//   3. OBSERVATIONS WITHIN ONE FILE ARE NOT INDEPENDENT. Consecutive requests share
//      nearly all their content, so n is not the thousands of rows it looks like — it
//      is closer to the number of FILES. An iid bootstrap reports absurdly tight
//      intervals. Resample whole files (cluster bootstrap).
//
//   4. COLLINEARITY IS THE REAL LIMIT, NOT NOISE. Categories that grow in lockstep
//      cannot be separated no matter how many rows there are. Report the correlation
//      structure and the bootstrap spread, and say plainly which coefficients are
//      identified and which are not.
//
//   5. PER-MESSAGE FRAMING IS AN OMITTED VARIABLE, AND IT LANDS ON `assistant text`.
//      Every message carries structural tokens no character column accounts for. That
//      overhead scales with TURN COUNT, and assistant-text characters are the design
//      matrix's best proxy for turn count -- so its coefficient absorbs the overhead
//      and the fit returns 0.79 chars/token, which is physically impossible (ASCII
//      prose floors near 3.5). A `messages` count column is not a refinement here; it
//      is the difference between a plausible number and a nonsense one.
//
//   6. `textLen(r)` ON A WHOLE RECORD MEASURES THE TRANSCRIPT, NOT THE CONTEXT. This
//      one is inherited from context-audit.js and it is a real defect there:
//        - `system` records: most have NO `content` at all, only durationMs /
//          messageCount / subtype bookkeeping. The whole record scores ~474 chars for
//          a 2-char payload, so `system notices` is almost entirely material that was
//          never sent to the model. First NNLS run pinned its beta at 0, which is the
//          fit correctly detecting a phantom regressor -- a good sanity check on the
//          method, and a bug report for the other tool.
//        - `attachment` records: carry ~383 chars of parentUuid/uuid/timestamp/cwd/
//          sessionId/version/gitBranch per record, none of it context. Measure
//          `r.attachment`, not `r`.
//      Both are corrected below. Their char figures therefore DO NOT match
//      context-audit.js until that tool is fixed the same way.
//
//   7. ONE POOLED INTERCEPT IS A MISSPECIFICATION, AND IT BENDS EVERY COEFFICIENT.
//      The preamble is NOT one constant: finding #4 measured 55k median for a main
//      loop against 23k for a subagent, and it also moves with which MCP servers and
//      skills a session loaded. Pooling forces one compromise value (41k, measured
//      here), which under-fits the deep main-loop contexts where the spend is -- and
//      the fit repays the shortfall by inflating whatever grows alongside context
//      depth. Symptom: `assistant text` at 0.98 chars/token, still impossible even
//      after burn #5 was fixed.
//      The fix is per-context FIXED EFFECTS: demean y and X within each context, so
//      beta is identified purely by WITHIN-context growth -- exactly the right source
//      of variation, since a context gaining 5k chars of tool results gains 5k/ratio
//      tokens. Every per-context constant drops out, whether or not we can name it.
//      The preamble is then recovered per context as mean(y) - mean(X).beta, which
//      turns one nuisance parameter into 185 estimates and a real cross-check against
//      finding #4's independently measured 55k / 23k. `--pooled` restores the old fit.
//
//   8. THINKING IS BILLED, RESIDENT, AND TRANSCRIBED AS AN EMPTY STRING. This is the
//      one that no amount of better character accounting can fix, so it decides the
//      whole specification. On Opus 5 (and Fable 5 / Opus 4.8 / 4.7 / Sonnet 5)
//      `thinking.display` defaults to "omitted": the blocks arrive with empty text.
//      Measured in this corpus: 5,660 of 5,660 thinking blocks carry ZERO characters.
//      The tokens were still generated, still charged, and still sit in context.
//      Corpus arithmetic makes the size of the hole visible: 6.60M exact assistant
//      output tokens against 9.97M visible characters is 1.51 chars/token, which is
//      below the floor for any real text. That hole is what inflated `assistant text`
//      to ~1.0 chars/token across every earlier specification; the column was
//      proxying for thinking.
//      HOW BIG THE HOLE ACTUALLY IS -- measured, not inferred: Claude Code 2.1.229+
//      writes `usage.output_tokens_details.thinking_tokens`, a SUBDIVISION of
//      output_tokens (never add the two). On the 2,773 of 9,488 requests that carry
//      it, thinking is 36.4% of output -- not the "roughly half" this comment first
//      inferred from the 1.51 figure. Subtract it and visible assistant output is
//      2.20 chars/token, next to the 2.15 fitted independently for tool results.
//      NOT YET CONSUMED HERE: wiring it in would split the AOUT column into thinking
//      and visible on that 29% of the corpus, and restore the `tool_use` line this
//      burn gives up below (visible splits 26% text / 74% tool_use by chars). The
//      fitted coefficients do not change either way -- AOUT already uses exact
//      output_tokens, thinking included. See docs/calibration.md
//      -> "Correction: thinking is directly measurable on 2.1.229+".
//      THE FIX IS TO STOP USING A CHARACTER PROXY WHERE EXACT COUNTS EXIST. usage
//      .output_tokens is the assistant's exact production per turn -- thinking, text
//      and tool_use together -- so one cumulative-output-tokens column replaces three
//      character columns, and its beta reports how much of it stays resident (~1.0 if
//      verbatim, less if the harness strips thinking on later turns).
//      THE COST, STATED PLAINLY: tool_use inputs live inside output_tokens, so they
//      can no longer be priced as their own line. That is a real loss of resolution
//      against finding #4's sub-finding -- but the char-based figure it replaces was
//      contaminated by thinking, so the resolution was illusory. `--char-assistant`
//      restores the old columns for comparison.
//
// Character measurement is deliberately IDENTICAL to context-audit.js (same textLen,
// same buckets, same exclusion of file-history/mode/last-prompt bookkeeping) so the
// coefficients can be dropped straight back into that tool.

const fs = require('fs');
const path = require('path');
const os = require('os');

const argv = process.argv.slice(2);
const flag = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const has = n => argv.includes(n);

const ROOT = flag('--root', path.join(os.homedir(), '.claude', 'projects'));
const AS_JSON = has('--json');
const BOOT = parseInt(flag('--boot', '300'), 10);
const MIN_OBS = parseInt(flag('--min-obs', '3'), 10);   // contexts with fewer usable requests are dropped
const SEED = parseInt(flag('--seed', '20260824'), 10);  // deterministic bootstrap
const POOLED = has('--pooled');                         // burn #7: FE is the default
const CHARAST = has('--char-assistant');                // burn #8: exact tokens are the default

if (has('--help')) {
  console.log([
    'context-calibrate — per-category chars/token, solved from exact usage records',
    '',
    '  node tools/context-calibrate.js [options]',
    '',
    '  --root <dir>     transcript store (default ~/.claude/projects)',
    '  --boot <n>       cluster-bootstrap replicates (default 300, 0 to skip)',
    '  --min-obs <n>    drop contexts with fewer usable requests (default 3)',
    '  --seed <n>       bootstrap seed (default 20260824)',
    '  --pooled         one shared intercept instead of per-context fixed effects',
    '  --char-assistant  proxy the assistant side by characters (hides thinking)',
    '  --json           machine-readable output',
  ].join('\n'));
  process.exit(0);
}

// ---------------------------------------------------------------- categories
// Coarse on purpose: every extra split costs identifiability (burn #4). `injected:*`
// is collapsed because the sub-types grow together and would fight each other.
const CATS = [
  'tool CALL inputs',
  'tool RESULTS',
  'assistant text',
  'assistant thinking',
  'user messages',
  'injected',
  'system notices',
];
const CI = {}; CATS.forEach((c, i) => { CI[c] = i; });
const NC = CATS.length;
// Burn #5: a COUNT column, not a character column. Its coefficient is tokens per
// message (role markers, block delimiters, content-array framing), so it is reported
// directly rather than inverted into chars/token.
const FRAME = NC;
// Burn #8: cumulative EXACT assistant output tokens (thinking + text + tool_use).
// Also a non-character column: its coefficient is a retention fraction, not a ratio.
const AOUT = NC + 1;
const INTERCEPT = NC + 2;
const P = NC + 3;
const NCOL = NC + 2;              // char categories + framing + exact assistant tokens

const textLen = v => (v == null ? 0 : (typeof v === 'string' ? v : JSON.stringify(v)).length);
const isSubagentPath = p => /[\\/]subagents[\\/]/.test(p);

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

// ---------------------------------------------------------------- collect
// One row per API request: cumulative chars by category (design matrix) against
// exact resident input tokens (response variable).
const rows = [];
const fileMeta = [];
let nFiles = 0, nReset = 0, nDroppedShort = 0, nReqSeen = 0, nRowsAfterReset = 0;

for (const file of walk(ROOT)) {
  const sub = isSubagentPath(file);
  let lines;
  try { lines = fs.readFileSync(file, 'utf8').split('\n'); } catch (e) { continue; }

  const cum = new Float64Array(NCOL);
  const seen = new Set();
  const local = [];
  let lastResident = 0, broken = false, framePending = 0, aoutPending = 0;

  for (const line of lines) {
    if (!line.trim()) continue;
    let r; try { r = JSON.parse(line); } catch (e) { continue; }

    // ---- burn #1: snapshot BEFORE this line's own characters are added.
    const u = r.type === 'assistant' && r.message && r.message.usage;
    if (u && r.requestId && !seen.has(r.requestId)) {
      seen.add(r.requestId);
      nReqSeen++;
      framePending = 1;
      aoutPending = u.output_tokens || 0;   // burn #8: resident from the NEXT turn on
      const resident = (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0)
        + (u.cache_read_input_tokens || 0);
      // ---- burn #2: a reset decouples tokens from the character tally. Stop here.
      if (resident > 0 && lastResident > 0 && resident < 0.7 * lastResident) {
        if (!broken) nReset++;
        broken = true;
      }
      if (!broken && resident > 0) local.push({ x: Float64Array.from(cum), y: resident });
      else if (broken) nRowsAfterReset++;
      if (resident > 0) lastResident = resident;
    }

    if (framePending) { cum[FRAME] += framePending; framePending = 0; }
    if (aoutPending) { cum[AOUT] += aoutPending; aoutPending = 0; }

    // ---- accumulate characters, exactly as context-audit.js measures them
    const add = (k, n) => { if (n) cum[CI[k]] += n; };
    if (r.type === 'assistant' && r.message && Array.isArray(r.message.content)) {
      // Burn #8: under the default spec the assistant side comes from exact
      // output_tokens, so these character columns are deliberately left empty.
      if (CHARAST) for (const c of r.message.content) {
        if (c.type === 'text') add('assistant text', textLen(c.text));
        else if (c.type === 'thinking') add('assistant thinking', textLen(c.thinking));
        else if (c.type === 'tool_use') add('tool CALL inputs', textLen(c.input));
      }
    } else if (r.type === 'user' && r.message && Array.isArray(r.message.content)) {
      for (const c of r.message.content) {
        if (c.type === 'tool_result') {
          const n = Array.isArray(c.content)
            ? c.content.reduce((a, b) => a + textLen(b && b.text != null ? b.text : b), 0)
            : textLen(c.content);
          add('tool RESULTS', n);
        } else if (c.type === 'text') add('user messages', textLen(c.text));
      }
    } else if (r.type === 'user') {
      add('user messages', textLen(r.message && r.message.content));
    } else if (r.type === 'attachment') {
      add('injected', textLen(r.attachment));          // burn #6: payload, not record
    } else if (r.type === 'system') {
      add('system notices', textLen(r.content));       // burn #6: most have no content
    }
    // file-history-* / mode / last-prompt are bookkeeping, never sent to the model.

    // Burn #5: one framing unit per message in the array. Assistant responses arrive
    // as several transcript lines for ONE message, so count them on first requestId.
    if (r.type === 'user' && r.message) cum[FRAME] += 1;
  }

  if (local.length < MIN_OBS) { nDroppedShort += local.length; continue; }
  const fi = nFiles++;
  fileMeta.push({ name: path.relative(ROOT, file), sub: sub, n: local.length });
  for (const o of local) rows.push({ x: o.x, y: o.y, file: fi, sub: sub });
}

if (rows.length < P * 4) {
  console.error('Not enough usable observations (' + rows.length + ') under ' + ROOT);
  process.exit(1);
}

// ---------------------------------------------------------------- fixed effects
// Burn #7. Demean within each context. The intercept column drops out of the fit (it
// demeans to exactly zero); per-context preambles are recovered from the residual.
const wrows = [];
{
  const sumY = new Float64Array(nFiles), cnt = new Float64Array(nFiles);
  const sumX = []; for (let f = 0; f < nFiles; f++) sumX.push(new Float64Array(NCOL));
  for (const r of rows) {
    sumY[r.file] += r.y; cnt[r.file]++;
    for (let c = 0; c < NCOL; c++) sumX[r.file][c] += r.x[c];
  }
  for (const r of rows) {
    const n = cnt[r.file];
    const x = new Float64Array(NCOL);
    for (let c = 0; c < NCOL; c++) x[c] = r.x[c] - sumX[r.file][c] / n;
    wrows.push({ x: x, y: r.y - sumY[r.file] / n, file: r.file, sub: r.sub });
  }
}
// Everything is fitted against SRC; attribution still walks the raw `rows`.
const SRC = POOLED ? rows : wrows;
const NFIT = POOLED ? P : NCOL;     // FE drops the intercept column from the design

// ---------------------------------------------------------------- NNLS
// Projected coordinate descent on the normal equations. beta_c must stay >= 0: a
// negative chars-per-token is not a physical quantity, and letting one category go
// negative to absorb another's collinearity is how a fit produces a confident lie.
function gram(idx, weight) {
  const G = [], b = new Float64Array(P);
  for (let i = 0; i < P; i++) G.push(new Float64Array(P));
  for (const k of idx) {
    const r = SRC[k];
    const w = weight ? weight(r) : 1;
    for (let a = 0; a < NFIT; a++) {
      const xa = (a === INTERCEPT ? 1 : r.x[a]) * w;
      if (!xa) continue;
      for (let c = a; c < NFIT; c++) {
        const xc = (c === INTERCEPT ? 1 : r.x[c]);
        if (xc) G[a][c] += xa * xc;
      }
      b[a] += xa * r.y;
    }
  }
  for (let a = 0; a < P; a++) for (let c = 0; c < a; c++) G[a][c] = G[c][a];
  return { G: G, b: b };
}

function nnls(G, b, iters) {
  const beta = new Float64Array(P);
  for (let it = 0; it < (iters || 600); it++) {
    let delta = 0;
    for (let j = 0; j < NFIT; j++) {
      if (G[j][j] <= 0) { beta[j] = 0; continue; }
      let s = b[j];
      for (let k = 0; k < NFIT; k++) if (k !== j) s -= G[j][k] * beta[k];
      const nv = Math.max(0, s / G[j][j]);
      delta = Math.max(delta, Math.abs(nv - beta[j]) / (Math.abs(beta[j]) + 1e-9));
      beta[j] = nv;
    }
    if (delta < 1e-10) break;
  }
  return beta;
}

const allIdx = rows.map((_, i) => i);

// Two fits, because they answer different questions and disagreement is informative:
//   ABSOLUTE — unweighted. Dominated by deep contexts, which is where the spend is.
//              The right fit for attributing MONEY.
//   RELATIVE — each row scaled by 1/y. Treats a 20k context and a 900k one alike.
//              The right fit for asking "what is this category's ratio".
const fitAbs = (() => { const g = gram(allIdx, null); return nnls(g.G, g.b); })();
const fitRel = (() => { const g = gram(allIdx, r => 1 / Math.max(1, Math.abs(r.y))); return nnls(g.G, g.b); })();

function metrics(beta, weight) {
  let rss = 0, tss = 0, sy = 0, sw = 0;
  for (const r of SRC) { const w = weight ? weight(r) : 1; sy += w * r.y; sw += w; }
  const ybar = sy / sw;
  for (const r of SRC) {
    const w = weight ? weight(r) : 1;
    let pred = POOLED ? beta[INTERCEPT] : 0;
    for (let c = 0; c < NCOL; c++) pred += beta[c] * r.x[c];
    rss += w * (r.y - pred) * (r.y - pred);
    tss += w * (r.y - ybar) * (r.y - ybar);
  }
  return { r2: 1 - rss / tss, rmse: Math.sqrt(rss / SRC.length) };
}
const mAbs = metrics(fitAbs, null);
const mRel = metrics(fitRel, r => 1 / Math.max(1, r.y * r.y));

// ---------------------------------------------------------------- bootstrap
// Burn #3: resample FILES, not rows.
const mulberry = (function (a) {
  return function () {
    a |= 0; a = a + 0x6D2B79F5 | 0;
    let t = Math.imul(a ^ a >>> 15, 1 | a);
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
})(SEED);

const byFile = [];
for (let i = 0; i < nFiles; i++) byFile.push([]);
rows.forEach((r, i) => byFile[r.file].push(i));

const boots = [];
for (let bi = 0; bi < BOOT; bi++) {
  const idx = [];
  for (let f = 0; f < nFiles; f++) {
    const pick = byFile[Math.floor(mulberry() * nFiles)];
    for (const k of pick) idx.push(k);
  }
  const g = gram(idx, null);
  boots.push(nnls(g.G, g.b, 300));
}
function quant(arr, q) {
  const s = arr.slice().sort((x, y) => x - y);
  const i = (s.length - 1) * q, lo = Math.floor(i), hi = Math.ceil(i);
  return s[lo] + (s[hi] - s[lo]) * (i - lo);
}
const ci = [];
for (let j = 0; j < P; j++) {
  const col = boots.map(b => b[j]);
  ci.push(BOOT ? { lo: quant(col, 0.05), hi: quant(col, 0.95) } : { lo: NaN, hi: NaN });
}

// ---------------------------------------------------------------- preamble recovery
// mean(y) - mean(X).beta per context. Main loop and subagent reported separately,
// because that split is what finding #4 measured independently (55k / 23k).
const preMain = [], preSub = [];
{
  const sumY = new Float64Array(nFiles), cnt = new Float64Array(nFiles);
  const sumX = []; for (let f = 0; f < nFiles; f++) sumX.push(new Float64Array(NCOL));
  const isSub = new Array(nFiles).fill(false);
  for (const r of rows) {
    sumY[r.file] += r.y; cnt[r.file]++; isSub[r.file] = r.sub;
    for (let c = 0; c < NCOL; c++) sumX[r.file][c] += r.x[c];
  }
  for (let f = 0; f < nFiles; f++) {
    let pred = 0;
    for (let c = 0; c < NCOL; c++) pred += fitAbs[c] * sumX[f][c] / cnt[f];
    (isSub[f] ? preSub : preMain).push(sumY[f] / cnt[f] - pred);
  }
}
const median = a => {
  if (!a.length) return NaN;
  const t = a.slice().sort((x, y) => x - y), m = t.length >> 1;
  return t.length % 2 ? t[m] : (t[m - 1] + t[m]) / 2;
};

// ---------------------------------------------------------------- collinearity
const corr = [];
{
  const mean = new Float64Array(NC), sd = new Float64Array(NC);
  for (const r of SRC) for (let c = 0; c < NC; c++) mean[c] += r.x[c];
  for (let c = 0; c < NC; c++) mean[c] /= SRC.length;
  for (const r of SRC) for (let c = 0; c < NC; c++) sd[c] += (r.x[c] - mean[c]) * (r.x[c] - mean[c]);
  for (let c = 0; c < NC; c++) sd[c] = Math.sqrt(sd[c] / SRC.length);
  for (let a = 0; a < NC; a++) corr.push(new Float64Array(NC));
  for (const r of SRC) for (let a = 0; a < NC; a++) for (let c = 0; c < NC; c++)
    corr[a][c] += (r.x[a] - mean[a]) * (r.x[c] - mean[c]);
  for (let a = 0; a < NC; a++) for (let c = 0; c < NC; c++)
    corr[a][c] = corr[a][c] / SRC.length / ((sd[a] * sd[c]) || 1);
}

// PRE must exist before attribution() runs.
const PRE = POOLED ? fitAbs[INTERCEPT] : median(preMain.concat(preSub));

// ---------------------------------------------------------------- attribution
// The payoff. Finding #4 split the non-preamble remainder by CHARACTER proportions,
// which assumes one ratio for every category. Redo it with the measured per-category
// ratios: contribution_c = SUM_i beta_c * chars_(i,c) — tokens, replay-weighted by
// construction, since every request the material survived contributes again.
function attribution(beta) {
  const contrib = new Float64Array(P);
  for (const r of rows) {
    for (let c = 0; c < NCOL; c++) contrib[c] += beta[c] * r.x[c];
    contrib[INTERCEPT] += POOLED ? beta[INTERCEPT] : PRE;
  }
  return { contrib: contrib, tot: contrib.reduce((a, b) => a + b, 0) };
}
// Comparator: the single-ratio method on the same rows. ANY single ratio yields the
// same shares — that is the point — so the gap below isolates the effect of the ratio
// varying between categories, and nothing else. The preamble is held at the measured
// intercept in both columns so the comparison is not contaminated by it.
function attributionFlat(preamble) {
  const contrib = new Float64Array(P);
  for (const r of rows) {
    for (let c = 0; c < NC; c++) contrib[c] += r.x[c] / 4;
    contrib[FRAME] += fitAbs[FRAME] * r.x[FRAME];   // not char categories: hold these
    contrib[AOUT] += fitAbs[AOUT] * r.x[AOUT];      // equal in both columns so the
    contrib[INTERCEPT] += preamble;                 // comparison isolates the ratios
  }
  return { contrib: contrib, tot: contrib.reduce((a, b) => a + b, 0) };
}
const attrM = attribution(fitAbs);
const attrF = attributionFlat(PRE);

// ---------------------------------------------------------------- report
const cpt = b => (b > 1e-9 ? (1 / b) : Infinity);
const f2 = n => (isFinite(n) ? n.toFixed(2) : ' -- ');
const pc1 = x => (100 * x).toFixed(1) + '%';
const K = n => (n / 1000).toFixed(0) + 'k';

if (AS_JSON) {
  const out = {
    root: ROOT, observations: rows.length, contexts: nFiles, requestsSeen: nReqSeen,
    resetsDetected: nReset, rowsDiscardedAfterReset: nRowsAfterReset,
    rowsDroppedShortContexts: nDroppedShort,
    r2: { absolute: mAbs.r2, relative: mRel.r2 }, rmseTokens: mAbs.rmse,
    specification: POOLED ? 'pooled-intercept' : 'context-fixed-effects',
    preambleTokens: POOLED
      ? { estimate: fitAbs[INTERCEPT], ci90: [ci[INTERCEPT].lo, ci[INTERCEPT].hi] }
      : { mainLoopMedian: median(preMain), subagentMedian: median(preSub),
          mainLoopContexts: preMain.length, subagentContexts: preSub.length },
    framingTokensPerMessage: { estimate: fitAbs[FRAME], ci90: [ci[FRAME].lo, ci[FRAME].hi] },
    assistantOutputRetention: CHARAST ? null
      : { estimate: fitAbs[AOUT], ci90: [ci[AOUT].lo, ci[AOUT].hi] },
    charsPerToken: {}, attribution: {},
  };
  CATS.forEach((c, i) => {
    out.charsPerToken[c] = {
      absolute: cpt(fitAbs[i]), relative: cpt(fitRel[i]),
      ci90: [cpt(ci[i].hi), cpt(ci[i].lo)],
    };
    out.attribution[c] = {
      measuredShare: attrM.contrib[i] / attrM.tot,
      flatShare: attrF.contrib[i] / attrF.tot,
    };
  });
  if (!CHARAST) out.attribution['assistant output (exact)'] = {
    measuredShare: attrM.contrib[AOUT] / attrM.tot,
    flatShare: attrF.contrib[AOUT] / attrF.tot,
  };
  out.attribution['messages (framing)'] = {
    measuredShare: attrM.contrib[FRAME] / attrM.tot,
    flatShare: attrF.contrib[FRAME] / attrF.tot,
  };
  out.attribution['harness preamble'] = {
    measuredShare: attrM.contrib[INTERCEPT] / attrM.tot,
    flatShare: attrF.contrib[INTERCEPT] / attrF.tot,
  };
  console.log(JSON.stringify(out, null, 2));
  process.exit(0);
}

console.log('\n  CONTEXT CALIBRATION  —  per-category chars/token, solved from exact usage records');
console.log('  ' + ROOT);
console.log('\n  ' + rows.length + ' usable requests across ' + nFiles + ' contexts   ('
  + nReqSeen + ' requests seen; ' + nReset + ' contexts hit a reset, discarding '
  + nRowsAfterReset + ' later rows; ' + nDroppedShort + ' rows in contexts under '
  + MIN_OBS + ' requests)');

console.log('\n  -- MEASURED CHARS PER TOKEN ---------------------------------------');
console.log('    category                abs fit   [90% CI]           rel fit   note');
for (let i = 0; i < NC; i++) {
  const wide = ci[i].lo > 0 && (ci[i].hi / ci[i].lo) > 3;
  const folded = !CHARAST && (i === CI['tool CALL inputs'] || i === CI['assistant text']
    || i === CI['assistant thinking']);
  const note = folded ? 'folded into assistant output (exact) — burn #8'
    : fitAbs[i] < 1e-9 ? 'pinned at 0 — NOT RESIDENT or unidentified'
    : (wide ? 'weakly identified' : '');
  console.log('    ' + CATS[i].padEnd(21) + f2(cpt(fitAbs[i])).padStart(8)
    + '   [' + f2(cpt(ci[i].hi)).padStart(6) + ',' + f2(cpt(ci[i].lo)).padStart(7) + ']'
    + f2(cpt(fitRel[i])).padStart(11) + '   ' + note);
}
if (!CHARAST) {
  console.log('\n    assistant output (EXACT usage tokens, not characters)   retention beta = '
    + fitAbs[AOUT].toFixed(3) + '   [' + ci[AOUT].lo.toFixed(3) + ', ' + ci[AOUT].hi.toFixed(3) + ']');
  console.log('      1.00 = every generated token stays resident verbatim; below 1.00 = the');
  console.log('      harness drops part of it (thinking stripped on later turns) — and this is');
  console.log('      the ONLY column that can see thinking at all (burn #8)');
}
console.log('\n    messages (framing + untranscribed per-turn injection)  '
  + fitAbs[FRAME].toFixed(0) + ' tok/message   [' + ci[FRAME].lo.toFixed(0) + ', '
  + ci[FRAME].hi.toFixed(0) + ']');
if (POOLED) console.log('    harness preamble (intercept)   ' + K(fitAbs[INTERCEPT]) + ' tokens   ['
  + K(ci[INTERCEPT].lo) + ', ' + K(ci[INTERCEPT].hi) + ']   <- never appears in the transcript');
if (!POOLED) {
  console.log('\n    harness preamble RECOVERED per context (never appears in the transcript):');
  console.log('      main loop  median ' + K(median(preMain)) + '   (n=' + preMain.length + ' contexts)');
  console.log('      subagent   median ' + K(median(preSub)) + '   (n=' + preSub.length + ' contexts)');
  console.log('      finding #4 measured these independently at 55k / 23k — that is the cross-check');
}
console.log('    single ratios in use today for comparison:  4.00 (context-audit.js)   2.68 (context-thresholds.sh)');
console.log('\n    specification: ' + (POOLED ? 'ONE POOLED INTERCEPT (--pooled)' : 'per-context FIXED EFFECTS (default)'));
console.log('    fit:  R2 = ' + mAbs.r2.toFixed(4)
  + (POOLED ? ' (pooled, spend-weighted)' : ' (WITHIN-context, spend-weighted)')
  + (POOLED ? '    R2 = ' + mRel.r2.toFixed(4) + ' (relative)' : '')
  + '    RMSE = ' + K(mAbs.rmse) + ' tok');
if (!POOLED) console.log('    (the relative-weighted fit is not reported under fixed effects: demeaned y'
  + ' straddles zero,\n     so 1/y weights are meaningless — use --pooled to see it)');

console.log('\n  -- COLLINEARITY  (of the variation that actually identifies beta) --');
const pairs = [];
for (let a = 0; a < NC; a++) for (let c = a + 1; c < NC; c++) pairs.push([a, c, corr[a][c]]);
pairs.sort((x, y) => Math.abs(y[2]) - Math.abs(x[2]));
for (const p of pairs.slice(0, 6))
  console.log('    r = ' + p[2].toFixed(3) + '   ' + CATS[p[0]] + '  vs  ' + CATS[p[1]]
    + (Math.abs(p[2]) > 0.97 ? '   <- effectively inseparable' : ''));

console.log('\n  -- RE-ATTRIBUTION: what one ratio was hiding ----------------------');
console.log('    both columns are replay-weighted token shares over the same rows, with the');
console.log('    same measured preamble; the ONLY difference is per-category vs one flat ratio');
console.log('\n    category               measured      flat       shift');
const attrRows = [];
for (let i = 0; i < NC; i++) attrRows.push([CATS[i], attrM.contrib[i] / attrM.tot, attrF.contrib[i] / attrF.tot]);
attrRows.push(['messages (framing)', attrM.contrib[FRAME] / attrM.tot, attrF.contrib[FRAME] / attrF.tot]);
if (!CHARAST) attrRows.push(['assistant output (exact)', attrM.contrib[AOUT] / attrM.tot, attrF.contrib[AOUT] / attrF.tot]);
attrRows.push(['harness preamble', attrM.contrib[INTERCEPT] / attrM.tot, attrF.contrib[INTERCEPT] / attrF.tot]);
attrRows.sort((a, b) => b[1] - a[1]);
for (const r of attrRows) {
  const shift = 100 * (r[1] - r[2]);
  console.log('    ' + r[0].padEnd(21) + pc1(r[1]).padStart(8) + pc1(r[2]).padStart(10)
    + ('  ' + (shift >= 0 ? '+' : '') + shift.toFixed(1) + ' pts').padStart(14));
}
const toolM = (attrM.contrib[CI['tool CALL inputs']] + attrM.contrib[CI['tool RESULTS']]) / attrM.tot;
const toolF = (attrF.contrib[CI['tool CALL inputs']] + attrF.contrib[CI['tool RESULTS']]) / attrF.tot;
if (CHARAST) {
  console.log('\n    tool traffic (calls + results):  measured ' + pc1(toolM) + '   flat ' + pc1(toolF)
    + '   -> ' + ((toolM - toolF) >= 0 ? '+' : '') + (100 * (toolM - toolF)).toFixed(1) + ' pts');
} else {
  console.log('\n    tool RESULTS alone (read-in material):  measured ' + pc1(attrM.contrib[CI['tool RESULTS']] / attrM.tot)
    + '   flat ' + pc1(attrF.contrib[CI['tool RESULTS']] / attrF.tot));
  console.log('    tool CALL inputs are inside `assistant output (exact)` and cannot be split out — burn #8');
}
console.log('');
