# 1. Rebuild upstream ceph-csi unmodified on an EL9 base

Status: Accepted (recorded after the fact, 2026-10)

## Context

From v3.18.0 upstream ceph-csi builds on Rocky Linux 10. EL10 requires x86-64-v3 (AVX2, FMA, BMI), so the image
dies with `Fatal glibc error: CPU does not support x86-64-v3` on older CPUs such as Ivy Bridge. Ceph Tentacle ships
the same client packages for EL9.

## Decision

Build upstream's tagged source with upstream's own `make image-cephcsi`, changing only the base: `build.env`'s
`BASE_IMAGE`, `FINAL_BASE_IMAGE` and `CEPH_RELEASE_RPM` point at Rocky 9 / 9-minimal and the el9 Ceph repo, pinned
in `versions.Dockerfile`. Patches are allowed only for upstream's e2e harness (`e2e/`), never for the image.

## Consequences

- The image is upstream's code and build; upstream's tests apply unchanged and are run in full.
- `build.sh checkout` fails loudly when upstream changes `build.env` in a way the rewrite does not cover, or when
  an e2e patch neither applies nor is already upstream.
- If Ceph stops shipping EL9 client packages, this approach ends; the alternative would be a source build
  (see ADR 0003 for where that work lives).
