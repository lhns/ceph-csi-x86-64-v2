# 3. The x86-64-v2 Ceph image is built with Nix in lhns/ceph-nix, not here

Status: Accepted (2026-10)

## Context

Ceph Umbrella (21.2.0) moved `quay.io/ceph/ceph` to Rocky Linux 10, so it needs x86-64-v3 like ceph-csi did.
Repeating ADR 0001 for Ceph would mean upstream's `container/Containerfile` on CentOS Stream 9, the only EL9 that
Ceph's shaman repos serve. CentOS Stream 9 is EOL on 2027-05-31, and shaman already has no EL9 ceph-iscsi repo, so
that rebuild would need patches from day one and a base change within months.

## Decision

Build Ceph from source with Nix in a separate repo, [lhns/ceph-nix](https://github.com/lhns/ceph-nix), which also
holds the NixOS modules for the Ceph servers and OpenCAS. This repo stays as it is: the ceph-csi rebuild.

## Consequences

- This repo's build, tests and release flow are unchanged.
- ceph-nix runs ceph-csi's acceptance e2e with both images, so the pair is tested together there.
- If ceph-csi is ever built with Nix too, it moves to ceph-nix and this repo is retired (a new ADR there).
