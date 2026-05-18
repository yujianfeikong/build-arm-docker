#!/usr/bin/env bash
set -euo pipefail

MODE="${MODE:-local-x86}"
ACTION="${ACTION:-build}"
ENV_FILE="${ENV_FILE:-}"
BUILDER_FORCE_RECREATE="${BUILDER_FORCE_RECREATE:-0}"
PLATFORM="${PLATFORM:-linux/arm64}"
IMAGE_NAME="${IMAGE_NAME:-custom-arm64:local}"
IMAGE_TAR_PATH="${IMAGE_TAR_PATH:-}"
CONTAINER_NAME="${CONTAINER_NAME:-custom-arm64}"
DOCKERFILE="${DOCKERFILE:-Dockerfile.arm64}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${WORK_DIR:-$SCRIPT_DIR/.build-work}"

SOURCE_TYPE="${SOURCE_TYPE:-git}"
GIT_REPO="${GIT_REPO:-}"
GIT_REF="${GIT_REF:-main}"
LOCAL_SOURCE_DIR="${LOCAL_SOURCE_DIR:-}"
SOURCE_SUBDIR="${SOURCE_SUBDIR:-.}"

BUILDER_IMAGE="${BUILDER_IMAGE:-maven:3.9.9-eclipse-temurin-21}"
BUILDER_APT_PACKAGES="${BUILDER_APT_PACKAGES:-git ca-certificates}"
BUILDER_SETUP_CMD="${BUILDER_SETUP_CMD:-:}"
BUILD_CMD="${BUILD_CMD:-true}"

ARTIFACT_PATH="${ARTIFACT_PATH:-}"
ARTIFACT_MODE="${ARTIFACT_MODE:-dir}"
RUNTIME_IMAGE="${RUNTIME_IMAGE:-eclipse-temurin:21-jre-jammy}"
RUNTIME_APT_PACKAGES="${RUNTIME_APT_PACKAGES:-ca-certificates curl}"
RUNTIME_SETUP_CMD="${RUNTIME_SETUP_CMD:-:}"
APP_DEST="${APP_DEST:-/opt/app}"
EXPOSE_PORTS="${EXPOSE_PORTS:-8012}"
START_COMMAND="${START_COMMAND:-}"
CONTAINER_PORT="${CONTAINER_PORT:-8012}"
HOST_PORT="${HOST_PORT:-8012}"
RUN_ENV_VARS="${RUN_ENV_VARS:-}"

BUILDER_NAME="${BUILDER_NAME:-multiarch-generic}"
DEFAULT_INSTALL_BINFMT=1
if [ "${GITHUB_ACTIONS:-}" = "true" ] && [ "${RUNNER_ARCH:-}" = "ARM64" ]; then
  DEFAULT_INSTALL_BINFMT=0
fi
INSTALL_BINFMT="${INSTALL_BINFMT:-$DEFAULT_INSTALL_BINFMT}"
LOCAL_OUTPUT="${LOCAL_OUTPUT:---load}"
DEFAULT_LOCAL_PROGRESS=auto
if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
  DEFAULT_LOCAL_PROGRESS=plain
fi
LOCAL_PROGRESS="${LOCAL_PROGRESS:-$DEFAULT_LOCAL_PROGRESS}"
EXTRA_BUILD_ARGS="${EXTRA_BUILD_ARGS:-}"

REMOTE_HOST="${REMOTE_HOST:-}"
REMOTE_PORT="${REMOTE_PORT:-22}"
REMOTE_USER="${REMOTE_USER:-}"
REMOTE_WORKDIR="${REMOTE_WORKDIR:-/tmp/generic-arm64-build}"
REMOTE_IMAGE_NAME="${REMOTE_IMAGE_NAME:-$IMAGE_NAME}"
REMOTE_PROGRESS="${REMOTE_PROGRESS:-plain}"
REMOTE_BUILD_CMD="${REMOTE_BUILD_CMD:-docker build}"
SYNC_TOOL="${SYNC_TOOL:-scp}"

