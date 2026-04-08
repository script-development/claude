---
name: maintain
description: >
  Maintain the shared skills & agents repo: scan other repos for new or updated skills/agents,
  check for stale content, and propose imports or updates. Use when the user says "anything to
  update?", "check for new skills", "scan repos", "maintain", "sync skills", "what's new",
  or wants to keep the shared library up to date.
argument-hint: "[repo path or 'all']"
---

# Maintain Shared Skills & Agents

Keep this shared repo up to date by scanning source repos for new or changed skills/agents,
auditing existing content for staleness, and proposing actionable updates.

## Modes

This skill has two modes based on what the user asks:

- **"Anything to update?"** → Run a full audit (Steps 1-4)
- **"Check [repo] for skills"** → Scan a specific repo (Step 2 only, targeted)

## Step 1: Inventory what we have

Read `README.md` to get the current catalog. Build a list of:
- All skills with their category (Generic / Kendo PM / Project-Specific Examples)
- All agents with their category
- Note which ones came from which source (check git log if needed)

## Step 2: Scan source repos for skills and agents

Parse `$ARGUMENTS` for a specific repo path. If empty or "all", scan common locations:

```bash
# Find all repos with .claude/skills or .claude/agents
find ~/Code -maxdepth 3 -type d -name ".claude" 2>/dev/null | while read dir; do
  if [ -d "$dir/skills" ] || [ -d "$dir/agents" ]; then
    echo "$dir"
  fi
done
```

For each repo found, list all skills and agents:

```bash
# Skills
find <repo>/.claude/skills -name "SKILL.md" 2>/dev/null
# Agents
find <repo>/.claude/agents -name "*.md" 2>/dev/null
```

### Compare with what we have

For each skill/agent found in source repos, categorize it:

| Category | Meaning | Action |
|----------|---------|--------|
| **New** | Not in shared repo at all | Candidate for import |
| **Updated** | Exists in shared repo but source is newer/different | Candidate for sync |
| **Already synced** | Exists and content matches | Nothing to do |
| **Shared-only** | Exists in shared repo but not in any source | Check if still relevant |

To compare, read the frontmatter of both versions and do a rough content comparison. Don't
do a full diff of every file — focus on structural changes (new sections, changed workflow,
different tools referenced).

## Step 3: Audit existing skills and agents

For each skill/agent already in the shared repo, check:

### Staleness indicators
- Does the skill reference tools, commands, or patterns that may have changed?
- Are there hardcoded paths or project-specific references that slipped through genericization?
- Does the skill description match what the body actually does?

### Quality checks
- Does each skill have a clear description with trigger words?
- Does each agent have frontmatter with name, description, tools, model?
- Are the README catalog entries accurate and up to date?
- Do any skills duplicate functionality?

### Cross-references
- Do skills reference other skills (e.g., `/commit`, `/newbranch`) that exist in this repo?
- Are there broken references to skills or agents that don't exist here?

## Step 4: Report

Present findings in this format:

```
## Shared Repo Maintenance Report

### New skills/agents found

| Source Repo | Name | Type | Description | Recommendation |
|-------------|------|------|-------------|----------------|
| ~/Code/foo | cool-skill | skill | Does X | Import — generic enough |
| ~/Code/bar | niche-agent | agent | Does Y | Skip — too project-specific |

### Updates available

| Skill/Agent | Source Repo | What changed | Recommendation |
|-------------|------------|--------------|----------------|
| commit | ~/Code/kendo | Added pre-push hook check | Sync — improvement applies generically |

### Stale or problematic

| Skill/Agent | Issue | Recommendation |
|-------------|-------|----------------|
| some-skill | References removed tool | Update or remove |

### Summary
- **Repos scanned:** N
- **New candidates:** N (M worth importing)
- **Updates available:** N
- **Issues found:** N
```

## Step 5: Act on findings (with user approval)

After presenting the report, ask the user which items to act on. For each approved action:

### Importing a new skill/agent
1. Read the full source
2. Assess: is it generic, needs genericizing, or project-specific example?
3. If it needs genericizing — strip project-specific references (hardcoded paths, project IDs,
   specific tech stack references, internal URLs)
4. Copy to the appropriate directory
5. Update `README.md` catalog

### Syncing an update
1. Read both versions (source and shared)
2. Identify what changed in the source
3. Apply relevant changes to the shared version — don't blindly overwrite, since the shared
   version may have been genericized
4. Update `README.md` if the description changed

### Fixing a stale skill
1. Read the skill and identify the issue
2. Propose a fix
3. Apply after user approval

After all changes, suggest a commit.
