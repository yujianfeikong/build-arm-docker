# ARM64 Image Builder

`ARM64 Image Builder` is a GitHub Actions based build template for producing downloadable `linux/arm64` Docker images from source projects that require custom build steps and runtime dependencies.

The current repository is maintained for GitHub Actions execution only. The primary example builds `kkFileView 5.0.0` on an ARM64 runner, exports the resulting image as a `.tar` archive, and publishes it as a workflow artifact.

## Overview

This repository provides the following components:

- [build-and-run-arm64.sh](/Users/bo/Documents/build-arm-docker/build-and-run-arm64.sh): build entry script invoked by GitHub Actions
- [Dockerfile.arm64](/Users/bo/Documents/build-arm-docker/Dockerfile.arm64): multi-stage ARM64 image template
- [docker-entrypoint.sh](/Users/bo/Documents/build-arm-docker/docker-entrypoint.sh): container entrypoint
- [examples/kkfileview-5.0.0.env](/Users/bo/Documents/build-arm-docker/examples/kkfileview-5.0.0.env): reference configuration for `kkFileView 5.0.0`
- [.github/workflows/build-kkfileview-arm64.yml](/Users/bo/Documents/build-arm-docker/.github/workflows/build-kkfileview-arm64.yml): workflow definition

## Workflow

The workflow is designed around GitHub-hosted ARM64 runners and follows this sequence:

1. Check out the repository.
2. Execute [build-and-run-arm64.sh](/Users/bo/Documents/build-arm-docker/build-and-run-arm64.sh) with [examples/kkfileview-5.0.0.env](/Users/bo/Documents/build-arm-docker/examples/kkfileview-5.0.0.env).
3. Build the image natively on the ARM64 runner and export it to `kkfileview-arm64-v5.0.0.tar.gz`.
4. Upload the tarball as a GitHub Actions artifact.

The reference workflow artifact name is `kkfileview-arm64-v5.0.0-image-tar`.

## Usage

Trigger the workflow from the GitHub Actions page:

1. Open the repository in GitHub.
2. Navigate to `Actions`.
3. Select `build-kkfileview-arm64`.
4. Run the workflow manually.

After the workflow completes:

1. Open the corresponding workflow run.
2. Locate the `Artifacts` section at the bottom of the page.
3. Download `kkfileview-arm64-v5.0.0-image-tar`.
4. Extract the archive to obtain `kkfileview-arm64-v5.0.0.tar.gz`.

Load the image on an ARM64 Docker host:

```bash
gzip -dc kkfileview-arm64-v5.0.0.tar.gz | docker load
```

Start the container:

```bash
docker run -d \
  --name kkfileview-arm64 \
  --platform linux/arm64 \
  -p 8012:8012 \
  -e KK_TRUST_HOST='*' \
  kkfileview-arm64:v5.0.0
```

## Configuration

The example configuration file [examples/kkfileview-5.0.0.env](/Users/bo/Documents/build-arm-docker/examples/kkfileview-5.0.0.env) defines the upstream source, build command, runtime packages, startup command, image name, and exported ports.

The reference `kkFileView` config is tuned for a smaller runtime image:

- use `eclipse-temurin:21-jre` instead of the heavier `jammy`-pinned runtime base
- install only the LibreOffice components needed for common document conversions
- use `fonts-wqy-zenhei` as a lighter Chinese font fallback
- remove LibreOffice gallery/template assets and package docs after install

The workflow currently sets the following GitHub Actions specific parameters:

- `IMAGE_TAR_PATH`: export location for `docker save`, with optional gzip compression when the path ends in `.gz`
- `LOCAL_PROGRESS=plain`: provides stable workflow logs

## Implementation Notes

This repository currently retains a general-purpose build script, but the documented and supported operating mode is GitHub Actions only.

The workflow has been optimized for the current execution model:

- build directly on a native ARM64 Docker host
- export a downloadable image tarball as the canonical build output

## Requirements

- GitHub Actions with access to ARM64 runners
- Docker-compatible ARM64 host for loading and running the exported image
- Sufficient disk space for build layers, runtime dependencies, and the exported image tarball

## Notes

- `kkFileView 5.0.0` requires `JDK 21+` according to the upstream project requirements.
- The generated artifact is intended for manual download and `docker load`; the current workflow does not push images to a container registry.
- If a registry-based distribution model is needed later, the workflow can be extended with an additional publish step without changing the build layout.
