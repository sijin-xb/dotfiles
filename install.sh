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

# --- 会话运行时依赖（只警告不失败；CachyOS 大多自带）---
declare -A runtime_deps=(
  [hyprland]=hyprland
  [qs]=quickshell
  [kitty]=kitty
  [jq]=jq
  [fish]=fish
  [matugen]=matugen
  [grim]=grim
  [wl-copy]=wl-clipboard
  [wtype]=wtype
  [playerctl]=playerctl
  [fcitx5]=fcitx5
  [python3]=python
)
missing=()
for cmd in "${!runtime_deps[@]}"; do
  command -v "$cmd" >/dev/null 2>&1 || missing+=("${runtime_deps[$cmd]}")
done
if ((${#missing[@]})); then
  printf '%s\n' 'Warning: missing runtime packages (configs applied, but the session needs these):' \
    "  sudo pacman -S --needed ${missing[*]}"
fi

printf '%s\n' \
  'Dotfiles applied.' \
  '- Hyprland (lua config) entry: ~/.config/hypr/hyprland.lua — 选择 Hyprland 会话登录即可。' \
  '- Quickshell 随会话自启（hypr execs.lua）；SUPER+T = 终端召唤，SUPER+S = scratchpad。' \
  'Log out and back in (or reboot) to start the full session.'
