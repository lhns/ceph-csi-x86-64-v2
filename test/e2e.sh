#!/usr/bin/env bash
# Upstream's e2e jobs on a GitHub runner, using upstream's scripts: the CentOS CI jobs on its ci/centos branch
# (mini-e2e*.groovy, k8s-e2e-external-storage.groovy, upgrade-tests.groovy) and .github/workflows/e2e-minikube-acceptance.yaml.
# Run from the ceph-csi checkout, with our image loaded as quay.io/cephcsi/cephcsi:<tag> and ./e2e.test present.
#   e2e.sh mini|operator|helm|upgrade|external-storage|acceptance K8S_MINOR [cephfs|rbd|nfs|nvmeof]
set -xeEuo pipefail
suite=$1 minor=$2 type=${3:-}

set -a
# shellcheck disable=SC1091
source build.env
set +a
KUBE_VERSION=$(curl -sfL "https://dl.k8s.io/release/stable-$minor.txt")
export KUBE_VERSION CONTAINER_CMD=docker
ns=cephcsi-e2e-$suite
image=quay.io/cephcsi/cephcsi:$CSI_IMAGE_VERSION

# Every job must test our build: the EL9 image, still under that tag at the end (a pull would have replaced it).
# E2E_IMAGE_EL=10 is for e2e-upstream-image.yml.
ours=$(docker image inspect -f '{{.Id}}' "$image")
docker run --rm --entrypoint cat "$image" /etc/os-release | grep -qx "VERSION_ID=\"${E2E_IMAGE_EL:-9}\..*\""
trap 'test "$(docker image inspect -f "{{.Id}}" "$image")" = "$ours" || { echo "$image was replaced by a pull" >&2; exit 1; }' EXIT
log=$PWD/e2e-output.log
collect() { # upstream's collect_logs, plus the ceph-csi namespaces it doesn't cover
	scripts/github-action-helper.sh collect_logs || true
	local n p d=/tmp/acceptance-e2e-logs
	kubectl describe pvc -A >"$d/pvc-describe.txt" 2>&1 || true
	for n in $(kubectl get ns -o name | grep -E 'cephcsi|ceph-csi|k8s-storage' | cut -d/ -f2); do
		kubectl -n "$n" get all,events -o wide >"$d/$n-all.txt" 2>&1 || true
		for p in $(kubectl -n "$n" get pods -o name); do
			kubectl -n "$n" logs "$p" --all-containers --prefix >"$d/$n-${p#pod/}.log" 2>&1 || true
			kubectl -n "$n" logs "$p" --all-containers --prefix --previous >"$d/$n-${p#pod/}.previous.log" 2>&1 || true
		done
	done
}
trap collect ERR

only() { # --test-* (and with $2, --deploy-*) flags enabling one driver
	local d f=""
	for d in cephfs rbd nfs nvmeof; do
		f+=" --test-$d=$([ "$d" = "$1" ] && echo true || echo false)"
		[ -z "${2:-}" ] || f+=" --deploy-$d=$([ "$d" = "$1" ] && echo true || echo false)"
	done
	echo "$f"
}
run_e2e() { make run-e2e NAMESPACE="$ns" E2E_ARGS="--delete-namespace-on-failure=false $*" 2>&1 | tee -a "$log"; }
# A suite that skips every spec passes; fail it instead.
ran() {
	grep -o 'Ran [0-9]* of [0-9]* Specs' "$log" | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
	! grep -q 'Ran 0 of' "$log"
}

[ -x e2e.test ] || chmod +x e2e.test
scripts/github-action-helper.sh install_minikube_prereqs
sudo sysctl fs.protected_regular=0
MEMORY=6144 scripts/minikube.sh up
scripts/github-action-helper.sh prepare_disk
for i in 1 2 3 4 5; do docker pull "$ROOK_CEPH_CLUSTER_IMAGE" && break; sleep 30; done
scripts/minikube.sh cephcsi
scripts/minikube.sh k8s-sidecar

