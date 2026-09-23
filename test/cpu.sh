#!/usr/bin/env bash
# Runs an image's binaries under qemu-user with a restricted CPU model (CPUID and instruction set).
#   cpu.sh IMAGE CPU pass   every binary must run
#   cpu.sh IMAGE CPU fail   every binary must be refused by glibc for lacking x86-64-v3, and nothing else
set -uo pipefail
image=$1 cpu=$2 expect=$3
qemu=$(command -v qemu-x86_64-static)
smoke=$(cd "$(dirname "$0")" && pwd)/smoke

cmds=(
	"/usr/local/bin/cephcsi --version"
	"/smoke"
	"/usr/bin/rbd --version"
	"/usr/bin/ceph-fuse --version"
	"/usr/bin/rbd-nbd --version"
	"/usr/bin/mount --version"
	"/usr/sbin/cryptsetup --version"
	"/usr/sbin/mkfs.xfs -V"
	"/usr/sbin/mke2fs -V"
	"/usr/sbin/nvme version"
)

rc=0
for cmd in "${cmds[@]}"; do
	# shellcheck disable=SC2086
	out=$(docker run --rm --entrypoint /qemu -v "$qemu:/qemu:ro" -v "$smoke:/smoke:ro" "$image" -cpu "$cpu" $cmd 2>&1)
	status=$?
	printf '### %s  [%s, exit %s]\n%s\n' "$cmd" "$cpu" "$status" "$out"
	case $expect in
	pass) [ "$status" -eq 0 ] || rc=1 ;;
	fail) [ "$status" -ne 0 ] && grep -q 'CPU does not support x86-64-v3' <<<"$out" || rc=1 ;;
	esac
done
echo "RESULT image=$image cpu=$cpu expect=$expect -> $([ $rc -eq 0 ] && echo OK || echo FAILED)"
exit $rc
