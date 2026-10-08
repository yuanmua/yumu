# 路线图

## 阶段 0：规划（已完成）

架构、接口契约、代码规范、ADR、CLAUDE.md。

## 阶段 1：macOS 原版能跑（进行中）

- [x] Heartwood 核心：平台层、下载器、Mojang 清单、Java 运行时、实例、安装、启动、离线账号。
- [x] `yumu` 命令行：`play`、`instance list`、`version list`。
- [x] 验收：在这台 Mac 上一条命令从零下载并启动最新正式版（26.3，2026-10-08 实测）。
- [ ] 旧版本（1.12 及以前的 `minecraftArguments` 格式）实测。
- [ ] 下载断点续传（目前失败的文件整个重下）。

## 阶段 2：本机发现与账号（进行中）

- [x] `discover.scan`：扫描官方启动器的版本与存档、Prism / MultiMC / Modrinth App 的存档、本机 Java；存档一键拷贝进实例。
- [x] `account.*`：微软设备码登录（Azure 应用已注册）、令牌刷新、离线账号按 ADR 0009 的规则。
- [ ] Mojang API 接入申请（软件功能完整后提交）。
- [x] Grain C ABI 层与头文件。

## 阶段 3：macOS 界面（进行中）

- [x] Swift Package + `build.sh` 产出 `Yumu.app`，链接 Rust 静态库，零第三方依赖。
- [x] 实例列表、详情、新建、删除，安装进度与运行状态，空状态引导。
- [x] 三语翻译（en、zh-Hans、ja）跟随系统语言；Bark 令牌生成。
- [x] 应用图标（`bark/icon/make-icon.swift` 程序化绘制，原木端面）。
- [x] 实例高级设置：名称、内存、Java（自动 / 本机检测到的 / 自定义路径）、JVM 参数、窗口大小，默认折叠。
- [x] 单一构建产物 `dist/Yumu.app`，命令行工具随包携带。
- [ ] 通用二进制（arm64 + x86_64）。
- [ ] 账号与本机发现的界面（等阶段 2）。
- [ ] 崩溃报告分类展示。
- [ ] 签名、公证、Sparkle 更新。

## 阶段 4：Mod 与整合包（进行中）

- [x] Fabric、Quilt 加载器：meta 服务器取 profile，版本 JSON 继承合并，首次安装时固定加载器版本。
- [x] Modrinth 搜索、安装、必需依赖自动解析；本地模组列表读取 jar 元数据；启用、禁用、移除。
- [x] `.mrpack` 导入：下载源白名单、路径穿越防护、overrides 解压、失败自动回滚实例。
- [x] 光影包与资源包的添加、启用、禁用、移除。
- [x] 界面：模组页（已安装 + 搜索安装）、资源页（含 Modrinth 搜索）、新建实例选加载器、拖入 `.mrpack` 或按钮导入、整合包浏览器、侧栏账号切换与微软登录。
- [x] Forge、NeoForge（1.13+）：下载安装器，解出 profile，在核心内用实例的 Java 跑客户端处理器，结果缓存一次。合并版本 JSON 时按 组:构件 去重库。
- [x] 五种实例在 1.21.1 上实测启动到主界面（见提交记录）。
- [x] Modrinth 搜索下载扩展到光影、资源包、整合包；整合包浏览器一键装成实例。
- [ ] CurseForge（需要 API key；禁止分发的文件跳转浏览器）。
- [ ] Forge 1.12 及更早（旧版安装器格式）。
- [ ] 模组更新检测、按哈希识别用户手动放入的模组。
- [ ] 整合包导出为 `.mrpack`。
- [ ] 显式"修复"操作：全量校验缓存哈希（日常启动只比对大小）。

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
| 微软登录需要 Mojang 审核 client ID | 已注册 Azure 应用；审批前用 `./build.sh dev` 的离线账号测试，网站搭好后再提交申请 |
| CurseForge API key 与第三方下载限制 | 禁止下载的文件跳转浏览器 |
| Windows 代码签名证书成本 | 阶段 5 前评估 Azure Trusted Signing |
| Forge 安装器处理器实现复杂 | 先 Fabric 后 Forge |
