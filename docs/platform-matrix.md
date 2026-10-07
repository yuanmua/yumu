# 平台与架构支持矩阵

## 1. 支持等级定义

| 等级 | 含义 |
|---|---|
| **T1** | CI 构建并自动测试，发布预编译包，问题优先修 |
| **T2** | CI 构建，发布预编译包，社区反馈驱动修复 |
| **T3** | 能从源码构建，不发布包，不保证 |
| **—** | 不支持 |

## 2. 启动器本身（Heartwood + UI）

| OS | 架构 | Heartwood | UI | 等级 |
|---|---|---|---|---|
| macOS 14+ | arm64 | ✓ | SwiftUI | T1 |
| macOS 14+ | x86_64 | ✓ | SwiftUI | T1 |
| Windows 10 1809+ | x86_64 | ✓ | WinUI 3 | T1（第二阶段） |
| Windows 11 | arm64 | ✓ | WinUI 3 | T2 |
| Linux glibc | x86_64 | ✓ | GTK4（待定） | T2（后期） |
| Linux glibc | aarch64 | ✓ | GTK4 | T2 |
| Linux glibc | riscv64 | ✓ | GTK4 | T3 |
| Linux glibc | loongarch64 | ✓ | GTK4 | T3 |
| Linux glibc | ppc64le | ✓ | GTK4 | T3 |
| Linux musl | 任意 | ✓ | 仅 CLI | T3 |

Heartwood 单独作为 CLI 可以在没有 UI 的平台上使用，这也是小众架构的第一步。

## 3. 游戏运行时（Java + LWJGL natives）

启动器能跑不等于游戏能跑。游戏要三样东西：该架构的 JVM、该架构的 LWJGL natives、能跑 OpenGL 的驱动。

| 平台 | Mojang JRE | LWJGL 官方 natives | 我们的做法 |
|---|---|---|---|
| macOS arm64 / x86_64 | 有 | 有 | 直接用 |
| Windows x86_64 | 有 | 有 | 直接用 |
| Windows arm64 | 有 | 有（LWJGL 3.3+） | 旧版本游戏用覆盖表替换 LWJGL |
| Linux x86_64 | 有 | 有 | 直接用 |
| Linux aarch64 | 有 | 有（3.3+） | 旧版本用覆盖表 |
| Linux riscv64 | 无 | 有（3.3.4+） | 系统 Java 或第三方 JDK + 覆盖表 |
| Linux loongarch64 | 无 | 无官方 | 系统 Java（龙芯 JDK）+ 社区 natives 覆盖表 |
| Linux ppc64le | 无 | 有（定制构建） | 系统 Java + 覆盖表 |

## 4. natives 覆盖表

数据文件 `heartwood/crates/heartwood/src/platform/natives.toml`，纯数据，社区可提 PR。

```toml
# 规则按顺序匹配，第一条命中生效
[[rule]]
os = "linux"
arch = "riscv64"
game_version = ">=1.13 <1.21"          # semver 范围，支持 Minecraft 版本比较
replace_lwjgl = "3.3.4"                 # 把版本 JSON 里的 LWJGL 全部替换为此版本
natives_source = "https://.../lwjgl-3.3.4-linux-riscv64.zip"
natives_sha1 = "..."

[[rule]]
os = "linux"
arch = "loongarch64"
game_version = ">=1.6 <1.20.2"
replace_lwjgl = "3.3.3"
natives_source = "..."
natives_sha1 = "..."
```

这张表的格式与思路参考 HMCL 的平台支持实现，初期可以直接复用社区已验证的 natives 来源。

## 5. Java 提供者

| 提供者 | 架构覆盖 | 说明 |
|---|---|---|
| `mojang` | x64、arm64（mac、win、linux） | 默认，与游戏版本精确匹配 |
| `system` | 任意 | 探测本机已装 JDK |
| `adoptium` | x64、arm64、ppc64le、s390x、riscv64（部分版本） | 小众架构的下载来源 |
| `custom` | 任意 | 用户手动指定路径 |

选择顺序：实例指定 → mojang 可用则用 mojang → 本机匹配主版本的 system → 提示用户安装。

## 6. 交叉编译

Heartwood 用 `cargo-zigbuild` 或 `cross` 交叉编译，TLS 用 rustls，SQLite 用 bundled 编译，不依赖任何系统 C 库。CI 为每个 T1、T2 目标产出二进制。
