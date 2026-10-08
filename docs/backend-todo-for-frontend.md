# 前端需要核心补的接口（临时清单）

> 给做 Heartwood / Grain 的会话。前端（macOS SwiftUI）已经按最终设计做完，下面每一项前端都先用「临时做法」顶着；核心做好后把临时做法删掉即可。做完一项就从这里划掉，全部做完删除本文件，正式契约写进 `docs/grain-api.md`。

## 1. 多进程：同一实例可以同时开多个

现状：`instance.launch` 返回 `{pid}`，`game.started` 带 `pid`，但 `game.exited` 只有 `instanceId`，前端分不清是哪一个进程退出了。

要做：

- `game.exited` 加 `pid`。前端已按 `pid` 匹配，没有 `pid` 时退化为「该实例最早的进程」。
- `game.list` → `[{pid, instanceId, startedAt, logPath}]`，同步。前端启动时调用一次，恢复重启前仍在跑的游戏（现在重启启动器就会丢失运行列表）。
- `game.stop {pid}`：向进程发 SIGTERM，超过 10 秒未退出再 SIGKILL。前端临时做法：Swift 直接 `kill(pid, SIGTERM)`，不做超时强杀。
- 核心内部不要再用「实例正在运行」做互斥；`instance.launch` 对已运行的实例也要能再起一个。`InstanceSummary.running` 改成 `runningCount` 或保留 `running` 但语义是「至少一个」。
- 同一实例并发启动时，补齐文件那一步要做互斥（两个 launch 同时下载同一个库会写同一个 `.part`）。

## 2. 运行监控

前端有「正在运行」页：每个进程一行，PID、已运行时间、CPU、内存、查看、结束。

- CPU 与内存：前端临时用 `proc_pid_rusage` 每 2 秒采一次，macOS 可用。Windows / Linux 需要核心提供：`game.stats {pid}` → `{cpuPercent, residentBytes}`，或者推 `game.stats` 事件（每 2 秒）。
- `game.started` 加 `logPath`。前端现在猜「`instances/<id>/logs/` 里最新的文件」。
- 可选：`game.log.tail {pid, lines}` → `[String]`。前端现在直接读文件末尾 512 KB。

## 3. 存档

前端「存档」标签直接读 `instances/<id>/.minecraft/saves/*`，用文件夹名当世界名、目录大小、修改时间。

要做：`instance.listSaves {id}` → `[{name, path, sizeBytes, lastPlayed, gameMode?, hardcore?}]`，从 `level.dat` 读真实名称与模式。前端拿到后删掉 `LocalFiles.worlds`。

另外「点存档直接进入世界」需要 `instance.launch {id, world?}`，用 `--quickPlaySingleplayer <世界目录名>`（1.20+），旧版本忽略。

## 4. 启动器级设置

前端把这些存在 UserDefaults 里，核心还不知道：

| 键 | 值 | 核心该做什么 |
|---|---|---|
| `downloadSource` | `auto` / `official` / `bmclapi` | 下载器按此选源，`auto` 测速 |
| `concurrency` | 1–32 | 下载并发数 |
| `proxy` | URL 或空 | reqwest 代理 |
| `defaultMemoryMb` | 1024–16384 | `instance.create` 时的默认 `maxMb` |
| `afterLaunch` | `keep` / `hide` | 前端自己处理 |
| `notifyOnExit` | bool | 前端自己处理 |
| `discover` | bool | 前端自己处理（不调 `discover.scan`） |

要做：`settings.get` → 上表核心相关的四项；`settings.update {…}`。契约里已列为「计划」。

## 5. 实例元数据

前端把收藏与图标存在 UserDefaults（`favorites`、`icon.<id>`），换电脑就丢。

要做：`instance.toml` 加 `favorite: bool`、`icon: String`（预设地形名或图片路径），`instance.list` 返回，`instance.update` 可改。前端拿到后删掉 `Prefs.favorites` / `Prefs.icon`。

## 6. 图标

用户要求线上下载的模组与整合包显示原本的图标。

- `mod.install` 把 Modrinth 的 `icon_url` 存进模组记录，`mod.listInstalled` 的 `record` 加 `iconUrl`。
- 手动放进来的 jar：`mod.listInstalled` 加 `iconPath`，从 jar 里解出 `fabric.mod.json` 的 `icon` / `META-INF/mods.toml` 的 `logoFile`，放到 `cache/icons/<hash>.png`。
- `modpack.installModrinth` 与 `modpack.import` 把整合包图标存成实例的 `icon`（见第 5 节），`instance.list` 返回。
- 前端临时做法（`Core/IconLookup.swift`）：对模组、光影、资源包文件算 SHA1，`POST https://api.modrinth.com/v2/version_files` 反查项目，再 `GET /v2/projects?ids` 拿 `icon_url`，存在 UserDefaults。核心本来就为每个下载算过哈希，把这一步挪进核心即可删掉前端代码。
- `mod.listInstalled` 现在在主线程同步读 jar 元数据，上百个模组时会卡；前端临时放到后台线程调用，核心最好改成异步任务。

## 7. 其他已在界面上预留、按钮灰着的

- `instance.duplicate {id, name}` → `{id}`：复制实例含模组与设置，不含存档（或带 `includeSaves`）。
- `modpack.export {id, path}`：导出 `.mrpack`。概览页「导出整合包」按钮已占位。
- `mod.checkUpdates {id}` → `[{fileName, latestVersionId, latestVersionNumber}]`：模组页要显示「有更新」标签与「全部更新」。
- 更新检查：`grain.checkUpdate` → `{version, url, notes}`。关于页按钮已占位。

## 8. 事件时序上的小问题

- `task.completed`（launch）与 `game.started` 的先后顺序没有保证，前端两边都清「准备中」状态。能保证 `game.started` 在 `task.completed` 之前更好。
- `game.exited` 后前端会重新拉 `instance.list` 拿游玩时长；如果核心能在 `game.exited` 里直接带 `playtimeSeconds`，可以省一次调用。

## 前端里的临时代码位置

| 文件 | 临时做法 | 核心做完后 |
|---|---|---|
| `apps/macos/Sources/Yumu/Core/LocalFiles.swift` | 读存档目录、日志文件、`proc_pid_rusage` | 改成调 `instance.listSaves`、`game.log.tail`、`game.stats` |
| `apps/macos/Sources/Yumu/Core/AppModel.swift` `stop(pid:)` | `kill(pid, SIGTERM)` | 调 `game.stop` |
| `apps/macos/Sources/Yumu/Core/AppModel.swift` `game.exited` 处理 | 没 `pid` 时按实例匹配最早的进程 | 只按 `pid` |
| `apps/macos/Sources/Yumu/Core/Prefs.swift` | UserDefaults 存设置、收藏、图标 | 改成 `settings.*` 与实例字段 |
