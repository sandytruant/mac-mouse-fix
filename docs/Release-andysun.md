# andysun 自用 Release

Mac Mouse Fix 3.1.0 + [Logitech 侧键按住](Logitech-M650-side-buttons.md)。仅 Apple Silicon，本地自签名（未公证）。

## 安装

1. 关闭并退出其他版本的 Mac Mouse Fix（包括官方版）。
2. 解压，把 `Mac Mouse Fix.app` 放到 `/Applications`。首次打开如被 Gatekeeper 拦截，右键选“打开”。
3. 启用 Helper，按提示授予辅助功能权限。
4. 不要用应用内更新，新版本从本 fork 下载。

配置目录：`~/Library/Application Support/com.andysun.mac-mouse-fix.dev/`。授权、试用逻辑与上游相同。

构建见 [本地签名 README](../tools/local-signing/README.zh-CN.md)。
