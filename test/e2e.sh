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
ours=$(docker image inspect -f '{{.Id}}' "$image")
docker run --rm --entrypoint cat "$image" /etc/os-release | grep -qx 'VERSION_ID="9\..*"'
trap 'test "$(docker image inspect -f "{{.Id}}" "$image")" = "$ours" || { echo "$image was replaced by a pull" >&2; exit 1; }' EXIT
trap 'scripts/github-action-helper.sh collect_logs || true' ERR

only() { # --test-* (and with $2, --deploy-*) flags enabling one driver
	local d f=""
	for d in cephfs rbd nfs nvmeof; do
		f+=" --test-$d=$([ "$d" = "$1" ] && echo true || echo false)"
		[ -z "${2:-}" ] || f+=" --deploy-$d=$([ "$d" = "$1" ] && echo true || echo false)"
	done
	echo "$f"
}
run_e2e() { make run-e2e NAMESPACE="$ns" E2E_ARGS="--delete-namespace-on-failure=false $*"; }

chmod +x e2e.test
scripts/github-action-helper.sh install_minikube_prereqs
sudo sysctl fs.protected_regular=0
MEMORY=6144 scripts/minikube.sh up
scripts/github-action-helper.sh prepare_disk
docker pull "$ROOK_CEPH_CLUSTER_IMAGE"
scripts/minikube.sh cephcsi
scripts/minikube.sh k8s-sidecar

if [ "$suite" = acceptance ]; then
	scripts/deploy-ceph-csi-operator.sh deploy
	scripts/minikube.sh install-snapshotter
	ROOK_DEPLOY_TIMEOUT=600 KUBECTL_RETRY_DELAY=5 scripts/minikube.sh deploy-rook
	cd e2e
	../e2e.test -test.v -ginkgo.v --ginkgo.label-filter=acceptance --ginkgo.timeout=25m --deploy-timeout=10 \
		--test-rbd=true --test-cephfs=true --test-nfs=true --test-nvmeof=false \
		--deploy-rbd=false --deploy-cephfs=false --operator-deployment --skip-vault=true
	exit
fi

# single-node-k8s.sh (ci/centos)
ROOK_DEPLOY_TIMEOUT=900 scripts/minikube.sh deploy-rook
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
	# mini-e2e-helm.groovy minus its --helm-test flag, which the 3.18 e2e no longer has (#6512).
	scripts/install-helm.sh up
	scripts/install-helm.sh install-cephcsi --namespace "$ns" --deploy-sc --deploy-secret
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
			kubernetes/test/bin/e2e.test -- -storage.testdriver="$PWD/$driver"
	done
	;;
*)
	echo "unknown suite $suite" >&2
	exit 2
	;;
esac
