---
name: review-mcp-descriptions
description: |
  Review and improve MCP tool and resource descriptions for Tool Search discoverability.
  Use after adding or modifying MCP tools or resources to ensure descriptions follow
  best practices. Trigger on: "review mcp descriptions", "check tool descriptions",
  "optimize mcp tools", or after creating new MCP tools/resources.
---

# Review MCP Descriptions

Review all MCP tool descriptions, resource descriptions, and server instructions for
Tool Search discoverability. Apply after adding new tools or resources.

## When to Run

- After adding a new MCP tool or resource
- After renaming or restructuring MCP tools
- Periodically to align with latest Tool Search best practices

## Review Checklist

For each **tool description**, verify:

### 1. Front-loaded action + synonyms in first sentence
The first sentence must contain the primary action AND common synonyms that users might type.

**Good:** `"Search, find, or filter issues within a project."`
**Bad:** `"Search issues within a project by text query and/or filters."`

Common synonym groups to consider (adapt to the tool's domain):
- Things: thing, item, record, entity (issue, ticket, task, bug, etc.)
- Search: search, find, filter, query, look up
- Create: create, add, new
- Update: update, edit, change, modify, move
- Delete: delete, remove
- Link: link, connect, associate, attach
- Group concept: epic, milestone, project
- Time period: sprint, iteration
- Status: lane, column, status, board
- Time tracking: time, hours, worklog, time entry
- Conversation: comment, note, reply, feedback

### 2. No "Before using this tool" boilerplate
Resource hints belong in server instructions, NOT in individual tool descriptions.
They waste tokens and don't help Tool Search matching.

**Remove patterns like:**
```
Before using this tool, read resource://projects to discover...
```

### 3. No parameter documentation in description
Required/optional parameters are already documented in the tool's schema definitions.
Don't repeat them in the tool description.

**Remove patterns like:**
```
Required parameters:
- project_id: The project to operate in
- title: The item title

Optional parameters:
- lane_id: The lane to place the item in
```

### 4. Max 2-4 lines
Tool descriptions should be concise. Every word must earn its place. If a description
exceeds 4 lines, it's too long.

### 5. No permission hints in descriptions
Role-based permissions are enforced at runtime — do not document them in tool descriptions.
They change independently and stale hints mislead callers.

### 6. Include destructive warnings if applicable
For destructive tools, include "destructive" or "cannot be undone" in the description.

---

For each **resource description**, verify:

### 7. Describes what data is returned
Not just "List items" but "List items with status, assignee, tags, and creation date."

### 8. Includes when/why to use it
Add guidance: "Read this to discover item IDs for creating or updating records."

### 9. Includes keyword synonyms
Same as tools — add synonyms in parentheses where helpful.

---

For **server instructions**, verify:

### 10. Keyword trigger list is complete
The server instructions should list all domain keywords that should trigger Tool Search.
When adding a new tool, add its keywords to this list.

### 11. Tool categories section is up to date
Each tool category should list its action verbs. New tools must be represented.

### 12. Resources section lists all resources
Every registered resource must appear in the resources list.

## Procedure

1. Find the MCP server definition file(s) — search for server registration, tool classes, and
   resource classes in the codebase
2. Read each tool file — check the description property/field
3. Read each resource file — check the description property/field
4. For each file, apply the checklist above
5. Report findings as a table: file, issue, suggested fix
6. After user approval, apply all fixes
7. Update server instructions if new tools/resources were added

## Example Improvements

### Tool: before/after

```
// BEFORE (bad: no synonyms, parameter docs repeated, boilerplate)
"Search items by text query and/or filters.
Before using this tool, read resource://projects to discover available projects.
Required parameters:
- project_id: The project to search in"

// AFTER (good: synonyms, concise, action-first)
"Search, find, or filter items within a project. Supports text search across title,
description, and key, plus filters for status, assignee, and priority.
Returns matching items ordered by most recently updated, max 100 results."
```

### Resource: before/after

```
// BEFORE (bad: minimal, no context on when to use)
"List all board lanes in a specific project, ordered by position"

// AFTER (good: synonyms, data details, usage hint)
"List board lanes (columns/statuses) in a project, ordered by position. Each lane
has an ID, title, color, and item count. Read this to discover lane IDs for creating
or moving items."
```
