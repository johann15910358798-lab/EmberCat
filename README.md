# EmberCat 0.6.12

macOS 菜单栏 Agent 测速宠物。首次默认显示原创胖黑猫。左/右键点击图标打开紧凑菜单，选择「Token 来源」后在同一浮层查看各来源，左上角返回菜单。菜单内可切换玛奇玛，选择会保留到下次启动。

## 0.6.12 玛奇玛连续动作

九种玛奇玛动作使用连续循环，并提供全部动作和上下车过程的高清预览。版本为 0.6.12 / build 28；本地安装包为 [EmberCat-0.6.12.dmg](dist/EmberCat-0.6.12.dmg)。

人物的脸、刘海、辫子和衬衫继续取自既有原画。走路至滑板五档重新编排双腿动作与重心，摆臂使用固定长度的二维关节，裤腿、袖子、鞋和轮具使用连续轮廓，消除旧切片关节的断开与重叠。走路包含脚跟落地、支撑、抬跟和摆腿；跑步有腾空和屈臂。黑猫仅共享图像变换与抗锯齿导出方式，人物不再套用猫的脚步轨迹或通用三维骨架。快走 84 帧 / 1.4 秒，跑步 72 帧 / 1.2 秒，走路 96 帧 / 1.6 秒；六种载具各为 144 帧 / 2.4 秒。所有运动与切换均以 60 Hz 调度，待机继续停止刷新。

轮滑有向后蹬腿、抬轮回收和单脚滑行；滑板支撑脚固定在板面，另一脚蹬地、抬过板面，随后双脚站板滑行。支撑、回收与重心变化分别编排，循环处的脚步速度连续。自行车双脚沿相反的曲柄位置踩踏，车轮与辫子随动。摩托车和跑车有转轮、悬挂及后轮接地扬尘。飞行背包有悬停起伏、腿部随动、变化的喷流和尾迹。运行速度仅选择动作，不改变玛奇玛同档步频。

菜单栏仍使用 36×20 pt 的 1×/2× PNG；全部动作和 45 组上下车过渡另有 576×320 高清预览。过渡按新循环实测的头部位置与大小重新配准，保留四张原画姿势，以 60 Hz 平滑混合；源动作在切换开始时继续运动。过渡仍是原画关键帧混合，放大慢放时可见短暂叠影，尚未重新逐帧绘制所有上下车动作。放大预览在过渡期间也保持高清。预览缓存最多保留三个动作/过渡集，避免浏览整套后常驻全部高清帧。

```sh
# Node 18+；Python 需要 Pillow 与 numpy
python3 scripts/pixelfx/render-makima.py --install
python3 scripts/pixelfx/render-vehicles.py --install
python3 scripts/pixelfx/render-suite.py --install
python3 scripts/pixelfx/render-transitions.py
python3 scripts/pixelfx/check-makima.py
python3 scripts/pixelfx/check-vehicles.py
python3 scripts/pixelfx/check-suite.py
python3 scripts/check-motion-art.py
./scripts/check-motion.sh
./scripts/build-pixelfx-preview.sh suite
python3 scripts/pixelfx/review-suite.py
open dist/EmberCat-PixelFX-Suite-Preview.app
open work/makima-suite/comparison.html
```

整套预览包有独立 bundle ID，启动后只打开模拟速度窗口，不读取真实 Token 会话，也不覆盖 `/Applications/EmberCat.app`。HTML 可逐档比较原版/新动画、查看实际尺寸、明暗背景、半速、逐帧，以及任意两档之间的切换。GIF 是 30 fps 查看副本；整套九动作总览播放 9.6 秒，不人为拼接不同周期的回环。完整 60 fps 请看 HTML 或原生预览。

本次为既有角色原画与重画肢体轮廓的动作重制，未使用新的 AI 人物原画。技术检查不代表用户认可动作观感。原走路 16 张、车辆 32 张、其余六档 96 张 1×/2× 文件分别保存在 `Artwork/Makima/PixelFX-Walk/original/`、`PixelFX-Vehicles/original/`、`PixelFX-Suite/original/`；360 张旧过渡 PNG 保存在 `PixelFX-Transitions/original/`。各自 manifest 保存来源、脚本和输出哈希。

PixelFX 固定为 `a84159688af3ca37a4be05a0d422b94451b2e24e`，用于确定性粒子、缓动与周期计算；来源与本地修改见 `Vendor/PixelFX/UPSTREAM.md`。源码图像、黑猫生产资源和已安装应用均独立保留。

## 形象与动作

