# Brief for <<WORKER>>: write the project's agent documents

Project: <<NAME>> in <<PROJECT_DIR>>. Read `<<NOTES>>/brief.md` and `<<NOTES>>/decisions.md`, then
the templates in <<NOTES>>/templates/ (HEAD-CARD.md, AGENTS.md, OWNER-INSTRUCTIONS.md,
NEXT-SESSION-HANDOFF.md). Fill each template for this project (replace every <<...>>, delete
sections that do not apply, keep wording short) and write:
1. `<<HEAD_FILE>>` from HEAD-CARD.md (if it is `AGENTS.md`, put the card at the top of it): at most 15 lines, NO `@` imports. A head card: role, who the owner is, where
   OWNER-INSTRUCTIONS.md is, the build/test commands, the risky areas.
2. `AGENTS.md`: worker handbook (build/test commands, architecture sketch, safety, docs).
3. `docs/agents/OWNER-INSTRUCTIONS.md`.
4. `docs/agents/NEXT-SESSION-HANDOFF.md`: one page.
5. `docs/agents/OWNER-SUMMARY.md`: one page in plain language for the owner (<<OWNER_PROFILE>>):
   what we are building, who does what, what the owner will be asked, what happens next.
Fill <<OWNER_PROFILE>>, <<HEAD>>, <<WORKER>>, <<REVIEWER>>, <<RISKY_REVIEWER>>, <<HEAD_FILE>> and <<BELT>> from brief.md and decisions.md.
Do not invent commands or architecture: where the stack or design is not chosen yet, write "undecided".
Do not touch any other file. Finish by checking that the head card section is at most 15 lines and that `grep -rn '<<' <<HEAD_FILE>> AGENTS.md docs/agents` finds nothing;
fix anything that fails. Reply with a 5-line receipt only.
