#!/bin/sh

REGISTRY=quay.io/rh_ee_fcharett
HTTPD_IMG=hummingbird-httpd-demo
RUST_IMG=hummingbird-rust-demo
PYTHON_IMG=hummingbird-python-demo
PYTHON_IMG_UBI=ubi-micro-python-demo

# cd httpd-demo-app
# echo "Build $HTTPD_IMG:latest"
# podman manifest create $REGISTRY/$HTTPD_IMG
# podman build --platform linux/amd64,linux/arm64 --manifest $REGISTRY/$HTTPD_IMG . && \
#     podman manifest push $REGISTRY/$HTTPD_IMG

cd ./rust-example
echo "Build $RUST_IMG:latest"
podman manifest create $REGISTRY/$RUST_IMG
podman build --platform linux/amd64,linux/arm64 --manifest $REGISTRY/$RUST_IMG . && \
    podman manifest push $REGISTRY/$RUST_IMG

# cd ../python-example
# echo "Build $PYTHON_IMG:latest"
# podman manifest create $REGISTRY/$PYTHON_IMG
# podman build --platform linux/amd64,linux/arm64 --manifest $REGISTRY/$PYTHON_IMG . && \
#     podman manifest push $REGISTRY/$PYTHON_IMG

# echo "Build $PYTHON_IMG:latest-minimal"
# podman manifest create $REGISTRY/$PYTHON_IMG:latest-minimal
# podman build --platform linux/amd64,linux/arm64 --manifest $REGISTRY/$PYTHON_IMG:latest-minimal -f Containerfile.2 . && \
#     podman manifest push $REGISTRY/$PYTHON_IMG:latest-minimal

# echo "Build $PYTHON_IMG_UBI:latest"
# podman manifest create $REGISTRY/$PYTHON_IMG_UBI:latest
# podman build --platform linux/amd64,linux/arm64 --manifest $REGISTRY/$PYTHON_IMG_UBI:latest -f Containerfile.3 . && \
#     podman manifest push $REGISTRY/$PYTHON_IMG_UBI:latest

# echo "Build $PYTHON_IMG_UBI:latest-scratch"
# podman manifest create $REGISTRY/$PYTHON_IMG_UBI:latest-scratch
# podman build --security-opt label=disable --cap-add=all --device=/dev/fuse \
#     --platform linux/amd64,linux/arm64 --manifest $REGISTRY/$PYTHON_IMG_UBI:latest-scratch -f Containerfile.4 . && \
#     podman manifest push $REGISTRY/$PYTHON_IMG_UBI:latest-scratch
# cd ..
echo "--- Finished ---"