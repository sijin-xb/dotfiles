# sijin-xb's dotfiles

Personal desktop configuration for Arch-based systems (developed on CachyOS)
with Hyprland and Quickshell. The source tree uses chezmoi-style naming
(`dot_` and `executable_` prefixes), but installation is handled by a
standalone bash script; the chezmoi binary is not required.

## Contents

- Hyprland configuration in Lua. `hyprland/` is the template layer,
  `custom/` is the user overlay; files in `custom/` load after the defaults
  and override them.
- Quickshell shell based on the end4-pC fork (bar, sidebars, launcher,
  overview, settings). This repository tracks only the diff layer.
- Lock screen: Quickshell LockSurface (clock, media card with album art and
  seekable progress, password entry, power actions). hyprlock is the fallback
  when quickshell is not running.
- Desktop lyrics overlay with per-word timing (Kugou KRC). Works with any
  MPRIS player.
- matugen wallpaper-based color generation for kitty, alacritty, foot,
  fastfetch, fcitx5, mako and Hyprland.
- fish configuration with fzf bindings and nvm.
- nvim (LazyVim-based), btop, fastfetch, fuzzel, mako configurations.

## Requirements

- Arch-based distribution (`/etc/arch-release` present)
- Hyprland on Wayland
- sudo access for pacman; the script runs as a normal user
- quickshell, matugen and mpvpaper are installed by the script if missing
  (pacman, AUR, or source build, in that order)

## Install

```bash
git clone https://github.com/sijin-xb/dotfiles.git
cd dotfiles
./install.sh           # TUI menu
./install.sh install   # run all steps directly
```

Install steps:

1. pacman dependencies (hyprland, kitty, fish, fuzzel, fcitx5, cliphist,
   hypridle, hyprlock, xdg portals, qt6 toolchain)
2. AUR packages (matugen, mpvpaper); bootstraps yay if no AUR helper exists
3. quickshell: existing binary, else pacman, else AUR, else source build
4. deploy `dot_*` entries to `$HOME`; differing existing files are backed up
   to `~/.local/state/dotfiles-backup/` before overwrite
5. clone the quickshell base (pctrade/end4-pC) on first run
6. create a python venv with pypinyin and dbus-python for launcher pinyin
   search

Re-running the installer is idempotent.

## Script commands

| Command | Behavior |
|---|---|
| `install` | full install; takes a pre-install snapshot first |
| `rollback` | restore the pre-install snapshot; takes a pre-rollback snapshot first |
| `restore` | re-apply the pre-rollback snapshot (undo a rollback) |
| `archive [-o PATH] [--delete]` | pack config, state and cache into a tar.gz with MANIFEST.txt; `--delete` removes sources after packing |
| `uninstall` | optionally archive, then remove managed paths |
| no args / `--tui` | two-level menu TUI |
| `-h` | help |

Snapshots cover only the managed path list (`SNAP_PATHS` in the script).
Files outside that list are never modified.

## Keybinds (selection)

| Key | Action |
|---|---|
| Super | launcher (pinyin search) |
| Super+T | terminal summon (quake-style kitty) |
| Super+S | scratchpad |
| Super+L | lock screen (quickshell lock surface) |
| Super+Q | close window |
| Super+1..0, Super+arrows | switch workspace / focus |
| Super+Shift+arrows | move window |
| Super+Shift+S, Print | region screenshot |
| Super+Shift+R | region record |
| Super+Shift+P / N / B | play-pause / next / previous |
| Super+F1 | restart fcitx5 |
| Ctrl+Super+T | wallpaper selector |

Full lists: `~/.config/hypr/hyprland/keybinds.lua` and
`~/.config/hypr/custom/keybinds.lua`.

## Directory layout

```
dot_config/
  hypr/
    hyprland.lua          entry point
    hyprland/             template layer (keybinds, general, rules, env, execs, scripts)
    custom/               user overlay (same filenames override the template)
    hyprlock.conf         fallback lock screen config
    hyprlock/             colors and helper scripts
  quickshell/end4-pC/     shell diff layer (modules, services, scripts)
  fish/  kitty/  foot/  alacritty/  nvim/  btop/  fastfetch/  fuzzel/  mako/  matugen/
install.sh                installer / uninstaller / rollback / archive / TUI
```

## Lock screen

`Super+L` dispatches `quickshell:lock`. The lock surface shows the blurred
desktop wallpaper (same source chain as the desktop background, including the
optional `lockWall` override and video thumbnails), clock and date, a media
card (album art, title/artist, seekable progress bar, previous/play/next),
the password entry and power actions. hypridle triggers the same lock on
idle timeout; hyprlock is used when quickshell is not running.

## Notes

- Colors regenerate on wallpaper change; templates live in
  `dot_config/matugen/templates/`.
- Desktop lyrics offset adjustment:
  `qs -c end4-pC ipc call desktoplyrics offset_faster / offset_slower`
- Backup root: `~/.local/state/dotfiles-backup/` (`snapshots/` and `state/`).

## License

MIT
