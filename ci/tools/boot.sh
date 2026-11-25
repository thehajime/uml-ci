#!/bin/bash
set -euo pipefail
mode=$1
backend=$2
timing=$3
release=$(cat release)
out=$PWD/build
mkdir -p results run-tmp
chmod +x "$out/linux"
option=off
[[ $backend == ptrace ]] || option=on
args=(ubd0=root.ext4 root=/dev/ubda ro rootfstype=ext4 mem=512M
      con=null con0=fd:0,fd:1 console=tty0 init=/init "seccomp=$option" panic=1)
clock=
case $timing in
normal) ;;
basic)
	clock=time-travel-clock
	args+=(time-travel) ;;
inf-cpu)
	clock=time-travel-clock
	args+=(time-travel=inf-cpu) ;;
ext)
	clock=time-travel-clock-external
	git init -q usfstl
	git -C usfstl fetch -q --depth=1 https://github.com/linux-test-project/usfstl 58ac4fd434872244c1153441a9d0d37c52603b95
	git -C usfstl checkout -q --detach FETCH_HEAD
	make -C usfstl/control
	socket="$PWD/run-tmp/calendar.sock"
	usfstl/control/controller --time="$socket" --clients=1 > results/controller.log 2>&1 &
	controller=$!
	trap 'kill "$controller" 2>/dev/null || :' EXIT
	for ((i=0; i<100; i++)); do
		[[ -S $socket ]] && break
		kill -0 "$controller"
		sleep .05
	done
	test -S "$socket"
	args+=("time-travel=ext:$socket") ;;
*) exit 2 ;;
esac
if [[ -n $clock ]]; then
	args+=(-- time-travel)
fi
echo "::group::Boot $mode / $backend / $timing"
{ printf '%q ' "$out/linux" "${args[@]}"; printf '\n'; } | tee "results/$backend.cmd"
log=results/$backend.log
TMPDIR="$PWD/run-tmp" timeout -k 10 150 "$out/linux" "${args[@]}" </dev/null 2>&1 | tee "$log"
tr -d '\r' < "$log" | grep -Fx "UML-CI $release PASS"
if grep -E 'Kernel panic|Oops:|BUG:|WARNING: CPU:' "$log"; then
	exit 1
fi
if [[ -n $clock ]]; then
	grep -Fx "clocksource: Switched to clocksource $clock" "$log"
fi
echo "::endgroup::"
