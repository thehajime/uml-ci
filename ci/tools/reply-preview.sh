#!/bin/bash
# Render one plain-text reply for the series. Input from mail and logs stays quoted.
set -euo pipefail
[[ -n ${REPLY:-} ]] || exit 0
failures=$(jq -r '.jobs[] | select(.conclusion == "failure") | . as $job |
	.steps[] | select(.conclusion == "failure") |
	select(.name == "Apply series" or .name == "Build kernel and rootfs" or
	       .name == "Boot guest and run tests") |
	[$job.name, .name, $job.id, $job.html_url] | @tsv' "$1")
[[ -n $failures ]] || exit 0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf '%s' "$REPLY" | base64 -d > "$tmp/mail"
while IFS=$'\t' read -r profile step id url; do
	# Infrastructure failures in the same step (apt, registry, controller) should
	# not be attributed to a patch. Match diagnostics from git am, Kbuild or UML.
	if ! curl -fsSL --retry 3 -H "Authorization: Bearer $GH_TOKEN" \
		"$GITHUB_API_URL/repos/$GITHUB_REPOSITORY/actions/jobs/$id/logs" -o "$tmp/log"; then
		echo "Could not retrieve logs for job $id" >&2
		exit 1
	fi
	case $step in
	'Apply series') pattern='^Patch failed at |^error: (patch|corrupt|.*does not apply)' ;;
	'Build kernel and rootfs') pattern='(^|: )(fatal )?error: |^make(\[[0-9]+\])?: \*\*\*' ;;
	*) pattern='Kernel panic - not syncing:|^Oops:|^BUG:|^WARNING: CPU:|^FAIL |^UML-CI .* FAIL$' ;;
	esac
	line=$(sed -E 's/^[0-9T:.Z-]+ //; s/\r$//' "$tmp/log" | grep -E "$pattern" | head -c 400 || :)
	[[ -n $line ]] || continue
	printf '%s — %s\n%s\n%s\n\n' "$profile" "$step" "${line%%$'\n'*}" "$url" >> "$tmp/body"
done <<< "$failures"
[[ -s $tmp/body ]] || { echo 'No patch diagnostic found for a reply preview.'; exit 0; }
echo 'Generated mailing-list reply preview.' >&2
printf '\n### Mailing-list reply preview (dry run)\n\n'
{
	jq -r '"To: " + .from, "Cc: linux-um@lists.infradead.org",
	      "Subject: Re: " + .subject, "In-Reply-To: <" + .id + ">",
	      "References: " + ([.refs, "<" + .id + ">"] | map(select(length > 0)) | join(" "))' "$tmp/mail"
	printf '\nUML CI observed the following failures after applying this series to %s.\n\n' "$SHA"
	cat "$tmp/body"
	printf 'Full run: %s/%s/actions/runs/%s\n' "$GITHUB_SERVER_URL" "$GITHUB_REPOSITORY" "$GITHUB_RUN_ID"
} | tr -d '\000-\010\013-\037\177' | sed 's/^/    /'