胖黑猫保留原创母图的圆肚、头、眼睛和尾巴，只使用站立、行走、跑动、滚动四种动作。行走采用四拍步态和落地支撑；跑动改用有腾空的成对迈腿，配合身体起伏和尾巴跟随。滚动先把头、四肢和尾巴收进圆形轮廓，再让整只猫球顺时针翻滚；减速离开时先完成当前一圈，转正后展开落地。三个循环各有 96 帧，收拢/展开共用可逆的 40 帧过渡，1×/2× 共 658 张 PNG。全部猫动作使用同一比例、原点和地面位置。

猫的步频随真实 tok/s 连续变化，使用速度滤波、步频缓动和相位积分，更新速度不会把动作跳回第一帧。动画以 60 Hz 调度，输出停止后自然展开、减速并站稳，随后停止计时器。升入行走、跑动、滚动分别需要 0.9、22、90 tok/s；降档边界为 0.25、16、70 tok/s，边界附近保持当前动作。大跳速经相邻步态衔接，卷起或展开用时 0.65 秒，已开始的身体过渡会完整播放，再按最新输入继续。逻辑集中在 `CatMotion.swift`，独立于玛奇玛的固定节奏。

猫的母图由 imagegen Skill 通过项目既有图片接口生成，不使用 RunCat 图片或图像参考；本次四种动画由现有母图离线派生。

玛奇玛在 0.6.2 恢复过 0.5.2 的黑白原画。此分支用连续动作替换九档循环，待机原文件不变。`Artwork/Makima/original-frame-sha256.json` 对应的 146 张原文件完整保留，其中 2 张待机图仍直接使用，144 张作为不可变对照保存。

45 对过渡的四张原画姿势按新循环重新定位，覆盖 90 个方向。反向按逆序播放，起点/终点使用实际运动中的循环帧。过渡持续 0.8 秒，长载具可以从画布侧边进入。速度从 3 跳到 70 tok/s 时直接经过上车姿势进入自行车，回到 3 则下车走路，不依次播放无关的中间档。

玛奇玛的 tok/s 只决定出行方式。走路、快走、跑步分别固定 1.6、1.4、1.2 秒一圈；六种载具固定 2.4 秒一圈。每档的帧数等于周期秒数乘以 60，高 tok/s 不会倍速播放。

| 动作 | 名义分界 tok/s | 升入该档 | 低于此值开始降档确认 |
| --- | ---: | ---: | ---: |
| 走路 | 0.8 | 1.0 | 0.25 |
| 快走 | 8 | 8.96 | 6.8 |
| 跑步 | 18 | 20.16 | 15.3 |
| 轮滑 | 30 | 33.6 | 25.5 |
| 滑板 | 44 | 49.28 | 37.4 |
| 自行车 | 60 | 67.2 | 51 |
| 摩托车 | 80 | 89.6 | 68 |
| 敞篷跑车 | 110 | 123.2 | 93.5 |
| 飞行背包 | 150 | 168 | 127.5 |

升档阈值约高于名义边界 12%，降档阈值约低于名义边界 15%。速度经过 0.35 秒上升、0.7 秒下降时间常数的平滑；原始速度和平滑速度必须指向同一目标档位才开始持续确认，避免平滑过程误确认中间档。升档确认 0.65 秒、降档确认 1.1 秒、回到待机确认 1.3 秒。每次过渡 0.8 秒，完成后至少停留 1.6 秒。已开始的过渡会完整播放；期间的新速度在停留后重新确认，使用最新输入，不排队播放旧目标。这些玛奇玛行为由 `MotionDirector.swift` 控制。

## 菜单栏与预览

点击人物，在菜单中切换「显示实时速度」。默认仅显示人物，选择会保存到下次启动。速度在人物旁单行显示，例如 `13.1 tok/s`，保留一位小数、不换行；它使用与人物动作相同的实时输出速度，不是今日累计 token 数。来源名称只显示在「Token 来源」页面中。

菜单栏按整组动作的可见范围裁去左右透明边距，不再固定占用 44pt。比如玛奇玛待机的原画从 36pt 宽裁至约 15pt，人物高度和比例保持不变。同一动作的全部帧使用相同裁剪范围；过渡使用起点、终点和过渡姿势的共同范围，避免逐帧跳宽或裁掉载具。

黑猫站立、行走、跑动共用 32pt 图像宽度；蜷成球时按收拢进度逐渐收窄，展开时逆序恢复，球形滚动的整圈保持 17pt。点击区域在图像外保留共 8pt 边距；显示速度时另加文字宽度和 4pt 间隔。源 PNG 仍保留 36×20pt 画布与 1×/2× 图像，系统模板着色适配菜单栏明暗。待机后停止动画计时器。

