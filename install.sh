#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/sijin-xb/dotfiles.git"

if [[ ! -f /etc/arch-release ]]; then
  printf '%s\n' 'This installer supports Arch Linux and Arch-based distributions only.' >&2
  exit 1
fi

if [[ ${EUID} -eq 0 ]]; then
  SUDO=()
else
  SUDO=(sudo)
fi

# github-cli is needed to authenticate against this private repo on a fresh system
"${SUDO[@]}" pacman -Syu --needed --noconfirm git chezmoi github-cli

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  gh auth setup-git
elif ! git ls-remote "$REPO_URL" HEAD >/dev/null 2>&1; then
  printf '%s\n' "Cannot read $REPO_URL (it is private). Run 'gh auth login' first, then re-run this script." >&2
  exit 1
fi

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$source_dir" == "$(chezmoi source-path)" ]]; then
  chezmoi apply
else
  chezmoi init --apply "$REPO_URL"
fi

printf '%s\n' 'Dotfiles applied. Log out and back in (or reboot) to start the full session.'
