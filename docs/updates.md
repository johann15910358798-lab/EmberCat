# Sparkle 与 GitHub Releases

客户端从最新正式 Release 的 `appcast.xml` 检查更新。每个更新条目的下载地址固定到对应版本的 ZIP，避免后续 Release 改变已公布安装包的内容。首次接入版本为 0.6.15；旧版需要手动安装一次。

## 应用配置

- `Package.swift` 固定 Sparkle 2.10.1，`Package.resolved` 记录提交；SwiftPM 校验二进制依赖摘要。
- `Resources/Info.plist` 配置 HTTPS 更新地址、EdDSA 公钥、每日检查和自动下载的初始值。之后的用户选择由 Sparkle 持久化，启动时不覆盖。
- `build-app.sh` 嵌入 Sparkle.framework 及其安装助手，保留供应方签名；应用外层仍使用 ad-hoc 签名。使用正式 Developer ID 分发时，应另行完成嵌套签名和公证流程。
- 菜单支持手动检查及自动检查、自动下载开关。后台发现更新后，菜单入口显示可用版本。
- 更新清单必须签名；更新 ZIP 必须在解压前通过签名验证。

## 签名密钥

当前签名私钥保存在本机登录钥匙串，Sparkle account 为 `com.johann.embercat`。代码仓库只保存公钥。不要重新生成或替换已发布应用所信任的密钥，也不要把私钥放入仓库、发布附件或日志。换电脑时通过 Sparkle 官方密钥工具安全迁移已有密钥。

`SPARKLE_ACCOUNT` 可选择其他已配置的钥匙串账户；准备脚本会先确认其公钥与应用配置完全一致。签名工具随固定版本的 SwiftPM 二进制依赖一起获取，不另外下载未固定的工具版本。

## 准备发布

先递增 `CFBundleShortVersionString` 和严格递增的 `CFBundleVersion`，更新对应的 `docs/releases/<版本>.md`。完成本次改动相关检查，然后执行：

```sh
./scripts/prepare-release.sh
```

脚本构建并签名应用，生成 ZIP、DMG、签名更新清单和 `SHA256SUMS.txt`，校验更新清单与 ZIP 的 EdDSA 签名、DMG 完整性，以及 ZIP 内每个文件和符号链接与构建应用的一致性。产物在 `dist/releases/<版本>/`。已有刚构建并验证的应用时可用 `--skip-build`；脚本仍核对源配置及包内版本。

此命令只准备本地文件，不创建 Git 标签、不推送、不发布。

## 发布到 GitHub

提交并推送对应源码，创建并推送与版本一致的标签。确认允许发布后，用下面的命令先建立草稿，检查其四个附件，再发布为最新正式版本。以下以首次版本为例：

```sh
gh release create v0.6.15 --verify-tag --draft \
  --title 'EmberCat 0.6.15 · 自动更新与火焰修复' \
  --notes-file docs/releases/0.6.15.md \
  dist/releases/0.6.15/EmberCat-0.6.15.dmg \
  dist/releases/0.6.15/EmberCat-0.6.15.zip \
  dist/releases/0.6.15/appcast.xml \
  dist/releases/0.6.15/SHA256SUMS.txt
gh release edit v0.6.15 --draft=false --latest
```

发布后需实际访问 `releases/latest/download/appcast.xml`，确认它指向刚发布的版本，再从安装版手动检查一次。草稿与预发布版本不会成为这条正式更新地址的目标。后续每个标为 latest 的正式 Release 都必须包含完整四个附件，否则客户端更新检查会失败。

不要修改已签名的更新清单、更新包或内嵌发布说明。需要修改时重新生成、验证并发布新版本。公钥签名验证不等同于 Apple Developer ID 签名或公证。

## 验证范围

`scripts/check-flame.sh` 验证 GPU 输出、外沿描边、横向约束及覆盖层生命周期；`scripts/check-flame-preview.sh` 在临时偏好中重走 45/80 档位编辑、保存、调速、关闭/重开，并核对实际提交帧数。它们使用明确标注的模拟速度，不修改真实测速记录。

本地签名和打包通过不代表线上更新已经发布，也不能代替未来跨版本安装的真实验证。发布状态以 GitHub Releases 和实际客户端检查为准。
