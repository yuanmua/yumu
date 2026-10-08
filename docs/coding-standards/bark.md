# Bark：设计令牌与动效规范

Bark 是 Yumu 的视觉与动效单一真相，目标是让 macOS 与 Windows 两套原生界面看起来是同一个产品。

## 1. 目录

```
bark/
├── tokens/
│   ├── color.json       语义色：background、surface、accent、text、status，分 light/dark
│   ├── space.json       间距刻度 4、8、12、16、24、32、48
│   ├── radius.json      圆角 6、10、14、20
│   ├── type.json        字号与字重刻度，字体由平台决定
│   ├── elevation.json   阴影层级 flat、raised、overlay，分 light/dark
│   └── motion.json      时长与缓动曲线
├── i18n/                翻译源，见 i18n.md
├── codegen/             生成 Swift 与 C# 常量；Swift 侧产出 Bark.Space / Radius / Motion / Colors / Text
├── guidelines.md        界面规范：窗口结构、页面清单、渐进披露、组件、动效、文案、平台映射
└── preview/index.html   规范的可交互演示，浏览器直接打开
```

布局、组件、动效、文案的完整规范在 [`bark/guidelines.md`](../../bark/guidelines.md)，本文只管令牌本身。

## 2. 令牌原则

- 语义命名，不按颜色值命名：`surface.elevated`，不是 `gray100`。
- 平台字体不进令牌：macOS 用 SF Pro，Windows 用 Segoe UI Variable，令牌只定义刻度。
- 深浅色成对定义，不存在只有一个模式的颜色。
- 强调色跟随系统强调色为默认，用户可覆盖。

## 3. 动效

| 名称 | 时长 | 曲线 | 用途 |
|---|---|---|---|
| `instant` | 0 | — | 减弱动态效果时的替代 |
| `quick` | 150 ms | ease-out | 悬停、按下、开关 |
| `standard` | 250 ms | spring(response 0.35, damping 0.85) | 列表增删、面板切换 |
| `emphasized` | 400 ms | spring(response 0.5, damping 0.8) | 导入完成、启动成功等关键反馈 |

规则：

- 一次只动一个主体，背景元素不同时大幅移动。
- 进度类反馈持续显示，不用模态阻塞。
- 系统开启减弱动态效果时，所有 spring 退化为 `instant`，淡入淡出保留。
- 动画时长不随内容数量变化，列表项错峰（stagger）上限 6 项，每项间隔 20 ms。

## 4. 布局原则（苹果风格）

- 左侧边栏为实例列表，右侧为详情，`NavigationSplitView` 的三栏在需要时第三栏显示 mod 或日志。
- 大留白、低对比分隔，少用边框，用背景层级区分区域。
- 主操作只有一个明显按钮（启动），其余操作收进菜单或次级按钮。
- 空状态必须有引导：没有实例时直接给「导入整合包」与「新建实例」两个入口。
- 所有破坏性操作二次确认，确认按钮写明动作（「删除实例」而不是「确定」）。

## 5. 傻瓜式操作的具体要求

- 拖一个 `.mrpack` 或 zip 到窗口任何位置即导入。
- 新建实例默认选最新正式版 + 推荐 loader，高级选项折叠。
- Java 缺失自动下载，不弹对话框问用户。
- 游戏崩溃后给出可读的原因分类（内存不足、mod 冲突、Java 版本不匹配）与一键建议。