「动作预览…」提供实际尺寸与全部玛奇玛动作、过渡的高清预览。黑猫显示四个动作按钮、平滑加减速、3 → 140 → 0 跳速及边界防抖演示。玛奇玛保留九档选择、全套升降档、3 ↔ 70 跳速及边界防抖演示。跳速演示还包含走路→飞行背包→待机，方便查看跨多档起飞和落地。它读取同一套生产资源，运行相同状态机和过渡渲染器，使用独立模拟速度；实际菜单栏继续读取真实会话。档位按钮使用能从上下两侧进入该档的示例速度；阈值防振区内保留当前动作。

## 0.6.6 来源页面

点击图标先显示 300×306pt 的紧凑菜单，选择「Token 来源」后，同一个浮层平滑展开至 536×402pt。左侧选择来源，右侧查看详情，左上角返回菜单。页面切换使用轻微位移与淡入淡出，来源详情与数值也有短过渡，遵循系统「减少动态效果」设置。菜单栏仍只显示形象和可选总速度。

版本为 0.6.6 / build 22。修复来源 logo 加载误访问缺失的 SwiftPM 资源包导致的崩溃。资源定位同时支持独立应用与 SwiftPM 构建；图标缺失或不可读时使用安全的通用图标。0.6.6 发布时的安装与操作检查见下方历史记录，不代表本试验已安装。

- [本地安装包](dist/EmberCat-0.6.6.dmg)。
- [检查记录](work/token-sources-0.6.6/verification.md)。

## 0.6.5 更新与交付记录

黑猫增加独立行走、跑动、真球形翻滚和收拢/展开过渡，速度平滑加减速。保留单行 `tok/s` 与紧凑模式，玛奇玛原画、固定节奏和 0.6.4 已完成的火焰移除保持不变。

版本为 0.6.5 / build 14。2026-10-30 已完成动作与资源检查、菜单栏实机检查、本机安装和 DMG 只读挂载验证。安装位置为 `/Applications/EmberCat.app`；安装状态、PID 和保存的偏好均以当日验收快照为准。

- [本地安装包](dist/EmberCat-0.6.5.dmg)；[0.6.4 回退安装包](dist/EmberCat-0.6.4.dmg)。
- [完整验收记录](work/cat-motion-0.6.5/verification.md)：检查日志、实机截图、安装与包内文件一致性、DMG 校验值。
- 生产渲染预览：[四种动作](work/cat-motion-0.6.5/preview/cat-actions.gif)、[收拢与展开](work/cat-motion-0.6.5/preview/cat-sequence.gif)、[平滑加减速](work/cat-motion-0.6.5/preview/cat-ramp.gif)。预览使用独立模拟速度。

以上交付文件位于本地 `dist/` 和 `work/`，两目录均被 `.gitignore` 排除；仅取得源码时，可按下方命令重建应用与预览。

## 0.6.4 修复

移除「刘海火焰」和「火焰设置与预览…」，取消火焰自动启动以及命令行预览、导出入口，避免再触发该功能导致的菜单栏消失问题。升级启动时清除旧火焰开关，保留形象和菜单栏显示偏好。发布应用不编译火焰代码，也不包含火焰资源；相关源码、原画和离线脚本暂留在项目中，不进入运行包。

## 测速来源

点击菜单栏图标先显示菜单，再选择「Token 来源」进入同一个浮层中的双栏页面，点击外部或按 Esc 关闭。左侧显示本机已发现来源的应用 logo、名称和当前 `tok/s`；右侧显示选中来源的输出速度、估算份额、今日输出 token、今日会话、生成/工具状态及本地记录位置。初次打开优先选择有输出的来源，手动选择后不会随速度变化自动跳走。左上角返回菜单。

13 类来源均配有 logo。Codex、Claude Desktop 和 Antigravity 优先使用本机已安装应用的图标，其余使用随应用打包的图标，不在运行时下载。WorkBuddy AI 与 WorkBuddy 共用品牌图标。

保留 Agent Speed 的本地 transcript 监控核心，以约 3 秒窗口的输出速率选择出行动作，可能包含估算份额。来源速度直接读取同一快照的 `SourceStatus.live.output`，与总速度使用相同窗口，不使用今日累计量或可见 Agent 列表代替。非零估算部分单独显示数值和比例。发现目录但尚无会话时显示「今日暂无会话」；扫描中、格式不支持和读取位置不可用也分别标注。

「已发现来源」是可用来源类型数量，不表示同时运行的 Agent 数量。Claude Code 和 Claude Desktop 可能共用记录目录，仍按核心识别的来源分别统计。

## 构建与检查

macOS 14+，Apple Silicon，Xcode Command Line Tools。

