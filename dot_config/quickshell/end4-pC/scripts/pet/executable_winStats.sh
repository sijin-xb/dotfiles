#!/usr/bin/env bash
# Per-window stats for Hyprland clients, one JSON array per invocation.
# cpuTicks = utime+stime summed over the whole process tree (the QML side
# diffs consecutive calls for CPU %); rssKb = summed RSS in KB.
set -euo pipefail

clk_tck=$(getconf CLK_TCK)
page_kb=$(( $(getconf PAGESIZE) / 1024 ))

clients=$(hyprctl clients -j 2>/dev/null || echo '[]')
pids=$(jq -r '[.[].pid] | join(" ")' <<<"$clients")

procmap=$(awk -v ROOTS="$pids" -v PAGEKB="$page_kb" '
	function collect(p,    nk, j, child, list, arr) {
		sum_ticks += ticks[p]
		sum_rss += rss[p]
		list = kids[p]
		nk = split(list, arr, " ")
		for (j = 1; j <= nk; j++) {
			child = arr[j] + 0
			if (child != p && (child in ticks))
				collect(child)
		}
	}
	{
		pid = $1
		line = $0
		sub(/^[0-9]+ \(/, "", line)
		k = split(line, seg, ")")
		# After the last ")": f[1]=state, f[2]=ppid, f[12]=utime, f[13]=stime, f[22]=rss
		split(seg[k], f, " ")
		ppid[pid] = f[2] + 0
		ticks[pid] = (f[12] + 0) + (f[13] + 0)
		rss[pid] = (f[22] + 0) * PAGEKB
		kids[ppid[pid]] = kids[ppid[pid]] " " pid
	}
	END {
		n = split(ROOTS, root_list, " ")
		for (i = 1; i <= n; i++) {
			r = root_list[i] + 0
			sum_ticks = 0
			sum_rss = 0
			if (r in ticks)
				collect(r)
			print r "\t" sum_ticks "\t" sum_rss
		}
	}' /proc/[0-9]*/stat)

jq -n --argjson clients "$clients" --arg procmap "$procmap" --argjson clk "$clk_tck" '
	($procmap | split("\n") | map(select(length > 0))
	 | map(split("\t") | {key: .[0], value: {ticks: (.[1] | tonumber), rss: (.[2] | tonumber)}})
	 | from_entries) as $m
	| [ $clients[] | {
		address: .address,
		pid: .pid,
		class: .class,
		title: .title,
		workspace: .workspace.id,
		cpuTicks: ($m[(.pid | tostring)].ticks // 0),
		rssKb: ($m[(.pid | tostring)].rss // 0),
		clkTck: $clk
	} ]'
