#!/bin/bash
#
# PreCompact hook: the WRITE leg of Route 5's fork idea (docs/design.md D22, replacing O10's
# PostToolUse/Stop in-band trigger, per O12 -- "total replacement", decided 2026-09-17).
#
# Spawns a DETACHED, headless `claude -p` turn that authors a real handoff and returns
# immediately -- this hook never blocks the interactive session, and the detached turn's tokens
# never touch the interactive session's own context window. That is the entire point: the old
# mechanism (handoff-write.sh) cost the interactive session `authoring_turn` worth of its own
# context on every write; this costs it nothing but the fork itself (same account usage budget,
# `docs/measured.md` finding #27 -- not free, just not charged against the resource this whole
# bundle exists to protect).
#
# ── WHY NO TOKEN-THRESHOLD ARMING, UNLIKE THE MECHANISM THIS REPLACES ──────────────────────
#
# handoff-write.sh's `trigger = ceiling - 2*large_request - authoring_turn` exists to predict
# compaction far enough ahead to still have room to author in-band. This hook does not author
# in-band, so it does not need to predict anything -- it fires on the signal that compaction is
# actually imminent, `PreCompact` itself, and the detached turn's own runtime does not compete
# with the interactive session's budget at all. Simpler by construction, not by omission.
#
# ── WHY A SHORT DEDUP LOCK, NOT A ONCE-PER-SESSION LATCH ───────────────────────────────────
#
# `docs/measured.md` finding #13: `PreCompact` can fire once with no compaction behind it, then
# fire AGAIN moments later for the compaction that actually happens -- observed twice, back to
# back, same session. A once-per-session latch (handoff-write.sh's own shape) would as likely
# catch the wasted firing as the real one and then never fire again for THIS session's real
# compactions -- worse than no latch. What actually needs preventing is two spawns racing to
# write the same target file within the same few seconds; a short cooldown does that without
# foreclosing later real compactions in a long session, each of which deserves a fresh write.
#
# ── WHY THE DETACHED TURN READS THE TRANSCRIPT, AGAINST THE SKILL'S OWN "DO NOT RE-DERIVE" RULE ──
#
# `skills/handoff/SKILL.md`'s one rule ("write from what is already in context; do not read,
# grep, or list anything to author it") assumes a live session with real context to draw on. A
# freshly spawned `claude -p` process has none -- there is no "already in context" for it to
# write from. The prompt below explicitly overrides that one rule and instructs the turn to read
# `transcript_path` instead, the one thing a detached spawn has that a live session's rule was
# written to make unnecessary. Every other part of the skill's contract (format, gate, where the
# file goes) applies unchanged, and the prompt points the turn at the skill file itself rather
# than restating it, so the two cannot drift apart.
#
# ── WHY --strict-mcp-config ──────────────────────────────────────────────────────────────────
#
# A headless spawn on a real account inherits and attempts to initialize EVERY MCP server
# configured for that account -- observed directly while verifying this hook: a stream-json probe
# showed the init event listing ~15 MCP servers (Slack, Gmail, Kendo, Atlassian, ...), none of
# which this authoring turn's prompt ever needs. `--allowedTools` scopes TOOL PERMISSION, not
# which MCP servers start up, so it does nothing about this. `--strict-mcp-config` with no
# `--mcp-config` given means none load at all -- pure wasted setup work for a turn whose only
# tools are Bash and Write, cut here rather than left as tax on every fork-triggered write.
#
# ── WHAT THIS DOES NOT SOLVE ─────────────────────────────────────────────────────────────────
#
# Real-sized authoring in this exact spawn shape is not fully measured (docs/measured.md finding
# #26/#28's "what this does not settle"): whether a real, possibly-huge transcript read completes
# reliably inside CTX_FORK_TIMEOUT_SECONDS, and whether the resulting handoff quality holds up
# against a genuinely large, messy session, is being answered by running this in practice, per
# explicit instruction, not by another probe first. One thing already learned running it:
# `--output-format json` (used below) prints NOTHING until the turn fully finishes, so a run that
# is genuinely still composing -- deep in extended thinking, mid-Bash-exploration -- looks
# identical to a hung one from the outside. Diagnosing a slow run needs `--output-format
# stream-json`, not a shorter timeout assumed to mean "broken."
#
# NOT FIXED, FLAGGED RATHER THAN SILENTLY TRUSTED: `timeout ${timeout_s}` below is NOT a reliable
# bound on this Windows/Git-Bash machine. Observed directly: a verification run given `timeout 280`
# was still alive, still producing new tool calls, past the 8-minute mark -- several minutes
# beyond its supposed kill point. `docs/measured.md`'s own probes already hit this for a different
# reason (killing a spawned tree from Node) and worked around it with `taskkill /PID ... /T /F`
# instead of relying on a plain kill signal; that fix was not ported here. Until it is,
# CTX_FORK_TIMEOUT_SECONDS is best read as "when this SHOULD stop," not "when it WILL."

