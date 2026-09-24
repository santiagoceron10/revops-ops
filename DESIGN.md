# Handoff Orchestrator Agent — Design (RevOps agent #4)

**Function:** RevOps Ops · **Repo:** `revops-ops` (public)
**Status:** ✅ System architecture & design + reference implementation — a complete, documented build you can deploy on your own stack (see setup below). Schema, workflow, and blueprint are complete and structurally validated.

Clones the RevOps template back to the **CRM-in** shape (like the reference [Deal Risk](https://github.com/santiagoceron10/revops-deal-review) agent): it reuses the **`opportunities`** mock CRM, filters to **closed-won** deals, and uses the local LLM to draft the **sales→CS handoff** — a brief + onboarding task checklist + watch-outs.

**Same stack:** n8n (Docker) + Postgres (`revops` DB) + local Ollama `gemma3:4b`.

---

## What it does

When a deal is won, nothing should fall through the cracks in the handoff to Customer Success. This agent scans closed-won deals and generates, for each, a **CS handoff packet**: a plain-English brief of what was sold and to whom, an **onboarding task checklist** with owners, and **watch-outs** (risks/promises to honor).

```
Trigger (scan closed-won) → fetch deal → shape facts → LLM draft handoff
   → parse + fallback → log + compose → mock notify (create CS tasks)
```

This is the same eight-node skeleton the other RevOps agents use — only the SQL, the prep logic, and the LLM prompt change.

## Data (Postgres `revops`)

- **Reuse `opportunities`** — filter `stage = 'ClosedWon'`. The seed adds several closed-won rows with champion / competitor / next-step context so each brief has material, plus a couple of non-won rows to prove the filter excludes them.
- **New `handoffs`** (output): `id`, `created_at`, `opp_id`, `account`, `amount`, `owner_rep`, `brief text`, `tasks jsonb`, `watch_outs text`.

*(An optional `handoff_created bool` on `opportunities` to mark processed deals is out of scope for this reference implementation — see below.)*

## Logic (Code node — light, no scoring)

Select closed-won deals; shape each deal's facts (account, amount, owner_rep, champion, competitor, next_step, close_date) into the prompt context. There's no scoring here — the LLM does the drafting. This is **swap-point 2** (PREP); the SQL above is **swap-point 1** (FETCH).

## LLM reasoning (Ollama / gemma3:4b) — swap-point 3 (PROMPT)

Prompt with the deal facts; require **JSON only**:

```json
{ "brief": "3-4 sentence sales->CS summary: who bought, what/why, key contacts",
  "tasks": [ {"owner": "CS|Onboarding|AE", "task": "…"} ],
  "watch_outs": ["risks, promises made, competitor context to honor"] }
```

Low temperature; "use only the deal facts; don't invent contract terms." **Fallback:** on JSON-parse failure (or a missing brief/tasks), the workflow synthesizes a templated brief + a default onboarding checklist from the deal fields so a run always completes.

## Output

- INSERT one `handoffs` row (tasks cast to `jsonb`).
- **Compose** a readable handoff packet (Brief / Onboarding tasks `[owner] task` / Watch-outs).
- **NoOp mock notify** — labeled swap-point for "create CS onboarding tasks + notify CS channel."

## Illustrative behavior (NOT executed — placeholder only)

- A won deal with a champion + competitor → brief names them; tasks include kickoff + success-plan; watch-outs cite the competitor displaced and the promise made.
- A sparse won deal → brief + generic onboarding checklist, no invented details.
- Non-JSON LLM response → templated fallback packet, run still completes.

## Success criteria (authoring only)

- `handoffs` + several ClosedWon rows in an idempotent `revops-schema.sql` (reuses `opportunities`).
- 8-node workflow cloned from the template with the three swap-points commented (FETCH closed-won / PREP facts / PROMPT handoff).
- Exported `handoff-orchestrator-agent.workflow.json` + `revops-schema.sql`; published public `revops-ops`; added to the profile "RevOps Agents" grouping.
- **No execution / no test run.** Statically authored placeholder; workflow JSON and embedded code are structurally validated only.

## Out of scope

Real CS-tool task creation (swap-point); dedupe / idempotency of already-processed deals; any live run or testing.
