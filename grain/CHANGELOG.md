# Grain 变更记录

## 未发布

- 新增方法：`version.listLoader`、`mod.listInstalled`、`mod.toggle`、`mod.remove`、`mod.search`、`mod.install`、`resource.list`、`resource.add`、`resource.remove`、`resource.toggle`、`modpack.inspect`、`modpack.import`。
- `instance.create` 新增可选参数 `loaderKind`、`loaderVersion`；`instance.list` 结果新增 `loaderVersion`。
- 新增错误 kind：`DOWNLOAD_HOST_NOT_ALLOWED`、`MOD_NOT_COMPATIBLE`、`INVALID_FILE_NAME`。

- 接口版本 0.1.0：`grain_init`、`grain_shutdown`、`grain_call`、`grain_start`、`grain_cancel`、`grain_string_free`、`grain_version`、`grain_api_version`、`grain_last_init_error`。
- 方法：`grain.ping`、`instance.list`、`instance.create`、`instance.delete`、`instance.launch`、`version.listGame`。
- 事件：`task.progress`、`task.completed`、`task.failed`、`task.cancelled`、`instance.changed`、`game.started`、`game.exited`。
- 登记错误 kind（`schema/errors.json`），新增 `INTERNAL`、`INVALID_REQUEST`。
