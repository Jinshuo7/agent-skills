---
name: grilling
description: Grill the user relentlessly about a plan, decision, or idea. Use when the user wants to stress-test their thinking, or uses any 'grill' trigger phrases.
---

Interview the user relentlessly until you reach a shared understanding. Map this as a **design tree**: every decision branches into the decisions that hang off it.

Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are already settled: the questions you can ask _now_ without guessing at answers you haven't heard yet. Ask the whole frontier in one round: number each question and give your recommended answer. Then wait for the user's answers before the next round.

**Ask every round as clickable cards** with the `AskUserQuestion` tool (load it with ToolSearch if it is deferred), not as text in the chat. The user wants to answer by clicking (user, 2026-11-27).

- One tool call takes 1–4 questions. For a bigger frontier, make several calls back to back in the same round, and number the questions across calls (Q1–Q4, Q5–Q8, …) in the `question` text.
- Each card stands on its own: the `question` holds the full context in one or two plain sentences, `header` is a short chip (≤12 chars), and each option gets a one-line `description` of what it means.
- Put your recommended answer first, with "(Recommended)" at the end of its label. Give 2–4 real options. The user can always type "Other".
- Use `multiSelect: true` only when the choices can be combined (e.g. "where should the badge show?").
- Use `preview` when options are easier to compare by seeing them (copy variants, layouts, code).
- Before the cards, write at most one line of chat text saying which round this is. Don't repeat the questions as text.

Fallback: only if `AskUserQuestion` is not available in this host, use this text format:

```
❓ **Q1** - **<question title>**: <question body>

➡️ <your recommended answer>
```

Word each fallback question so "yes" accepts your recommended answer.

Each round the user answers reshapes the tree: settled decisions push the frontier outward and unblock questions that depended on them. Recompute the frontier and ask the next round. A question whose answer depends on another question still open in this round belongs to a _later_ round, not this one.

Finding _facts_ is your job, never the user's. When a frontier question needs a fact from the environment (filesystem, tools, etc.), dispatch a sub-agent with a fresh context window to find it; don't ask the user for anything you could look up yourself. Don't block on it: a running exploration is an unsettled prerequisite, so only the questions downstream of it wait for the sub-agent to report; ask the rest of the frontier now. The _decisions_ are the user's: put each to them and wait.

The session is done when the frontier is empty: every branch of the design tree visited, nothing left silently assumed. Do not act on it until the user confirms you have reached a shared understanding.
