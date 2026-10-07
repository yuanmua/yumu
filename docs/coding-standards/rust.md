# Rust 代码规范（Heartwood）

## 1. 工具链

- Edition 2024，MSRV 为当前 stable 减两个版本，写在 `rust-toolchain.toml` 与 `Cargo.toml` 的 `rust-version`。
- 格式化：`cargo fmt`，使用仓库根的 `rustfmt.toml`，不允许本地覆盖。
- Lint：`cargo clippy --workspace --all-targets -- -D warnings`，clippy 配置在 `Cargo.toml` 的 `[workspace.lints]`，启用 `clippy::pedantic` 并显式允许少数噪音项。
- 依赖审计：`cargo deny check`，许可证白名单 MIT、Apache-2.0、BSD、ISC、MPL-2.0、Zlib、Unicode。
- 以上全部在 CI 强制，本地用 `just check` 一键跑。

## 2. Workspace 结构

- 三个 crate：`heartwood`（核心库，按模块组织）、`grain`（C ABI）、`yumu`（命令行）。模块超过约 2000 行再拆 crate，见 ADR 0004。
- 模块依赖方向见架构文档，不允许反向引用。
- 公共依赖版本统一在 `[workspace.dependencies]` 声明，子 crate 用 `workspace = true`。

## 3. 核心依赖选型

| 用途 | 选择 | 禁止 |
|---|---|---|
| 异步运行时 | tokio | async-std |
| HTTP | reqwest + rustls | 任何链接 OpenSSL 的配置 |
| 序列化 | serde、serde_json、toml | |
| 错误 | thiserror（库）、anyhow（仅二进制与测试） | 在库 crate 用 anyhow |
| 日志 | tracing | log、println |
| SQLite | rusqlite（bundled），Mod 阶段再引入 | sqlx |
| 哈希 | sha1、sha2、自写 murmur2 | |
| 压缩 | zip、flate2 | |
| 凭据 | keyring | 自己写文件 |
| CLI | clap（derive） | |
| 测试 HTTP | wiremock | 真实网络 |

白名单与准入门槛见 ADR 0007。新增依赖须在 PR 描述里逐条对照门槛说明，并给出二进制体积影响。

## 4. 错误处理

- 每个 crate 一个公开 `Error` 枚举，用 thiserror。
- 每个变体对应 Grain 的一个 `kind`，`Error::kind()` 返回它，`grain` crate 负责序列化。
- 用 `#[source]` 保留底层错误链，用 `#[error("...")]` 写给开发者看的英文消息。
- 禁止在库代码里 `unwrap()`、`expect()`、`panic!()`。测试代码除外。不可能失败的地方用 `expect("why this cannot fail")` 并写明原因。
- 禁止 `as` 做有损数值转换，用 `try_from`。

## 5. 异步与并发

- 所有 IO 函数是 `async fn`，接收 `CancellationToken` 或通过任务系统取消。
- 阻塞操作（zip 解压、哈希大文件、SQLite）放 `spawn_blocking`。
- 共享状态优先用消息传递；必须共享时用 `Arc<Mutex>` 或 `RwLock`，锁的持有范围不能跨 `await`。
- 不用 `static mut`，不用全局可变单例。配置与依赖通过构造函数注入。

## 6. 模块与可见性

- 默认私有，只 `pub` 真正需要跨 crate 的类型与函数。
- 每个 crate 的 `lib.rs` 只做 re-export 与文档，不写逻辑。
- 接口（trait）定义在使用方 crate，实现在提供方 crate。模块之间同理：`ModProvider` trait 定义在使用它的模块里。

## 7. 命名

- 类型 `UpperCamelCase`，函数与变量 `snake_case`，常量 `SCREAMING_SNAKE_CASE`。
- 与 Grain 字段对应的结构体字段用 `snake_case`，序列化时 `#[serde(rename_all = "camelCase")]`。
- 不缩写：`instance` 不写 `inst`，`version` 不写 `ver`。例外：`id`、`url`、`uuid`。

## 8. 文档与注释

- 所有 `pub` 项必须有 `///` 文档注释，CI 开 `missing_docs`。
- 注释写为什么，不写是什么。代码本身应当说明是什么。
- 文档里的示例代码用 `cargo test --doc` 跑。

## 9. 测试

- 单元测试放在同文件 `#[cfg(test)] mod tests`。
- 集成测试放 `tests/`，外部 API 用 wiremock 录制的 fixture，fixture 文件放 `tests/fixtures/`。
- 表驱动测试：多组输入用数组加循环，不复制粘贴测试函数。
- 文件系统测试用 `tempfile`，不碰真实数据目录。
- 覆盖率不设硬指标，但 `download`、`rules`、`launch` 的参数组装必须有测试。

## 10. 日志

- 用 `tracing` 的结构化字段，不拼字符串：`info!(instance_id = %id, "instance created")`。
- 级别：`error` 需要用户介入，`warn` 自动恢复了但值得注意，`info` 关键生命周期事件，`debug` 开发用，`trace` 高频细节。
- 永不记录 token、密码、邮箱。URL 中的 query 参数一律脱敏。

## 11. 二进制体积

release profile 固定为：

```toml
[profile.release]
opt-level = "z"
lto = "fat"
codegen-units = 1
panic = "unwind"   # C 边界要 catch_unwind，不能 abort
strip = true
```

CI 记录每次构建的体积并在 PR 评论里标出变化，增长超过 300 KB 需要说明。
