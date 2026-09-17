# Pusher-rootless

[Pusher](https://github.com/NoahSaso/Pusher) 的 rootless 适配版本，用于将 iPhone 收到的系统通知转发到其他设备或消息服务。

当前面向 **iOS 15–16 的 rootless 越狱环境**，设置界面已中文化。

## 功能

- 内置 Pushover、Pushbullet、IFTTT、Pusher Receiver、飞书、Bark、企业微信和 NotifyHub 渠道。
- 支持自定义 HTTP 服务，可选择 GET/POST，以及无认证、请求头认证或请求体认证。
- 支持全局和单个渠道的应用黑名单/白名单。
- 可按设备锁定状态、Wi-Fi/蜂窝网络和应用通知权限筛选需要转发的通知。
- 支持按应用覆盖渠道配置，并提供发送测试通知和最近 100 条日志。
- 包含 Flipswitch 开关，可快速启用或停用 Pusher。

> Pusher 只负责转发设备收到的通知。各渠道的账号、Webhook 和服务器需要自行准备。

## 安装

1. 从本仓库的 [Releases](https://github.com/x-dr/pusher-rootless/releases) 下载最新的 `.deb` 文件。
2. 使用 Sileo、Zebra 等软件包管理器安装；软件包声明依赖 MobileSubstrate、AltList 和 RocketBootstrap。
3. 安装完成并重启 SpringBoard 后，打开“设置 → Pusher”。
4. 开启总开关，在“全局设置”中配置转发条件。
5. 进入“服务”填写渠道参数，然后点击右上角“编辑”，将需要使用的渠道拖到“已启用”分组。
6. 打开渠道详情页，点击“发送测试通知”验证配置。

## NotifyHub 配置

1. 在 NotifyHub 中创建使用 Bearer 鉴权的接入点，并保存仅展示一次的接入点密钥。
2. 打开“设置 → Pusher → 服务 → NotifyHub”。
3. 填写完整的 Webhook URL 和 Bearer Token。Webhook URL 必须符合以下格式，建议始终使用 HTTPS：

   ```text
   https://notify.example.com/api/v1/hooks/<接入点 ID>
   ```

4. 按需设置应用黑名单或白名单，返回服务列表后将 NotifyHub 移到“已启用”。
5. 在 NotifyHub 详情页发送测试通知，并通过 Pusher 日志和 NotifyHub 事件记录确认结果。

发送到 NotifyHub 的标准事件包含：

- `title`：通知标题；
- `content`：通知正文；
- `level`：固定为 `info`；
- `occurredAt`：通知发生时间；
- `metadata.appName`、`metadata.appID`、`metadata.deviceName`：来源应用和设备信息。

请求使用 `Authorization: Bearer <token>` 鉴权，并携带 `X-NotifyHub-Event-Id` 作为事件标识。客户端将 HTTP `202` 且响应 JSON 中 `code` 为 `0`、`data` 为对象视为发送成功；失败请求最多尝试 5 次。后续渠道选择和消息模板由 NotifyHub 规则统一管理。

## 从源码构建

需要可用的 [Theos](https://theos.dev/docs/installation) 环境、iOS 16.5 SDK，以及 AltList、RocketBootstrap 和 Flipswitch 对应的开发文件。当前构建目标的最低系统版本为 iOS 15.0。

```bash
git clone https://github.com/x-dr/pusher-rootless.git
cd pusher-rootless
make package FINALPACKAGE=1
```

生成的软件包位于 `packages/`。如需安装到测试设备，请先按 Theos 文档配置设备连接信息，再运行 `make install`；安装后会重启 SpringBoard。

仓库中的 GitHub Actions 会在推送 `v*` 标签时构建 `.deb` 并附加到对应 Release。标签版本号会同步写入构建产物，例如：

```bash
git tag v1.5.1
git push origin v1.5.1
```

## 隐私与安全

- 通知可能包含验证码、聊天内容等敏感信息。启用渠道前，请确认目标服务和网络环境可信。
- 不要在 Issue、日志截图或提交记录中公开 Token、Webhook 密钥及其他凭据。
- NotifyHub 的 Bearer Token 会保存在设备偏好设置中；请妥善保护越狱设备，并在疑似泄露后及时轮换密钥。
- 自定义服务使用 GET 时会把通知数据放入 URL 查询参数；处理敏感通知时优先使用 HTTPS POST。

## 致谢

- 原项目及主要实现：[NoahSaso/Pusher](https://github.com/NoahSaso/Pusher)
- 本仓库在原项目基础上维护 rootless 适配、中文界面及新增渠道。
