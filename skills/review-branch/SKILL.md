---
name: review-branch
description: >
  Comprehensive code review of all changes on the current branch compared to the base branch.
  Use when the user wants a code review, wants to check their work before a PR, or says
  "review my changes", "review branch", "check my code", or "what did I change".
---

# Branch Review

Review all changes on the current branch vs the base branch.

## Workflow

### 1. Determine the base branch

Check what the PR targets or fall back to the default branch:
```bash
gh pr view --json baseRefName --jq '.baseRefName' 2>/dev/null || git symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's|origin/||'
```

Fetch the base branch, then use `git diff origin/<base>...HEAD` for a three-dot diff — this shows
only changes introduced on this branch, excluding changes from the base.

### 2. Get changed files

```bash
git diff origin/<base>...HEAD --name-only
```

### 3. Review each file

Use `git diff origin/<base>...HEAD -- <file>` to see the full diff per file.

Analyze for:

- Possible bugs and edge cases
- Inconsistencies and naming errors
- Code duplication and dead code
- Security issues (injection, XSS, secrets in code)
- Performance concerns
- Test coverage gaps — are new code paths tested?
- Consistency with existing patterns in the codebase

Review both implementation and test files together to ensure changes are properly tested and follow
project conventions.

### 3. Documentation checks

Check if any documentation needs updating based on the changes:

- README or project docs if public API changed
- Config files if new environment variables were added
- Type definitions if interfaces changed

### 4. Output

Conclude with a numbered list of **actionable suggestions**, including:

- Specific file and line references (using `file.ts:42` format)
- Clear description of the issue
- Concrete fix recommendation
- Priority level (Critical/High/Medium/Low)

**Example:**

1. `src/auth/service.ts:156` — Missing error handling for API call. Add try-catch block. **High**
2. `tests/auth/service.spec.ts:89` — Missing branch coverage for empty state. Add test case for when array is empty. **Medium**
3. `src/models/user.ts:42` — Property should be readonly. Add readonly modifier. **Low**
