#!/bin/bash
# The state checkout contains data only. Never execute code from incoming mail.
set -euo pipefail
archive=https://lore.kernel.org/linux-um/0
cursor=$(cat state/cursor)
[[ $cursor =~ ^[0-9a-f]{40}$ ]]
tip=$(git ls-remote --exit-code "$archive" HEAD | cut -f1)
if [[ $cursor == "$tip" && ! -s state/pending ]]; then
	echo 'No new patches.'
	exit 0
fi
mkdir -p inbox
git -C inbox init -q
git -C inbox fetch -q --depth=64 "$archive" "$tip"
while ! git -C inbox merge-base --is-ancestor "$cursor" "$tip" 2>/dev/null; do
	[[ $(git -C inbox rev-parse --is-shallow-repository) == true ]] || {
		echo 'Archive history diverged from the saved cursor.' >&2; exit 1;
	}
	git -C inbox fetch -q --deepen=256 "$archive" "$tip"
done
git -C inbox rev-list --reverse "$cursor..$tip" > commits
while IFS= read -r commit; do
	# public-inbox also records removals; only imported messages have m.
	git -C inbox cat-file -e "$commit:m" 2>/dev/null || continue
	git -C inbox show "$commit:m" > mail
	subject=$(git mailinfo -k /dev/null /dev/null < mail | sed -n 's/^Subject: //p')
	[[ $subject =~ ^\[([^]]*PATCH[^]]*)\] ]] || continue
	tag=${BASH_REMATCH[1]}
	if [[ $tag =~ ([0-9]+)/([0-9]+) ]]; then
		(( 10#${BASH_REMATCH[1]} <= 1 )) || continue
	fi
	id=$(sed '/^\r*$/q' mail | sed -n 's/^Message-ID:[[:space:]]*<\([^<>[:space:]]*\)>[[:space:]]*$/\1/Ip')
	[[ $id != -* && $id =~ ^[^[:space:]/@\<\>?#]+@[^[:space:]/@\<\>?#]+$ ]] || continue
	grep -Fxq -- "$id" state/sent state/pending || echo "$id" >> state/pending
done < commits
printf '%s\n' "$tip" > state/cursor
if [[ -s state/pending ]]; then
	sudo apt-get update -qq
	sudo apt-get install -y b4
fi
: > remaining
while IFS= read -r id; do
	rc=0
	bash ci/tools/series.sh "$id" > series-check.log 2>&1 || rc=$?
	case $rc in
	0) ;;
	42) continue ;; # First patch already belongs to a cover letter.
	*) printf 'Series pending (%s): %s\n' "$rc" "$id"
	   echo "$id" >> remaining
	   continue ;;
	esac
	key=$(printf %s "$id" | sha256sum | cut -c1-16)
	# Recover dispatches accepted before the preceding state push completed.
	gh run list --workflow uml-series.yml --branch main --event workflow_dispatch \
		--limit 200 --json displayTitle > runs.json
	if ! jq -e --arg suffix " · $key" 'any(.[]; .displayTitle | endswith($suffix))' runs.json >/dev/null; then
		title=$(jq -r '.subject | sub("^\\[[^]]*PATCH[^]]*\\]\\s*"; "") |
			if length > 60 then .[:59] + "…" else . end' reply.json)
		gh workflow run uml-series.yml --ref main -f "message_id=$id" -f "inbox_key=$key" -f "patch_title=$title"
	fi
	echo "$id" >> state/sent
done < state/pending
mv remaining state/pending
git -C state add cursor pending sent
if ! git -C state diff --cached --quiet; then
	git -C state -c user.name=uml-ci -c user.email=ci@localhost commit -qm 'Advance linux-um inbox'
	git -C state push origin HEAD:inbox-state
fi
printf 'Pending series: %s\n' "$(wc -l < state/pending)"
