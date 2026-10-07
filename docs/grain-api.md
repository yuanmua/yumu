# Grain：核心对外接口契约

Grain 是 Heartwood 暴露给各平台界面的 C ABI。头文件 `heartwood/crates/grain/include/grain.h` 手写并提交，是唯一真相。CI 用 Rust 侧的 `extern "C"` 签名核对头文件。

## 1. 设计原则

1. **接口极少**：句柄、调用、释放、回调，总共不超过二十个函数。业务方法不单独做 C 函数，统一走一个 `grain_call`。
2. **复杂数据走 JSON 字符串**：请求参数与返回值都是 UTF-8 JSON，Swift 用 `Codable`、C# 用 `System.Text.Json` 解。
3. **谁分配谁释放**：核心返回的字符串用 `grain_string_free` 释放。
4. **核心零文案**：错误与进度只有 `kind` 与 `args`。
5. **schema 先行**：每个方法的参数与返回结构定义在 `grain/schema/`，Swift 与 C# 的模型类型按 schema 手写或由仓库内脚本生成，不引入外部生成器。

## 2. 函数一览

```c
typedef struct GrainCore GrainCore;                     // 不透明句柄
typedef void (*GrainEventFn)(const char* json, void* user_data);

GrainCore* grain_init(const char* config_json, GrainEventFn on_event, void* user_data);
void       grain_shutdown(GrainCore* core);

// 同步调用。返回 JSON：{"ok":{...}} 或 {"err":{"kind":"...","args":{...}}}
char*      grain_call(GrainCore* core, const char* method, const char* params_json);

// 异步调用。立即返回 JSON：{"ok":{"taskId":"..."}}。进度与结果经 on_event 推送。
char*      grain_start(GrainCore* core, const char* method, const char* params_json);
char*      grain_cancel(GrainCore* core, const char* task_id);

void       grain_string_free(char* s);
const char* grain_version(void);                        // 核心版本
const char* grain_api_version(void);                    // 接口版本，semver
```

`config_json` 包含数据目录覆盖、语言无关的运行参数。`grain_init` 失败返回 NULL，原因通过 `grain_last_init_error()` 取。

## 3. 方法命名空间

方法名 `<namespace>.<verb>`。

| 命名空间 | 方法 | 同步/异步 |
|---|---|---|
| `instance` | `list`、`get`、`create`、`update`、`delete`、`duplicate` | 同步 |
| `instance` | `install`、`launch` | 异步 |
| `version` | `listGame`、`listLoader` | 同步（缓存）/ 异步（刷新） |
| `account` | `list`、`addOffline`、`remove`、`setActive`、`beginMicrosoftLogin` | 同步 / 异步 |
| `mod`、`resource`、`modpack` | 后续阶段 | |
| `discover` | `scan` | 异步 |
| `task` | `list`、`cancel` | 同步 |
| `settings` | `get`、`update` | 同步 |

## 4. 事件

回调收到的 JSON：`{"topic":"...","payload":{...}}`。

| topic | payload |
|---|---|
| `task.progress` | `{taskId, fraction, bytesDone, bytesTotal, stage:{kind,args}}` |
| `task.completed` | `{taskId, result}` |
| `task.failed` | `{taskId, error:{kind,args}}` |
| `task.cancelled` | `{taskId}` |
| `instance.changed` | `{id, change}` |
| `game.started` | `{instanceId, pid}` |
| `game.exited` | `{instanceId, code, crashReportPath?}` |
| `account.loginCode` | `{taskId, userCode, verificationUri}` |

进度事件每个任务每 100 毫秒最多一条。

## 5. 错误

`kind` 是 SCREAMING_SNAKE_CASE，全部登记在 `grain/schema/errors.json`，每个都有对应的英文翻译键 `error.<KIND>`。核心 `Error` 枚举的每个变体对应且只对应一个 kind。

## 6. 线程与内存

- `grain_call` 可从任何线程调用，内部可重入。
- 回调可能来自任意核心线程，界面必须自行切回主线程。
- 核心内部所有 panic 在 C 边界被捕获，转成 `INTERNAL` 错误并记录日志，进程不退出。
- 所有传入的 `const char*` 在函数返回后核心不再引用。

## 7. 版本

接口版本独立于应用版本。次版本只增不删。破坏性变更主版本加一并写 ADR。界面与核心总是一起编译、一起发布，所以版本协商只在调试时有意义。