usage() {
  cat <<'EOF'
Usage:
  ./build-and-run-arm64.sh [options]

Core idea:
  Build a linux/arm64 image from either:
  1. a local source directory
  2. a git repository

Modes:
  --mode local-x86      Build ARM64 image on local x86 with docker buildx.
  --mode remote-arm     Sync build context to remote ARM host and build there natively.

Actions:
  --action build        Build only. Default.
  --action print-test   Print manual run/test commands only.
  --action prepare      Only prepare the temporary build context locally.

Config options:
  --env-file FILE       Load variables from a shell-style env file first.

Source options:
  --source-type git|local
  --repo URL
  --ref REF
  --local-source-dir DIR
  --source-subdir DIR   Project subdir where build command runs. Default: .

Build options:
  --build-cmd CMD
  --builder-image IMAGE
  --builder-apt-packages "pkg1 pkg2"
  --builder-setup-cmd CMD

Artifact options:
  --artifact-path PATH
  --artifact-mode archive|dir|file
  --app-dest DIR

Runtime options:
  --runtime-image IMAGE
  --runtime-apt-packages "pkg1 pkg2"
  --runtime-setup-cmd CMD
  --start-command CMD
  --expose-ports PORTS

Run/test helper options:
  --image NAME
  --image-tar PATH
  --container-name NAME
  --host-port PORT
  --container-port PORT
  --run-env-vars "KEY1=V1,KEY2=V2"

Local x86 options:
  --builder NAME
  --local-output VALUE
  --extra-build-args "ARGS"
  --skip-binfmt
  --progress VALUE
  --force-recreate-builder  Recreate buildx builder before build.

Remote ARM options:
  --remote-host HOST
  --remote-user USER
  --remote-port PORT
  --remote-workdir DIR
  --remote-image NAME
  --remote-build-cmd CMD
  --sync-tool scp|rsync

Examples:
  Build from env file:
    ./build-and-run-arm64.sh --env-file examples/kkfileview-5.0.0.env

  Build kkFileView from git:
    ./build-and-run-arm64.sh \
      --source-type git \
      --repo https://github.com/kekingcn/file-online-preview.git \
      --ref v5.0.0 \
      --build-cmd "mvn -pl server -am -DskipTests clean package" \
      --artifact-path "server/target/kkFileView-*.tar.gz" \
      --artifact-mode archive \
      --runtime-apt-packages "libreoffice libreoffice-java-common fonts-noto-cjk fontconfig locales tzdata ca-certificates curl procps" \
      --app-dest /opt/kkFileView \
      --start-command "java -Dfile.encoding=UTF-8 -Dspring.config.location=/opt/kkFileView/config/application.properties -jar \$(find /opt/kkFileView/bin -maxdepth 1 -type f -name 'kkFileView-*.jar' | head -n 1)" \
      --image kkfileview-arm64:v5.0.0

  Build generic app from local directory:
    ./build-and-run-arm64.sh \
      --source-type local \
      --local-source-dir /path/to/project \
      --build-cmd "pnpm install && pnpm build" \
      --builder-image node:20-bookworm \
      --builder-apt-packages "git ca-certificates" \
      --artifact-path dist \
      --artifact-mode dir \
      --runtime-image nginx:alpine \
      --runtime-apt-packages "" \
      --start-command "nginx -g 'daemon off;'" \
      --image demo-web-arm64:latest
EOF
}

