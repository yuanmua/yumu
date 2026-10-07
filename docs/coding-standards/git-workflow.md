# Git 工作流

## 1. 分支模型

- 主干开发。`main` 受保护，只能通过 PR 合入，必须 CI 全绿并至少一人批准。
- 功能分支短生命周期，命名 `<type>/<scope>-<short-desc>`，例如 `feat/heartwood-download-resume`、`fix/macos-instance-list-flicker`。
- 不保留长期的 `develop` 分支。发布用 tag，热修在 `main` 修完后 cherry-pick 到 `release/x.y` 分支。

## 2. 提交信息

Conventional Commits：

```
<type>(<scope>): <subject>

<body>

<footer>
```

- `type`：`feat`、`fix`、`refactor`、`perf`、`docs`、`test`、`build`、`ci`、`chore`。
- `scope`：`heartwood`、`grain`、`bark`、`macos`、`windows`、`linux`、`docs`、`ci`，或 `yumu`。
- `subject` 用英文祈使句，小写开头，不加句号，不超过 72 字符。
- 破坏性变更在 footer 写 `BREAKING CHANGE:`，协议破坏性变更同时引用 ADR 编号。
- 一个提交只做一件事。

## 3. PR 规则

- 标题即将来 squash 后的提交信息，遵循上面的格式。
- 描述模板（`.github/PULL_REQUEST_TEMPLATE.md`）：做了什么、为什么、怎么测的、是否改了协议或文档、体积影响。
- 改了行为必须改文档，改了 `grain.h` 或 schema 必须改 `grain/CHANGELOG.md`。
- 合并方式：squash merge，保持 `main` 线性。
- PR 控制在 400 行变更以内，超出要拆。

## 4. 版本与发布

- 语义化版本。0.x 阶段次版本可破坏兼容，1.0 之后严格。
- tag 格式 `v0.3.1`，由 CI 打包签名发布。
- CHANGELOG 用 git-cliff 从提交信息生成，发布前人工润色。
- Grain 协议版本独立维护，见协议文档。

## 5. CI 必跑项

| 范围 | 检查 |
|---|---|
| 全局 | 提交信息格式、文件尾换行、禁止提交秘密（gitleaks） |
| heartwood | fmt、clippy、test、deny、多目标交叉构建、体积报告 |
| grain | schema 校验、`grain.h` 与 Rust `extern "C"` 签名一致 |
| bark | 令牌与翻译生成结果与提交一致、每个错误 kind 有英文翻译 |
| macos | SwiftFormat、SwiftLint、build、test |
| windows | dotnet format、build、test |

## 6. 代码评审

- 评审看：正确性、是否符合本仓库规范、是否更新文档、是否引入不必要依赖。
- 风格问题交给工具，人不评论格式。
- 用「建议」与「必须改」两种标记，必须改的要给理由。
