# 0007. 第三方依赖准入门槛

状态：接受
日期：2026-10-08

## 背景

项目不接受维护状况不明的社区代码。但任何语言写网络程序都不该自己写 TLS，依赖不可能为零，问题是依赖谁。

## 决定

每个第三方依赖必须同时满足：

1. 由基金会或多家公司共同维护，不是个人项目。
2. 被大型生产系统使用。
3. 过去一年有发布，有安全响应流程。
4. 许可证在白名单内（MIT、Apache-2.0、BSD、ISC、MPL-2.0、Zlib、Unicode）。

当前白名单：tokio、reqwest（rustls）、serde、serde_json、toml、sha1、sha2、zip、clap、thiserror、anyhow、tracing、tracing-subscriber、uuid、rusqlite（引入时再评估）。

不在白名单又确实需要的，写 ADR 并 vendoring 进仓库，视为自己的代码维护。其余领域逻辑（murmur2、Forge 安装器处理、整合包格式、下载调度、镜像探测）一律自己写。

## 后果

- 新增依赖的 PR 必须引用本 ADR 并逐条说明。
- `cargo deny` 在 CI 强制许可证与安全公告检查。
