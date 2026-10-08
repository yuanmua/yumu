# Yumu 架构总览

## 1. 一句话

一个 Rust 核心库（Heartwood）包含全部业务逻辑，编译成静态库直接链接进每个平台的原生应用（macOS SwiftUI、Windows WinUI 3），对外只暴露一份手写的 C 头文件（Grain）。最终产物是单个应用文件。

```
┌──────────────────────────────────────────────────────┐
│  Yumu.app  /  Yumu.exe        （单个可执行文件）         │
│                                                      │
│  ┌──────────────────┐   C ABI (Grain)   ┌───────────┐ │
│  │ 原生界面          │◄────────────────►│ Heartwood  │ │
│  │ Swift / C#       │  直接函数调用       │ Rust 静态库 │ │
│  └──────────────────┘   回调推送事件      └─────┬─────┘ │
└───────────────────────────────────────────────┼───────┘
                                                │ 分离拉起
                                                ▼
                                         Java / Minecraft
```

命令行工具 `yumu` 是另一个二进制，链接同一个核心库，用于调试、自动化和没有图形界面的平台。

## 2. 关键决定

| 关注点 | 决定 | ADR |
|---|---|---|
| 核心语言 | Rust | 0001 |
| 核心与界面的边界 | 进程内静态库 + 手写 C ABI，复杂数据以 JSON 字符串跨边界，不用任何绑定生成器 | 0002 |
| 界面技术 | 每平台原生，macOS 先行 | 0003 |
| 仓库与代码组织 | 单仓库；核心先是一个 lib crate，模块超过约 2000 行再拆 crate | 0004 |
| 命名 | Yumu / Heartwood / Grain / Bark | 0005 |
| 存储 | 每实例一个 TOML + 共享可丢弃缓存 | 0006 |
| 第三方依赖 | 四条准入门槛，白名单约十个 crate，其余自己写 | 0007 |
| 文案 | 核心零自然语言，界面翻译 | 0008 |

## 3. 代码组织

```
heartwood/
├── Cargo.toml              workspace
└── crates/
    ├── heartwood/          核心库，一个 crate，按模块划分
    │   └── src/
    │       ├── lib.rs
    │       ├── error.rs    统一 Error 枚举，每个变体对应一个 Grain 错误 kind
    │       ├── platform/   mod.rs 选平台，macos.rs / windows.rs / linux.rs 编译期择一
    │       ├── download.rs 并发下载、重试、哈希校验、原子写入
    │       ├── mojang.rs   版本清单、版本 JSON、资源索引、Java 运行时清单的数据类型与拉取
    │       ├── rules.rs    版本 JSON 的 OS / 架构 / feature 规则求值
    │       ├── java.rs     Mojang 运行时安装、系统 Java 探测
    │       ├── instance.rs 实例模型与 TOML 读写
    │       ├── install.rs  把一个实例补齐到可启动：版本、库、资源、natives、Java
    │       ├── launch.rs   组装参数、拉起游戏、日志落盘
    │       ├── account.rs  账号列表与会话；离线账号规则见 ADR 0009
│       ├── auth.rs     微软设备码登录与令牌刷新
│       ├── loader.rs   Fabric、Quilt 的 profile
│       ├── forge.rs    Forge、NeoForge 安装器与处理器
│       ├── mods.rs     Modrinth 搜索、安装、依赖解析，本地模组列表
│       ├── modpack.rs  .mrpack 导入
│       ├── resource.rs 光影包与资源包
│       ├── discover.rs 本机已有的存档、版本与 Java
│       ├── crash.rs    崩溃原因分类
    │       └── discover.rs 识别本机已有的 Minecraft 安装与存档
    ├── grain/              C ABI 层：extern "C" 函数、句柄、回调、JSON 编解码。头文件 include/grain.h 手写
    └── yumu/               命令行二进制
```

依赖方向：`yumu` → `heartwood`；`grain` → `heartwood`。`heartwood` 不依赖另外两个。

模块之间的依赖方向：`launch`、`install`、`discover` → `instance`、`java`、`mojang`、`download` → `platform`、`error`。不允许反向引用。

## 4. 平台差异在编译期解决

