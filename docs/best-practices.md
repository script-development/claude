# Writing Effective Skills & Agents

## Skill anatomy

```
skill-name/
├── SKILL.md              (required — the skill definition)
├── scripts/              (optional — executable code for repetitive tasks)
├── references/           (optional — docs loaded into context as needed)
└── assets/               (optional — templates, icons, fonts used in output)
```

Skills use progressive disclosure — three levels of loading:

1. **Metadata** (name + description) — always in Claude's context (~100 words). This is what determines whether the skill triggers.
2. **SKILL.md body** — loaded when the skill triggers. Keep it under 500 lines.
3. **Bundled resources** — loaded on demand. No size limit. Scripts can execute without being loaded into context.

## Writing the description (most important part)

The `description` field in frontmatter is the primary trigger mechanism. Claude sees this in its available skills list and decides whether to consult the skill based on it.

Claude tends to *undertrigger* — it won't use a skill unless the description clearly matches. Write descriptions that are slightly "pushy": include not just what the skill does, but the contexts where it should activate.

**Weak:**
> Formats commit messages.

**Strong:**
> Formats commit messages following conventional commits. Use this whenever the user mentions commits, commit messages, git history cleanup, or asks to write a commit message — even if they don't mention "conventional commits" specifically.

## Writing instructions

**Explain the why, not just the what.** Claude has good judgment — when it understands *why* something matters, it handles edge cases better than when following rigid rules.

Instead of:
> You MUST ALWAYS validate the input schema before processing.

Try:
> Validate the input schema first — malformed input causes silent failures downstream that are painful to debug.

**Use imperative form.** "Check for existing tests" not "You should check for existing tests."

**Include examples.** The most effective way to convey quality expectations. Show what good output looks like:

```markdown
**Example 1:**
Input: Added user authentication with JWT tokens
Output: feat(auth): implement JWT-based authentication
```

**Keep it lean.** If an instruction isn't pulling its weight, remove it. Read through the skill with fresh eyes — if something feels like filler, it probably is. Every line should earn its place.

## Structuring larger skills

If your skill approaches 500 lines, add a layer of hierarchy:

- Put domain-specific details in `references/` files
- Have the SKILL.md point to the right reference based on context
- For multi-variant skills (e.g., different cloud providers), keep one reference per variant

```
cloud-deploy/
├── SKILL.md            (workflow + variant selection logic)
└── references/
    ├── aws.md
    ├── gcp.md
    └── azure.md
```

Claude reads only the relevant reference file — keeps context lean.

## Common pitfalls

- **Overusing MUST/NEVER/ALWAYS** — these feel authoritative but often backfire. Claude follows reasoning better than commands. If you find yourself writing in all caps, reframe it as an explanation.
- **Overfitting to examples** — skills get used across many different prompts. Write general instructions, not ones tailored to specific test cases.
- **Forgetting the description** — a perfect skill with a vague description won't trigger. The description is what makes the skill discoverable.
- **Kitchen sink skills** — a skill that does 10 things does none of them well. Split it up. One skill, one job.
- **No examples** — abstract instructions without examples leave too much to interpretation. Show, don't just tell.

## Testing and iterating with /skill-creator

The `/skill-creator` skill is an official Anthropic plugin that helps you build, test, and optimize skills through a structured loop: draft, run test cases, review outputs, improve, repeat.

**What it does:**
- Helps capture your intent and write a first draft
- Generates realistic test prompts and runs them (with and without the skill) to compare
- Opens a browser-based viewer for you to review outputs side-by-side and leave feedback
- Runs quantitative benchmarks (assertion-based grading, timing, token usage)
- Iterates on the skill based on your feedback
- Optimizes the description field for better triggering accuracy

**Install it:**
```bash
claude plugins install skill-creator@claude-plugins-official
```

**Use it:** Type `/skill-creator` in Claude Code when you want to create a new skill or improve an existing one.

You don't need to use `/skill-creator` for every skill — for simple, straightforward skills a manual draft and a few test runs is fine. But for complex skills where output quality matters, the structured eval loop catches issues you'd miss from eyeballing alone.

## Quick manual testing

If you're not using `/skill-creator`, at minimum run your skill on 2-3 realistic prompts — the kind of thing a real user would actually say. If it works well on those, it's ready to share. If something's off, iterate on the instructions.

## Agents

Agents are simpler — a single `.md` file with frontmatter and instructions. The main thing that matters:

- **Clear scope** — define what's in and out of bounds
- **Focused output** — agents that return structured, specific output are more useful than ones that produce open-ended text
- **Explain the perspective** — if the agent exists to provide a specific viewpoint (security review, performance analysis), make that explicit