if [ "$suite" = acceptance ]; then
	scripts/deploy-ceph-csi-operator.sh deploy
	scripts/minikube.sh install-snapshotter
	ROOK_DEPLOY_TIMEOUT=600 KUBECTL_RETRY_DELAY=5 scripts/minikube.sh deploy-rook
	cd e2e
	../e2e.test -test.v -ginkgo.v --ginkgo.label-filter=acceptance --ginkgo.timeout=25m --deploy-timeout=10 \
		--test-rbd=true --test-cephfs=true --test-nfs=true --test-nvmeof=false \
		--deploy-rbd=false --deploy-cephfs=false --operator-deployment --skip-vault=true 2>&1 | tee -a "$log"
	ran
	exit
fi

# ci/centos preloads vault:latest from its registry mirror; docker.io dropped that tag (1.13.3 was the last).
docker pull -q docker.io/library/vault:1.13.3
docker tag docker.io/library/vault:1.13.3 docker.io/library/vault:latest

# single-node-k8s.sh (ci/centos). It gives Rook three OSDs, as partitions of one disk; the EC pool needs three.
disk=/dev/$(scripts/github-action-helper.sh find_extra_block_dev 2>/dev/null)
sudo sgdisk -n1:0:+6G -n2:0:+6G -n3:0:0 "$disk"
sudo partprobe "$disk"
lsblk "$disk"
ROOK_DEPLOY_TIMEOUT=900 scripts/minikube.sh deploy-rook
# The NVMe-oF nodeplugin connects over NVMe/TCP; the runner's cloud kernel ships that module separately.
if [ "$type" = nvmeof ]; then
	sudo modprobe nvme-tcp || { sudo apt-get install -y -qq "linux-modules-extra-$(uname -r)" && sudo modprobe nvme-tcp; }
fi
scripts/minikube.sh create-block-pool
scripts/minikube.sh create-block-ec-pool
scripts/install-snapshot.sh delete-crd || true
scripts/install-snapshot.sh install

case $suite in
mini)
	run_e2e "$(only "$type" deploy)"
	;;
operator)
	scripts/deploy-ceph-csi-operator.sh deploy
	run_e2e "$(only "$type") --deploy-cephfs=false --deploy-rbd=false --deploy-nfs=false --operator-deployment=true"
	;;
helm)
	# mini-e2e-helm.groovy, less what the 3.18 e2e dropped with --helm-test (#6512): the e2e now
	# creates the StorageClasses and secrets itself, so the charts must not.
	scripts/install-helm.sh up
	scripts/install-helm.sh install-cephcsi --namespace "$ns"
	run_e2e "--deploy-cephfs=false --deploy-rbd=false $(only "$type")"
	;;
upgrade)
	run_e2e "--upgrade-version=$CSI_UPGRADE_VERSION --upgrade-testing=true $(only "$type")"
	;;
external-storage)
	kubectl create namespace "$ns"
	(cd scripts/k8s-storage && ./create-configmap.sh "$ns" && ./create-storageclasses.sh "$ns" && ./create-volumesnapshotclasses.sh "$ns")
	OPERATOR_NAMESPACE=$ns scripts/deploy-ceph-csi-operator.sh deploy
	# run-k8s-external-storage-e2e.sh (ci/centos); NFS is skipped there too unless TEST_NFS is set.
	curl -sfLO "https://dl.k8s.io/$KUBE_VERSION/kubernetes-test-linux-amd64.tar.gz"
	tar xzf kubernetes-test-linux-amd64.tar.gz kubernetes/test/bin/ginkgo kubernetes/test/bin/e2e.test
	KUBECONFIG=$(mktemp)
	kubectl config view --raw --flatten >"$KUBECONFIG"
	export KUBECONFIG
	for driver in scripts/k8s-storage/driver-*.yaml; do
		case $driver in */driver-nfs.yaml) [ "${TEST_NFS:-}" = true ] || continue ;; esac
		kubernetes/test/bin/ginkgo --vv -focus='External.Storage.*.csi.ceph.com' \
			-skip='\[Feature:|\[Disruptive\]|Generic Ephemeral-volume' \
			kubernetes/test/bin/e2e.test -- -storage.testdriver="$PWD/$driver" 2>&1 | tee -a "$log"
	done
	;;
*)
	echo "unknown suite $suite" >&2
	exit 2
	;;
esac
ran
