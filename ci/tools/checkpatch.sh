#!/bin/bash
set -euo pipefail
mkdir patches
git mailsplit -opatches series.mbox
status=0
for patch in "$PWD"/patches/*; do
	(cd linux && scripts/checkpatch.pl --no-color "$patch") > checkpatch.log 2>&1 || status=1
	while IFS= read -r line; do
		printf '  %s\n' "$line"
		case $line in
		WARNING:*) level=warning ;;
		ERROR:*) level=error ;;
		*) continue ;;
		esac
		message=${line#*: }
		message=${message//'%'/'%25'}
		message=${message//$'\r'/'%0D'}
		printf '::%s title=checkpatch %s::%s\n' "$level" "${patch##*/}" "$message"
	done < checkpatch.log
done
exit "$status"
