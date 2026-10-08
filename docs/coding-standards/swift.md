# Swift 代码规范（apps/macos）

## 1. 工具链

- Swift 6，开启严格并发检查（`-strict-concurrency=complete`）。
- 最低部署目标 macOS 14。
- 格式化：SwiftFormat，配置 `.swiftformat` 在 `apps/macos/`。
- Lint：SwiftLint，配置 `.swiftlint.yml`，CI 强制零警告。
- 工程是一个 Swift Package，没有 Xcode 工程文件；仓库根的 `build.sh` 负责编译 Rust 静态库、生成翻译与令牌、画图标、`swift build`、组装并签名 `dist/Yumu.app`。Xcode 可以直接打开 `Package.swift` 开发。第三方依赖只用 SwiftPM，目前为零。

## 2. 目录

```
apps/macos/
├── Package.swift
├── Info.plist                 应用包的 plist，根目录 build.sh 拷贝进 Yumu.app
└── Sources/
    ├── CGrain/                系统库目标：module.modulemap + 指向 heartwood 的 grain.h 符号链接
    └── Yumu/
        ├── YumuApp.swift      入口与窗口
        ├── Grain/             GrainClient（唯一碰 C 接口的地方）与 Codable 模型
        ├── Bark/              L() 翻译助手、动效助手，Tokens.generated.swift 由 bark/codegen 生成
        ├── Core/              AppModel：跨界面的状态与事件处理
        ├── Features/<Feature>/ 各界面的 View
        └── Resources/         <locale>.lproj/Localizable.strings，由 bark/i18n/build.py 生成
```

依赖方向：`Features` → `Core` → `Grain`、`Bark`。Feature 之间不互相依赖，需要通信经由 `Core`。

## 3. 架构模式

- View 只声明界面；状态与意图处理在 `@MainActor @Observable` 的模型类里（目前一个 `AppModel`，按 Feature 拆分时再分）；Model 是与 Grain schema 对应的 `Codable` 结构。
- `GrainClient` 是 `Sendable final class`，封装 `grain.h` 的全部调用：`grain_call` 包成泛型 `call<R: Decodable>(method, params)`，C 回调把事件送进 `AsyncStream<GrainEvent>`，模型在主线程上 `for await` 消费。界面其他部分不直接碰 C 函数。
- View 里不出现业务判断，不直接调用 `GrainClient`。
- 导航状态集中在 `Core/Router`，用 `NavigationSplitView` 与 `NavigationStack`。

## 4. 并发

- UI 状态只在 `@MainActor` 上修改。
- 不用 `DispatchQueue`，统一 `async/await` 与 `Task`。
- 长任务的进度通过 `AsyncStream` 消费，在 ViewModel 里用 `for await` 更新状态，View 消失时取消 `Task`。
- 禁止 `@unchecked Sendable`，除非附带注释说明为何安全。

## 5. 命名

- 遵循 Swift API Design Guidelines。
- View 以 `View` 结尾，ViewModel 以 `ViewModel` 结尾，文件名与类型名一致。
- 枚举 case 用 `lowerCamelCase`。
- 布尔属性用 `is`、`has`、`can` 前缀。

## 6. 文案与本地化

- 所有用户可见字符串经 `L("key")` 取得，键定义在 `bark/i18n/en.json`，生成到 `Resources/<locale>.lproj/Localizable.strings`。
- 禁止在代码里写硬编码英文。
- 错误显示：从 Grain 错误的 `kind` 查键 `error.<KIND>`，`args` 作为插值。

## 7. 设计令牌与动效

- 颜色、间距、圆角、字号、动画时长与曲线一律引用 `Bark` 包的生成常量，不在 View 里写字面量。
- 动画用 `.barkAnimation(Bark.Motion.standard, value:)`，它在系统开启「减弱动态效果」时自动退化为无动画。
- 优先使用 SwiftUI 原生动画；需要精细控制时下沉 `NSViewRepresentable`，并在文件头注释说明原因。

## 8. 测试

- ViewModel 单元测试用 Swift Testing，`GrainClient` 用协议抽象替换为假实现。
- 快照测试覆盖主要界面的浅色与深色、中英日三种语言。
- 不写依赖真实 Heartwood 的 UI 测试，端到端留给手工与集成环境。

## 9. 禁止事项

- 禁止 `try!`、`as!`、隐式解包可选，除 IBOutlet 与测试外。
- 禁止在 `body` 里做 IO 或创建 `Task`，放到 `.task {}` 修饰符。
- 禁止用 `UserDefaults` 存业务数据，业务设置都走 Heartwood 的 `settings.*`，`UserDefaults` 只存窗口尺寸这类纯界面偏好。
