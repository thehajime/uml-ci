#!/bin/bash
set -euo pipefail
jobs=$1
result() {
	jq -r --arg name "$1" '
	  [.jobs[] | select(.name == $name)][0] |
	  if . == null then "—" else
	    "[\(.conclusion // .status)](\(.html_url))" +
	    ([.steps[]? | select(.conclusion == "failure") | .name][0] |
	      if . then " (" + . + ")" else "" end)
	  end' "$jobs"
}
printf 'Series `%s` · base `%s`\n\n' "$MID" "$SHA"
printf 'Apply %s · ' "$(result apply)"
printf 'Checkpatch %s\n' "$(result checkpatch)"
if ! jq -e 'any(.jobs[]; .name == "apply" and .conclusion == "success")' "$jobs" >/dev/null; then
	echo
	echo 'Kernel builds and boot tests were skipped.'
	exit 0
fi
for mode in mmu nommu; do
	printf '\n### %s\n\nBuild %s\n\n' "${mode^^}" "$(result "build / $mode")"
	echo '| Backend | Normal | Basic | Inf-cpu | Ext |'
	echo '|---|---|---|---|---|'
	for backend in ptrace seccomp; do
		printf '| %s |' "$backend"
		for clock in normal basic inf-cpu ext; do
			printf ' %s |' "$(result "$mode / $backend / $clock")"
		done
		printf '\n'
	done
done
