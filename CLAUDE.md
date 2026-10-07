# Yumu 工作约定（给 AI 与新成员）

改代码前先读 `docs/architecture.md` 与 `docs/grain-api.md`。本文件只列硬规则。

## 项目是什么

Yumu 是一个 Minecraft 启动器。Rust 核心库 Heartwood 包含全部逻辑，编译为静态库链接进原生界面（macOS SwiftUI、Windows WinUI 3），对外只暴露一份手写 C 头文件 Grain。命令行 `yumu` 链接同一核心。

## 目录

- `heartwood/crates/heartwood` 核心库，按模块组织，不要过早拆 crate
- `heartwood/crates/grain` C ABI 层与手写头文件
- `heartwood/crates/yumu` 命令行
- `apps/macos` SwiftUI 应用
- `bark/` 设计令牌与翻译源
- `docs/` 设计文档与 ADR

## 代码风格

- 简洁优先。不写用不到的抽象、配置项、trait、feature。一个功能能用 50 行写完就不要写 150 行。
- 不加注释解释代码在做什么，只在"为什么这么做"不明显时写一句。
- 不写防御性代码处理不可能发生的情况。
- 公开 API 才需要文档注释。
- 命名不缩写，`instance` 不写 `inst`。

## Rust 硬规则

- `cargo fmt`、`cargo clippy --all-targets -- -D warnings`、`cargo test` 三个全过才算完成。
- 库代码禁止 `unwrap`、`expect`、`panic!`、`as` 有损转换。
- 错误用 `thiserror`，每个变体对应一个 Grain 错误 `kind`。`anyhow` 只在 `yumu` 二进制与测试里用。
- 所有 IO 是 `async fn`，阻塞操作放 `spawn_blocking`。
- 日志用 `tracing`，不用 `println!`（CLI 的用户输出除外）。永不记录 token。
- 平台差异放 `platform/` 下按 `cfg(target_os)` 选文件，业务代码里不写 `cfg`。
- 核心不含任何面向用户的文案，只返回 `kind` 与 `args`。

## 稳定性硬规则

- 写文件先写 `.part` 再重命名，下载的文件哈希校验通过才重命名。
- 网络请求必须有连接超时与读超时，失败指数退避重试三次。
- 解压防路径穿越。
- `cache/` 必须可整体删除后自动重建。
- 游戏进程分离拉起，输出直接写日志文件，不走管道。

## 第三方依赖

见 `docs/adr/0007-dependency-gate.md`。白名单之外的 crate 不要加。领域逻辑自己写。

## 文档

- 改了行为就改对应文档，同一个 PR。
- 重要决定写 ADR，`docs/adr/0000-template.md`。
- 文档、提交信息、PR 描述用中文；代码、标识符、代码注释、日志用英文。

## 提交

Conventional Commits，`type(scope)` 英文，标题与正文中文。scope 用 `heartwood`、`grain`、`yumu`、`macos`、`bark`、`docs`。正文写为什么和怎么验证的，不复述代码。详见 `docs/coding-standards/git-workflow.md`。

提交信息和 PR 描述里不加任何 AI 署名或生成痕迹（没有 `Co-Authored-By`、`Generated with` 之类的行）。作者就是提交的人。

## 完成一个任务前自查

1. 三个检查命令都过了吗。
2. 有没有多余的代码、注释、依赖。
3. 文档改了吗。
4. 真的跑过了吗，不是只编译过。
