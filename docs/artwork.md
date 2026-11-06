# 素材与动画

[返回首页](../README.md) · [开发指南](development.md)

## 原始素材与运行资源

| 素材 | 原始文件或记录 | 运行资源 |
| --- | --- | --- |
| 原创黑猫 | [Artwork/Prompts/cat-master-v3.txt](../Artwork/Prompts/cat-master-v3.txt)、[Artwork](../Artwork/) | `Sources/EmberCat/Resources/MenuBarPets/` |
| 玛奇玛 | [Artwork/Makima](../Artwork/Makima/)、[原画摘要](../Artwork/Makima/original-frame-sha256.json) | `MenuBarPets/` 与 `PetPreview/` |
| Dock 待机黑猫 | [原始透明图](../Artwork/DockIdleCat/black-cat-original.png)、[来源记录](../Artwork/DockIdleCat/provenance.json) | `Sources/EmberCat/Resources/DockIdleCat/` |
| 三档仓鼠 | [slow.gif](../Artwork/NotchLightning/Hamsters/slow.gif)、[fast.gif](../Artwork/NotchLightning/Hamsters/fast.gif)、[turbo.gif](../Artwork/NotchLightning/Hamsters/turbo.gif) | `Sources/EmberCat/Resources/NotchLightning/` |
| 能量条材质 | [概念参考图](../Artwork/NotchLightning/direction-reference-v3.png) | 同上，能量与漏电图集 |
| 来源图标 | [来源与摘要](../Sources/EmberCat/Resources/SourceIcons/provenance.json) | `Sources/EmberCat/Resources/SourceIcons/` |

原画、原始 GIF 与不可变对照保留；处理结果输出为独立的运行资源。应用直接加载随包素材，运行时无需调用生图 API。

黑猫的步频随输出速度变化；玛奇玛同档保持固定节奏。两者使用独立运动逻辑，不共用步态轨迹。菜单栏资源提供 1×/2× PNG，高清动作和过渡预览独立存放。

## 离线重建

下列命令从仓库根目录运行，会更新素材文件，按实际需要执行。Python 工具需要 Pillow；人物重建还需要 numpy 和 Node.js。

### 黑猫与 Dock 待机图

```sh
python3 scripts/prepare-pets.py --cat-only
python3 scripts/prepare-dock-idle.py
```

`--cat-only` 保留玛奇玛资源。Dock 坐姿从透明原图提取眼珠、高光与眼眶遮罩，用于原生视线跟随。

### 玛奇玛连续动作

```sh
python3 scripts/pixelfx/render-makima.py --install
python3 scripts/pixelfx/render-vehicles.py --install
python3 scripts/pixelfx/render-suite.py --install
python3 scripts/pixelfx/render-transitions.py
```

不要把不带参数的 `prepare-pets.py` 当作当前人物资源的完整重建入口：它会恢复早期玛奇玛资源，随后还需依次执行上面的四个渲染命令。历史帧与过渡原画保存在 `Artwork/Makima/` 下各 `original/` 目录，manifest 记录来源、生成参数和摘要。

人物步态由 `scripts/pixelfx/human-gait.mjs` 编排，肢体与衣服轮廓由 `gait_art.py` 绘制。过渡使用原画关键姿势与实际循环帧混合，放大慢放时可能看到短暂叠影。

可用 `scripts/pixelfx/check-makima.py`、`scripts/pixelfx/check-vehicles.py`、`scripts/pixelfx/check-suite.py` 和 `scripts/check-motion-art.py` 检查重建结果。独立预览包由 `./scripts/build-pixelfx-preview.sh suite` 生成；使用独立 bundle ID，不覆盖正常安装的 EmberCat。

### 仓鼠与能量材质

```sh
python3 scripts/prepare-lightning-hamsters.py
python3 scripts/prepare-lightning.py
```

仓鼠处理脚本对齐跑轮中心，生成 72 帧透明图集及原始时长清单。慢速循环为 0.96 秒，高速和极速各为 0.72 秒；三份原始 GIF 不在原位修改。

左右仓鼠共享原始帧，右侧镜像朝内，并错开播放相位。能量材质来自已有 Sunburst 概念图的离线处理；这套重建命令不重新生成原画。

README 演示图由 0.6.23 的应用渲染器导出，使用明确标注的模拟速度，保留 150 帧、25 fps、6 秒循环。重新生成方法见[开发指南](development.md#原生预览与导出)。

## 来源与许可

- **Agent Speed**：测速核心及原始版权见 [AGENT-SPEED-LICENSE](../Vendor/AGENT-SPEED-LICENSE) 和 [UPSTREAM.md](../Vendor/UPSTREAM.md)。
- **Ghostty Blackhole**：感谢 s13k（@s0xDk）提供参考实现；[改编记录](../Vendor/GHOSTTY-BLACKHOLE.md)与 [MIT 许可](../Vendor/GHOSTTY-BLACKHOLE-LICENSE)保留在仓库及应用中。
- **黑猫**：本项目原创形象，原画由项目既有生图流程生成，动画离线派生。旧 RunCat 参考的历史记录见 [RUNCAT-NOTICE.md](../Vendor/RUNCAT-NOTICE.md)。
- **玛奇玛**：用户指定角色的同人图像，原画由项目既有生图流程生成，保留原始文件及来源摘要。
- **PixelFX**：离线动作工具使用的随机、粒子与缓动依赖，见[上游记录](../Vendor/PixelFX/UPSTREAM.md)和[许可证](../Vendor/PixelFX/LICENSE)。
- **来源图标**：来自 LobeHub、oh-my-pi、ZCode 等，具体文件、版本、摘要及随附许可见 [SourceIcons](../Sources/EmberCat/Resources/SourceIcons/)。
- **zstd**：见 [CZstd/LICENSE](../Vendor/CZstd/LICENSE)。Sparkle 的固定依赖与随包许可处理见 [Package.swift](../Package.swift) 和 [build-app.sh](../build-app.sh)。
