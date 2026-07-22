#!/usr/bin/env bash

input=$(cat)

used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
tokens=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(echo "$input" | jq -r '.model.display_name // .model // empty')

# Colours (soft 256-colour pastels) — light blue for context, yellow for project, magenta for model
BLUE='\e[38;5;153m'
YELLOW='\e[38;5;222m'
MAGENTA='\e[38;5;183m'
RESET='\e[0m'

project_str="-"
if [ -n "$cwd" ]; then
  git_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
  [ -n "$git_root" ] && project_str=$(basename "$git_root")
fi

# Context usage
if [ -n "$used" ]; then
  used_int=$(printf "%.0f" "$used")
  context_str="${used_int}%"
  if [ -n "$tokens" ] && [ "$tokens" -gt 0 ]; then
    if [ "$tokens" -ge 1000 ]; then
      tokens_str=$(awk -v t="$tokens" 'BEGIN { printf "%.1fk", t/1000 }')
    else
      tokens_str="${tokens}"
    fi
    context_str="${context_str} (${tokens_str})"
  fi
else
  context_str="--%"
fi

# Strip trailing parenthetical (e.g. "Opus 4.8 (1M context)" -> "Opus 4.8")
model_str=$(echo "${model:--}" | sed -E 's/ *\(.*\)$//')

printf '%b\n' "${YELLOW}P: ${project_str}${RESET} | ${BLUE}C: ${context_str}${RESET} | ${MAGENTA}M: ${model_str}${RESET}"