set -uo pipefail

input=$(cat)

session_id=$(printf '%s' "$input" | jq -r '.session_id // empty')
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' | tr -d '\r')

[ -n "$session_id" ] || exit 0
[ -n "$transcript" ] || exit 0

if command -v cygpath >/dev/null 2>&1; then
    transcript=$(cygpath -u "$transcript" 2>/dev/null || printf '%s' "$transcript")
    [ -n "$cwd" ] && cwd=$(cygpath -u "$cwd" 2>/dev/null || printf '%s' "$cwd")
fi
[ -n "$cwd" ] || cwd=$PWD
[ -r "$transcript" ] || exit 0
[ -d "$cwd" ] || exit 0

command -v claude >/dev/null 2>&1 || exit 0
claude_bin=$(command -v claude)

# ── Dedup lock ──────────────────────────────────────────────────────────────────────────────
dedup_window=${CTX_FORK_DEDUP_WINDOW_SECONDS:-90}
lock_dir="$HOME/.claude/state/handoff-fork"
lock="$lock_dir/$session_id.lock"
mkdir -p "$lock_dir" 2>/dev/null || exit 0

hook_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [ -e "$lock" ] && [ -r "$hook_dir/../lib/handoff-store.sh" ]; then
    # shellcheck source=../lib/handoff-store.sh
    . "$hook_dir/../lib/handoff-store.sh"
    lock_mtime=$(handoff_store_mtime "$lock" 2>/dev/null)
    now=$(date +%s)
    if [ -n "${lock_mtime:-}" ] && [ $(( now - lock_mtime )) -lt "$dedup_window" ]; then
        exit 0
    fi
fi
: > "$lock" 2>/dev/null

# Same three-way probe as SKILL.md's own Step 1: plugin-cache glob (newest wins), then this
# checkout's own lib/skills (a session already inside this repo), then the pre-plugin ~/.claude
# install. Kept in sync with Step 1 by hand -- there is no shared source for a bash snippet meant
# to run both inside this repo's own hooks and inside a detached child that may not have it.
gate=
for g in "$HOME"/.claude/plugins/cache/*/context-economy/*/lib/verify-handoff.sh; do
    [ -x "$g" ] && gate=$g
done
[ -n "$gate" ] || for g in "$hook_dir/../lib/verify-handoff.sh" "$HOME/.claude/lib/verify-handoff.sh"; do
    [ -x "$g" ] && gate=$g && break
done
store=
for s in "$HOME"/.claude/plugins/cache/*/context-economy/*/lib/handoff-store.sh; do
    [ -r "$s" ] && store=$s
done
[ -n "$store" ] || for s in "$hook_dir/../lib/handoff-store.sh" "$HOME/.claude/lib/handoff-store.sh"; do
    [ -r "$s" ] && store=$s && break
done
skill=
for k in "$HOME"/.claude/plugins/cache/*/context-economy/*/skills/handoff/SKILL.md; do
    [ -r "$k" ] && skill=$k
