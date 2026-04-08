---
name: research
description: >
  Run a research query, produce a structured markdown report, and file it so knowledge accumulates
  instead of dying in conversations. Use when the user asks to research a topic, investigate a
  question, compare options, analyze competitors, or any exploratory query where the output should
  be preserved. Trigger on: "research", "investigate", "deep dive", "compare", "analyze",
  "look into", "what do we know about", or any question that deserves a filed answer rather than
  a chat response.
---

# Research

Run a research query and file the output as a permanent knowledge base article. Research
outputs live in a `research/` directory and can be indexed for future reference.

## Why this exists

Every conversation with an LLM produces insights that evaporate when the conversation ends.
If you research pricing models today and someone asks the same question next week, you start
from zero. This skill makes research cumulative — each query adds to the knowledge base,
and future queries can build on past research.

## Workflow

### 1. Define the question (mandatory gate)

Before touching a single file or running a single search, articulate the specific research
question. Research without a thesis is data hoarding.

The user provides a research question, either as:
- A direct question: "Research how Linear handles permissions"
- A topic: "/research competitor pricing models"
- A comparison: "/research Plane vs Linear feature matrix"

**If the input is vague** (e.g., "research competitors", "look into our architecture"):
1. Propose 2-4 specific research questions that could be answered
2. Get confirmation on which question(s) to pursue before proceeding
3. Do NOT start reading files or searching until the question is defined

### 2. Check existing research

Before starting, check if this topic has already been researched:

```bash
ls research/ 2>/dev/null
```

Search for existing articles on the topic using Grep. If existing research covers it:
- Read it first
- Build on it rather than starting from scratch
- Note what's new vs. what confirms existing knowledge

### 3. Research

Use all available tools to investigate:

- **Web search** — for current data, recent articles, competitor pages
- **Web fetch** — to read specific URLs the user provided or you discovered
- **Existing docs** — project documentation, wiki files, internal context
- **Codebase** — when the research involves the project's own implementation

Cast a wide net first, then focus on what's most relevant. Take notes as you go — don't
rely on remembering everything at the end.

### 4. Produce the report

Write a structured markdown report. The format depends on the query type:

#### For comparisons:

```markdown
---
title: "<Topic A> vs <Topic B>"
date: YYYY-MM-DD
type: comparison
tags: [relevant, tags]
sources:
  - https://source-1.com
  - https://source-2.com
---

# <Title>

## Summary
<2-3 sentence executive summary — the answer, not the process>

## Comparison Matrix

| Dimension | Option A | Option B |
|-----------|----------|----------|
| ... | ... | ... |

## Analysis
<what the data means for the project specifically>

## Recommendations
<concrete next steps, if applicable>
```

#### For investigations:

```markdown
---
title: "How X works / Why Y happens"
date: YYYY-MM-DD
type: investigation
tags: [relevant, tags]
sources:
  - https://source-1.com
---

# <Title>

## Summary
<the answer, upfront>

## Findings

### <Finding 1>
<detail with evidence>

### <Finding 2>
<detail with evidence>

## Implications
<what this means for the project, product, or strategy>

## Open Questions
<what we still don't know — seeds for future research>
```

#### For market/landscape analysis:

```markdown
---
title: "<Market/Landscape> Analysis"
date: YYYY-MM-DD
type: analysis
tags: [market, landscape, trends]
sources:
  - https://source-1.com
---

# <Title>

## Summary
<key takeaway>

## Landscape

### <Player/Trend 1>
<what's happening and why it matters>

## Opportunities
<where we can win>

## Risks
<what to watch out for>
```

### 5. File the report

Save to `research/<descriptive-name>.md`.

Naming convention:
- Use lowercase kebab-case
- Lead with the topic, not the date: `linear-permissions-model.md` not `2026-04-research.md`
- Be specific: `competitor-pricing-q2-2026.md` not `pricing.md`

### 6. Cross-integrate

After filing the report, check if any findings should update existing project documentation.
If yes, make the updates with a provenance link back to the research article.

### 7. Report to the user

```
Filed: research/<name>.md (<word count> words)
Sources: <number> sources consulted

Key finding: <one-sentence highlight>
```

Keep it short. The user can read the full report in the file.

## Quality standards

- **Lead with the answer.** The summary comes first. Supporting evidence follows. The reader
  should get the key insight in 10 seconds, details in 2 minutes.
- **Cite sources.** Every factual claim should be traceable. Include URLs in the frontmatter
  and inline where relevant.
- **Be specific about implications.** Generic market analysis is everywhere. The value
  of this research is the "so what does this mean for us?" section.
- **Flag uncertainty.** If data is conflicting or sources disagree, say so. Don't smooth
  over ambiguity.
- **Include Open Questions.** Every research article should seed future research. What
  couldn't you answer? What would need a deeper dive?

## Updating existing research

If research on a topic already exists and you're adding new data:

1. Read the existing article
2. Update it in place rather than creating a duplicate
3. Add new sources to the frontmatter
4. Update the date
5. Mark updated sections with `(Updated YYYY-MM-DD)` if the change is significant

## Research without filing

If the user explicitly asks for a quick answer and doesn't want it filed (e.g., "quick question,
don't file this"), just answer in the conversation. But default to filing — the whole point
is accumulation.
