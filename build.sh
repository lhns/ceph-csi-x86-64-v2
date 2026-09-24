#!/usr/bin/env bash
# Builds upstream ceph-csi with its own Makefile, on the EL9 (x86-64-v2) base pinned in versions.Dockerfile.
#   build.sh checkout     clone ceph/ceph-csi at the pinned tag into ./src and point build.env at our base
#   build.sh image        make image-cephcsi -> quay.io/cephcsi/cephcsi:<tag>, the name upstream's e2e deploys
#   build.sh make ARGS    any other upstream make target
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
src=$here/src

pin() { awk -v s="$1" '$1 == "FROM" && $4 == s { print $2 }' "$here/versions.Dockerfile"; }
version=$(pin ceph-csi); version=${version##*:}
base=$(pin base)
final=$(pin final)

case ${1:-} in
checkout)
	git clone --quiet --depth 1 --branch "$version" https://github.com/ceph/ceph-csi "$src"
	cd "$src"
	# Upstream's only x86-64-v3 dependency is its EL10 base; Tentacle ships the same packages for EL9.
	sed -i -e "s|^BASE_IMAGE=.*|BASE_IMAGE=$base|" \
		-e 's|^\(CEPH_RELEASE_RPM=.*\)/el10/noarch/ceph-release-1-1\.el10\.noarch\.rpm$|\1/el9/noarch/ceph-release-1-1.el9.noarch.rpm|' \
		build.env
	grep -qx "BASE_IMAGE=$base" build.env
	grep -q '^CEPH_RELEASE_RPM=.*/el9/noarch/ceph-release-1-1\.el9\.noarch\.rpm$' build.env || {
		echo "build.env: CEPH_RELEASE_RPM not rewritten; upstream changed it" >&2; exit 1; }
	# Committed so upstream's "tree is clean" checks (mod-check, check-all-committed) still apply.
	git -c user.name=ceph-csi-x86-64-v2 -c user.email=noreply@github.com commit --quiet -am "build.env: x86-64-v2 base"
	git --no-pager show --stat --format='%h %s' HEAD
	git --no-pager diff HEAD^ HEAD
	;;
image)
	cd "$src"
	# The Makefile doesn't forward FINAL_BASE_IMAGE; $(CPUSET) is the free slot in its `docker build` line.
	make image-cephcsi CONTAINER_CMD=docker GOARCH=amd64 GIT_COMMIT="$(git rev-parse HEAD^)" \
		CPUSET="--build-arg=FINAL_BASE_IMAGE=$final --label=org.opencontainers.image.source=https://github.com/lhns/ceph-csi-x86-64-v2"
	;;
make)
	shift
	cd "$src"
	make CONTAINER_CMD=docker GOARCH=amd64 "$@"
	;;
version)
	echo "$version"
	;;
*)
	sed -n '2,5p' "$0" >&2
	exit 2
	;;
esac
