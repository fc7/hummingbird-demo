#!/bin/sh

REGISTRY=quay.io/rh_ee_fcharett
HTTPD_IMG=hummingbird-httpd-demo
RUST_IMG=hummingbird-rust-demo
PYTHON_IMG=hummingbird-python-demo

cd httpd-demo-app
echo "Build $HTTPD_IMG"
podman manifest create $REGISTRY/$HTTPD_IMG
podman build --platform linux/amd64,linux/arm64 --manifest $REGISTRY/$HTTPD_IMG . && \
    podman manifest push $REGISTRY/$HTTPD_IMG

cd ../rust-example
echo "Build $RUST_IMG"
podman manifest create $REGISTRY/$RUST_IMG
podman build --platform linux/amd64,linux/arm64 --manifest $REGISTRY/$RUST_IMG . && \
    podman manifest push $REGISTRY/$RUST_IMG

cd ../python-example
echo "Build $PYTHON_IMG"
podman manifest create $REGISTRY/$PYTHON_IMG
podman build --platform linux/amd64,linux/arm64 --manifest $REGISTRY/$PYTHON_IMG . && \
    podman manifest push $REGISTRY/$PYTHON_IMG

echo "Build $PYTHON_IMG:latest-minimal"
podman manifest create $REGISTRY/$PYTHON_IMG:latest-minimal
podman build --platform linux/amd64,linux/arm64 --manifest $REGISTRY/$PYTHON_IMG:latest-minimal -f Containerfile.2 . && \
    podman manifest push $REGISTRY/$PYTHON_IMG:latest-minimal

cd ..
echo "--- Finished ---"