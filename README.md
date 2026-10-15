# Support Ticket Analysis using SQL (MySQL)

A SQL project that analyzes customer support tickets across voice, chat and email channels. It measures resolution time, SLA breaches and recurring issues, the kind of reporting used in application and technical support teams.

> The data is randomly generated sample data. No real company or customer data is used.

## Database design

| Table | Purpose |
| --- | --- |
| `customers` | Customer name and city |
| `agents` | Support agents and their team (Voice, Chat, Email) |
| `tickets` | Category, priority, channel, created/resolved time, status |
| `escalations` | Tickets escalated to L2/L3 |

A view, `v_ticket_sla`, adds resolution time and the SLA target for each ticket:

| Priority | SLA target |
| --- | --- |
| Critical | 4 hours |
| High | 8 hours |
| Medium | 24 hours |
| Low | 48 hours |

## SQL concepts used

- Joins (`JOIN`) across tickets, agents and escalations
- Aggregations with `GROUP BY`, `COUNT`, `AVG`, `SUM`
- Conditional logic with `CASE`
- CTEs (`WITH`) and window functions (`RANK() OVER (PARTITION BY ...)`)
- Date functions (`TIMESTAMPDIFF`, `DATE_FORMAT`, `DATE_ADD`)
- Views and a stored procedure for a weekly SLA report
- Indexes, checked with `EXPLAIN` before and after

## How to run

1. Install MySQL 8.0 or later.
2. Run `support_ticket_analysis.sql` (for example, `\source D:/Download/support_ticket_analysis.sql` in MySQL Shell's SQL mode).
3. Run the queries from the file one at a time, or call the report:

```sql
USE support_analysis;
CALL sp_weekly_sla_report('2025-03-03');
```

## Queries and findings

> Replace the text below with what YOUR results show. Because the data is random, your numbers will differ.

### 1. Average resolution time by category and priority
Which issue types take longest to resolve.
**Finding:** [Example: "Hardware tickets with Low priority had the longest average resolution time at X hours."]

![Query 1](screenshots/query1.png)

### 2. SLA breach rate by agent
Which agents miss SLA targets most often.
**Finding:** [Example: "Agent 0X had the highest breach rate at X%."]

![Query 2](screenshots/query2.png)

### 3. SLA compliance by channel
Voice vs chat vs email.
**Finding:** [Example: "Email had the lowest SLA compliance at X%."]

![Query 3](screenshots/query3.png)

### 4. Top 3 recurring issue categories per month
Uses a CTE and `RANK()` to find the most common issue types each month.
**Finding:** [Example: "Login Issue was the top category in X of the months."]

![Query 4](screenshots/query4.png)

### 5. Weekly SLA report (stored procedure)
`sp_weekly_sla_report(week_start)` returns resolved tickets, breaches and compliance % by priority for a given week.

![Query 5](screenshots/query5.png)

## Indexing

Added indexes on `created_at` and `(category, priority)`, and compared `EXPLAIN` output before and after. [Add one line on what changed, for example "the query moved from a full table scan to a range scan."]

## Author

Sujal Rasal | MCA (Computer Science) | [LinkedIn URL, optional]
