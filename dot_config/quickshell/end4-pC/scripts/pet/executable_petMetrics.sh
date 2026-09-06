#!/usr/bin/env bash
# System vitals for the desktop pet, one JSON object per invocation.
# cpuJiffies/rxBytes are raw counters: the QML side diffs consecutive calls
# to get CPU % and download rate, so this script stays stateless.
set -euo pipefail

# Aggregate CPU across all cores: total vs idle jiffies
read -r cpu_jiffies idle_jiffies < <(
	awk '/^cpu /{ total=$2+$3+$4+$5+$6+$7+$8; idle=$5+$6; print total, idle }' /proc/stat
)

# Total received bytes over every interface except loopback
rx_bytes=$(awk 'NR > 2 { split($1, a, ":"); if (a[1] != "lo") sum += $2 } END { print sum + 0 }' /proc/net/dev)

# Online = a default route exists (no traffic is generated)
if ip route show default 2>/dev/null | grep -q '^default'; then
	net_online=true
else
	net_online=false
fi

# Battery (first BAT* supply; desktops have none)
battery_exists=false
battery_percent=100
charging=false
for supply in /sys/class/power_supply/BAT*; do
	[ -d "$supply" ] || continue
	battery_exists=true
	battery_percent=$(<"$supply/capacity")
	status=$(<"$supply/status")
	if [[ $status == Charging || $status == Full ]]; then
		charging=true
	fi
	break
done

# Something compiler-ish running?
compile_count=$(pgrep -fc '(^|/| )(gcc|g\+\+|cc1|clang|clang\+\+|rustc|cargo|make|ninja|cmake|tsc|javac|go)( |$)' 2>/dev/null || true)
compile_count=${compile_count:-0}

hour=$(date +%H)
ts=$(date +%s%3N)

jq -n \
	--argjson cpuJiffies "$cpu_jiffies" \
	--argjson idleJiffies "$idle_jiffies" \
	--argjson rxBytes "$rx_bytes" \
	--argjson netOnline "$net_online" \
	--argjson batteryExists "$battery_exists" \
	--argjson batteryPercent "$battery_percent" \
	--argjson charging "$charging" \
	--argjson compileCount "$compile_count" \
	--argjson hour "$hour" \
	--argjson ts "$ts" \
	'{ cpuJiffies: $cpuJiffies, idleJiffies: $idleJiffies, rxBytes: $rxBytes,
	   netOnline: $netOnline, batteryExists: $batteryExists,
	   batteryPercent: $batteryPercent, charging: $charging,
	   compileCount: $compileCount, hour: $hour, ts: $ts }'
