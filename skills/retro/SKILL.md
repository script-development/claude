---
name: retro
description: >
  Write a retrospective capturing what went wrong, why, and what changed. Use when something
  went wrong that's worth documenting, after a failed approach, or when the user says "retro",
  "retrospective", "lessons learned", "post-mortem", or "what went wrong". Also trigger
  proactively when a significant mistake or repeated issue is detected in the conversation.
---

# Retrospective

Write a retrospective that captures what went wrong, why it happened, and what was
changed to prevent it from happening again. Retros live in a `retrospectives/` directory
and are numbered sequentially.

## Why retros matter

Retros are how lessons persist across sessions. A lesson that only exists in a conversation
is lost when the conversation ends. A retro persists, gets referenced in future work, and
prevents the same mistake from being made twice. The audience is future-you (or a future
agent) who has zero context about what happened today.

## Workflow

### 1. Determine the next number

```bash
ls retrospectives/RETRO-*.md 2>/dev/null | sort -V | tail -1
```

Increment the highest number. If no retros exist, create the `retrospectives/` directory
and start at 001.

### 2. Gather context from the conversation

The retro's value comes from the current conversation — you were there when it happened.
Extract:

- **What happened** — the sequence of events. What was the original goal? What went wrong?
- **Why** — root cause. Not "we made a mistake" but why the mistake was possible in the
  first place. Was there a missing check? A wrong assumption? A structural gap?
- **What changed** — concrete fixes. Not "we'll be more careful" but specific changes to
  files, processes, or workflows.
- **The lesson** — the generalizable takeaway. Someone reading only this section should
  understand the principle without needing the full story.

If anything is unclear, ask the user. A vague retro is worse than no retro — it gives
false confidence that a lesson was captured.

### 3. Write the retro

Save to `retrospectives/RETRO-<NNN>-<short-name>.md`.

Pick a short name that captures the theme (e.g., `convention-violations`, `stale-docs-drift`,
`missing-validation`). Someone scanning a file listing should get the gist.

Use this structure:

```markdown
# RETRO-<NNN>: <Title>

**Date:** <YYYY-MM-DD>
**Trigger:** <what prompted this retro — the specific event or discovery>
**Cost:** <impact — time lost, restarts, sessions spent>

## What happened

<Narrative of what occurred. Start with the goal, then describe what went wrong.
Be specific — reference file names, commands, error messages. A reader with no
context should be able to follow the story.>

## Why it happened

<Root cause analysis. Go deeper than "we made a mistake." Why was the mistake
possible? What structural gap, missing check, or wrong assumption enabled it?
If there were multiple contributing factors, number them.>

## What we changed

### 1. <First change>

<What was changed and why. Reference the specific file or process modified.>

### 2. <Second change>

<Continue for each change. Keep each subsection focused on one thing.>

## Lesson

<1-2 paragraphs. The generalizable principle. This should make sense even to
someone who doesn't know the specific feature or project involved. Think: what
would you tell a new team member to watch out for?>
```

### 4. Present and commit

Show the retro content inline, then commit it:

```bash
git add retrospectives/RETRO-<NNN>-<short-name>.md
git commit -m "$(cat <<'EOF'
docs: add RETRO-<NNN> <short description>

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

## Writing tips

- **Be specific, not generic.** "The approach was inconsistent" is weak. "3 of 5 endpoints
  returned different error formats" is useful.
- **Name names.** Reference specific files, commands, and line numbers. The retro should be
  traceable.
- **The "Why" section is the hardest and most valuable.** Push past the surface. If the
  answer is "nobody checked," ask why nobody checked. Was there no tool? No process?
- **"What we changed" must be concrete.** If a change isn't committed to a file somewhere,
  it's not a change — it's an intention.
- **The lesson should be quotable.** Someone should be able to read just the lesson and
  get value. "Don't let the generator grade its own work" is quotable. "We should be more
  careful" is not.
