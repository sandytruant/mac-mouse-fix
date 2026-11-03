# 本地签名自用构建（Apple Silicon）

## 下载后使用

1. 解压 `Mac Mouse Fix.app`，放到 `/Applications` 或自己的 `~/Applications`。
2. 停用其他版本的 Helper，打开本地版，点击启用。
3. 按 macOS 提示允许“设备控制和数据访问”（旧系统称“辅助功能”）；如系统提示钥匙串访问，请核对是这个 App/Helper 后允许。

**不需要预先迁移、激活许可证或创建钥匙串记录。** 没有记录时使用上游原有首次运行流程；仅在原程序实际保存状态时才创建记录。地区免费资格、许可证校验、试用计数和付费界面仍使用上游代码，没有硬编码免费状态。

本地构建使用传统登录钥匙串，不使用受 provisioning profile 限制的共享组。新记录的 ACL 同时允许主 App 和嵌入的 Helper 访问；已有本地记录不会被初始化覆盖。读取缺失、读取异常和写入错误沿用原 SecureStorage API 的返回语义，不强制退出，也不把迁移作为启动条件。

此构建与开发版共享 `com.andysun.mac-mouse-fix.dev` 配置目录，但本地钥匙串和旧同步钥匙串是两个存储位置。已有付费许可证或试用记录的用户可以在首次使用本地版前选择迁移，避免丢失旧状态；新记录不存在（例如上游地区免费）不妨碍使用。

## 签名及限制

- 目前仅 arm64，使用 `andysun Local Code Signing` 本地证书。
- App/Helper 无 restricted entitlements，不带 embedded.provisionprofile，无 Personal Team 七天描述文件限制。
- 这是自用签名，不是 Developer ID 分发签名，也未做 Apple 公证。其他 Mac 不会因此自动信任它；辅助功能权限也不能随包分发。
- 本地签名框架没有 Apple TeamID，为避免 library validation 拒绝加载，仅此构建关闭 Hardened Runtime。没有修改系统 Gatekeeper、SIP 或 TCC 设置。
- 保存好本地证书和私钥，不要上传私钥。当前证书有效期至 2036-10-31。
- 不同时运行官方版、旧开发版或其他鼠标驱动。不要使用应用内更新替换此 fork。

## 构建

需要 Xcode、Python 3.9+、仓库外部依赖和上述签名证书。证书指纹保存在 `common.py`，其他人重建需换成自己的证书。

```sh
bash tools/local-signing/build.sh --output "$HOME/Downloads/MMF-local-direct"
```

输出目录必须尚不存在，避免覆盖已安装或运行中的应用。脚本复制源码到临时目录构建，Release 构建号自增只发生在副本，不改工作区。通过 `MF_LOCAL_SIGNING=1` 选择本地钥匙串，普通开发构建保持原同步钥匙串行为。签名从内到外完成，最后严格检查 App/Helper；不会安装、启动应用或修改用户钥匙串。

## 测试

```sh
bash tools/local-signing/test.sh
python3 tools/local-signing/acl-test.py
sh Tests/Logitech/run.sh
python3 Tests/UI/accessibility-sheet.py
```

fake transport 测试不接触真实钥匙串。ACL 测试仅创建临时钥匙串与虚构数据，立即恢复原搜索列表并在退出时删除测试钥匙串；模拟 Apple Development 签名迁移器和两个本地签名进程的读写，不读取用户记录。UI 测试会短暂显示测试窗口，不启用鼠标处理。

## 可选：保留旧同步存储

仅适用于旧同步记录确实存在、且还持有有效 Apple Development 签名包的用户。不是启动前置步骤。

停用并退出所有 MMF 实例，将本地包放在最终使用位置后，执行：

```sh
bash tools/local-signing/migrate.sh \
  --source-app '/tmp/mmf-andysun-release/Build/Products/Release/Mac Mouse Fix.app' \
  --local-app "$HOME/Applications/Mac Mouse Fix Local.app" \
  --confirm-migration
```

工具借用原包的有效授权读取源记录，仅在内存中原样复制到本地钥匙串，不打印或删除原数据。目标已存在时拒绝覆盖，避免破坏已经开始使用的本地状态。源不存在会报告 `errSecItemNotFound`，此时无需迁移，直接使用本地版即可。
