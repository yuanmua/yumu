# Grain 变更记录

## 未发布

- `game.exited` 新增 `logPath` 与 `crash`（崩溃原因分类）。
- `discover.scan` 的 `versions` 从字符串数组改为 `{id, gameVersion, loaderKind, loaderVersion}` 对象数组。

- 新增方法：`grain.info`、`instance.get`、`instance.update`、`discover.scan`、`discover.importSave`。
- 开发版特性 `dev-offline`：`grain.info.offlineWithoutMicrosoft` 为 true 时离线账号不要求先有微软账号。

- 新增方法：`account.list`、`account.addOffline`、`account.remove`、`account.setActive`、`account.beginMicrosoftLogin`、`resource.install`、`modpack.search`、`modpack.installModrinth`。`mod.search` 新增 `projectType`，`id` 变为可选。`instance.launch` 不再接受 `playerName`，改用当前账号。
- 新增事件：`account.loginCode`、`account.changed`。
- 新增错误 kind：`AUTH_FAILED`、`AUTH_NO_XBOX_ACCOUNT`、`AUTH_NO_GAME`、`AUTH_APP_NOT_APPROVED`、`ACCOUNT_REQUIRED`、`ACCOUNT_NOT_FOUND`、`ACCOUNT_OFFLINE_REQUIRES_MICROSOFT`、`LOADER_INSTALL_FAILED`。

- 新增方法：`version.listLoader`、`mod.listInstalled`、`mod.toggle`、`mod.remove`、`mod.search`、`mod.install`、`resource.list`、`resource.add`、`resource.remove`、`resource.toggle`、`modpack.inspect`、`modpack.import`。
- `instance.create` 新增可选参数 `loaderKind`、`loaderVersion`；`instance.list` 结果新增 `loaderVersion`。
- 新增错误 kind：`DOWNLOAD_HOST_NOT_ALLOWED`、`MOD_NOT_COMPATIBLE`、`INVALID_FILE_NAME`。

- 接口版本 0.1.0：`grain_init`、`grain_shutdown`、`grain_call`、`grain_start`、`grain_cancel`、`grain_string_free`、`grain_version`、`grain_api_version`、`grain_last_init_error`。
- 方法：`grain.ping`、`instance.list`、`instance.create`、`instance.delete`、`instance.launch`、`version.listGame`。
- 事件：`task.progress`、`task.completed`、`task.failed`、`task.cancelled`、`instance.changed`、`game.started`、`game.exited`。
- 登记错误 kind（`schema/errors.json`），新增 `INTERNAL`、`INVALID_REQUEST`。
