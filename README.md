# Slim, Secure Containers with Hummingbird and UBI Micro: A Hands-On Workshop

Author: François Charette

Repository: <https://github.com/fc7/hummingbird-demo>

This hands-on workshop focuses on building and maintaining minimal container
images with a special concern for security, using images from **Project Hummingbird**
and **Red Hat UBI**, especially the **UBI micro** variant for the final runtime images.

---

## Overview

This workshop consists of four different labs. Use this as a pacing guide; adjust for your audience (pure developers vs platform/security).

| Block | Time (typ.) | Intent |
|--------|-------------|--------|
| **Intro** | 10–15 min | Why “small” and “fewer CVEs” are related but not identical; introduce attack surface and scanner signal vs noise. |
| **UBI vs Hummingbird** | 15–20 min | UBI standard → minimal → **micro** (distroless-style); Hummingbird as an opinionated, curated stack. Tie to [RHEL 10: types of container images](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html-single/building_running_and_managing_containers/index). |
| **Lab 1 — Trust but verify** | 15 min | Run Hummingbird `curl`, scan with Grype, peek inside layers with Skopeo. |
| **Lab 2 — Layers + customization** | 20 min | `httpd`, custom image, scan comparison. |
| **Lab 3 — Multi-stage + SBOM** | 30 min | Rust example: builder vs runtime, SBOM, Grype on binary. |
| **Lab 4 — Python: getting rid of builder cruft** | 45-60 min | Single-stage builder image vs `installroot` minimal runtime; highlights why builder ≠ runtime. Hummingbird and UBI Micro. Alternative with nested buildah |
| **Wrap-up** | 10 min | When to choose Hummingbird vs UBI; additional resources. |

