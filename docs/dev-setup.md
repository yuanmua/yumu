# 开发环境

## 安装

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
rustup component add rustfmt clippy
```

macOS 界面开发另需 Xcode 15 以上。

## 构建与运行

```bash
cd heartwood
cargo build
cargo run -p yumu -- play            # 最新正式版，离线账号，装好就启动
cargo run -p yumu -- play --version 1.21.1 --name 生存 --player Steve
cargo run -p yumu -- instance list
cargo run -p yumu -- version list
```

数据目录默认在 `~/Library/Application Support/Yumu`，可用 `YUMU_DATA_DIR` 环境变量指到别处，测试时建议指向临时目录。

## 提交前检查

三条全过才算完成：

```bash
cargo fmt --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test
```

## 网络不通畅时

- 代理对 HTTP/2 处理不好会让 cargo 拉取索引极慢，加 `CARGO_HTTP_MULTIPLEXING=false`。
- rustup 下载慢可换镜像：`RUSTUP_DIST_SERVER=https://mirrors.ustc.edu.cn/rust-static RUSTUP_UPDATE_ROOT=https://mirrors.ustc.edu.cn/rust-static/rustup`。
- Heartwood 自己的下载固定用 HTTP/1.1 多连接，不受此影响。
