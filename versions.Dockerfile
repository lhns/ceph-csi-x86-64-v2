# Base image pins: build.sh reads them, Dependabot bumps them. Never built.
# The ceph-csi version is not pinned here; release/release.sh picks it.
FROM quay.io/rockylinux/rockylinux:9@sha256:bb5755f96bec05ff26165e779ec843d7167544be9e50770508f307019a6d05c4 AS base
FROM quay.io/rockylinux/rockylinux:9-minimal@sha256:96aef88435673089451d3ca68780d3f68936f19a03b15b685bff54e55b6ef3a5 AS final
