#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { printf "${GREEN}[ok]${NC}    %s\n" "$1"; }
warn()    { printf "${YELLOW}[warn]${NC}  %s\n" "$1"; }
skipped() { printf "${YELLOW}[skip]${NC}  %s\n" "$1"; }
err()     { printf "${RED}[err]${NC}   %s\n" "$1"; }

symlink() {
  local src="$1"
  local dst="$2"

  if [ -L "$dst" ]; then
    current_target=$(readlink "$dst")
    if [ "$current_target" = "$src" ]; then
      skipped "$dst already points to $src"
      return
    else
      warn "$dst exists but points to $current_target — relinking to $src"
      rm "$dst"
    fi
  elif [ -e "$dst" ]; then
    local backup="${dst}.bak.$(date +%Y%m%d%H%M%S)"
    warn "$dst exists as a real file — backing up to $backup"
    mv "$dst" "$backup"
  fi

  ln -s "$src" "$dst"
  info "linked $dst -> $src"
}

check_deps() {
  local missing=()
  for cmd in jq curl git; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [ ${#missing[@]} -gt 0 ]; then
    err "Missing dependencies: ${missing[*]}"
    err "Install them before running this script."
    exit 1
  fi
}

main() {
  echo "Installing ai-bits configuration..."
  echo

  check_deps

  mkdir -p "$CLAUDE_DIR"

  # Claude Code config
  symlink "$REPO_DIR/claude/CLAUDE.md"     "$CLAUDE_DIR/CLAUDE.md"
  symlink "$REPO_DIR/claude/settings.json" "$CLAUDE_DIR/settings.json"
  symlink "$REPO_DIR/claude/statusline.sh" "$CLAUDE_DIR/statusline.sh"

  echo
  echo "Done. Restart your agent to pick up the new settings."
  echo
  echo "Third-party skills are not tracked here. Reinstall them with:"
  echo "  npx skills add <owner/repo>"
}

main "$@"
