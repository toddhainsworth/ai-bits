#!/usr/bin/env bash

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "Unknown Model"')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
vim_mode=$(echo "$input" | jq -r '.vim.mode // empty')
agent_name=$(echo "$input" | jq -r '.agent.name // empty')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // empty')

# Mode emoji: agent, vim insert, vim normal, or default chat
if [ -n "$agent_name" ]; then
  mode_emoji="🤖"
elif [ "$vim_mode" = "INSERT" ]; then
  mode_emoji="✏️"
elif [ "$vim_mode" = "NORMAL" ]; then
  mode_emoji="👁️"
else
  mode_emoji="💬"
fi

# Context usage
if [ -n "$used" ]; then
  used_int=$(printf "%.0f" "$used")
  context_str="📝 ${used_int}%"
else
  context_str="📝 --%"
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

if [ -f "$USAGE_CACHE" ]; then
  IFS='|' read -r plan_pct resets_at < "$USAGE_CACHE"
  plan_str="🔋 ${plan_pct}%"

  # Calculate remaining time until reset
  if [ -n "$resets_at" ]; then
    reset_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "${resets_at%%.*}" "+%s" 2>/dev/null)
    now_epoch=$(date +%s)
    if [ -n "$reset_epoch" ] && [ "$reset_epoch" -gt "$now_epoch" ]; then
      remaining=$(( reset_epoch - now_epoch ))
      hours=$(( remaining / 3600 ))
      mins=$(( (remaining % 3600) / 60 ))
      plan_str="${plan_str} (⏱️ ${hours}h${mins}m)"
    fi
  fi
else
  plan_str="🔋 --%"
fi

# Git repo (clickable link) and branch
git_str=""
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
  # Convert SSH remotes to HTTPS for GitHub, Bitbucket, and GitLab
  remote=$(git -C "$cwd" remote get-url origin 2>/dev/null \
    | sed 's|git@github\.com:|https://github.com/|' \
    | sed 's|git@bitbucket\.org:|https://bitbucket.org/|' \
    | sed 's|ssh://git@bitbucket\.org/|https://bitbucket.org/|' \
    | sed 's|git@gitlab\.com:|https://gitlab.com/|' \
    | sed 's|ssh://git@gitlab\.com/|https://gitlab.com/|' \
    | sed 's|\.git$||')

  if [ -n "$remote" ]; then
    repo_name=$(basename "$remote")
    # OSC 8 clickable link: \e]8;;URL\a TEXT \e]8;;\a
    repo_link=$(printf '\e]8;;%s\a%s\e]8;;\a' "$remote" "$repo_name")
    git_str=" | ${repo_link}"
  fi

  if [ -n "$branch" ]; then
    git_str="${git_str} 🌿 ${branch}"
  fi
fi

if [ -n "$git_str" ]; then
  location_str="🔗 ${git_str# | }"
else
  dir_name="${cwd##*/}"
  location_str="📁 ${dir_name:-~}"
fi

printf '%b' "$mode_emoji $model | $plan_str | $context_str | $location_str\n"
