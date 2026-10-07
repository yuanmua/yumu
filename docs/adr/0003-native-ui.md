# 0003. 界面每平台原生，macOS 先行

状态：接受
日期：2026-10-08

## 背景

要求界面美观、动画流畅、体积小、苹果风格布局。

## 决定

macOS 用 SwiftUI，Windows 用 WinUI 3，Linux 后期决定。视觉与动效规范由 Bark 统一。先只做 macOS。

## 备选与放弃理由

- Electron：体积与内存不可接受。
- Tauri、Flutter：一套界面省人力，但系统 WebView 或自绘引擎做不到与系统一致的质感，体积也更大。

## 后果

- 三套界面是最大的长期维护成本，用 Bark 令牌与 Grain 契约把界面层压到最薄。