从项目根目录运行。`build-app.sh` 生成并以 ad-hoc 签名 `dist/EmberCat.app`，随后直接运行打包应用的资源检查；图标检查需要可访问 macOS 图形会话。Python 素材检查和 GIF 工具需要 Pillow。

```sh
./build-app.sh
./scripts/check-animation.sh
./scripts/check-cat-motion.sh
./scripts/check-motion.sh /tmp/embercat-motion-trace.json
python3 scripts/check-motion-art.py /tmp/embercat-art-check.json
dist/EmberCat.app/Contents/MacOS/EmberCat --check-assets
```

打开原生动作预览窗口：

```sh
dist/EmberCat.app/Contents/MacOS/EmberCat --preview-motion
```

导出预览素材，并生成黑猫 GIF 与姿势对照图：

```sh
dist/EmberCat.app/Contents/MacOS/EmberCat --export-motion-preview /tmp/embercat-review
dist/EmberCat.app/Contents/MacOS/EmberCat --export-cat-preview /tmp/embercat-cat-review
python3 scripts/render-cat-review.py /tmp/embercat-cat-review /tmp/embercat-cat-gifs
```

原画和提示词在 `Artwork/`，猫的提示词为 `Artwork/Prompts/cat-master-v3.txt`。`scripts/motion_rigs.py` 定义猫的动作并提供共用图像变换；`scripts/pixelfx/human-gait.mjs` 独立编排人物步态，`gait_art.py` 绘制连续的肢体与衣服轮廓。`scripts/prepare-pets.py --cat-only` 只重建黑猫。若执行不带参数的 `prepare-pets.py`，它会恢复旧版玛奇玛资源，随后必须依次运行上方四个 PixelFX 渲染命令，才能重建本分支的 3252 张菜单栏 PNG；放大预览另有 1393 张 PNG（包含黑猫走路与 180 张过渡关键帧）。

`check-motion-art.py` 检查猫的支撑与循环、圆球转动、收拢精确首尾姿势、全部模板格式、原画对照与新走路资源哈希。`scripts/pixelfx/check-makima.py` 检查骨长、脚步支撑、96 帧差异、循环接缝和来源哈希。`scripts/pixelfx/check-vehicles.py` 检查两个动作各 144 张不同帧、三位文件名顺序、接地扬尘可见性与方向、画布边界、首尾衔接及高分辨率资源哈希。`gait_checks.py` 还检查脚底支撑、膝盖方向、轮滑收腿及滑板蹬地/双脚滑行的板面接触。这些检查不代替对动作观感的视觉判断。

`check-cat-motion.sh` 检查猫的相位连续性、加减速上限、不同刷新率的一致性、边界防抖、转正后展开、过渡中的最新速度、全部动作之间的往返以及停止计时器。`check-motion.sh` 保留玛奇玛全部 90 个有方向状态组合、跳速、过渡、防抖与固定节奏的回归检查。

`--check-assets` 加载全部稳态与过渡资源，验证 1×/2× 图像和菜单栏裁剪不丢失任何非透明像素；验证猫的六种有方向过渡、相同步态下高 tok/s 的实际播放加速，以及玛奇玛 90 个方向的合成和 5400 次固定节奏帧比较。它还检查 13 类来源的内置及显示图标、资源目录缺失时的回退、图标文件不可读时的回退，避免本机已安装的来源应用掩盖安装包漏图的问题。`--export-cat-preview` 使用生产状态机和渲染器，导出四动作、完整收拢/展开、连续加减速的 60 Hz PNG 和状态记录；`scripts/render-cat-review.py` 可据此生成实际尺寸与放大演示 GIF。预览速度明确标记为模拟，不写入真实测速记录。

`--export-motion-preview` 保留玛奇玛完整跳速 PNG 与状态记录，每个稳态动作至少展示两个完整循环；`cadence/` 导出其全部十种状态的低/高 tok/s 对照素材。

## 来源

测速核心来自 Agent Speed，见 `Vendor/AGENT-SPEED-LICENSE`；zstd 见 `Vendor/CZstd/LICENSE`。猫是本项目原创形象；玛奇玛为用户指定角色的同人图像，原画由项目既有生图流程生成；本分支从原画派生连续动作与菜单栏透明模板。PixelFX 为离线骨架、确定性随机与缓动依赖，许可见 `Vendor/PixelFX/LICENSE`。

来源 logo 的文件、上游版本、哈希及随附许可保存在 `Sources/EmberCat/Resources/SourceIcons/`；详见 `provenance.json`。图标来自 LobeHub、oh-my-pi 和 ZCode，用于标识对应来源。