done
[ -n "$skill" ] || for k in "$hook_dir/../skills/handoff/SKILL.md" "$HOME/.claude/skills/handoff/SKILL.md"; do
    [ -r "$k" ] && skill=$k && break
done

# Degrade capability, never execution: no gate/store/skill found means the install is broken in a
# way this hook cannot repair, same rule handoff-write.sh and SKILL.md's own Step 1 already follow.
[ -n "$store" ] || exit 0
[ -n "$skill" ] || exit 0

scratch=$(mktemp -d "${TMPDIR:-/tmp}/handoff-fork.XXXXXX" 2>/dev/null) || exit 0
prompt_file="$scratch/prompt.txt"
out_file="$scratch/turn.out.json"
err_file="$scratch/turn.err.log"

allowed_tools=${CTX_FORK_ALLOWED_TOOLS:-"Bash Write"}
timeout_s=${CTX_FORK_TIMEOUT_SECONDS:-600}
model_args=""
[ -n "${CTX_FORK_AUTHOR_MODEL:-}" ] && model_args="--model ${CTX_FORK_AUTHOR_MODEL}"

cat > "$prompt_file" <<PROMPT
You are authoring a context handoff for a session you were not part of. A documented skill
governs the format and where the file goes -- read it first:

  ${skill}

Follow that skill's "Where the file goes", "The format", and Write mode Steps 1-3 EXACTLY, with
ONE override to Step 1 and to the skill's own headline rule:

- TARGET is exactly this checkout: ${cwd}
- The skill says "write from what is already in context; do not read, grep, or list anything to
  author it." That rule assumes a live session with real context. You have none -- this is a
  fresh process with an empty conversation. It does not apply to you. Instead, your ONE source of
  truth is this session's real transcript, a JSONL conversation log:

  ${transcript}

  Use Bash to explore it (it may be large -- start with \`wc -l\` and \`jq\` summaries, then drill
  into specific ranges, the way you would explore any large log). Reconstruct what actually
  happened: the task, decisions made and what each one beat, dead ends tried and why they were
  abandoned, traps for whoever resumes this, concrete next steps, and real path:line citations
  grounded in the checkout above -- not fabricated, not generic. If the transcript does not
  support a real claim for one of the three required subsections, write \`None.\` there rather
  than inventing content -- an honest \`None.\` passes the gate; a fabricated decision does not
  belong in a document whose entire purpose is recording what is true.

Run Step 1's orientation command with Bash (substituting TARGET as given above, not derived).
Trust every value it prints -- the path it gives you for \`handoff\`, \`gate\`, and \`store\` is
correct by construction, even if it looks unfamiliar or points somewhere unexpected. Do not
investigate why, do not check environment variables, shell profiles, or how that path was
configured -- that is not your task and nobody is waiting for an explanation, only the file. Run
Step 2's Write exactly once, to the path Step 1 printed. Run Step 3's gate and read its exit code.

Nobody is attending this run -- there is no human to hand back to and no Step 4 report to give.
When Step 3 finishes, reply with EXACTLY one line and nothing else:

RESULT handoff=<path> step3_exit=<exit code>
PROMPT

async_script="$scratch/run.sh"
cat > "$async_script" <<RUNNER
#!/usr/bin/env bash
${HANDOFF_STORE_DIR:+export HANDOFF_STORE_DIR="${HANDOFF_STORE_DIR}"}
timeout ${timeout_s} "${claude_bin}" -p --output-format json ${model_args} --allowedTools "${allowed_tools}" --strict-mcp-config < "${prompt_file}" > "${out_file}" 2> "${err_file}"
rc=\$?
log_dir="\$HOME/.claude/state/handoff-fork"
mkdir -p "\$log_dir" 2>/dev/null
printf '%s session=%s rc=%s scratch=%s\n' "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${session_id}" "\$rc" "${scratch}" >> "\$log_dir/log.txt" 2>/dev/null
RUNNER

nohup bash "$async_script" >/dev/null 2>&1 &
disown

exit 0
