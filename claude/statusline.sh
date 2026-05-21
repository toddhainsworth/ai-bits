#!/usr/bin/env bash

input=$(cat)

used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
tokens=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')

# Colours (soft 256-colour pastels) — green for plan, light blue for context, yellow for project
GREEN='\e[38;5;151m'
BLUE='\e[38;5;153m'
YELLOW='\e[38;5;222m'
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

# Plan usage (5h window) — cached for 60s to avoid hammering the API
USAGE_CACHE="/tmp/claude-statusline-usage-cache"
USAGE_CACHE_MAX_AGE=60

usage_cache_stale() {
  [ ! -f "$USAGE_CACHE" ] || \
  [ $(($(date +%s) - $(stat -f %m "$USAGE_CACHE" 2>/dev/null || echo 0))) -gt $USAGE_CACHE_MAX_AGE ]
}

if usage_cache_stale; then
  token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | jq -r '.claudeAiOauth.accessToken // empty')
  if [ -n "$token" ]; then
    resp=$(curl -s --max-time 3 "https://api.anthropic.com/api/oauth/usage" \
      -H "Authorization: Bearer $token" \
      -H "anthropic-beta: oauth-2025-04-20" \
      -H "Content-Type: application/json")
    util=$(echo "$resp" | jq -r '.five_hour.utilization // empty')
    resets_at=$(echo "$resp" | jq -r '.five_hour.resets_at // empty')
    if [ -n "$util" ]; then
      printf "%.0f|%s" "$util" "$resets_at" > "$USAGE_CACHE"
    fi
  fi
fi

plan_str="--%"
if [ -f "$USAGE_CACHE" ]; then
  IFS='|' read -r plan_pct resets_at < "$USAGE_CACHE"
  now_epoch=$(date +%s)
  reset_epoch=""
  if [ -n "$resets_at" ]; then
    reset_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "${resets_at%%.*}" "+%s" 2>/dev/null)
  fi

  # Only show the cached % if the window hasn't already reset
  if [ -n "$reset_epoch" ] && [ "$reset_epoch" -gt "$now_epoch" ]; then
    remaining=$(( reset_epoch - now_epoch ))
    hours=$(( remaining / 3600 ))
    mins=$(( (remaining % 3600) / 60 ))
    plan_str="${plan_pct}% (${hours}h${mins}m)"
  fi
fi

printf '%b\n' "${YELLOW}P: ${project_str}${RESET} | ${GREEN}U: ${plan_str}${RESET} | ${BLUE}C: ${context_str}${RESET}"
