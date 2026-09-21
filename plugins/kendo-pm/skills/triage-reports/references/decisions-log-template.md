# Triage dismissal log — template

Copy this file to `docs/triage/decisions.md` in the consuming repo the first time `/triage-reports`
dismisses a report. The path is a convention shared by every consumer of the skill, so the log
is found in the same place everywhere. Strip this header paragraph after copying.

---

# Triage dismissal log

Every report we **Dismiss** during `/triage-reports` records its reason here — a Dismiss is never
a silent black hole. (Promote/Combine become tracked issues; **Park** leaves the report Pending
with no record by design.)

## Why this file exists

The report queue only stores `Pending` / `Promoted` / `Dismissed` — `Dismissed` carries no reason.
So "why did we dismiss this?" is lost the moment it's archived, and recurring off-strategy asks get
re-judged from scratch every time. This file is the interim home for that reason.

> **Interim scaffolding.** If the product grows a required `triage_reason` field on the report
> itself (a reason category + note captured at dismiss time), migrate these rows onto the reports
> and delete this file.

## Reason categories

`off-strategy` · `noise` · `duplicate` · `already-shipped` · `not-a-product-change`

## Dismissal log

One row per dismissed report, newest on top.

| Report ID | Title | Reason | Note | Dismissed |
|-----------|-------|--------|------|-----------|
| 42 | Example: "add velocity charts" | off-strategy | No persona prioritises velocity statistics; see the **metrics and reporting** declined pattern below. | 2026-01-01 · Name |

## Declined patterns

Reusable "we don't do this" rules — for requests that recur (often from external users). When a
new pending report matches one of these, dismiss it on sight with reason `off-strategy` and point
at the rule here, rather than re-running the fit gate each time.

- **Metrics and reporting dashboards** — example pattern. Replace with the product's own rules:
  name the ask, the persona or principle it conflicts with, and the date it was first declined.
