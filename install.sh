#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f /etc/arch-release ]]; then
  printf '%s\n' 'This installer supports Arch Linux and Arch-based distributions only.' >&2
  exit 1
fi

if [[ ${EUID} -eq 0 ]]; then
  SUDO=()
else
  SUDO=(sudo)
fi

"${SUDO[@]}" pacman -Syu --needed --noconfirm git chezmoi

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  gh auth setup-git
fi

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$source_dir" == "$(chezmoi source-path)" ]]; then
  chezmoi apply
else
  chezmoi init --apply https://github.com/sijin-xb/dotfiles.git
fi
