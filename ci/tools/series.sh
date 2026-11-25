#!/bin/bash
# Write the requested single patch or complete revision to series.mbox.
set -euo pipefail
mid=${1#<}
mid=${mid%>}
[[ $mid != -* && $mid =~ ^[^[:space:]/@\<\>?#]+@[^[:space:]/@\<\>?#]+$ ]] || { echo "Invalid Message-ID" >&2; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/messages" "$tmp/selected"
curl -gfLsS --retry 3 --max-time 120 "https://lore.kernel.org/linux-um/$mid/t.mbox.gz" |
	gzip -dc > "$tmp/thread"
git mailsplit -o"$tmp/messages" "$tmp/thread" >/dev/null

# Keep the root and its descendants; a thread can contain unrelated rerolls.
subject=
refs=
for mail in "$tmp"/messages/*; do
	headers=$(sed '/^\r*$/q' "$mail" | sed ':a;N;$!ba;s/\n[ \t]\+/ /g')
	id=$(sed -n 's/^Message-ID:[[:space:]]*//Ip' <<< "$headers")
	if [[ $id == "<$mid>" ]]; then
		info=$(git mailinfo --no-inbody-headers -k /dev/null /dev/null < "$mail")
		subject=$(sed -n 's/^Subject: //p' <<< "$info")
		from=$(sed -n 's/^Email: //p' <<< "$info")
		refs=$(sed -n 's/^References:[[:space:]]*//Ip' <<< "$headers")
		parent=$(sed -n 's/^In-Reply-To:[[:space:]]*//Ip' <<< "$headers")
		jq -n --arg id "$mid" --arg subject "$subject" --arg from "$from" \
			--arg refs "${refs:-$parent}" '{id:$id,subject:$subject,from:$from,refs:$refs}' > reply.json
	elif ! grep -Ei '^(In-Reply-To|References):' <<< "$headers" | grep -F "<$mid>" >/dev/null; then
		continue
	fi
	cat "$mail" >> "$tmp/subthread"
done
[[ $subject =~ ^\[([^]]*PATCH[^]]*)\] ]] || { echo "Patch or cover letter missing" >&2; exit 1; }
tag=${BASH_REMATCH[1]}
version=1
expected=1
if [[ $tag =~ (^|[[:space:]])v([0-9]+)($|[[:space:]]) ]]; then version=${BASH_REMATCH[2]}; fi
if [[ $tag =~ ([0-9]+)/([0-9]+) ]]; then
	pos=${BASH_REMATCH[1]}
	expected=${BASH_REMATCH[2]}
	(( 10#$pos <= 1 )) || { echo "Use the cover or first patch Message-ID" >&2; exit 1; }
	if (( 10#$pos == 1 )); then
		for mail in "$tmp"/messages/*; do
			ancestor=$(sed '/^\r*$/q' "$mail" | sed -n 's/^Message-ID:[[:space:]]*//Ip')
			[[ -n $ancestor && " $refs $parent " == *" $ancestor "* ]] || continue
			title=$(git mailinfo -k /dev/null /dev/null < "$mail" | sed -n 's/^Subject: //p')
			if [[ $title =~ ^\[([^]]*PATCH[^]]*)\] ]]; then
				cover=${BASH_REMATCH[1]}
				rev=1
				if [[ $cover =~ (^|[[:space:]])v([0-9]+)($|[[:space:]]) ]]; then rev=${BASH_REMATCH[2]}; fi
				if [[ $rev == "$version" && $cover =~ (^|[[:space:]])0+/0*([1-9][0-9]*)($|[[:space:]]) ]] &&
				   (( 10#${BASH_REMATCH[2]} == 10#$expected )); then
					echo 'Use the cover letter Message-ID' >&2
					exit 42
				fi
			fi
		done
	fi
fi
b4 --offline-mode am -m "$tmp/subthread" -v "$version" -T -o - "$mid" > "$tmp/series"
count=$(git mailsplit -o"$tmp/selected" "$tmp/series")
(( count > 0 && count == 10#$expected )) || { echo "Expected $expected patches, got $count" >&2; exit 1; }
mv "$tmp/series" series.mbox
