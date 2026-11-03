# andysun 自用 Release

源码 fork：https://github.com/sandytruant/mac-mouse-fix

## 当前构建

- 上游 Mac Mouse Fix 3.1.0，自用构建 25415，包含 M650 HID++ 修复和本地开发标识。
- 平台：Apple Silicon / arm64；不是 Intel 通用包。
- 使用 Apple Development 签名，未做 Developer ID 分发签名或 Apple 公证。
- 当前免费团队 provisioning profiles 于 **2026-11-10 05:08 UTC** 左右到期，只覆盖构建时注册的 Mac。到期后需要用 Xcode 更新描述文件并重新构建；不能当成永久有效的发行包。
- ZIP 中的应用必须保留 embedded.provisionprofile 才能保持原始签名/授权配置；描述文件包含注册设备标识，因此本次 GitHub Release 保持 **draft**，不公开发布资产。
- 保留上游 MMF License、作者归属、原有许可证/试用/支付逻辑。自用构建不是免费解锁版，许可状态仍需正常处理。

## 安装

1. 在运行中的 Debug/官方版本里关闭“启用 Mac Mouse Fix”，退出应用并停止 Xcode 调试。
2. 从自己的 GitHub Release 草稿下载 ZIP，解压。
3. 备份旧应用后，把新 `Mac Mouse Fix.app` 放到 `/Applications`，避免长期从 DerivedData 运行。
4. 打开新应用，启用 Helper，必要时重新授权“设备控制和数据访问”（旧系统名为“辅助功能”）。不需要为了运行而全局关闭 Gatekeeper。
5. 配置仍位于 `~/Library/Application Support/com.andysun.mac-mouse-fix.dev/config.plist`，与当前 andysun Debug 版共享；不要让两个 Helper 同时运行。
6. 不使用应用内更新切回上游版本；后续从自己的 fork 构建。

## 重建

```sh
sh Tests/Logitech/run.sh
python3 Tests/UI/accessibility-sheet.py
xcodebuild -project 'Mouse Fix.xcodeproj' -scheme App -configuration Release \
  -derivedDataPath /tmp/mmf-andysun-release ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
codesign --verify --deep --strict '/tmp/mmf-andysun-release/Build/Products/Release/Mac Mouse Fix.app'
```

需要 Xcode 中登录自己的开发账号。描述文件过期时，先在 Xcode 中自动管理签名并更新。Release 构建阶段会增加源码 Info.plist 中的构建号；发布前应提交该变更，使 tag 对应的源码记录与产物构建号一致。
