-- =====================================================
-- Support Ticket Analysis (MySQL 8.0+)
-- Author: Sujal Rasal
-- Sample data is randomly generated; no real company data.
-- =====================================================

-- ---------- STEP 1: Create the database and tables ----------
DROP DATABASE IF EXISTS support_analysis;
CREATE DATABASE support_analysis;
USE support_analysis;

CREATE TABLE customers (
    customer_id   INT PRIMARY KEY AUTO_INCREMENT,
    customer_name VARCHAR(100) NOT NULL,
    city          VARCHAR(50)
);

CREATE TABLE agents (
    agent_id   INT PRIMARY KEY AUTO_INCREMENT,
    agent_name VARCHAR(100) NOT NULL,
    team       VARCHAR(50)
);

CREATE TABLE tickets (
    ticket_id   INT PRIMARY KEY AUTO_INCREMENT,
    customer_id INT NOT NULL,
    agent_id    INT NOT NULL,
    category    VARCHAR(50) NOT NULL,
    priority    ENUM('Low','Medium','High','Critical') NOT NULL,
    channel     ENUM('Voice','Chat','Email') NOT NULL,
    created_at  DATETIME NOT NULL,
    resolved_at DATETIME NULL,
    status      ENUM('Open','Resolved','Escalated') NOT NULL,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    FOREIGN KEY (agent_id)    REFERENCES agents(agent_id)
);

CREATE TABLE escalations (
    escalation_id INT PRIMARY KEY AUTO_INCREMENT,
    ticket_id     INT NOT NULL,
    escalated_to  VARCHAR(20) NOT NULL,
    escalated_at  DATETIME NOT NULL,
    FOREIGN KEY (ticket_id) REFERENCES tickets(ticket_id)
);

-- ---------- STEP 2: Load sample data ----------
SET SESSION cte_max_recursion_depth = 2000;   -- raise this if you increase the row count
SET SQL_SAFE_UPDATES = 0;

INSERT INTO agents (agent_name, team) VALUES
('Agent 01','Voice'),('Agent 02','Voice'),('Agent 03','Voice'),
('Agent 04','Chat'),('Agent 05','Chat'),('Agent 06','Chat'),
('Agent 07','Email'),('Agent 08','Email');

-- 50 customers
INSERT INTO customers (customer_name, city)
WITH RECURSIVE n AS (
    SELECT 1 AS i UNION ALL SELECT i + 1 FROM n WHERE i < 50
)
SELECT CONCAT('Customer ', i),
       ELT(1 + FLOOR(RAND() * 4), 'Pune','Mumbai','Nashik','Nagpur')
FROM n;

-- 1000 tickets created between Jan 2025 and Sep 2025
INSERT INTO tickets (customer_id, agent_id, category, priority, channel, created_at, status)
WITH RECURSIVE n AS (
    SELECT 1 AS i UNION ALL SELECT i + 1 FROM n WHERE i < 1000
)
SELECT 1 + FLOOR(RAND() * 50),
       1 + FLOOR(RAND() * 8),
       ELT(1 + FLOOR(RAND() * 5), 'Login Issue','Network','Software Bug','Account','Hardware'),
       ELT(1 + FLOOR(RAND() * 4), 'Low','Medium','High','Critical'),
       ELT(1 + FLOOR(RAND() * 3), 'Voice','Chat','Email'),
       TIMESTAMP('2025-01-01') + INTERVAL FLOOR(RAND() * 270) DAY
                               + INTERVAL FLOOR(RAND() * 86400) SECOND,
       'Open'
FROM n;

-- Resolve about 90% of tickets (10 minutes to 72 hours); leave about 10% open
UPDATE tickets
SET resolved_at = created_at + INTERVAL (10 + FLOOR(RAND() * 4320)) MINUTE,
    status = 'Resolved'
WHERE ticket_id % 10 <> 0;

-- Mark about 12% of resolved tickets as escalated
UPDATE tickets
SET status = 'Escalated'
WHERE status = 'Resolved' AND RAND() < 0.12;

INSERT INTO escalations (ticket_id, escalated_to, escalated_at)
SELECT ticket_id,
       ELT(1 + FLOOR(RAND() * 2), 'L2','L3'),
       created_at + INTERVAL 30 MINUTE
FROM tickets
WHERE status = 'Escalated';

-- Quick check
SELECT 'customers' AS tbl, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'agents', COUNT(*) FROM agents
UNION ALL SELECT 'tickets', COUNT(*) FROM tickets
UNION ALL SELECT 'escalations', COUNT(*) FROM escalations;

-- ---------- STEP 3: View with SLA logic ----------
-- SLA targets: Critical 4h, High 8h, Medium 24h, Low 48h
CREATE VIEW v_ticket_sla AS
SELECT t.*,
       TIMESTAMPDIFF(MINUTE, t.created_at, t.resolved_at) / 60 AS resolution_hours,
       CASE t.priority
            WHEN 'Critical' THEN 4
            WHEN 'High'     THEN 8
            WHEN 'Medium'   THEN 24
            ELSE 48
       END AS sla_hours
