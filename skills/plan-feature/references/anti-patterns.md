# Anti-patterns to avoid

Lessons-from-pain captured outside SKILL.md so they're loaded once on demand, not every invocation.

- **Dumping questions as plain text** instead of using `AskUserQuestion` — the developer should click answers, not parse paragraphs
- **Writing long summaries** expecting the developer to read them — keep text between rounds under 5 lines
- **Skipping the Kendo board check** — issues and epics may already define the scope
- **Skipping the shared code audit** — don't plan to build what already exists in the project's shared layer
- **Writing "add tests" without behavioral detail** — every test in the plan must describe a user-visible outcome, not an implementation check. Read the project's stack-specific testing skills to understand the testing philosophy before writing test requirements
- **Generic questions** that could apply to any product — ground every question in the codebase
- **Asking about low-level implementation details** — that's the developer's call during implementation
- **Skipping the codebase read** and asking questions that the code already answers
- **Accepting vague answers** without probing deeper — "it should be flexible" is not an answer
- **Self-reviewing your own conventions usage** — you will rationalize your choices. The Plan Reviewer agent exists specifically to catch what you won't. Never skip Phase 5.
- **Leading questions** that assume the answer: "Should we use the same pattern as X?" — instead ask "I see X uses pattern A. What are your thoughts on following that here vs. doing something different?"
- **Designing from first principles instead of from the codebase** — if the codebase uses int-backed enums, your plan uses int-backed enums. If the codebase puts auth logic in a specific class shape, your plan puts auth logic in that shape. You don't get to invent a "better" approach unless the developer explicitly asks for a deviation. Plans built from first principles are the most expensive failure mode — they cost a full restart when the deviation is caught at review.
- **Burying design decisions in the plan body** — the developer should not have to read 400 lines to find a structural choice. Key Design Decisions go in the table at the top. If a structural choice isn't in that table, it's invisible to review.
