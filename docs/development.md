# 开发指南

[返回首页](../README.md) · [素材说明](artwork.md) · [发布流程](updates.md)

## 从源码构建

环境要求：macOS 14+、Apple Silicon、支持 Swift 6 的 Xcode Command Line Tools。涉及 GPU、窗口或应用图标的检查需要可访问桌面图形会话。

在仓库根目录执行：

```sh
./build-app.sh
open dist/EmberCat.app
```

脚本通过 SwiftPM 构建应用，嵌入 Sparkle 和运行资源，以 ad-hoc 签名 `dist/EmberCat.app`，然后运行包内资源检查。依赖版本由 [Package.swift](../Package.swift) 与 [Package.resolved](../Package.resolved)固定。

`dist/`、`work/`、`output/`、`.build/` 均为本地产物目录，不进入 Git。公开安装包从 [Releases](https://github.com/johann15910358798-lab/EmberCat/releases) 获取。

## 按改动范围检查

这些命令从仓库根目录运行。选与改动相关的检查，不必为文档修改重跑整套应用测试。

| 改动范围 | 检查入口 |
| --- | --- |
| 基础动画 | `./scripts/check-animation.sh` |
| 黑猫步态、过渡与节奏 | `./scripts/check-cat-motion.sh` |
| 待机黑猫视线 | `./scripts/check-cat-gaze.sh` |
| 玛奇玛动作与跨档切换 | `./scripts/check-motion.sh` |
| 原画、模板和动作资源 | `python3 scripts/check-motion-art.py` |
| Dock 几何、脚印与生命周期 | `./scripts/check-dock-orbit.sh --native` |
| 流焰渲染与生命周期 | `./scripts/check-flame.sh` |
| Matrix 渲染与鼠标交互 | `bash scripts/check-matrix.sh --native` |
| 设置编辑、保存和窗口重开 | `./scripts/check-flame-preview.sh` |
| 仓鼠发电机、参数和悬停恢复 | `./scripts/check-lightning.sh --native` |

需要留存仓鼠发电机和设置回归报告时，可使用：

```sh
./scripts/check-lightning.sh --native --report /tmp/embercat-lightning-check.json
./scripts/check-flame-preview.sh --report /tmp/embercat-preview-check.json
```

发电机检查包含 GIF 帧与时长、独立调速、随机放电、配置兼容、参数极值、固定窗口、悬停恢复和减少动态效果。渲染检查通过不等同于视觉认可，涉及画面的修改仍需查看实际预览。

构建脚本已经执行资源检查；单独复查现有包时使用：

```sh
dist/EmberCat.app/Contents/MacOS/EmberCat --check-assets
```

## 原生预览与导出

```sh
dist/EmberCat.app/Contents/MacOS/EmberCat --preview-motion
dist/EmberCat.app/Contents/MacOS/EmberCat --preview-flame
dist/EmberCat.app/Contents/MacOS/EmberCat --preview-matrix
dist/EmberCat.app/Contents/MacOS/EmberCat --preview-lightning
```

这些窗口使用模拟速度。普通特效设置窗口在「保存并应用」后会写入应用配置；需要隔离参数试验时，使用独立草稿：

```sh
./scripts/check-lightning.sh --interactive
bash scripts/export-matrix-draft.sh --interactive --configuration 1.75 1.8 2 0
```

独立草稿分别使用 `EmberCat.LightningInteractiveDraft` 和 `EmberCat.MatrixInteractiveDraft` 设置域，不更改已安装应用的参数。

通过实际生产渲染器导出素材：

```sh
dist/EmberCat.app/Contents/MacOS/EmberCat --export-cat-preview /tmp/embercat-cat-preview
dist/EmberCat.app/Contents/MacOS/EmberCat --export-motion-preview /tmp/embercat-motion-preview
dist/EmberCat.app/Contents/MacOS/EmberCat --export-flame-preview /tmp/embercat-flame-preview
dist/EmberCat.app/Contents/MacOS/EmberCat --export-matrix-preview /tmp/embercat-matrix-preview
dist/EmberCat.app/Contents/MacOS/EmberCat --export-lightning-preview /tmp/embercat-lightning-preview
```

输出包含对应的图片、动画或状态记录。黑猫 PNG 序列可进一步生成演示 GIF：

```sh
python3 scripts/render-cat-review.py /tmp/embercat-cat-preview /tmp/embercat-cat-gifs
```

预览与导出的速度均为模拟输入，不写入真实测速记录。README 的仓鼠演示来自 `--export-lightning-preview` 的 `lightning-motion.gif`；发布到文档的副本位于 [docs/images](images/)。

## 代码与文档入口

| 内容 | 权威入口 |
| --- | --- |
| 测速与来源 | [Agent Speed 集成说明](../Vendor/UPSTREAM.md)、[测速定义](../Vendor/METRICS.md) |
| 黑猫运动 | [CatMotion.swift](../Sources/EmberCat/CatMotion.swift) |
| 玛奇玛动作切换 | [MotionDirector.swift](../Sources/EmberCat/MotionDirector.swift) |
| 特效参数与持久化 | [NotchFlameSettings.swift](../Sources/EmberCat/NotchFlameSettings.swift) |
| 显示器适配 | [NotchDisplayProfile.swift](../Sources/EmberCat/NotchDisplayProfile.swift) |
| 共用渲染和鼠标反馈 | [NotchFlameRenderer.swift](../Sources/EmberCat/NotchFlameRenderer.swift) |
| 特效设置与布局 | [NotchFlamePreviewController.swift](../Sources/EmberCat/NotchFlamePreviewController.swift) |
| 素材原始文件及重建 | [素材说明](artwork.md) |
| 应用版本与发布 | [Info.plist](../Resources/Info.plist)、[发布流程](updates.md) |

README 介绍当前产品和使用入口；操作与参数放在使用指南，构建与检查放在本页，逐版变化放在 `docs/releases/` 和 GitHub Releases。历史版本说明保留当时的事实，不作为当前操作说明。

本地验收记录可以保存在 `work/`，公开文档应引用仓库中实际存在的文件或公开发布地址。只有构建、测试、上传、发布或真实安装各自完成后，才记录对应状态。
