# ARM64 Image Builder

通用 ARM64 Docker 镜像构建脚本。目标是让你只通过“源码来源 + 构建命令 + 运行时依赖 + 启动命令”四类信息，就能在 x86 或远程 ARM 机器上一键产出 `linux/arm64` 镜像。

适用场景：

- 从 Git 仓库构建 ARM64 镜像
- 从本地目录构建 ARM64 镜像
- 需要自定义 builder/runtime 基础镜像
- 需要安装特定构建依赖或运行时依赖
- 需要在本地 x86 交叉构建，或在远程 ARM 原生构建

## 文件说明

- [build-and-run-arm64.sh](/Users/bo/Documents/build-arm-docker/build-and-run-arm64.sh)：主脚本
- [Dockerfile.arm64](/Users/bo/Documents/build-arm-docker/Dockerfile.arm64)：通用多阶段 Dockerfile 模板
- [docker-entrypoint.sh](/Users/bo/Documents/build-arm-docker/docker-entrypoint.sh)：通用容器入口
- [`.env.example`](/Users/bo/Documents/build-arm-docker/.env.example)：通用配置模板
- [examples/kkfileview-5.0.0.env](/Users/bo/Documents/build-arm-docker/examples/kkfileview-5.0.0.env)：`kkFileView 5.0.0` 完整示例
- [docs/phase-01-arm64-build.md](/Users/bo/Documents/build-arm-docker/docs/phase-01-arm64-build.md)：阶段记录

## 快速开始

先给脚本执行权限：

```bash
chmod +x /Users/bo/Documents/build-arm-docker/build-and-run-arm64.sh
```

查看帮助：

```bash
cd /Users/bo/Documents/build-arm-docker
./build-and-run-arm64.sh --help
```

## 推荐用法

### 1. 用配置文件驱动

最推荐。先复制模板，再修改变量：

```bash
cp /Users/bo/Documents/build-arm-docker/.env.example /Users/bo/Documents/build-arm-docker/.env.local
./build-and-run-arm64.sh --env-file /Users/bo/Documents/build-arm-docker/.env.local
```

如果改过代理配置，或者之前 builder 创建失败，建议强制重建 builder：

```bash
./build-and-run-arm64.sh \
  --env-file /Users/bo/Documents/build-arm-docker/.env.local \
  --force-recreate-builder
```

### 2. 在 GitHub Actions 里执行

最适合当前仓库的使用方式，是直接在 GitHub Actions ARM runner 上调用脚本。

示例 workflow：

- [.github/workflows/build-kkfileview-arm64.yml](/Users/bo/Documents/build-arm-docker/.github/workflows/build-kkfileview-arm64.yml)

### 3. 从 Git 仓库构建

```bash
./build-and-run-arm64.sh \
  --source-type git \
  --repo https://github.com/example/project.git \
  --ref main \
  --build-cmd "mvn -DskipTests package" \
  --artifact-path "target/app.tar.gz" \
  --artifact-mode archive \
  --runtime-apt-packages "ca-certificates curl" \
  --app-dest /opt/app \
  --start-command "java -jar /opt/app/app.jar" \
  --image example-arm64:latest
```

### 4. 从本地目录构建

```bash
./build-and-run-arm64.sh \
  --source-type local \
  --local-source-dir /path/to/project \
  --builder-image node:20-bookworm \
  --build-cmd "pnpm install && pnpm build" \
  --artifact-path dist \
  --artifact-mode dir \
  --runtime-image nginx:alpine \
  --runtime-apt-packages "" \
  --start-command "nginx -g 'daemon off;'" \
  --image demo-web-arm64:latest
```

### 5. 在远程 ARM 主机原生构建

```bash
./build-and-run-arm64.sh \
  --mode remote-arm \
  --remote-host 192.168.1.10 \
  --remote-user ubuntu \
  --source-type local \
  --local-source-dir /path/to/project \
  --build-cmd "go build -o app ./cmd/server" \
  --artifact-path app \
  --artifact-mode file \
  --runtime-image ubuntu:22.04 \
  --runtime-apt-packages "ca-certificates" \
  --start-command "/opt/app/app" \
  --image my-go-app-arm64:latest
```

## kkFileView 5.0.0 完整示例

直接运行：

```bash
./build-and-run-arm64.sh --env-file /Users/bo/Documents/build-arm-docker/examples/kkfileview-5.0.0.env
```

切到远程 ARM 原生构建：

```bash
./build-and-run-arm64.sh \
  --env-file /Users/bo/Documents/build-arm-docker/examples/kkfileview-5.0.0.env \
  --mode remote-arm \
  --remote-host 192.168.1.10 \
  --remote-user ubuntu
```

只打印手动测试命令：

```bash
./build-and-run-arm64.sh \
  --env-file /Users/bo/Documents/build-arm-docker/examples/kkfileview-5.0.0.env \
  --action print-test
```

## 核心参数

源码来源：

- `SOURCE_TYPE=git|local`
- `GIT_REPO`
- `GIT_REF`
- `LOCAL_SOURCE_DIR`
- `SOURCE_SUBDIR`

构建阶段：

- `BUILDER_IMAGE`
- `BUILDER_APT_PACKAGES`
- `BUILDER_SETUP_CMD`
- `BUILD_CMD`

产物与运行阶段：

- `ARTIFACT_PATH`
- `ARTIFACT_MODE=archive|dir|file`
- `RUNTIME_IMAGE`
- `RUNTIME_APT_PACKAGES`
- `RUNTIME_SETUP_CMD`
- `APP_DEST`
- `START_COMMAND`

执行方式：

- `MODE=local-x86|remote-arm`
- `ACTION=build|prepare|print-test`
- `REMOTE_HOST`
- `REMOTE_USER`
- `REMOTE_WORKDIR`

## 手动测试

脚本默认不自动运行容器。构建完成后，可用：

```bash
./build-and-run-arm64.sh --env-file /Users/bo/Documents/build-arm-docker/.env.local --action print-test
```

或手动运行：

```bash
docker run -d \
  --name custom-arm64 \
  --platform linux/arm64 \
  -p 8012:8012 \
  custom-arm64:local
```

## 注意事项

- 本地 `x86 + QEMU` 构建安装大量 ARM64 系统包时，可能遇到兼容性问题。
- 如果目标项目依赖 LibreOffice、图形库、编解码库等大体量系统包，优先建议 `remote-arm`。
- `kkFileView 5.0.0` 按上游说明要求 `JDK 21+`。
- `kkFileView 5.0.0` 在本地 x86 交叉构建时，安装 LibreOffice 依赖仍可能受 QEMU 稳定性影响。
- 如果你使用 GitHub Actions ARM runner 构建，通常不需要额外处理代理问题。