log() {
  printf '[INFO] %s\n' "$*"
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

load_env_file() {
  [ -n "$ENV_FILE" ] || return 0
  [ -f "$ENV_FILE" ] || die "env file not found: $ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
}

ssh_target() {
  if [ -n "$REMOTE_USER" ]; then
    printf '%s@%s' "$REMOTE_USER" "$REMOTE_HOST"
  else
    printf '%s' "$REMOTE_HOST"
  fi
}

cleanup_workdir() {
  rm -rf "$WORK_DIR"
}

export_image_tar() {
  [ -n "$IMAGE_TAR_PATH" ] || return 0
  require_cmd docker
  mkdir -p "$(dirname "$IMAGE_TAR_PATH")"
  docker image inspect "$IMAGE_NAME" >/dev/null 2>&1 || die "image not found locally for export: $IMAGE_NAME. Use --local-output --load when exporting tar."
  log "exporting docker image tar to $IMAGE_TAR_PATH"
  docker save --output "$IMAGE_TAR_PATH" "$IMAGE_NAME"
}

prepare_context() {
  cleanup_workdir
  mkdir -p "$WORK_DIR/local-source"
  cp "$SCRIPT_DIR/$DOCKERFILE" "$WORK_DIR/$DOCKERFILE"
  cp "$SCRIPT_DIR/docker-entrypoint.sh" "$WORK_DIR/docker-entrypoint.sh"

  if [ "$SOURCE_TYPE" = "local" ]; then
    [ -n "$LOCAL_SOURCE_DIR" ] || die "--local-source-dir is required for source-type=local"
    [ -d "$LOCAL_SOURCE_DIR" ] || die "local source dir not found: $LOCAL_SOURCE_DIR"
    cp -a "$LOCAL_SOURCE_DIR"/. "$WORK_DIR/local-source/"
  fi
}

print_manual_test() {
  local env_lines=""
  if [ -n "$RUN_ENV_VARS" ]; then
    IFS=',' read -r -a env_items <<< "$RUN_ENV_VARS"
    for item in "${env_items[@]}"; do
      env_lines="${env_lines}     -e ${item} \\
"
    done
  fi

  cat <<EOF
Manual test steps for image: ${IMAGE_NAME}

1. Start container manually on an ARM64-capable Docker host:
   docker run -d \\
     --name ${CONTAINER_NAME} \\
     --platform ${PLATFORM} \\
     -p ${HOST_PORT}:${CONTAINER_PORT} \\
${env_lines}     ${IMAGE_NAME}

2. Watch startup logs:
   docker logs -f ${CONTAINER_NAME}

3. Verify service:
   Open http://localhost:${HOST_PORT}/

4. Stop and remove:
   docker rm -f ${CONTAINER_NAME}

Container notes:
  - Image expects START_COMMAND=${START_COMMAND:-<not set>}
  - Exposed ports: ${EXPOSE_PORTS}
  - App destination: ${APP_DEST}
EOF
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --env-file) ENV_FILE="$2"; shift 2 ;;
      --mode) MODE="$2"; shift 2 ;;
      --action) ACTION="$2"; shift 2 ;;
      --image) IMAGE_NAME="$2"; REMOTE_IMAGE_NAME="$2"; shift 2 ;;
      --image-tar) IMAGE_TAR_PATH="$2"; shift 2 ;;
      --container-name) CONTAINER_NAME="$2"; shift 2 ;;
      --source-type) SOURCE_TYPE="$2"; shift 2 ;;
      --repo) GIT_REPO="$2"; shift 2 ;;
      --ref) GIT_REF="$2"; shift 2 ;;
      --local-source-dir) LOCAL_SOURCE_DIR="$2"; shift 2 ;;
      --source-subdir) SOURCE_SUBDIR="$2"; shift 2 ;;
      --build-cmd) BUILD_CMD="$2"; shift 2 ;;
      --builder-image) BUILDER_IMAGE="$2"; shift 2 ;;
      --builder-apt-packages) BUILDER_APT_PACKAGES="$2"; shift 2 ;;
      --builder-setup-cmd) BUILDER_SETUP_CMD="$2"; shift 2 ;;
      --artifact-path) ARTIFACT_PATH="$2"; shift 2 ;;
      --artifact-mode) ARTIFACT_MODE="$2"; shift 2 ;;
      --runtime-image) RUNTIME_IMAGE="$2"; shift 2 ;;
      --runtime-apt-packages) RUNTIME_APT_PACKAGES="$2"; shift 2 ;;
      --runtime-setup-cmd) RUNTIME_SETUP_CMD="$2"; shift 2 ;;
      --app-dest) APP_DEST="$2"; shift 2 ;;
      --start-command) START_COMMAND="$2"; shift 2 ;;
      --expose-ports) EXPOSE_PORTS="$2"; shift 2 ;;
      --host-port) HOST_PORT="$2"; shift 2 ;;
      --container-port) CONTAINER_PORT="$2"; shift 2 ;;
      --run-env-vars) RUN_ENV_VARS="$2"; shift 2 ;;
      --dockerfile) DOCKERFILE="$2"; shift 2 ;;
      --platform) PLATFORM="$2"; shift 2 ;;
      --builder) BUILDER_NAME="$2"; shift 2 ;;
      --local-output) LOCAL_OUTPUT="$2"; shift 2 ;;
      --extra-build-args) EXTRA_BUILD_ARGS="$2"; shift 2 ;;
      --skip-binfmt) INSTALL_BINFMT=0; shift 1 ;;
      --force-recreate-builder) BUILDER_FORCE_RECREATE=1; shift 1 ;;
      --progress) LOCAL_PROGRESS="$2"; REMOTE_PROGRESS="$2"; shift 2 ;;
      --remote-host) REMOTE_HOST="$2"; shift 2 ;;
      --remote-user) REMOTE_USER="$2"; shift 2 ;;
      --remote-port) REMOTE_PORT="$2"; shift 2 ;;
      --remote-workdir) REMOTE_WORKDIR="$2"; shift 2 ;;
      --remote-image) REMOTE_IMAGE_NAME="$2"; shift 2 ;;
      --remote-build-cmd) REMOTE_BUILD_CMD="$2"; shift 2 ;;
      --sync-tool) SYNC_TOOL="$2"; shift 2 ;;
      --help|-h) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
  done
}

