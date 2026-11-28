# How to plug in known tools (mechanics only)

No model picks and no prices here: those come from the person and from the trial. These are facts
about calling each tool from a script, learned the hard way. `belt slot-test` is still the judge.
`<provider>` and `<model>` come from the tool's own model list.

## Claude Code (`claude`)
- Slots need the `claude` command line tool, not just the desktop app (`command -v claude`; sign in
  with `claude auth login`, which the person does themselves).
- The prompt goes on standard input: `claude -p --model <model> < "$BELT_PROMPT_FILE"`.
- Worker: add `--permission-mode acceptEdits` so it can edit files.
- Reviewer, read-only: `--allowedTools Read,Grep,Glob --disallowedTools Bash,Edit,Write,NotebookEdit`.
- It only reads and writes inside the folder it runs in: copy anything it needs into the project first.

## Codex (`codex`)
- `codex exec -m <model> ... - < "$BELT_PROMPT_FILE"` (the `-` reads the prompt from standard input).
- Reviewer: `-s read-only -o "$BELT_OUT_FILE"` (writes its final answer to the out file).
  Worker: `-s workspace-write`.
- Outside a git repo add `--skip-git-repo-check`. It cannot write `.git`: the belt commits.

## pi (`pi`)
- `pi --provider <provider> --model <model> -p "$(cat "$BELT_PROMPT_FILE")" </dev/null`.
- Without `</dev/null` it waits for input forever. Always pass `--provider` and `--model`; list them
  with `pi --list-models`.
- No sandbox: a reviewer can technically edit files; the belt's unchanged-folder check catches it.

## Anything else
Research how to call it non-interactively, then prove it with `belt slot-test`. Add what you learn here
only if it is a mechanical fact (a flag, a hang, a permission), never a model choice or a price.
