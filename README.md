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

[`ci.yml`](.github/workflows/ci.yml) runs upstream's test suite against this build:

- upstream's GitHub checks: `go-test`, `go-test-api`, `go-lint`, `lint-extras`, `codespell`, `mod-check`, `link-check`,
  `uncommitted-code-check`, `e2e.test` and single-arch builds;
- upstream's CentOS CI e2e jobs and its minikube acceptance workflow, on GitHub runners (minikube + Rook):
  cephfs, rbd, nfs and nvmeof, via manifests, the operator and the Helm charts; upgrade from `CSI_UPGRADE_VERSION`;
  Kubernetes external-storage;
- [`test/cpu.sh`](test/cpu.sh): the image's binaries and a librados/librbd/libcephfs smoke test under
  `qemu-x86_64 -cpu IvyBridge` and `-cpu Nehalem`. Upstream's v3.18.0 image must fail the same test.

A push to `main` publishes the tested image only after all of that passes.

## Updating

[`versions.Dockerfile`](versions.Dockerfile) pins the upstream tag and the base digests. It is never built.
Dependabot opens a PR when upstream publishes a release; CI runs; merging publishes
`ghcr.io/lhns/ceph-csi-x86-64-v2:<tag>`. Consumers pin the digest from the run summary.
