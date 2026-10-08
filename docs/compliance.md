# 下载源与第三方服务合规

Yumu 是分发给全球用户的启动器，碰到的每个外部来源都要先回答两个问题：**我们有权从这里下载吗，有权把下载的东西放到用户机器上吗**。这份文档是答案的登记表，新增来源必须先补这里。

## 1. 原则

1. 游戏本体永远从 Mojang 官方服务器拉取，Yumu 不托管、不镜像、不缓存任何 Mojang 文件到自己的服务器上。
2. 只分发许可证允许再分发的 Java 运行时。
3. 第三方平台的内容按平台 API 条款走，平台说不能分发的文件就跳转浏览器，不绕。
4. 下载 URL 必须命中白名单主机，否则拒绝（`Downloader::check_host`）。白名单与来源写在代码常量里，改动需要同步改这里。
5. 任何镜像源都只能是用户显式选择的，不做默认。

## 2. 来源登记

| 来源 | 内容 | 许可 / 条款 | 结论 |
|---|---|---|---|
| `piston-meta.mojang.com`、`piston-data.mojang.com`、`libraries.minecraft.net`、`resources.download.minecraft.net` | 版本清单、客户端 jar、库、资源 | Minecraft EULA；官方启动器同样方式下载 | 允许，默认且唯一 |
| Mojang Java 运行时清单（`launchermeta.mojang.com/v1/products/java-runtime`） | Microsoft Build of OpenJDK | GPLv2 + Classpath Exception | 允许。注意它**不是** Oracle JDK |
| Adoptium Temurin（`api.adoptium.net`） | OpenJDK | GPLv2 + CE | 允许，用于 Mojang 不提供的架构。尚未接入 |
| Oracle JDK | | Oracle NFTC / OTN，禁止再分发 | **禁止**，任何情况下不下载 |
| `meta.fabricmc.net`、`maven.fabricmc.net` | Fabric 加载器与库 | Apache 2.0 | 允许 |
| `meta.quiltmc.org`、`maven.quiltmc.org` | Quilt 加载器与库 | Apache 2.0 | 允许 |
| `maven.minecraftforge.net`、`maven.neoforged.net` | Forge / NeoForge 安装器 | LGPL 2.1；Prism 等启动器直接从 maven 取安装器 | 允许，阶段 4 后半接入 |
| `api.modrinth.com`、`cdn.modrinth.com` | 模组、整合包元数据与文件 | Modrinth API 条款：必须带可识别的 User-Agent，遵守速率限制 | 允许。`.mrpack` 内文件只允许来自 cdn.modrinth.com、github.com、raw.githubusercontent.com、gitlab.com（Modrinth 格式规范） |
| CurseForge API | 模组、整合包 | 需要 API key；文件带 `allowModDistribution=false` 时不得第三方下载 | 阶段 4 后半接入。被禁止的文件跳转浏览器让用户手动下载 |
| OptiFine | 光影前置 | 作者禁止再分发，只能从 optifine.net 下载 | 不自动下载，引导用户去官网，下载后拖进 Yumu |
| BMCLAPI 等社区镜像 | Mojang 文件的镜像 | 灰色地带 | 不默认，不推荐；仅作为用户显式选择的可选项，并提示风险 |

## 3. User-Agent

所有请求带 `yumu/<版本>`。发布前改成 Modrinth 要求的格式 `yumu/<版本> (<联系方式>)`，联系方式用项目主页或邮箱。见 `heartwood/crates/heartwood/src/download.rs` 的 `USER_AGENT`。

## 4. 微软账号登录为什么需要开发者注册一次

每个玩家登录的是自己的微软账号，这一点和官方启动器一样。但 OAuth 要求"发起登录的应用"有一个身份，即 client ID。所有第三方启动器（Prism、HMCL、PCL2、MultiMC）都注册了自己的应用，client ID 是公开字符串，直接写在它们的开源代码里。这是**开发者做一次、免费、所有用户共用**的事情，不是让每个用户去验证。

步骤：

1. 登录 [Azure 门户](https://portal.azure.com)，Microsoft Entra ID → 应用注册 → 新注册。账户类型选"任何组织目录中的账户和个人 Microsoft 账户"。
2. 平台配置选"移动和桌面应用程序"，勾选 `https://login.microsoftonline.com/common/oauth2/nativeclient`。设备码流程不需要回调地址。
3. 在"API 权限"里加 `XboxLive.signin`、`offline_access`。
4. 填写 Mojang 的 [Minecraft API 接入申请表](https://aka.ms/mce-reviewappid)，提供应用 ID 与用途说明，通常几天到几周批复。
5. 批复后把 client ID 写进 `hw-auth` 的常量。它可以公开，不是秘密。

未批复期间可以用本机已安装官方启动器的凭据做开发测试，但不能发布。

## 5. 离线账号策略（待决定）

离线账号绕过了正版验证。参考做法：

- Prism：必须先添加至少一个微软账号，之后才允许创建离线账号。
- HMCL、PCL2：直接允许离线账号。
- Modrinth App：只支持微软账号。

建议采用 Prism 的做法，在合规与单机便利之间取平衡。这是产品决定，由 yuanmu 拍板后写 ADR，阶段 2 的 `account.*` 落地时实现。目前开发阶段允许离线账号。

## 6. 游戏文件缓存的边界

`cache/` 里的所有文件都来自上表允许的来源，只存在用户自己的电脑上，Yumu 不会上传、同步或在用户之间共享它们。便携模式也遵守同一规则。
