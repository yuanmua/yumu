# Git 工作流

## 1. 分支模型

- 主干开发。`main` 受保护，只能通过 PR 合入，必须 CI 全绿并至少一人批准。
- 功能分支短生命周期，命名 `<type>/<scope>-<short-desc>`，例如 `feat/heartwood-download-resume`、`fix/macos-instance-list-flicker`。
- 不保留长期的 `develop` 分支。发布用 tag，热修在 `main` 修完后 cherry-pick 到 `release/x.y` 分支。

## 2. 提交信息

团队以中文和英文为主，提交信息用**中文**写，结构沿用 Conventional Commits，`type` 与 `scope` 保持英文小写，方便工具解析与生成 CHANGELOG：

```
<type>(<scope>): <中文一句话说明>

<正文：为什么改、改了什么、怎么验证的。每行不超过 72 个字符宽度。>

<footer>
```

- `type`：`feat`、`fix`、`refactor`、`perf`、`docs`、`test`、`build`、`ci`、`chore`。
- `scope`：`heartwood`、`grain`、`bark`、`macos`、`windows`、`linux`、`docs`、`ci`，或 `yumu`。多个用逗号分隔。
- 标题不超过 50 个字，不加句号，说清楚"做了什么"，不写"修改了一些文件"这类空话。
- 正文写动机与取舍，代码本身能看出来的不重复。涉及实测的写上结果。
- 破坏性变更在 footer 写 `BREAKING CHANGE:`，协议破坏性变更同时引用 ADR 编号。
- 一个提交只做一件事。
- 不加 AI 署名或生成痕迹（`Co-Authored-By`、`Generated with` 等），作者就是提交的人。
- 代码、标识符、代码注释、日志仍然用英文，因为项目是面向全球的开源项目；提交信息和设计文档面向团队，用中文。

示例：

```
feat(grain,macos): C ABI 层与 SwiftUI 应用

Grain：手写 grain.h，进程内核心带任务运行时与事件回调，
方法 instance.list/create/delete/launch 与 version.listGame，
附 C ABI 往返测试。

macOS：Swift Package 直接链接 Rust 静态库，零第三方依赖；
实例列表、详情（安装进度、运行状态）、新建、空状态页。
```

## 3. PR 规则

- 标题即将来 squash 后的提交信息，遵循上面的格式，用中文。描述也用中文。
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
