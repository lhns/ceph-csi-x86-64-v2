# 2. Release each upstream version once; never overwrite a tag

Status: Accepted (recorded after the fact, 2026-10)

## Context

Consumers run this image on storage nodes. A tag whose content changes under them breaks reproducibility and makes
rollbacks guesswork.

## Decision

`release.yml` builds every stable upstream release from v3.18.0 on that has no GitHub release here, each through
the full `ci.yml`. Only when everything passes is `ghcr.io/lhns/ceph-csi-x86-64-v2:<version>` pushed, once. A tag
already in ghcr is never pushed again; it only gets its missing GitHub release ("adopt"), which records the digest,
base images and CI run. Pushes and PRs only test.

## Consequences

- Consumers pin `<version>@<digest>` from the release notes.
- Base-image or harness fixes after a release do not reach that version; they apply to the next upstream release.
- A failed version publishes nothing and is retried the next day.
