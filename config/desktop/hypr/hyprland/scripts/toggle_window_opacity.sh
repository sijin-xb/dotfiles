#!/bin/bash
# Toggle the active window's opacity between 1.0 and 0.1.
# Bound to SUPER + A in keybinds.lua.
#
# Uses socket2 IPC directly because `hyprctl dispatch setprop` in this
# Lua-config build parses multi-word dispatchers through Lua, which breaks.

MIN_OPACITY=0.1
NORMAL_OPACITY=1.0

SIG="${HYPRLAND_INSTANCE_SIGNATURE:-$(ls -t /run/user/$(id -u)/hypr/ 2>/dev/null | head -1)}"
SOCKET="/run/user/$(id -u)/hypr/$SIG/.socket2.sock"
[ -S "$SOCKET" ] || exit 0

ADDR=$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty')
[ -z "$ADDR" ] && exit 0

STATE_FILE="/tmp/hypr_window_low_opacity"
touch "$STATE_FILE"

if grep -qF "$ADDR" "$STATE_FILE"; then
    sed -i "\|^$ADDR$|d" "$STATE_FILE"
    echo "dispatch setprop address:$ADDR opacity $NORMAL_OPACITY override $NORMAL_OPACITY override $NORMAL_OPACITY override" | socat - UNIX-CONNECT:"$SOCKET"
else
    echo "$ADDR" >> "$STATE_FILE"
    echo "dispatch setprop address:$ADDR opacity $MIN_OPACITY override $MIN_OPACITY override $MIN_OPACITY override" | socat - UNIX-CONNECT:"$SOCKET"
fi
