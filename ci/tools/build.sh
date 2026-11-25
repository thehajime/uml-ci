#!/bin/bash
# Run from a scratch directory containing the kernel checkout in linux/.
set -euo pipefail
mode=$1
guest=$(cd "$(dirname "$0")/../tests" && pwd)
out=$PWD/build
mkdir -p results
kmake=(make -C linux ARCH=um O="$out")
"${kmake[@]}" x86_64_defconfig
setting=-e
expected='CONFIG_MMU=y'
image='alpine@sha256:c64c687cbea9300178b30c95835354e34c4e4febc4badfe27102879de0483b5e'
if [[ $mode == nommu ]]; then
	setting=-d
	expected='# CONFIG_MMU is not set'
	image='ghcr.io/thehajime/alpine@sha256:cb6faeaacad2fd6da516b092723c741acd1c5e55a99fab8a7dc1cd60602067e4'
fi
linux/scripts/config --file "$out/.config" "$setting" MMU -d SMP -d RAID6_PQ_BENCHMARK -e UML_TIME_TRAVEL_SUPPORT -d MODULES -d DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT -e DEBUG_INFO_NONE -e BINFMT_ELF_FDPIC
"${kmake[@]}" olddefconfig
cp "$out/.config" results/config
grep -Fxq "$expected" results/config
grep -Fxq CONFIG_UML_TIME_TRAVEL_SUPPORT=y results/config
release=$("${kmake[@]}" -s --no-print-directory kernelrelease)
echo "$release" > release
printf '%s\n' "$image" "$release" > results/environment
uname -a >> results/environment
gcc --version | head -1 >> results/environment
echo "::group::Build $mode kernel $release"
if ! "${kmake[@]}" -j"$(nproc)" linux 2>&1 | tee results/build.log; then
	echo "::endgroup::"
	echo BUILD-FAIL > results/status
	exit 1
fi
echo "::endgroup::"

# Copy only the guest loader and BusyBox from the pinned image.
mkdir -p root/{bin,dev,lib,proc,tests}
cid=$(docker create "$image" /bin/sh)
trap 'docker rm "$cid" >/dev/null' EXIT
docker cp -L "$cid:/bin/busybox" root/bin/busybox
docker cp -L "$cid:/lib/ld-musl-x86_64.so.1" root/lib/ld-musl-x86_64.so.1
ln -s ld-musl-x86_64.so.1 root/lib/libc.musl-x86_64.so.1
ln -s busybox root/bin/sh
install -m755 "$guest"/*.sh root/tests/
install -m755 "$guest/guest-init" root/init
musl-gcc -O2 -fPIE -pie "$guest/smoke.c" -o root/smoke
# Use the same vDSO symbol resolver and selftest on both sides.
git -C linux archive "$SHA" tools/testing/selftests/{kselftest.h,vDSO} | tar -x
tests=tools/testing/selftests
musl-gcc -O2 -fPIE -pie -I"$tests/vDSO" -idirafter /usr/include \
	-idirafter "/usr/include/$(gcc -print-multiarch)" "$guest/vdso-clock.c" \
	"$tests/vDSO/parse_vdso.c" -o root/vdso-clock
if [[ $mode == mmu ]]; then
	gcc -static -O2 -I"$tests" "$tests/vDSO/vdso_test_gettimeofday.c" \
		"$tests/vDSO/parse_vdso.c" -o root/vdso-test
fi
truncate -s 32M root.ext4
mkfs.ext4 -q -F -d root root.ext4
