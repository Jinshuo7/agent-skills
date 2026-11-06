# Scout prompts (fill <<...>>; each scout writes ONE file, at most one page)

Common tail for both: "Plain language for the owner. At most one page (about 40 lines). Cite
URLs. Mark anything unverified as unverified. No raw dumps, no long quotes. Write only to <<OUT>>."

## (a) Does this already exist?
Project brief: <<contents of brief.md>>
Find (1) existing apps that do this, with price and what they lack; (2) open-source projects to
reuse or adapt, each with licence (say if the licence blocks commercial or App Store use),
last commit date, stars, and language/platform; (3) a verdict: build / adapt X / don't build,
with the reason in two lines. Search the web and GitHub (`gh search repos`).

## (b) Which tools fit?
Project brief: <<contents of brief.md>>
Inspect whatever the person already uses: their skills manager if they have one, otherwise the head
tool's own skills, plugins and MCP servers (Claude Code: `~/.claude/skills`, `.claude/skills`,
`claude mcp list`).
Find (1) skills and MCP servers that would help this project, each with a one-line reason, source
and whether it is already installed (search with the CLI's `skills search <q>`, the head tool's own
marketplace, and the web); (2) what to switch off for this project: MCP servers cost the most
context, skills cost only their description until used, so name the ones to turn off and why;
(3) a recommended minimal set (≤6 skills, ≤3 MCP servers). Do not install or change anything.
