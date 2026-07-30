-- RevOps · Handoff Orchestrator Agent — schema + seed (Postgres 16)
-- Idempotent: safe to re-run to reset the demo between takes.
-- DB: revops | user: n8n | reached by n8n at host "n8n-postgres" port 5432 (shared docker network).
-- No secrets in this file. Create the Postgres credential in the n8n UI.
--
-- This agent goes back to the CRM-in shape (like the reference Deal Risk agent):
-- it REUSES the `opportunities` table, filters to closed-won deals, and drafts a
-- sales→CS handoff packet for each. It adds one output table (`handoffs`) to the
-- shared `revops` database. Keep this agent's seed focused on closed-won deals.
--
-- Dates are computed relative to CURRENT_DATE so the seed tells the same story
-- every time you reset it.

BEGIN;

DROP TABLE IF EXISTS handoffs CASCADE;
DROP TABLE IF EXISTS opportunities CASCADE;

-- Reused mock-CRM table — identical shape to the reference Deal Risk agent.
CREATE TABLE opportunities (
  id                  serial PRIMARY KEY,
  name                text    NOT NULL,               -- e.g. "Acme — Platform Expansion"
  account             text    NOT NULL,
  owner_rep           text    NOT NULL,
  stage               text    NOT NULL,               -- Discovery / Demo / Proposal / Negotiation / ClosedWon / ClosedLost
  amount              numeric NOT NULL DEFAULT 0,
  created_date        date    NOT NULL,
  close_date          date    NOT NULL,               -- expected / actual close
  last_activity_date  date,                            -- most recent touch
  days_in_stage       int     NOT NULL DEFAULT 0,     -- days in current stage
  champion_identified boolean NOT NULL DEFAULT false,
  competitor          text,                            -- nullable — who we displaced
  next_step           text,                            -- nullable — for won deals: what was promised / kickoff note
  pushed_count        int     NOT NULL DEFAULT 0       -- # times close_date slipped
);

-- Output table — one handoff packet per closed-won deal.
CREATE TABLE handoffs (
  id           serial PRIMARY KEY,
  created_at   timestamptz NOT NULL DEFAULT now(),
  opp_id       int  REFERENCES opportunities(id),
  account      text NOT NULL,
  amount       numeric,
  owner_rep    text,
  brief        text,                                   -- LLM (gemma3:4b) — or templated fallback
  tasks        jsonb,                                  -- [{owner, task}, ...] — LLM or default checklist
  watch_outs   text                                    -- risks / promises to honor (semicolon-joined)
);

-- ---------------------------------------------------------------------------
-- Seed — a handful of ClosedWon deals with champion / competitor / next_step
-- context so each handoff brief has real material to work from. Two non-won
-- deals are included to prove the scan's WHERE filter excludes them.
-- ---------------------------------------------------------------------------

-- A · RICH won deal — champion + competitor displaced + a promised next step.
--     Brief should name the champion, cite the competitor we beat, and the promise.
INSERT INTO opportunities
  (name, account, owner_rep, stage, amount, created_date, close_date, last_activity_date, days_in_stage, champion_identified, competitor, next_step, pushed_count)
VALUES
  ('Acme — Platform Expansion', 'Acme Corp', 'Dana Reyes', 'ClosedWon', 82000,
   CURRENT_DATE - 70, CURRENT_DATE - 4, CURRENT_DATE - 2, 6, true, 'Initech',
   'Promised a 4-6 week rollout and a dedicated onboarding contact', 0);

-- B · RICH won deal — champion + competitor + phased-rollout promise.
INSERT INTO opportunities
  (name, account, owner_rep, stage, amount, created_date, close_date, last_activity_date, days_in_stage, champion_identified, competitor, next_step, pushed_count)
VALUES
  ('Globex — ERP Add-on', 'Globex', 'Sam Ortega', 'ClosedWon', 145000,
   CURRENT_DATE - 110, CURRENT_DATE - 8, CURRENT_DATE - 6, 9, true, 'SAP',
   'Committed to a two-phase go-live and quarterly business reviews', 2);

-- C · SPARSE won deal — no champion, no competitor, no promised next step.
--     Brief should stay generic and NOT invent details; default onboarding checklist.
INSERT INTO opportunities
  (name, account, owner_rep, stage, amount, created_date, close_date, last_activity_date, days_in_stage, champion_identified, competitor, next_step, pushed_count)
VALUES
  ('Umbrella — Analytics Seats', 'Umbrella Inc', 'Priya Nair', 'ClosedWon', 38000,
   CURRENT_DATE - 45, CURRENT_DATE - 3, CURRENT_DATE - 3, 4, false, NULL,
   NULL, 0);

-- D · RICH won deal — champion, competitor, security/SSO promise to honor.
INSERT INTO opportunities
  (name, account, owner_rep, stage, amount, created_date, close_date, last_activity_date, days_in_stage, champion_identified, competitor, next_step, pushed_count)
VALUES
  ('Hooli — Search Migration', 'Hooli', 'Priya Nair', 'ClosedWon', 210000,
   CURRENT_DATE - 130, CURRENT_DATE - 10, CURRENT_DATE - 5, 7, true, 'Pied Piper',
   'SSO must be enabled before go-live; migration window agreed for month-end', 1);

-- Two NON-won deals — must be EXCLUDED by the scan's WHERE filter (proves the filter works).
INSERT INTO opportunities
  (name, account, owner_rep, stage, amount, created_date, close_date, last_activity_date, days_in_stage, champion_identified, competitor, next_step, pushed_count)
VALUES
  ('Soylent — Data Platform', 'Soylent Co', 'Dana Reyes', 'Proposal', 61000,
   CURRENT_DATE - 60, CURRENT_DATE + 10, CURRENT_DATE - 5, 12, true, NULL,
   'Follow up on pricing questions', 0),
  ('Stark — R&D Pilot', 'Stark Industries', 'Sam Ortega', 'ClosedLost', 120000,
   CURRENT_DATE - 100, CURRENT_DATE - 40, CURRENT_DATE - 45, 60, false, 'Wayne Ent',
   'Lost to competitor', 4);

COMMIT;

-- Quick verification view (closed-won deals only — what the scan will process):
-- SELECT id, name, account, owner_rep, amount, champion_identified, competitor, next_step
-- FROM opportunities
-- WHERE stage = 'ClosedWon'
-- ORDER BY id;
