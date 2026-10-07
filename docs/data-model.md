# 数据模型与磁盘布局

## 1. 数据根目录

| 平台 | 路径 |
|---|---|
| macOS | `~/Library/Application Support/Yumu/` |
| Windows | `%APPDATA%\Yumu\` |
| Linux | `$XDG_DATA_HOME/yumu/`，默认 `~/.local/share/yumu/` |

可用环境变量 `YUMU_DATA_DIR` 覆盖；应用旁有 `yumu-portable` 文件时使用应用旁的 `data/`。

## 2. 目录布局

```
Yumu/
├── settings.toml              全局设置
├── accounts.toml              账号列表（不含 token，token 在系统钥匙串）
├── instances/
│   └── <instance-id>/
│       ├── instance.toml      实例定义，唯一真相
│       ├── icon.png           可选
│       ├── logs/              每次启动一个日志文件，保留最近 20 个
│       └── .minecraft/        游戏目录：mods、saves、resourcepacks、shaderpacks、config…
└── cache/                     可整体删除
    ├── versions/<id>/         <id>.json、<id>.jar
    ├── libraries/             Maven 布局，所有实例共享
    ├── assets/indexes/ objects/
    ├── natives/<version-id>/  解压后的 natives
    ├── java/<component>/      Mojang 运行时
    └── meta/                  版本清单等远程 JSON 的缓存
```

原则：`instances/` 是用户数据，`cache/` 是可再生数据，绝不混放。

## 3. instance.toml

```toml
schema = 1
name = "我的生存"
edition = "java"                 # 预留：java | bedrock
created_at = 1759900000          # unix 秒
last_played_at = 1759910000
playtime_seconds = 5400

[game]
version = "1.21.1"

[loader]
kind = "vanilla"                 # vanilla | fabric | quilt | forge | neoforge
version = ""

[java]
provider = "mojang"              # mojang | system | custom
path = ""                        # provider = custom 时填写

[memory]
max_mb = 4096

[jvm]
extra_args = []

[window]
width = 1280
height = 720
```

- 实例 id 就是目录名，由名称生成的 slug，重名时追加 `-2`、`-3`。目录可以整个拷贝到另一台机器。
- `edition` 只接受 `java`，其他值返回 `INSTANCE_EDITION_UNSUPPORTED`，这是给基岩版留的唯一钩子。
- `schema` 升级提供迁移函数，旧文件永远能读。
- 不认识的键原样保留。

## 4. Mod 列表是派生数据

不单独存文件，扫描 `.minecraft/mods/` 得到，元数据从缓存补全。用户手动拖 jar 进目录是常见行为，派生数据不会与目录不一致。禁用方式是加 `.disabled` 后缀，与 Prism、Modrinth App 兼容。

## 5. settings.toml

```toml
schema = 1
language = "auto"
download_concurrency = 16
mirror = "auto"                  # auto | official | <mirror-id>
theme = "system"
```

## 6. 本机发现结果

`discover.scan` 返回但不落盘：

```json
{
  "installations": [
    {"launcher": "official", "path": "~/Library/Application Support/minecraft",
     "versions": ["1.21.1", "1.20.4"], "saves": [{"name": "New World", "path": "...", "lastPlayed": 0}]}
  ]
}
```

用户选择后，存档以拷贝方式进入实例，或实例的 `.minecraft` 直接指向原目录（引用模式，后续阶段）。
