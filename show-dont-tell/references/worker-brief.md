# Worker brief (template)

The lead fills the `<…>` parts, saves it as `brief.txt` in the round's folder and runs the user config's `worker.call` there (with bash allowed). One brief per job; jobs that don't depend on each other run at the same time.

```
Task: <one line: run this image round | build the compare sheet | import these images into Eagle>. The lead shows your result to the user.
Skill folder: <skill>. Work folder: <save_to>.

Inputs (use only these):
- <slug>-NN.prompt.txt …   (or the images and refs for the sheet / import)

Run exactly:
<the command(s) from SKILL.md, filled in>

Rules:
- Run the commands as written. Change no file except the ones the commands write.
- Do not retry with other settings, libraries or models. Do not open, sign in to or switch anything.
- If a command prints FAILED, an error, or Eagle refuses the library: stop and report it word for word.

Report (plain text, nothing else):
1. Each command and its last 5 lines of output.
2. Each output file: path and pixel size (`sips -g pixelWidth -g pixelHeight`), or "missing".
3. What slowed me down.
Self-check: every file in 2 exists on disk.
```

The lead checks the report against the files before the round report reaches the user.
