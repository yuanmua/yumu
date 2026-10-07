# 路线图

## 阶段 0：规划（已完成）

架构、接口契约、代码规范、ADR、CLAUDE.md。

## 阶段 1：macOS 原版能跑（进行中）

- [x] Heartwood 核心：平台层、下载器、Mojang 清单、Java 运行时、实例、安装、启动、离线账号。
- [x] `yumu` 命令行：`play`、`instance list`、`version list`。
- [x] 验收：在这台 Mac 上一条命令从零下载并启动最新正式版（26.3，2026-10-08 实测）。
- [ ] 旧版本（1.12 及以前的 `minecraftArguments` 格式）实测。
- [ ] 下载断点续传（目前失败的文件整个重下）。

## 阶段 2：本机发现与账号

- `discover`：扫描官方与第三方启动器的版本与存档。
- 微软账号登录（需要 Azure 应用注册）。
- Grain C ABI 层与头文件。

## 阶段 3：macOS 界面

- SwiftUI 应用，Bark 令牌与动效，实例列表与详情，首次启动引导。
- 签名、公证、Sparkle 更新。

## 阶段 4：Mod 与整合包

- Fabric、Quilt 安装；Modrinth 搜索与安装；`.mrpack` 导入。
- Forge、NeoForge；CurseForge（需要 API key）。
- 光影、资源包管理。

## 阶段 5：Windows

- WinUI 3 界面，Native AOT 单文件。
- 代码签名方案。

## 阶段 6：Linux 与小众架构

- natives 覆盖表、第三方 Java 提供者。
- GTK4 界面或仅命令行。

## 远期

- 基岩版（数据模型已预留）。
- 便携模式。

## 已知风险

| 风险 | 处理 |
|---|---|
| 微软登录需要 Azure 应用注册并通过 Mojang 审核 | 阶段 2 前申请 |
| CurseForge API key 与第三方下载限制 | 禁止下载的文件跳转浏览器 |
| Windows 代码签名证书成本 | 阶段 5 前评估 Azure Trusted Signing |
| Forge 安装器处理器实现复杂 | 先 Fabric 后 Forge |
