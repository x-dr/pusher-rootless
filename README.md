# Pusher-rootless

rootless version of [NoahSaso/Pusher](https://github.com/NoahSaso/Pusher)  
无根版本的 [NoahSaso/Pusher](https://github.com/NoahSaso/Pusher)

Support for iOS 15-16 / 支持 iOS 15-16

有汉化需求的fork一份自己做，勿提PR :)

## NotifyHub 渠道

1. 在 NotifyHub 中创建使用 Bearer 鉴权的接入点，保存仅展示一次的接入点密钥。
2. 打开“设置 → Pusher → 服务 → NotifyHub”，填写完整 Webhook URL 和 Bearer Token。
3. 按需设置应用黑白名单，然后返回服务列表，点击“编辑”并把 NotifyHub 移到“已启用”。

发送的标准事件包含通知标题、正文、`info` 级别，以及来源应用名称、Bundle ID 和设备名称。后续渠道选择与消息模板由 NotifyHub 规则统一管理。
