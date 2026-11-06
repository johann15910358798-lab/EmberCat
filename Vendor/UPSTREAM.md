# Upstream

Agent Speed: https://github.com/zoefix/agent-speed

Inspected commit: a94a67fcc78e5d8eea5f82d8d5e737bccf994e2c

`AgentSpeedCore` and `CZstd` were copied unchanged from `macos/Sources` at this commit.

EmberCat integrates the core through [SpeedMonitorModel.swift](../Sources/EmberCat/SpeedMonitorModel.swift). Source discovery and token measurements follow [METRICS.md](METRICS.md). Build and validation commands are in the [development guide](../docs/development.md); published versions are listed in [GitHub Releases](https://github.com/johann15910358798-lab/EmberCat/releases).

The Agent Speed MIT license is in `AGENT-SPEED-LICENSE`. The zstd BSD license and vendoring notes are inside `CZstd`.
