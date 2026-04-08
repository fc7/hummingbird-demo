#!/usr/bin/env bash
# 
# This script builds the same Python container image based on UBI micro directly on a RHEL host, using Buildah + dnf --installroot
# For context, see https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html-single/building_running_and_managing_containers/index#using-the-ubi-micro-images
#
# This is mainly for learning purposes. 
# The nested approach inside a container should generally be preferred.
# 
# Prerequisites on the host: buildah, dnf, python3, python3-pip
#
# Usage:
#   ./build-ubi-micro-buildah.sh [image-name]
# Example:
#   ./build-ubi-micro-buildah.sh localhost/python-example-ubi-micro:latest

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${1:-localhost/python-example-ubi-micro:latest}"

ctr=""
cleanup() {
  [[ -n "${ctr}" ]] || return 0
  buildah unmount "${ctr}" 2>/dev/null || true
  buildah rm "${ctr}" 2>/dev/null || true
}
trap cleanup ERR

ctr="$(buildah from registry.access.redhat.com/ubi10/ubi-micro:latest)"
mnt="$(buildah mount "$ctr")"

dnf install -y --installroot="${mnt}" --releasever=10 \
  --setopt=install_weak_deps=0 --nodocs \
  libstdc++ \
  libgcc \
  python3
dnf clean all --installroot="${mnt}"

pip3 install --no-cache-dir --root "${mnt}" -r "${SCRIPT_DIR}/requirements.txt"

install -d "${mnt}/app"
install -m 0644 "${SCRIPT_DIR}/app.py" "${mnt}/app/app.py"

if ! grep -q '^appuser:' "${mnt}/etc/passwd" 2>/dev/null; then
  printf '%s\n' 'appuser:x:1001:0:Application user:/app:/sbin/nologin' >> "${mnt}/etc/passwd"
fi

buildah config \
  --workingdir /app \
  --user 1001 \
  --port 8080/tcp \
  --cmd '["python3","./app.py"]' \
  "$ctr"

buildah commit "$ctr" "$IMAGE_NAME"
buildah rm "$ctr"
ctr=""
trap - ERR

echo "Built ${IMAGE_NAME}"
echo "Try:  podman run --rm -d -p 8091:8080 ${IMAGE_NAME}"
