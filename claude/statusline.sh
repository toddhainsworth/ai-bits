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
AMBER='\e[38;5;215m'
RED='\e[38;5;203m'
RESET='\e[0m'

# Point at which each model's output quality noticeably degrades, and double that
OPUS_WARN_TOKENS=250000
SONNET_WARN_TOKENS=400000

project_str="-"
if [ -n "$cwd" ]; then
  git_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
  [ -n "$git_root" ] && project_str=$(basename "$git_root")
fi

# Strip trailing parenthetical (e.g. "Opus 4.8 (1M context)" -> "Opus 4.8")
model_str=$(echo "${model:--}" | sed -E 's/ *\(.*\)$//')

warn_tokens=""
case "$model_str" in
  Opus\ 5*) warn_tokens="$OPUS_WARN_TOKENS" ;;
  Sonnet\ 5*) warn_tokens="$SONNET_WARN_TOKENS" ;;
esac

context_colour="$BLUE"
context_warn=""
if [ -n "$warn_tokens" ] && [ -n "$tokens" ]; then
  if [ "$tokens" -ge $((warn_tokens * 2)) ]; then
    context_colour="$RED"
    context_warn="!! "
  elif [ "$tokens" -ge "$warn_tokens" ]; then
    context_colour="$AMBER"
    context_warn="! "
  fi
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

printf '%b\n' "${YELLOW}P: ${project_str}${RESET} | ${context_colour}${context_warn}C: ${context_str}${RESET} | ${MAGENTA}M: ${model_str}${RESET}"
