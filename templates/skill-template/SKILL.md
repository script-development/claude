---
name: my-skill-name
description: >
  What this skill does and when Claude should use it. Be specific and slightly "pushy" —
  Claude tends to undertrigger skills, so include contexts where it should activate even
  if the user doesn't explicitly ask for it. Example: "Generates changelog entries from
  git history. Use this whenever the user mentions changelogs, release notes, version
  bumps, or asks what changed between two commits."
---

<!-- Delete all these comments when filling in the template. They're here to guide you. -->

<!-- The body is loaded into context when the skill triggers (~500 lines max).
     If you need more space, put details in references/ files and point to them. -->

# My Skill Name

Brief description of what this skill accomplishes and why it exists.

## How it works

<!-- Explain the approach at a high level. This helps Claude understand the intent
     behind the instructions, not just the steps. -->

## Instructions

<!-- Use imperative form. Explain *why* each step matters rather than piling on
     MUST/NEVER/ALWAYS — Claude responds better to reasoning than to commands.

     Example — instead of:
       "You MUST ALWAYS check for existing tests before writing new ones."
     Try:
       "Check for existing tests first — duplicating test coverage wastes time
        and makes the suite harder to maintain." -->

1. First step
2. Second step
3. Third step

## Output format

<!-- Define what the output should look like. Use a template if the format is fixed. -->

```
ALWAYS use this structure:
# [Title]
## Section
- Detail
```

## Examples

<!-- Include at least one example. Concrete examples are the most effective way to
     convey what good output looks like. -->

**Example 1:**
Input: description of what the user asked
Output: what the skill should produce

<!-- OPTIONAL: Bundled resources
     If your skill needs additional files, organize them like this:

     my-skill-name/
     ├── SKILL.md              (this file)
     ├── scripts/              (executable code for repetitive tasks)
     │   └── process.py
     ├── references/           (docs loaded into context as needed)
     │   └── api-guide.md
     └── assets/               (files used in output — templates, icons, etc.)
         └── template.html

     Reference them from the instructions above:
     "Read `references/api-guide.md` for the full API specification."
     "Run `scripts/process.py` to transform the input."

     For multi-domain skills (e.g., supporting AWS/GCP/Azure), put each variant
     in references/ and have the instructions select the right one. -->