validate_args() {
  case "$MODE" in
    local-x86|remote-arm) ;;
    *) die "unsupported mode: $MODE" ;;
  esac

  case "$ACTION" in
    build|print-test|prepare) ;;
    *) die "unsupported action: $ACTION" ;;
  esac

  case "$SOURCE_TYPE" in
    git|local) ;;
    *) die "unsupported source type: $SOURCE_TYPE" ;;
  esac

  case "$ARTIFACT_MODE" in
    archive|dir|file) ;;
    *) die "unsupported artifact mode: $ARTIFACT_MODE" ;;
  esac

  [ -f "$SCRIPT_DIR/$DOCKERFILE" ] || die "dockerfile not found: $SCRIPT_DIR/$DOCKERFILE"
  [ -f "$SCRIPT_DIR/docker-entrypoint.sh" ] || die "missing docker-entrypoint.sh"

  if [ "$ACTION" != "print-test" ]; then
    if [ "$SOURCE_TYPE" = "git" ] && [ -z "$GIT_REPO" ]; then
      die "--repo is required for source-type=git"
    fi

    if [ "$MODE" = "remote-arm" ] && [ -z "$REMOTE_HOST" ]; then
      die "--remote-host is required in remote-arm mode"
    fi
  fi
}

ensure_local_builder() {
  require_cmd docker
  docker buildx version >/dev/null 2>&1 || die "docker buildx is required"

  if [ "${GITHUB_ACTIONS:-}" = "true" ] && [ "${RUNNER_ARCH:-}" = "ARM64" ] && [ "$BUILDER_FORCE_RECREATE" != "1" ]; then
    if docker buildx inspect >/dev/null 2>&1; then
      log "using existing buildx builder from GitHub Actions ARM runner"
      docker buildx inspect --bootstrap >/dev/null
      return 0
    fi
  fi

  if [ "$BUILDER_FORCE_RECREATE" = "1" ] && docker buildx inspect "$BUILDER_NAME" >/dev/null 2>&1; then
    log "recreating buildx builder: $BUILDER_NAME"
    docker buildx rm "$BUILDER_NAME" >/dev/null
  fi

  if ! docker buildx inspect "$BUILDER_NAME" >/dev/null 2>&1; then
    log "creating buildx builder: $BUILDER_NAME"
    docker buildx create --name "$BUILDER_NAME" --use >/dev/null
  else
    docker buildx use "$BUILDER_NAME" >/dev/null
  fi

  if [ "$INSTALL_BINFMT" = "1" ]; then
    log "installing binfmt for cross-arch emulation"
    docker run --privileged --rm tonistiigi/binfmt --install all >/dev/null
  fi

  docker buildx inspect --bootstrap >/dev/null
}

build_args_common() {
  BUILD_ARGS=(
    --build-arg "BUILDER_IMAGE=${BUILDER_IMAGE}"
    --build-arg "RUNTIME_IMAGE=${RUNTIME_IMAGE}"
    --build-arg "SOURCE_TYPE=${SOURCE_TYPE}"
    --build-arg "GIT_REPO=${GIT_REPO}"
    --build-arg "GIT_REF=${GIT_REF}"
    --build-arg "SOURCE_SUBDIR=${SOURCE_SUBDIR}"
    --build-arg "BUILDER_APT_PACKAGES=${BUILDER_APT_PACKAGES}"
    --build-arg "BUILDER_SETUP_CMD=${BUILDER_SETUP_CMD}"
    --build-arg "BUILD_CMD=${BUILD_CMD}"
    --build-arg "ARTIFACT_PATH=${ARTIFACT_PATH}"
    --build-arg "ARTIFACT_MODE=${ARTIFACT_MODE}"
    --build-arg "RUNTIME_APT_PACKAGES=${RUNTIME_APT_PACKAGES}"
    --build-arg "RUNTIME_SETUP_CMD=${RUNTIME_SETUP_CMD}"
    --build-arg "APP_DEST=${APP_DEST}"
    --build-arg "EXPOSE_PORTS=${EXPOSE_PORTS}"
    --build-arg "DEFAULT_START_COMMAND=${START_COMMAND}"
  )
}

