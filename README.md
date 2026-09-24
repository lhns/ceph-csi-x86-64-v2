# ceph-csi-x86-64-v2

Upstream [ceph-csi](https://github.com/ceph/ceph-csi), unmodified, built on an x86-64-**v2** base:
`ghcr.io/lhns/ceph-csi-x86-64-v2:<upstream tag>`.

## Why

From v3.18.0 upstream builds on Rocky Linux 10 (`build.env`: `BASE_IMAGE=quay.io/rockylinux/rockylinux:10`,
final stage `rockylinux:10-minimal`). EL10 requires x86-64-v3 (AVX2, FMA, BMI), so on older CPUs, e.g. Ivy Bridge,
the image dies with `Fatal glibc error: CPU does not support x86-64-v3`.

This repo changes only the base: Rocky Linux 9 / 9-minimal with the EL9 build of the same Ceph release (Tentacle),
set through upstream's `build.env` and the Dockerfile's `FINAL_BASE_IMAGE`. Everything else is upstream's
`make image-cephcsi`. See [`build.sh`](build.sh).

## Tests

[`ci.yml`](.github/workflows/ci.yml) runs upstream's tests against this build:

- upstream's GitHub checks, target for target: `go-test`, `go-test-api`, `go-lint`, `lint-extras`, `codespell`,
  `mod-check`, `link-check`, `tickgit`, `uncommitted-code-check`, the `e2e.test` build, `image-cephcsi` (amd64);
- upstream's CentOS CI e2e jobs (`ci/centos` branch) and its minikube acceptance workflow, on GitHub runners with
  minikube and Rook, via [`test/e2e.sh`](test/e2e.sh): cephfs, rbd, nfs and nvmeof on Kubernetes 1.33–1.35;
  cephfs, rbd and nfs through the operator, cephfs and rbd through the Helm charts; upgrade from
  `CSI_UPGRADE_VERSION`; Kubernetes external-storage;
- [`test/cpu.sh`](test/cpu.sh): the image's binaries and a librados/librbd/libcephfs smoke test under
  `qemu-x86_64 -cpu IvyBridge` and `-cpu Nehalem`. Upstream's v3.18.0 image must fail the same test.

A few specs fail identically with upstream's own image in this harness; `e2e.sh` tolerates exactly those, by name.
[`e2e-upstream-image.yml`](.github/workflows/e2e-upstream-image.yml) runs one e2e job against upstream's image,
to tell a regression in this build from a harness or runner problem.

## Releasing

1. Upstream tags a release.
2. Dependabot bumps the tag in [`versions.Dockerfile`](versions.Dockerfile) (the pins; never built) and opens a PR.
3. CI runs everything above on the PR. Merging reruns it on `main`, then publishes the tested image as
   `ghcr.io/lhns/ceph-csi-x86-64-v2:<tag>`; the digest is in the run summary.
4. Consumers pin that digest.

The Rocky 9 digests are bumped the same way. A rebuild republishes the same tag under a new digest.
