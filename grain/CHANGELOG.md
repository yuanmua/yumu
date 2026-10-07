# Grain 变更记录

## 未发布

- 接口版本 0.1.0：`grain_init`、`grain_shutdown`、`grain_call`、`grain_start`、`grain_cancel`、`grain_string_free`、`grain_version`、`grain_api_version`、`grain_last_init_error`。
- 方法：`grain.ping`、`instance.list`、`instance.create`、`instance.delete`、`instance.launch`、`version.listGame`。
- 事件：`task.progress`、`task.completed`、`task.failed`、`task.cancelled`、`instance.changed`、`game.started`、`game.exited`。
- 登记错误 kind（`schema/errors.json`），新增 `INTERNAL`、`INVALID_REQUEST`。