build_local_x86() {
  prepare_context
  ensure_local_builder

  log "building ARM64 image on local x86 host"
  log "image=${IMAGE_NAME} source_type=${SOURCE_TYPE}"

  local -a BUILD_ARGS
  local -a EXTRA_ARGS=()
  build_args_common
  if [ -n "$EXTRA_BUILD_ARGS" ]; then
    read -r -a EXTRA_ARGS <<< "$EXTRA_BUILD_ARGS"
  fi

  docker buildx build \
    --platform "$PLATFORM" \
    --progress "$LOCAL_PROGRESS" \
    -f "$WORK_DIR/$DOCKERFILE" \
    -t "$IMAGE_NAME" \
    "$LOCAL_OUTPUT" \
    "${BUILD_ARGS[@]}" \
    "${EXTRA_ARGS[@]}" \
    "$WORK_DIR"

  export_image_tar

  cat <<EOF

Build finished for local-x86 mode.
Source type: ${SOURCE_TYPE}
Image: ${IMAGE_NAME}
Image tar: ${IMAGE_TAR_PATH:-<not exported>}
EOF
  print_manual_test
}

sync_remote_files() {
  local target
  target="$(ssh_target)"

  case "$SYNC_TOOL" in
    scp)
      require_cmd scp
      require_cmd ssh
      ssh -p "$REMOTE_PORT" "$target" "mkdir -p '$REMOTE_WORKDIR'"
      scp -P "$REMOTE_PORT" -r "$WORK_DIR/." "$target:$REMOTE_WORKDIR/"
      ;;
    rsync)
      require_cmd rsync
      require_cmd ssh
      rsync -av -e "ssh -p $REMOTE_PORT" "$WORK_DIR"/ "$(ssh_target):$REMOTE_WORKDIR/"
      ;;
    *)
      die "unsupported sync tool: $SYNC_TOOL"
      ;;
  esac
}

build_remote_arm() {
  require_cmd ssh
  prepare_context
  local -a BUILD_ARGS
  local args_file
  build_args_common
  args_file="$WORK_DIR/.build-args.sh"
  printf 'BUILD_ARGS=(\n' > "$args_file"
  for arg in "${BUILD_ARGS[@]}"; do
    printf '  %q\n' "$arg" >> "$args_file"
  done
  printf ')\n' >> "$args_file"
  sync_remote_files
  if [ "$SYNC_TOOL" = "scp" ]; then
    scp -P "$REMOTE_PORT" "$args_file" "$(ssh_target):$REMOTE_WORKDIR/.build-args.sh"
  else
    rsync -av -e "ssh -p $REMOTE_PORT" "$args_file" "$(ssh_target):$REMOTE_WORKDIR/.build-args.sh"
  fi

  log "building ARM64 image on remote ARM host $(ssh_target)"

  ssh -p "$REMOTE_PORT" "$(ssh_target)" "\
    set -euo pipefail; \
    cd '$REMOTE_WORKDIR'; \
    . ./.build-args.sh; \
    ${REMOTE_BUILD_CMD} \
      --progress '${REMOTE_PROGRESS}' \
      -f '${DOCKERFILE}' \
      -t '${REMOTE_IMAGE_NAME}' \
      \"\${BUILD_ARGS[@]}\" \
      ."

  cat <<EOF

Remote ARM build finished.
Remote host: $(ssh_target)
Remote image: ${REMOTE_IMAGE_NAME}
EOF
}

main() {
  parse_args "$@"
  load_env_file
  parse_args "$@"
  validate_args

  case "$ACTION" in
    print-test)
      print_manual_test
      ;;
    prepare)
      prepare_context
      log "prepared build context at $WORK_DIR"
      ;;
    build)
      case "$MODE" in
        local-x86) build_local_x86 ;;
        remote-arm) build_remote_arm ;;
      esac
      ;;
  esac
}

main "$@"
