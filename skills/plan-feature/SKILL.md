---
name: plan-feature
description: |
  Structured feature planning workflow: interrogate the developer with hard, codebase-informed
  questions until requirements are crystal clear, then produce a plan document. Use when
  planning a feature, designing a feature, "how should we build this", "let's plan", "I want to
  build X", or any request that needs architectural thinking before implementation. If a feature
  touches multiple layers or modules, trigger this skill before coding.
---

# Plan Feature

You are entering interrogation mode. Your job is to deeply understand what needs to be built
before any code gets written. You will grill the developer with hard, specific questions informed
by the actual codebase — not generic product-manager questions.

The goal: by the end of this process, you and the developer have a shared, precise understanding
of what's being built, what's NOT being built, and how it should work in edge cases. Then you
produce the plan yourself — you have the deepest context, having read the code and run the
entire conversation.

## Phase 1: Research before asking

Before asking a single question, do two things:

### 1a. Find the closest existing feature

Before designing anything, find the feature in the codebase that most closely resembles what
the developer wants to build. Trace it through the full stack — this becomes the blueprint.

Use Glob/Grep to find the candidate. For example, if the developer wants to build "comments on
posts", look at how existing related features work — they likely follow similar patterns.

Once you find it, read the key files and note:
- How the code is structured (what patterns, what layers)
- How tests are organized
- What conventions are followed

This existing feature becomes the reference implementation in your plan.

### 1b. Audit existing code for reuse

This step is non-negotiable. The codebase already has components, helpers, services, and
patterns for most common needs. Building something that already exists wastes time and
creates inconsistency.

Search shared/common directories for reusable code. Make a concrete list of what you found —
this list goes into your questions so you can confirm with the developer what to reuse.

## Phase 2: Interrogate

Now ask questions. Your questions should demonstrate that you've read the codebase — reference
specific files, patterns, and existing behavior.

### First round: present what you found

Your first question round should always present what you discovered in Phase 1:

1. **The reference feature** you found — "I looked at how [X] works. It follows [pattern]. I'd
   like to use that as the blueprint. Sound right?"
2. **Shared code you plan to reuse** — "I found these existing pieces: [list]. Anything missing
   or anything you'd rather rebuild?"
3. **The patterns you'd follow** — "The closest existing implementation is [X]. I'd follow that
   structure. Does that match what you have in mind?"

This grounds the conversation in the actual codebase and catches "we already have that" early.

### What to ask about

- **Scope boundaries** — "You said X. Does that include Y? Where does this feature stop?"
- **User behavior** — "What happens when a user does Z? What if they do it twice?"
- **Edge cases** — "What about empty states? What about large datasets? What about permissions?"
- **Existing patterns** — "I see `[specific file]` handles something similar by doing A. Should we follow that pattern or diverge?"
- **Priority trade-offs** — "This could be done as a quick version without B, or a full version with B. Which matters more right now?"
- **What's NOT being built** — "Just to be clear: this does NOT include C, correct?"
- **Data model** — "Where does this data live? New table? New column? Derived from existing data?"
- **UI expectations** — "Is this a new page, a panel, a modal, or part of an existing view?"

### Rules for questioning

- **Push back on vague answers.** If the developer says "it should be flexible" or "whatever makes sense", don't accept it. Follow up with a concrete example.
- **Minimum 2 rounds of questions.** Even if the first round covers a lot, there are always follow-ups.
- **Reference the codebase** in your questions. Grounded questions are better than generic ones.
- **Don't ask about low-level implementation details** — "Should we use a computed property or a watcher?" is the developer's call during implementation.

### When to stop asking

Stop when ALL of the following are true:
- You know exactly what the user will see and interact with
- You know what data is involved and where it lives
- You know the scope boundaries (in AND out)
- You know how edge cases are handled
- You've identified which existing patterns to follow

## Phase 3: Confirm understanding

Before producing the plan, write a summary and get explicit confirmation:

```
Here's my understanding:

**What we're building:** [one sentence]
**In scope:**
- [explicit list]

**Out of scope:**
- [explicit list]

**Key decisions:**
- [each non-obvious decision from the Q&A]

**Edge cases:**
- [how each is handled]

**Patterns to follow:**
- [specific files/components to mirror]

**Acceptance criteria:**
- [ ] [verifiable pass/fail condition]
- [ ] ...

Is this correct? Anything to add or change?
```

Do NOT proceed until the developer confirms.

## Phase 4: Produce the plan

Once the developer confirms, write a PLAN.md document (location agreed with the developer, or
a sensible default like the repo root or a `docs/plans/` directory):

```markdown
# <Feature Name>

**Date:** <YYYY-MM-DD>
**Status:** Draft

## Goal
<one sentence — what this enables for the user>

## Scope
- **In scope:** <explicit list>
- **Out of scope:** <explicit list>

## Approach
<which files to create/modify, in what order>

## Acceptance Criteria

| # | Criterion | Verification |
|---|-----------|-------------|
| 1 | <user-visible outcome — binary pass/fail> | <how to verify> |
| 2 | ... | ... |

## Shared Reuse
<list shared components, services, and patterns being reused — with file paths>

## Patterns to Follow
<reference existing code that does something similar, with file paths>

## Schema Changes
<if applicable — table changes, new columns, indexes>

## Edge Cases
<cases from the Q&A — how each is handled>

## Risks
<what could go wrong, what to watch for during implementation>
```

Present the plan to the developer and ask for approval. When approved, update the status to
`Approved`.

## Anti-patterns to avoid

- **Skipping the codebase read** and asking questions the code already answers
- **Skipping the shared code audit** — don't plan to build what already exists
- **Accepting vague answers** without probing deeper — "it should be flexible" is not an answer
- **Generic questions** that could apply to any product — ground every question in the codebase
- **Asking about low-level implementation details** — that's the developer's call
- **Designing from first principles instead of from the codebase** — if the codebase uses a pattern,
  your plan uses that pattern. Don't invent a "better" approach unless the developer asks for it.
