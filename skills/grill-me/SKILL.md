---
name: grill-me
description: >
  Interview the developer about an idea or implementation BEFORE any code is written, so both
  sides share a precise understanding of what's being built. Works in any repository — it
  grounds every question in the codebase you are standing in and drives the whole conversation
  through the `AskUserQuestion` tool, always recommending an option with a reason. Ends with one
  final question round: record the alignment as plan docs (PLAN.md + DECISIONS.md, written by
  /build-it onto the new branch) or skip docs, and build now or stop. Use when the developer says
  "grill me", "interview me", "interrogate me about X", "let's get aligned before I build this",
  "poke at this idea first", "make sure we're on the same page", "/grill-me", or drops an
  idea/approach that needs pinning down before implementation. NOT for stress-testing a call
  already made, and NOT a replacement for a repo's own heavyweight gated planning pipeline
  (e.g. /plan-feature) when a multi-layer feature needs one.
---

# Grill Me

You are in interview mode. The job is to reach a shared, precise understanding of an idea or
implementation **before** any code gets written — so we don't confidently build the wrong thing.
This is the fast alignment pass, not a planning ceremony: no issue, no reviewer gate, and plan
docs only if the developer asks for them at the end.

This skill writes nothing — no code, no docs, no worktree. `/build-it` owns all three.

## The three rules (non-negotiable)

1. **Every question goes through `AskUserQuestion`** — never a text wall. Each question becomes a
   clickable option so the developer answers in a second, not by parsing a paragraph.
2. **Every question recommends an option.** Put your pick **first** and append `(Recommended)` to
   its label, and make that option's `description` say *why* ("I'd pick this because …"). The
   developer should be reacting to a stance, not authoring answers from cold. A neutral quiz with
   no opinion is a worse interview, not a politer one. ("Other" is always available, so a
   recommendation never boxes them in.)
3. **Every question is grounded in the codebase.** Cite a `file:line` or a concrete existing
   pattern in the question. If the code already answers it, **confirm it — don't ask it**
   ("I see `OrderList.vue:42` already loads through the store — wiring this the same way?" is one
   click; "should this be real-time?" wastes attention on something we can already see).

   Grounding covers an option's **premise**, not just its proposal — check what each option
   *assumes true*, not only what it does. Three ways a premise fails:

   - It assumes a surface, file, route, or state **exists** when it doesn't.
   - A recommendation asserts one signal or behaviour **subsumes** another (so the other is safe
     to drop) when the subsumption holds only on the happy path.
   - An option offers to **edit a text this repo doesn't own** — a shared convention, an upstream
     contract, a vocabulary set elsewhere. Check ownership before any option proposes changing it.

   For any "A subsumes B, so drop B" claim, check *every* state that produces A and B
   independently. A property read off a path-scoped function — especially one named for that path
   — may not generalise. A premise error caught pre-interview costs a reworded option; once the
   developer has ratified it, it costs a re-decision and a wrong build.

## Phase 0: Parse the topic

`$ARGUMENTS` is the thing to grill about — an idea, a feature, a refactor, an approach, a change.
If it's empty, ask (plain text is fine here, there's nothing to offer options for yet): *"What are
we grilling — and what's the rough shape you have in mind?"* Then proceed.

## Phase 1: Research first (this is what makes the questions sharp)

Before the first question, spend a few minutes in the actual code — proportionate to the topic, a
scan not a census:

- **Find the closest existing thing** this resembles and read it. It becomes the blueprint every
  question is framed against ("the list view loads through the store in `useOrders.ts:88` — same
  shape here, or not?").
- **Note what's reusable** — existing helpers, patterns, modules the idea could lean on instead of
  rebuilding.
- **List the real decision points** — the ambiguities that would actually change the
  implementation. Those, and only those, are what you interrogate. Don't sweep generic
  product-manager questions.

**When there is no closest existing thing** — young repos often don't have one — say so out loud
rather than inventing a precedent. Then ground the questions in what *is* fixed: the stack, the
directory split, the conventions already visible in config and CLAUDE.md. A first-of-its-kind
decision sets the pattern everything after it copies, so it deserves *more* interview, not less.

If you suspect a claim the developer made about how the code behaves is wrong, check the code
before continuing — surfacing the contradiction (`"you said X, but Y.ts:31 does Z"`) is worth more
than tactfully agreeing.

## Phase 2: Interview

Ask in **dependency order** — settle upstream before downstream, or a late data-shape change
invalidates decisions already made:

1. **Shape & data** — what entities/modules exist, what owns what, where state lives
2. **Behaviour & boundaries** — what happens when, who/what can do it, what's transactional
3. **Edge cases & failure modes** — empty states, races, scale, errors, partial failure
4. **Scope** — what's in, and at least one explicit thing that's **out**

Mechanics:

- **1–4 questions per `AskUserQuestion` call**, related ones grouped.
- **Concrete options drawn from the codebase**, first one `(Recommended)` with the why in its
  description (rule 2). Use the `preview` field for UX / structure / code-shape comparisons where
  seeing the options side by side helps.
- **First round: present what you found** — the reference feature you'd mirror, the pieces you'd
  reuse, the shape you'd follow — and get it confirmed. This catches "we already have that" early.
- **Between rounds, restate a 2–3 line running tally**: "Agreed: A→X, B→Y. Open: Z." In-flight
  alignment beats a wall-of-summary at the end.
- **Push back on vague answers.** "Flexible" / "whatever makes sense" isn't an answer — follow up
  with a concrete scenario: "User does Z twice while someone else does W — what happens?"
- **Usually 1–2 rounds.** Keep going only while decisions that would change the implementation are
  still open; stop once they're settled. Don't manufacture rounds for their own sake.

## Phase 3: Align

When the open decisions are closed, write a short confirmation:

```
Here's what we're aligned on:
- Building: <one sentence>
- In scope: <list>
- Out of scope: <at least one explicit non-goal>
- Key decisions: <each non-obvious call from the Q&A, one line each>
- Edge cases: <how each is handled>
- Patterns to follow: <specific files/modules to mirror>
```

## Phase 4: Docs or not, build or not

Immediately after the alignment block, one final `AskUserQuestion` call with two questions:

1. **"Record this alignment as plan docs on the new branch?"** — options `No docs` and
   `PLAN.md + DECISIONS.md`. Recommend **No docs** for a small change — the alignment in this
   conversation is enough, and a doc nobody re-reads is noise. Recommend **docs** when the
   session settled several non-obvious decisions, the work carries an issue key, or the repo
   gives the docs a job (some repos' reviewers honour `docs/plans/**` records as waivers, and
   some repos' implement skills read `PLAN.md`) — say which reason applies in the description.
2. **"Build it now?"** — `Build now (Recommended)` / `Stop here`.

Then act on the answers:

- **Build now** → invoke the `/build-it` skill. It cuts the worktree, writes the chosen docs
  into it so they ride the new branch, implements the alignment, and ships the PR.
- **Stop here** → stop. The alignment and the docs answer stay in this conversation; a later
  `/build-it` consumes them as-is. Do not write anything now — docs only exist on a branch, and
  the branch is `/build-it`'s to cut.
