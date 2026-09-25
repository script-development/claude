# Triage decisions file — template

Copy this file to `docs/triage/decisions.md` in the consuming repo the first time `/triage-reports`
needs it: to record a **Declined pattern**, or to log a dismissal on a Kendo release whose
`dismiss-report-tool` takes no `category`. The path is a convention shared by every consumer of
the skill, so the file is found in the same place everywhere. Strip this header paragraph after
copying.

---

# Triage decisions

Reusable "we don't do this" rules for `/triage-reports`, plus a dismissal log for Kendo releases
that can't store a reason on the report.

## Where a dismissal reason lives

`dismiss-report-tool` takes a `category` (+ optional `note`) and stores it on the report itself
(`dismiss_reason` / `dismiss_reason_note`). When it does, nothing is written here per dismissal:
the report is the record. The **Dismissal log** below is only for a Kendo release whose tool takes
`report_id` alone, so that "why did we dismiss this?" is not lost the moment a report is archived.
Once the tenant's release accepts `category`, stop adding rows and delete the section when it is
empty or no longer read.

## Reason categories

`not-planned` · `invalid` · `duplicate` · `already-shipped`

## Dismissal log

Only on a release without `category`. One row per dismissed report, newest on top.

| Report ID | Title | Reason | Note | Dismissed |
|-----------|-------|--------|------|-----------|
| 42 | Example: "add velocity charts" | not-planned | No persona prioritises velocity statistics; see the **metrics and reporting** declined pattern below. | 2026-01-01 · Name |

## Declined patterns

Reusable "we don't do this" rules — for requests that recur (often from external users). When a
new pending report matches one of these, dismiss it on sight with reason `not-planned` and point
at the rule here, rather than re-running the fit gate each time.

- **Metrics and reporting dashboards** — example pattern. Replace with the product's own rules:
  name the ask, the persona or principle it conflicts with, and the date it was first declined.
