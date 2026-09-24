# Pins only: build.sh reads them, Dependabot bumps them. Never built.
FROM quay.io/cephcsi/cephcsi:v3.18.0 AS ceph-csi
FROM quay.io/rockylinux/rockylinux:9@sha256:8101994123cf3d0a8fee517bee7f39e555c7d92bd2d9eb3303cc988a0eeed00f AS base
FROM quay.io/rockylinux/rockylinux:9-minimal@sha256:e1d0a9f5ed99d52e7faf03afe7ee32e48b231c4dd9586808b3d1aedf894dff04 AS final
