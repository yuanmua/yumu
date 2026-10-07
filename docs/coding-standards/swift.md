# Swift 代码规范（apps/macos）

## 1. 工具链

- Swift 6，开启严格并发检查（`-strict-concurrency=complete`）。
- 最低部署目标 macOS 14。
- 格式化：SwiftFormat，配置 `.swiftformat` 在 `apps/macos/`。
- Lint：SwiftLint，配置 `.swiftlint.yml`，CI 强制零警告。
- 项目用 Xcode 工程 + Swift Package 划分模块，第三方依赖只用 SwiftPM。

## 2. 模块划分

```
apps/macos/
├── Yumu.xcodeproj
├── Yumu/                      App target：入口、窗口、依赖装配
├── Packages/
│   ├── Grain/                 C 头文件的 Swift 封装：GrainClient actor、Codable 模型、事件流
│   ├── Bark/                  设计令牌、通用组件、动效常量。生成代码在 Generated/
│   ├── Features/
│   │   ├── Instances/
│   │   ├── Mods/
│   │   ├── Modpacks/
│   │   ├── Accounts/
│   │   └── Settings/
│   └── Core/                  跨 Feature 的状态容器、路由
└── Tests/
```

依赖方向：`Yumu` → `Features` → `Core` → `Grain`、`Bark`。Feature 之间不互相依赖，需要通信经由 `Core`。

## 3. 架构模式

- MVVM。View 只声明界面，ViewModel 持有状态与意图处理，Model 来自 Grain 生成类型。
- ViewModel 是 `@Observable final class`，标注 `@MainActor`。
- `GrainClient` 是 `actor`，封装 `grain.h` 的全部调用：`grain_call` 包成泛型 `call<P: Encodable, R: Decodable>`，C 回调转成 `AsyncStream<GrainEvent>` 并切回主线程。界面其他部分不直接碰 C 函数。
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

- 所有用户可见字符串用 `String(localized:)` 或 `LocalizedStringKey`，键来自 `bark/i18n/en.json` 生成的 String Catalog。
- 禁止在代码里写硬编码英文。
- 错误显示：从 Grain 错误的 `kind` 查键 `error.<KIND>`，`args` 作为插值。

## 7. 设计令牌与动效

- 颜色、间距、圆角、字号、动画时长与曲线一律引用 `Bark` 包的生成常量，不在 View 里写字面量。
- 动画用 `.animation(Bark.Motion.standard, value:)` 形式，`Motion` 常量集中定义。
- 尊重系统「减弱动态效果」设置，`Bark.Motion` 在该设置开启时自动退化为无动画。
- 优先使用 SwiftUI 原生动画；需要精细控制时下沉 `NSViewRepresentable`，并在文件头注释说明原因。

## 8. 测试

- ViewModel 单元测试用 Swift Testing，`GrainClient` 用协议抽象替换为假实现。
- 快照测试覆盖主要界面的浅色与深色、中英日三种语言。
- 不写依赖真实 Heartwood 的 UI 测试，端到端留给手工与集成环境。

## 9. 禁止事项

- 禁止 `try!`、`as!`、隐式解包可选，除 IBOutlet 与测试外。
- 禁止在 `body` 里做 IO 或创建 `Task`，放到 `.task {}` 修饰符。
- 禁止用 `UserDefaults` 存业务数据，业务设置都走 Heartwood 的 `settings.*`，`UserDefaults` 只存窗口尺寸这类纯界面偏好。
