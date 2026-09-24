# Pins only: build.sh reads them, Dependabot bumps them. Never built.
FROM quay.io/cephcsi/cephcsi:v3.17.1 AS ceph-csi
FROM quay.io/rockylinux/rockylinux:10@sha256:827d37bc128288ccf160ee318bb3cb92d591164cb217e92f8bc61e3982ae1834 AS base
FROM quay.io/rockylinux/rockylinux:10-minimal@sha256:bc5c1e7a2ec7f4bcef1e51c7f0ebb2d43f05409e0108cdd34f693921d0604360 AS final
