# GitHub Actions ARM64 构建记录

日期：2026-05-18

## 已确认事项

- 仓库已存在 workflow：`.github/workflows/build-kkfileview-arm64.yml`
- 触发方式为 `workflow_dispatch`
- Runner 为 `ubuntu-24.04-arm`
- 构建入口脚本为 `./build-and-run-arm64.sh --env-file examples/kkfileview-5.0.0.env`

## 当前阻塞

- 本地 `gh` CLI 已安装，但当前默认账号 `yujianfeikong` 的 GitHub token 已失效
- 环境变量中未发现可直接复用的 `GH_TOKEN` 或 `GITHUB_TOKEN`
- 因此当前无法从本地直接触发远程 GitHub Actions

## 后续处理

在重新完成 GitHub 认证后，可执行：

```bash
rtk gh auth login -h github.com
rtk gh workflow run build-kkfileview-arm64.yml
rtk gh run watch

## 变更记录

- 发现 GitHub Actions 构建阶段拉取上游源码时使用的是 `https://gitee.com/kekingcn/file-online-preview.git`
- Actions 环境下该地址触发了 `fatal: could not read Username for 'https://gitee.com'`
- 已将示例构建源地址切换为 GitHub：`https://github.com/kekingcn/file-online-preview.git`
```