**Environment:** The [RHEL 10 interactive lab](https://www.redhat.com/en/interactive-labs/enterprise-linux#operate)
from Red Hat works well (`podman`, `buildah` and `skopeo` are preinstalled). The session is time-limited but should be sufficient. A recent Fedora or RHEL 10 environment with Podman and is also fine. RHEL 9 may also work but is untested.

NB: Pulling from `registry.redhat.io` needs [registry authentication](https://access.redhat.com/RegistryAuthentication) for UBI-based
builds, but partipants can also use the unauthenticated option with `registry.access.redhat.com`
(which is what the Containerfiles in the repo use).

---

## Introduction

Containers make deployments predictable. They also make every unused binary and library in the image part of your security posture.
Scanners dutifully report CVEs against that full inventory — sometimes far more than your app will ever touch.

Security is a continuous, company-wide comprehensive process - not a simple metric.

This workshop is therefore not about chasing a mythical “zero CVEs” goal for its own sake. It is about:

1. Deliberately shrinking what you ship (multi-stage builds, minimal runtimes, curated bases).
2. Choosing bases that match your threat model and compliance story (redistributable UBI vs hardened Hummingbird images).
3. Knowing how to add dependencies without dragging a full builder toolchain into production using various image build patterns.
4. Knowing when to use UBI Micro vs Hummingbird for production use cases.

We will run tools, compare scan results, and reflect on the implications for running containerized workloads in production.

---

## UBI vs Hummingbird

### UBI images

Red Hat’s [Building, running, and managing containers (RHEL 10)](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html-single/building_running_and_managing_containers/index) describes a family of images:

- **UBI standard (`ubi`)** — full `dnf`, rich utilities, good when the image *is* the dev environment or needs broad RPM flexibility.
- **UBI init** — systemd-oriented; useful when the container behaves like a miniature VM with services.
- **UBI minimal** — smaller footprint, **`microdnf`** for modules and targeted installs.
- **UBI micro** — **no package manager** in the final image. Dependencies are not meant to be installed *inside* that runtime; you assemble the root filesystem elsewhere. The documentation explicitly ties this to **minimizing attack surface** and describes this style as a **distroless**-like image: your runtime is “the OS bits you need,” not “a general-purpose Linux distro you can keep patching interactively.”

**Workshop mantra:** *You almost never want `dnf` or `microdnf` in the image that faces the internet.* You want them in a build stage to construct `/rootfs` (or equivalent), then copy only that into a `scratch`, `ubi-micro` or Hummingbird runtime base image.

---

### Project Hummingbird

In late 2025, Red Hat [announced](http://redhat.com/en/about/press-releases/red-hat-introduces-project-hummingbird-zero-cve-strategies) project [Hummingbird](https://hummingbird-project.io/).

> Project Hummingbird builds a collection of minimal, hardened, and secure container images with a significantly reduced attack surface. This strong focus on security combined with a highly automated update workflow aims to minimize CVE counts, targeting near-zero vulnerabilities. All images support amd64 and arm64 architectures.

More details about the project can be found [on this page](https://hummingbird-project.io/docs/using/).

Each set of Hummingbird images are shipped with different [image variants](https://hummingbird-project.io/docs/using/#understanding-image-variants), the default variant (`:latest`) and the builder variant (`:latest-builder)`). In addition, many images are also available in different version (`:<version>` and `:<version>-builder`).

### What are the major differences between Project Hummingbird and RHEL/UBI?

| Feature | Universal Base Image (UBI) | Hummingbird Images |
| :---- | :---- | :---- |
| **Primary Focus** | Highly flexible & redistributable images with a RHEL userspace | Purpose built, minimal attack surface, “bleeding edge” security posture |
| **Use Case** | Enterprise applications that require the stability and security of RHEL | Hardened components built to accelerate developers & reduce their security burden |
| **CVE** | RHEL CVE policy | Near-zero CVEs with 7 day SLA for critical |
| **Update Cadence** | Standard RHEL errata | Continuous builds |
| **Image Size** | Standard RPM install | Distroless builds from a minimal base |
| **Life Cycle** | Predictable 10y life cycle | Mirrors Upstream |
| **Support** | Fully support when run on RHEL/OCP | Full support included with RHEL/OCP |
| **Redistribution** | Yes | Yes |

---

In this lab you will use:

- UBI images from `registry.access.redhat.com/ubi10`
- Published Hummingbird images from the registry `quay.io/hummingbird/…`
- CI helpers from `quay.io/hummingbird-ci/gitlab-ci` (Grype wrapper)
- Local `Containerfile` examples under `httpd-demo-app/`, `rust-example/`, and `python-example/`

## Lab 1 — “Hello, minimal curl”

**Story:** Pull a tiny, focused utility image and contrast *size / trust* with *scanner results*.

Use the Hummingbird `curl` image similarly to the familiar `curlimages/curl`:

```sh
podman run quay.io/hummingbird/curl -s 'https://api.ipify.org?format=json' | jq
```

**Grype** (via the Hummingbird CI image; first run populates a vulnerability DB cache):

```sh
podman run --volume vuln-db:/tmp/.cache quay.io/hummingbird-ci/gitlab-ci \
  grype-hummingbird.sh quay.io/hummingbird/curl:latest
```

You may see output similar to:

```none
No vulnerabilities found
```

**Discussion beat:** “No findings” is a function of database timing, what Grype knows, and what is *in* the image—not a guarantee of invulnerability. Use scans as **inputs**, not **totems**.

### Optional: Skopeo image inspection

Inspect the artifact without running any container:

```sh
pushd "$(mktemp -d)"
skopeo copy --dest-decompress --all docker://quay.io/hummingbird/curl:latest dir:.
file *
# One layer per arch is typical; inspect with tar -tf on the layer blob.
popd
```

List tags with skopeo:

```sh
skopeo list-tags docker://quay.io/hummingbird/curl > curl-tags.txt
wc -l curl-tags.txt
grep -v 'sha256-' curl-tags.txt
rm curl-tags.txt
```

---

## Lab 2 — Apache httpd: using default image and adding customized layer

**Story:** A production service is rarely “vanilla.” The security question
becomes: what did we add, and on what foundation?

Run the basic Hummingbird `httpd` image:

```sh
podman run --rm -d --name httpd -p 8080:8080 quay.io/hummingbird/httpd
curl -s localhost:8080
```

Or use a user-defined network and reach httpd from a Hummingbird curl sidecar:

```sh
podman network create my-network
podman run -d --name httpd --network my-network -p 8080:8080 \
  quay.io/hummingbird/httpd:latest
podman run --network my-network quay.io/hummingbird/curl \
  -s http://httpd:8080
```

### Customized httpd with your application layer

In `httpd-demo-app/`, a short `Containerfile` adds static assets on top of the Hummingbird httpd base image:

```dockerfile
FROM quay.io/hummingbird/httpd:latest

COPY index.html /usr/local/apache2/htdocs/
COPY style.css /usr/local/apache2/htdocs/css/
```

Build and run:

```sh
cd httpd-demo-app
podman build -t custom-httpd .
podman run -d --rm -p 8081:8080 custom-httpd
```

Open <http://localhost:8081> in your browser.

**Scan note:** The `README` reminds you that Grype against images pulled from a
registry is straightforward; for purely local tags, push to a registry or adapt
the workflow.

```sh
podman run --volume vuln-db:/tmp/.cache quay.io/hummingbird-ci/gitlab-ci \
  grype-hummingbird.sh quay.io/hummingbird/httpd:latest
```

Sample output may list items such as `coreutils-single` with medium
severity—**facilitator:** talk about EPSS, severity, and whether the workload
*uses* those binaries.

---

## Lab 3 — Rust: multi-stage build with SBOM

**Story:** Compiled languages are the textbook case for **builder ≠ runtime**.
You want compilers and dev tooling (such as cargo for Rust) at build time;
you do not want them in production.

Inspect `rust-example/Containerfile`: builder stage (`*-builder`), tiny runtime
(`core-runtime`), SBOM copied beside the binary.

```sh
RUST_IMG=rust-example
cd rust-example
podman build -t "${RUST_IMG}" .
podman create --name hello -p 8088:8080 "${RUST_IMG}"
# While building: walk through the Containerfile line by line with the group.
podman cp hello:/cargo-sbom.json cargo-sbom.json
podman run --rm --volume vuln-db:/tmp/.cache quay.io/hummingbird-ci/gitlab-ci \
  grype-hummingbird.sh "${RUST_IMG}"
podman run -it --rm --volume vuln-db:/tmp/.cache \
  --volume ./cargo-sbom.json:/cargo-sbom.json:z \
  --entrypoint=/bin/sh quay.io/hummingbird-ci/gitlab-ci
# Inside that shell:   grype /cargo-sbom.json
rm -f cargo-sbom.json
podman start hello
curl -s localhost:8088
curl -s localhost:8088/hey
```

**Bonus path:** Compare Hummingbird and UBI approaches using the
[actix-qrcode](https://github.com/fc7/actix-qrcode) project’s
`Containerfile.hummingbird` vs a UBI-based `Containerfile`—same app, different
security/compliance tradeoffs.

---

## Lab 4 — Python with native dependencies

### 4.1 - Single stage build with Hummingbird Python builder image

**Story:** Python looks easy until you need native wheels and system RPMs. The
first `Containerfile` in `python-example/` stays on `python:latest-builder`
for runtime, which is convenient but leaves a large attack surface and makes security scans very noisy.

```sh
cd python-example
PYTHON_IMG=quay.io/rh_ee_fcharett/hummingbird-python-demo:latest
podman build -t "${PYTHON_IMG}" .
podman run --rm --name roots -d -p 8089:8080 "${PYTHON_IMG}"
curl -s -X POST http://localhost:8089/roots \
  -H "Content-Type: application/json" \
  -d '{"coefficients": [1, 7, -1]}'
```

Scan the resulting image: you may see multiple vulnerabilities associated with **libxml2**, **gnutls**, etc.
(the exact listing will change with time and increase as the image ages).

### 4.2 - Multi-stage build: escaping the builder overhead thanks to `--installroot`

Now build the intentionally minimal variant that uses the Hummingbird runtime variant in the final stage:

```sh
PYTHON_IMG_MIN=quay.io/rh_ee_fcharett/hummingbird-python-demo:latest-minimal
podman build -t "${PYTHON_IMG_MIN}" -f Containerfile.2 .
podman run --rm --name roots2 -d -p 8090:8080 "${PYTHON_IMG_MIN}"
```

Repeat the same API test as above using curl on port 8090 to confirm that the container is working identically despite being much smaller.

Then re-scan `${PYTHON_IMG_MIN}`. As we have far fewer packages in the image, the scan yields far fewer findings.

### 4.3 — Same app on **UBI micro**

The same can be done with UBI micro instead of Hummingbird: see `Containerfile.3`.

**Story:** The final image resulting from `Containerfile.2` is based on
Hummingbird’s curated Python runtime image. Now we shall produce an equivalent
image based on `ubi10/ubi-micro`. Because we still need `dnf` and `pip`
somewhere to install the required dependencies, we install them with in a
temporary rootfs that will be copied to our final image.

### 4.4 — Variant of the above with nested `buildah`

The procedure amounts to:

1. Creating and mounting a `ubi-micro` working container;
2. installing system dependencies with `dnf --installroot`
   and Python dependencies with `pip3 --prefix`,
   both pointing to the mount point of that working container;
3. passing that filesystem layer to the next building stage,
   which is then copied over an empty `SCRATCH` base image.

Look at `python-example/Containerfile.4` for the details.

**Caveat** nested Buildah needs extra capabilities and privileges:

```sh
PYTHON_IMG=quay.io/rh_ee_fcharett/ubi-micro-python-demo:latest-scratch
podman build --security-opt label=disable \
  --cap-add=all --device=/dev/fuse \
  -f Containerfile.4 -t ${PYTHON_IMG} .
```

After confirming that the build is successful, run the image as before and make the API
call to confirm it is working in the same way as the previous two variants.

Participants can also run **Grype** on the resulting image in the same way they scanned the
Hummingbird images (after pushing to a registry if running the syft/grype wrapper inside a container).

### 4.5 (optional) — Equivalent procedure to 4.4 with buildah running directly on a RHEL host

If the nested builder container is causing issues or is not possible in a given
CI environment, you can achieve the same directly on a RHEL system using the
script `python-example/build-ubi-micro-buildah.sh`. It performs the same steps
on the host, closely matching the RHEL 10 documentation for UBI micro (see **References** below).

---

## Wrap-up

**Compare and contrast debrief:**

| Axis | Hummingbird runtime / examples in this repo | UBI micro final stage |
|------|-----------------------------------------------|------------------------|
| **Governance** | Curated stacks, project automation | Your responsibility; fully redistributable UBI |
| **Base size & contents** | Opinionated minimal sets | Smallest UBI; you supply the rootfs |
| **Adding Dependencies** | Follow variant docs | `installroot`, multi-stage `COPY`, or nested Buildah / host Buildah |
| **Learning curve** | Lower if you fit the catalog | More control, more Containerfile craft |

---

## References

- [Hummingbird — Using the images](https://hummingbird-project.io/docs/using/)
- [Hummingbird on Quay](https://quay.io/repository/hummingbird)
- [Using UBI micro](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html-single/building_running_and_managing_containers/index#using-the-ubi-micro-images)
- [Syft](https://github.com/anchore/syft) — SBOM generation
- [Grype](https://github.com/anchore/grype) — vulnerability scanning
- [Skopeo](https://github.com/containers/skopeo) — copy/inspect without daemon
- [Lower your container image size and improve compliance](https://www.opensourcerers.org/2025/01/27/lower-your-container-image-size-and-improve-compliance/) — context for multi-stage minimal Python
