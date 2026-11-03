# andysun 自用 Release

源码：https://github.com/sandytruant/mac-mouse-fix

## 当前版本：本地签名版

- Mac Mouse Fix 3.1.0，包含 M650 HID++ 侧键修复及 andysun 开发标识。
- Apple Silicon / arm64，不支持 Intel。
- 使用 `andysun Local Code Signing` 自签名证书，不含 provisioning profile，不受 Personal Team 七天描述文件限制。当前证书到期日为 2036-10-31。
- 未做 Apple 公证，不是 Developer ID 分发签名；主要供创建并信任此证书的本人 Mac 使用，不能承诺在其他 Mac 上像官方公证包一样直接通过 Gatekeeper。
- 缺少钥匙串记录时正常首次使用，不要求迁移，不强制退出。原有地区免费资格、许可证、试用计数及支付逻辑保留。
- 仅本地构建使用传统登录钥匙串并关闭 Hardened Runtime；没有修改系统 Gatekeeper/SIP/TCC。已有同步授权记录可选迁移，本地已有记录不覆盖。
- 保留上游 MMF License 和作者归属。这不是绕过授权的免费解锁版。

## 安装与使用

1. 在旧版本中关闭“启用 Mac Mouse Fix”，退出应用并停止 Xcode 调试。
2. 下载 ZIP，解压，将新 `Mac Mouse Fix.app` 替换到 `/Applications` 或自己的 `~/Applications`。
3. 打开并启用 Helper，按系统提示授权“设备控制和数据访问”（旧称“辅助功能”）。
4. 不需要先运行迁移脚本或购买/输入许可证。符合上游地区免费规则时按原逻辑使用；其他地区仍遵循原有试用和付费规则。
5. 配置目录仍为 `~/Library/Application Support/com.andysun.mac-mouse-fix.dev/`。不要同时运行两个版本或竞争鼠标驱动。
6. 后续下载自己 fork 的新版本，不用应用内更新切回上游。

构建及可选迁移说明：[本地签名 README](../tools/local-signing/README.zh-CN.md)。

## 历史版本

`v3.1.0-andysun.1` 是 Personal Team 签名的草稿版，含七天描述文件，约于 2026-11-10 到期。新本地签名版取代该包；不要再下载该草稿作为长期版本。
