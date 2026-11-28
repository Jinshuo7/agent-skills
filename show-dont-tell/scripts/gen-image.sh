#!/bin/zsh
# Generate one image with ChatGPT's image model through the Codex CLI bundled in the ChatGPT app.
# Uses the user's signed-in ChatGPT plan (~/.codex/auth.json). No API key needed.
# Run from the project folder. Usage: <skill>/scripts/gen-image.sh <prompt-file> <output-path> [reference-image ...]
# Log goes to gen-logs/<output-name>.log in the current folder.
set -e
[ -f "$1" ] || { echo "FAILED, prompt file not found: $1"; exit 1; }
C=/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex
P="$1"; OUT="$2"; shift 2
NAME="${OUT:t:r}"; mkdir -p gen-logs "${OUT:h}"
REFS=(); for r in "$@"; do REFS+=(-i "$r"); done
HEAD="Use your image generation tool to create ONE image. Do not write code or change any file except saving the final image. Save it as $OUT in the current folder (copy it from wherever the tool writes it). Reply only with the saved path."
"$C" exec --skip-git-repo-check -s workspace-write -C "$PWD" "${REFS[@]}" -o "gen-logs/$NAME.last.txt" "$HEAD

$(cat "$P")" </dev/null > "gen-logs/$NAME.log" 2>&1 || true   # report below, not a silent exit
[ -f "$OUT" ] && echo "OK $OUT" || { echo "FAILED, see gen-logs/$NAME.log"; exit 1; }