FROM tickets t;

-- ---------- STEP 4: Analysis queries ----------

-- Q1. Average resolution time by category and priority (JOIN-free aggregation + GROUP BY)
SELECT category, priority,
       COUNT(*) AS resolved_tickets,
       ROUND(AVG(resolution_hours), 1) AS avg_resolution_hours
FROM v_ticket_sla
WHERE resolved_at IS NOT NULL
GROUP BY category, priority
ORDER BY category, priority;

-- Q2. SLA breach rate by agent (JOIN + conditional aggregation)
SELECT a.agent_name, a.team,
       COUNT(*) AS resolved_tickets,
       SUM(v.resolution_hours > v.sla_hours) AS sla_breaches,
       ROUND(100 * SUM(v.resolution_hours > v.sla_hours) / COUNT(*), 1) AS breach_pct
FROM v_ticket_sla v
JOIN agents a ON a.agent_id = v.agent_id
WHERE v.resolved_at IS NOT NULL
GROUP BY a.agent_id, a.agent_name, a.team
ORDER BY breach_pct DESC;

-- Q3. SLA compliance by channel (voice vs chat vs email)
SELECT channel,
       COUNT(*) AS resolved_tickets,
       ROUND(100 * (1 - SUM(resolution_hours > sla_hours) / COUNT(*)), 1) AS sla_compliance_pct
FROM v_ticket_sla
WHERE resolved_at IS NOT NULL
GROUP BY channel
ORDER BY sla_compliance_pct DESC;

-- Q4. Top 3 recurring issue categories per month (CTE + window function)
WITH monthly AS (
    SELECT DATE_FORMAT(created_at, '%Y-%m') AS ticket_month,
           category,
           COUNT(*) AS ticket_count
    FROM tickets
    GROUP BY ticket_month, category
),
ranked AS (
    SELECT ticket_month, category, ticket_count,
           RANK() OVER (PARTITION BY ticket_month ORDER BY ticket_count DESC) AS rnk
    FROM monthly
)
SELECT ticket_month, category, ticket_count, rnk
FROM ranked
WHERE rnk <= 3
ORDER BY ticket_month, rnk;

-- Q5. Tickets still open for more than 48 hours (as of 1 Oct 2025, date functions)
SELECT ticket_id, category, priority, channel, created_at,
       TIMESTAMPDIFF(HOUR, created_at, '2025-10-01 00:00:00') AS hours_open
FROM tickets
WHERE status = 'Open'
  AND TIMESTAMPDIFF(HOUR, created_at, '2025-10-01 00:00:00') > 48
ORDER BY hours_open DESC;

-- Q6. Escalation summary by category (JOIN)
SELECT t.category, e.escalated_to, COUNT(*) AS escalated_tickets
FROM escalations e
JOIN tickets t ON t.ticket_id = e.ticket_id
GROUP BY t.category, e.escalated_to
ORDER BY escalated_tickets DESC;

-- ---------- STEP 5: Stored procedure for the weekly SLA report ----------
DROP PROCEDURE IF EXISTS sp_weekly_sla_report;

DELIMITER //
CREATE PROCEDURE sp_weekly_sla_report(IN p_week_start DATE)
BEGIN
    SELECT priority,
           COUNT(*) AS resolved_tickets,
           SUM(resolution_hours > sla_hours) AS sla_breaches,
           ROUND(100 * (1 - SUM(resolution_hours > sla_hours) / COUNT(*)), 1) AS sla_compliance_pct
    FROM v_ticket_sla
    WHERE resolved_at IS NOT NULL
      AND created_at >= p_week_start
      AND created_at <  DATE_ADD(p_week_start, INTERVAL 7 DAY)
    GROUP BY priority;
END //
DELIMITER ;

CALL sp_weekly_sla_report('2025-03-03');

-- ---------- STEP 6: Indexing (before and after) ----------
-- Tip: for a visible speed difference, raise the ticket count (for example 100000)
-- and cte_max_recursion_depth in STEP 2, then re-run.

-- BEFORE: check the query plan (look at "type" = ALL, meaning a full table scan)
EXPLAIN SELECT * FROM tickets
WHERE created_at >= '2025-03-01' AND created_at < '2025-04-01';

CREATE INDEX idx_tickets_created_at ON tickets (created_at);
CREATE INDEX idx_tickets_category_priority ON tickets (category, priority);

-- AFTER: run the same EXPLAIN again (look for "type" = range and the index name)
EXPLAIN SELECT * FROM tickets
WHERE created_at >= '2025-03-01' AND created_at < '2025-04-01';
