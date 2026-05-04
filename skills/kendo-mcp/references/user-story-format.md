# Dutch User Story Format

Guidelines for writing concise, implementable user stories in Dutch.

## Contents

1. [Template Structure](#template-structure)
2. [Writing Principles](#writing-principles)
3. [Example](#example)

---

## Template Structure

### For Features (type: 0)

```
Als [rol] wil ik [functionaliteit] zodat [doel]
```

### For Bugs (type: 2)

Direct problem description without user story format.

### Standard Sections

1. **Title**: Short, descriptive summary
2. **User Story**: "Als...wil ik...zodat..." format (for features)
3. **Context**: Brief background (1-2 sentences)
4. **Acceptance Criteria**: 3-5 essential, testable criteria
5. **Scope**: Clear what is/isn't included

### Testing Section

Keep brief - developers know the standards:

```markdown
## Testing
- 100% coverage voor nieuwe code
- Alle tests blijven slagen
```

## Writing Principles

### DO

- Focus on core functionality and user value
- Write 3-5 testable acceptance criteria
- Right-size stories: 2-5 days work
- Use professional Dutch language
- Define clear scope boundaries

### AVOID

- Overly detailed explanations
- Lengthy testing sections
- Code implementations or file paths
- Obvious requirements (TypeScript, error handling)
- Multi-week epics (break into smaller stories)

## Example

```markdown
# Gebruiker kan wachtwoord resetten

## User Story
Als gebruiker wil ik mijn wachtwoord kunnen resetten zodat ik weer toegang krijg tot mijn account.

## Context
Gebruikers vergeten soms hun wachtwoord en moeten dit zelfstandig kunnen herstellen.

## Acceptance Criteria
1. Gebruiker kan reset-link aanvragen via e-mailadres
2. E-mail met reset-link wordt binnen 1 minuut verzonden
3. Reset-link is 24 uur geldig
4. Nieuw wachtwoord moet voldoen aan wachtwoordeisen

## Scope
**Wel**: Reset via e-mail
**Niet**: Reset via SMS, security questions

## Testing
- 100% coverage voor nieuwe code
- Alle tests blijven slagen
```

## Issue Types

| Type | Value | Description |
|------|-------|-------------|
| Feature | 0 | New functionality (use user story format) |
| General | 1 | General task |
| Bug | 2 | Problem or defect (direct description) |

## Priority Levels

| Priority | Value |
|----------|-------|
| Highest | 0 |
| High | 1 |
| Medium | 2 (default) |
| Low | 3 |
| Lowest | 4 |
