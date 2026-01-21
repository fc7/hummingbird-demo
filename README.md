# Hummingbird Demo and Lab

François Charette

January 22, 2026

---

## Introduction

Red Hat recently [announced](http://redhat.com/en/about/press-releases/red-hat-introduces-project-hummingbird-zero-cve-strategies) project [Hummingbird](https://hummingbird-project.io/).

> Project Hummingbird builds a collection of minimal, hardened, and secure container images with a significantly reduced attack surface. This strong focus on security combined with a highly automated update workflow aims to minimize CVE counts, targeting near-zero vulnerabilities. All images support amd64 and arm64 architectures.

More details about the project can be found [on this page](https://hummingbird-project.io/docs/using/).

### Useful links

* <https://hummingbird-project.io/docs/using/>
* <https://quay.io/repository/hummingbird>
* <http://redhat.com/en/about/press-releases/red-hat-introduces-project-hummingbird-zero-cve-strategies>
* [Syft](https://github.com/anchore/syft) SBOM Generator
* [Grype](https://github.com/anchore/grype) Vulnerability scanner

## DEMO

Each participant can use the RHEL 10 open lab environment under <https://www.redhat.com/en/interactive-labs/enterprise-linux#operate> to reproduce the demo (requires a RH account).

Podman and other tools are already installed.

The environment stops and is deleted after 60 minutes.

### 1. Use curl image

The Hummingbird curl image is similar to [curlimages/curl](https://hub.docker.com/r/curlimages/curl) from Docker Hub.

```sh
podman run quay.io/hummingbird/curl -s https://api.ipify.org?format=json | jq
```

More use cases: <https://quay.io/repository/hummingbird/curl>

Now let's use the grype tool included in the hummingbird CI image to scan the above curl image for eventual vulnerabilities:

```sh
podman run --volume vuln-db:/tmp/.cache quay.io/hummingbird-ci/gitlab-ci grype-hummingbird.sh quay.io/hummingbird/curl:latest
```

Expected output:

```none
Downloading CPE dictionary...
Downloading supplementary CPE mappings...
Processing supplementary CPE mappings...
Building CPE vendor lookup map...
No vulnerabilities found
```

Let's now examine the content of the `curl` image with `skopeo`:

```sh
pushd `mktemp -d`
skopeo copy --dest-decompress --all docker://quay.io/hummingbird/curl:latest dir:.
file *       # NB: there is one layer for amd64 and an another one for arm64
tar -tf ... | grep '^usr/bin' 
rm *
popd
```

Tags available for an image:

```sh
skopeo list-tags docker://quay.io/hummingbird/curl > curl-tags.txt
wc -l curl-tags.txt
grep -v 'sha256-' curl-tags.txt
rm curl-tags.txt
```

More details on the three variants: <https://hummingbird-project.io/docs/using/#understanding-image-variants>

### 2. Using the Apache httpd image

This image provides the httpd Apache server.

First, let's run the image without any customization.

```sh
$ podman run --rm -d --name httpd -p8080:8080 quay.io/hummingbird/httpd
$ curl localhost:8080
<html>
<head>
<title>It works! Apache httpd</title>
</head>
<body>
<p>It works!</p>
</body>
</html>
```

Alternatively run curl in a container within the same network:

```sh
podman network create my-network
podman run -d --name httpd-server --network my-network -p 8080:8080 quay.io/hummingbird/httpd:latest
podman run --network my-network quay.io/hummingbird/curl -s httpd-server:8080
```

#### Custom httpd image

Now let's build a custom image based on httpd.

Go to the [httpd-demo-app folder](./httpd-demo-app/) which contains the following `Containerfile` together with a simple webpage (html + css):

```dockerfile
FROM quay.io/hummingbird/httpd:latest

COPY index.html /usr/local/apache2/htdocs/
COPY style.css /usr/local/apache2/htdocs/css/
```

Now build the above image:

```sh
podman build -t custom-httpd .
```

The same image can also be found under `quay.io/rh_ee_fcharett/hummingbird-httpd-demo:latest`.

Then run it with

```sh
podman run -d --rm -p 8081:8080 custom-httpd # or use the above image
```

Point your browser to `localhost:8081`.

#### Vulnerability scan

```sh
$ podman run --volume vuln-db:/tmp/.cache quay.io/hummingbird-ci/gitlab-ci grype-hummingbird.sh quay.io/hummingbird/httpd:latest
NAME              INSTALLED  TYPE    VULNERABILITY  SEVERITY  EPSS           RISK
coreutils-single  9.9        binary  CVE-2016-2781  Medium    < 0.1% (24th)  < 0.1
```

Now it might be useful for auditing purposes to have a closer inspection of the content of an image.
We can do this with skopeo.

```sh
pushd `mktemp -d`
skopeo copy --dest-decompress --all docker://quay.io/hummingbird/curl:latest dir:.
file *       # NB: there is one layer for amd64 and an another one for arm64
tar -tf ... | grep '^usr/bin' 
rm *
popd
```

### 3. Rust app with multi-stage build

Have a look at the [Containerfile](./rust-example/Containerfile).

```sh
RUST_IMG=rust-example # or use quay.io/rh_ee_fcharett/hummingbird-rust-demo
cd rust-example
podman build -t ${RUST_IMG} .
podman create --name hello -p 8088:8080 ${RUST_IMG}
podman cp hello:/cargo-sbom.json cargo-sbom.json
podman run --rm --volume vuln-db:/tmp/.cache quay.io/hummingbird-ci/gitlab-ci grype-hummingbird.sh ${RUST_IMG}
podman run -it --rm --volume vuln-db:/tmp/.cache --volume ./cargo-sbom.json:/cargo-sbom.json:z --entrypoint=/bin/sh quay.io/hummingbird-ci/gitlab-ci
sh-5.3$ cat /cargo-sbom.json | grype # << executed from inside the container
rm cargo-sbom.json
podman start hello
curl localhost:8088
curl localhost:8088/hey
```

We have included a SBOM in our final container image to enable vulnerability "scanning" of our compiled binary.

**Bonus**: Build and run my [qrcode Rust app](https://github.com/fc7/actix-qrcode) on Github using the provided `Containerfile.hummingbird`. Compare it to the UBI-based `Containerfile`.

### 4. Python example

```sh
cd python-example
PYTHON_IMG=quay.io/rh_ee_fcharett/hummingbird-python-demo:latest
podman build -t ${PYTHON_IMG} .
podman run --rm --name roots -d -p 8089:8080 ${PYTHON_IMG}
curl -X POST http://localhost:8089/roots \
     -H "Content-Type: application/json" \
     -d '{"coefficients": [1, 7, -1]}'
# {"polynomial_coefficients":[1,7,-2],"roots":["-7.274917217635375","0.27491721763537486"]}
```

Vulnerability scan of the Python image we just used:

```sh
$ podman run --volume vuln-db:/tmp/.cache quay.io/hummingbird-ci/gitlab-ci grype-hummingbird.sh ${PYTHON_IMG}  
NAME              INSTALLED  FIXED IN         TYPE    VULNERABILITY   SEVERITY  EPSS           RISK
libxml2           2.12.10                     binary  CVE-2025-6021   High      0.6% (69th)    0.5
libxml2           2.12.10    2.13.9           binary  CVE-2025-49796  Critical  0.5% (66th)    0.5
libxml2           2.12.10    2.13.9           binary  CVE-2025-49794  Critical  0.3% (52nd)    0.3
libxml2           2.12.10    2.13.9           binary  CVE-2025-49795  High      0.2% (37th)    0.1
gnutls            3.8.11                      binary  CVE-2025-32990  High      0.2% (36th)    0.1
gnutls            3.8.11                      binary  CVE-2025-32989  Medium    < 0.1% (25th)  < 0.1
libxml2           2.12.10    *2.13.8, 2.14.2  binary  CVE-2025-32414  High      < 0.1% (18th)  < 0.1
coreutils-single  9.9                         binary  CVE-2016-2781   Medium    < 0.1% (24th)  < 0.1
libxml2           2.12.10    *2.13.8, 2.14.2  binary  CVE-2025-32415  High      < 0.1% (8th)   < 0.1
libxml2           2.12.10                     binary  CVE-2025-6170   Low       < 0.1% (3rd)   < 0.1
```

Hmm ... because we had to install some dependencies, we had to use the builder image, but this has some vulnerabilities!

#### Multi-stage minimal version

Now let's try a more complex multi-stage build to solve this, to really have the smallest possible runtime image for our Python app in the end.

NB: This is inspired by how Hummingbird works internally!
See also this interesting [blog post](https://www.opensourcerers.org/2025/01/27/lower-your-container-image-size-and-improve-compliance/) for more details.

```sh
PYTHON_IMG_MIN=quay.io/rh_ee_fcharett/hummingbird-python-demo:latest-minimal
podman build -t ${PYTHON_IMG_MIN} -f Containerfile.2 .
podman run --rm --name roots2 -d -p 8090:8080 ${PYTHON_IMG_MIN}
# same output
```

Let's scan the second image:

```sh
$ podman run --volume vuln-db:/tmp/.cache quay.io/hummingbird-ci/gitlab-ci grype-hummingbird.sh ${PYTHON_IMG_MIN}
NAME              INSTALLED  TYPE    VULNERABILITY  SEVERITY  EPSS           RISK
coreutils         9.9        binary  CVE-2016-2781  Medium    < 0.1% (24th)  < 0.1
coreutils-common  9.9        binary  CVE-2016-2781  Medium    < 0.1% (24th)  < 0.1
```

This looks much better now!

NB: There is a plan to make the above multi-stage build more user-friendly: <https://issues.redhat.com/browse/HUM-201>
