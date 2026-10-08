# Yumu

Yumu 是一个简洁、轻量、跨平台的 Minecraft 启动器。核心用 Rust 编写，界面在每个平台上用原生技术实现。

目标：

- 体积小、占用低、启动快
- 一键导入整合包，管理 Mod、光影、资源包
- 界面美观，动画流畅，操作傻瓜式

> 当前阶段：macOS 应用支持微软账号登录（等待 Mojang 审批，开发版可用离线账号），原版 / Fabric / Quilt / Forge / NeoForge 五种实例均实测可启动，从 Modrinth 搜索安装模组、光影、资源包与整合包，导入 `.mrpack`，扫描本机已有存档、版本与 Java，实例高级设置。

## 命名

| 名字 | 含义 | 职责 |
|---|---|---|
| **Yumu** | 产品名，源自（原木） | 整体品牌，命令行工具 `yumu` |
| **Heartwood** | 心材，树的核心 | Rust 核心进程，所有业务逻辑 |
| **Grain** | 木纹 | 核心对外的 C ABI 接口契约 |
| **Bark** | 树皮，最外层 | 设计令牌、视觉与动效规范、翻译源文件 |

## 仓库结构

```
yumu/
├── heartwood/   Rust workspace：核心库 heartwood、C ABI 层 grain、命令行 yumu
├── grain/       错误码登记与接口变更记录；C 头文件在 heartwood/crates/grain/include
├── bark/        设计令牌、动效规范、翻译源
├── apps/
│   ├── macos/   SwiftUI 应用
│   └── windows/ WinUI 3 应用
├── docs/        所有设计文档
├── build.sh     唯一的构建入口，产出 dist/Yumu.app
└── CLAUDE.md    给 AI 与新成员的工作约定
```

## 文档索引

先读这三份：

1. [架构总览](docs/architecture.md)
2. [Grain 接口契约](docs/grain-api.md)
3. [工作约定 CLAUDE.md](CLAUDE.md)

其余：

- [数据模型与磁盘布局](docs/data-model.md)
- [平台与架构支持矩阵](docs/platform-matrix.md)
- [国际化](docs/i18n.md)
- [路线图](docs/roadmap.md)
- [开发环境](docs/dev-setup.md)
- [下载源与第三方服务合规](docs/compliance.md)
- [界面规范 Bark](bark/guidelines.md) · [效果演示](bark/preview/index.html)
- 代码规范：[Rust](docs/coding-standards/rust.md) · [Swift](docs/coding-standards/swift.md) · [Git 工作流](docs/coding-standards/git-workflow.md) · [Bark 设计令牌](docs/coding-standards/bark.md)
- [架构决策记录 ADR](docs/adr/README.md)

## 快速开始

```bash
cd heartwood && cargo run -p yumu -- play
```

或者构建 macOS 应用，产物只有一个 `dist/Yumu.app`，双击即用：

```bash
./build.sh && open dist/Yumu.app
```

第一次运行会下载 Java 运行时、游戏文件与资源，之后直接启动。详见[开发环境](docs/dev-setup.md)。

## 许可证

MIT，见 [LICENSE](LICENSE)。