`platform/mod.rs` 按 `cfg(target_os)` 引入一个实现文件，暴露同一组函数。不该出现在某个平台二进制里的代码根本不参与编译。

| 能力 | macOS | Windows | Linux |
|---|---|---|---|
| 数据目录 | `~/Library/Application Support/Yumu` | `%APPDATA%\Yumu` | `$XDG_DATA_HOME/yumu` |
| 日志目录 | `~/Library/Logs/Yumu` | `%LOCALAPPDATA%\Yumu\Logs` | `$XDG_STATE_HOME/yumu/logs` |
| 官方启动器目录 | `~/Library/Application Support/minecraft` | `%APPDATA%\.minecraft` | `~/.minecraft` |
| 版本 JSON 里的 OS 名 | `osx` | `windows` | `linux` |
| Mojang 运行时平台键 | `mac-os` / `mac-os-arm64` | `windows-x64` / `windows-arm64` | `linux` / `linux-i386` |
| 缓存到实例的零拷贝 | APFS clonefile | 硬链接 | reflink，回退硬链接 |
| 凭据存储 | `accounts.toml` 0600（钥匙串为后续改进） | 同左 | 同左 |
| 游戏进程分离 | 独立进程组 | 不加入 Job 对象 | 独立进程组 |

可选能力用 Cargo feature 开关，不需要的构建直接裁掉。目前只有一个：`dev-offline`（开发版放开离线账号限制），`./build.sh dev` 打开。

## 5. 核心的运行模型

- 核心内部持有一个 tokio 运行时，由 `grain_init` 创建，`grain_shutdown` 销毁。
- 快速查询（列实例、读设置）是同步函数，直接返回 JSON。
- 耗时操作（安装、启动、导入）立即返回任务 id，进度与结果通过回调推送。
- 回调从核心线程触发，界面负责切回主线程。
- 游戏进程以分离方式拉起，标准输出直接重定向到实例日志文件，不经过管道。这样启动器退出、崩溃都不会影响游戏。

## 6. 稳定性原则

这些是写代码时的硬规则，不是建议：

1. **所有写盘先写临时文件再重命名**，刚下载的文件校验哈希通过后才重命名到位。已在缓存里的文件日常只比对大小，不逐个哈希，全量校验留给显式的修复操作。
2. **所有网络请求有连接超时与读超时**，失败按指数退避重试三次。
3. **缓存可随时整体删除**，删了只是变慢。用户数据只在 `instances/`。
4. **核心永不 panic 到界面**：C ABI 边界 `catch_unwind`，转成 `INTERNAL` 错误。
5. **解压任何压缩包都防路径穿越**。
6. **同一实例同时只允许一个安装类任务**，用内存锁；跨进程用目录锁文件。
7. **版本 JSON 中不认识的字段原样保留**，TOML 中不认识的键原样保留。

## 7. 面向新用户的自动化

目标用户打开 Yumu 时什么都不用懂：

- 首次启动扫描本机：官方启动器目录、常见第三方启动器目录（Prism、MultiMC、HMCL、PCL、Modrinth App），列出已有的存档与版本，一键导入或直接引用。
- 没有任何现成内容时，首页只有两个按钮：「开始游戏」（最新正式版，自动装 Java）与「导入整合包」。
- Java 缺失、版本不匹配一律自动处理，不弹技术性对话框。
- 崩溃后把崩溃报告分类成人话：内存不足、Mod 冲突、Java 不匹配、显卡驱动。

## 8. 分发形态

- macOS：一个 `Yumu.app`，Developer ID 签名加公证，拖进任何位置都能打开。不走 App Store，不启用沙盒。
- Windows：一个 `Yumu.exe`，.NET Native AOT 把核心静态库与界面合成单文件。
- 用户数据默认放在系统标准目录，应用文件本身随时可复制、可移动。后续提供便携模式：应用旁边存在 `yumu-portable` 标记文件时，数据放在应用旁边。

## 9. 性能目标

| 指标 | 目标 |
|---|---|
| 冷启动到可交互 | < 1 秒 |
| 空闲内存 | < 60 MB |
| 应用体积（macOS，含核心） | < 15 MB |
| 1.21 原版全新安装 | 瓶颈只在带宽 |
