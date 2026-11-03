# andysun 本地开发签名

本分支的主应用和 Helper（Debug/Release）统一使用以下标识：

| 用途 | 标识 |
| --- | --- |
| App | `com.andysun.mac-mouse-fix.dev` |
| Helper / SM launchd Label | `com.andysun.mac-mouse-fix.dev.helper` |
| 旧版 launchd Label | `com.andysun.mac-mouse-fix.dev.helper.legacy` |
| 共享钥匙串组 | `$(AppIdentifierPrefix)com.andysun.mac-mouse-fix.dev.keychain-group` |
| SecureStorage Label | `com.andysun.mac-mouse-fix.dev.secure-storage` |

保留用户在 Xcode 中选择的开发 Team；用户名不是 Team ID。两个 Target 必须使用同一 Team，启用 Automatically manage signing。重新打开工程，选择 **App → My Mac**，按 ⌘B。若 Xcode 仍显示旧 ID，可先 Clean Build Folder（⇧⌘K）。新 ID 的注册和 provisioning profile 仍需要 Xcode 登录账号并联网；本地编译通过不代表 Apple 已完成注册，也不保证名称尚未被占用。

同步位置包括 `project.pbxproj`、`Shared/Constants.h`、两个 entitlements、launchd plists、SecureStorage、Helper Scheme 及截图工具相关引用。日志 subsystem、线程名称、历史注释和第三方授权/更新网址不改。未修改授权/付费检查。

## 运行注意

- 配置位于 `~/Library/Application Support/com.andysun.mac-mouse-fix.dev/config.plist`，不会自动继承官方版配置或钥匙串状态。
- 新 Helper 需要单独授予辅助功能权限。
- 先停用官方版 Helper，再运行开发版；虽然 IPC 和 launchd 标识已隔离，但两个 Helper 同时处理鼠标会互相干扰。
- 应用文件名、`macmousefix` URL scheme 和更新源仍沿用上游；不要把此配置当成可完全并行安装、自动更新的正式发行版。测试时不要执行应用内更新。
- 推荐 App Scheme。部分旧 Helper 调试 Scheme 仍保留原作者 DerivedData 可执行文件路径，不应直接使用。

## 无签名编译检查

```sh
xcodebuild -project 'Mouse Fix.xcodeproj' -scheme App -configuration Debug \
  -derivedDataPath /tmp/mmf-andysun-build CODE_SIGNING_ALLOWED=NO build
```

此命令只检查编译，不生成适合验证开发签名的产物；实机签名请在 Xcode 中构建。
