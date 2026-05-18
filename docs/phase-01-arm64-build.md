# 阶段记录

## Phase 01: 通用 ARM64 构建脚本落地

日期：2026-05-18

本阶段完成项：

- 提供通用 `build-and-run-arm64.sh`，支持从源码构建 ARM64 Docker 镜像。
- 提供 `Dockerfile.arm64` 多阶段构建模板，覆盖常见产物打包方式。
- 提供 `kkFileView 5.0.0` 示例配置，用于验证 Java 应用及其运行时依赖场景。

## Phase 02: GitHub Actions 导出 tar 并上传 Artifact

日期：2026-05-18

本阶段完成项：

- workflow 新增镜像导出与 `upload-artifact`，构建完成后可直接下载镜像 tar。
- 脚本新增 `IMAGE_TAR_PATH`，支持在构建完成后执行 `docker save`。
- workflow 启用 BuildKit `type=gha` 缓存，并按 ARM64 runner 场景跳过多余初始化步骤。

## Phase 03: README 收敛为 GitHub Actions 使用说明

日期：2026-05-18

本阶段完成项：

- README 删除本地构建与远程构建使用叙述，仅保留 GitHub Actions 运行方式。
- README 文案调整为更正式的开源项目说明风格。
- README 明确 artifact 下载、`docker load` 以及容器启动流程。
