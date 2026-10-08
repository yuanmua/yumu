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
cargo run -p yumu -- account login  # 微软账号登录；开发期可用 --features dev-offline 后 account offline <名字>
cargo run -p yumu -- play            # 最新正式版，当前账号，装好就启动
cargo run -p yumu -- play --version 1.21.1 --name 生存 --player Steve
cargo run -p yumu -- play --version 1.21.1 --name 模组 --loader fabric
cargo run -p yumu -- mod search 模组 sodium
cargo run -p yumu -- mod install 模组 sodium-extra   # 会一并装上依赖 sodium
cargo run -p yumu -- mod list 模组
cargo run -p yumu -- modpack import ~/Downloads/pack.mrpack
cargo run -p yumu -- instance create 测试 --version 1.21.1 --loader neoforge
cargo run -p yumu -- instance install 测试        # 只下载安装，不启动
cargo run -p yumu -- discover                     # 本机已有的存档、版本与 Java
cargo run -p yumu -- instance list
cargo run -p yumu -- version list
```

数据目录默认在 `~/Library/Application Support/Yumu`，可用 `YUMU_DATA_DIR` 环境变量指到别处，测试时建议指向临时目录。

## 构建产物只有一个

```bash
./build.sh        # 正式版
./build.sh dev    # 开发版：允许不登录直接添加离线账号，用于 Mojang 审批前的测试
```

产物是 `dist/Yumu.app`，双击即用，已做 ad-hoc 签名。命令行工具在包内：

```bash
dist/Yumu.app/Contents/MacOS/yumu-cli play --name 我的实例
```

脚本依次做：编译 Rust 核心静态库与命令行、生成翻译与设计令牌、从 `bark/icon/make-icon.swift` 画应用图标、`swift build`、组装并签名应用包。改了 `bark/` 下任何源文件后重新跑脚本，生成文件要一起提交。

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
