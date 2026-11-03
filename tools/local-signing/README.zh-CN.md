# 本地签名构建（Apple Silicon）

## 标识

| 用途 | 标识 |
| --- | --- |
| App | `com.andysun.mac-mouse-fix.dev` |
| Helper / SM launchd Label | `com.andysun.mac-mouse-fix.dev.helper` |
| 旧版 launchd Label | `com.andysun.mac-mouse-fix.dev.helper.legacy` |
| SecureStorage | 登录钥匙串，service `com.andysun.mac-mouse-fix.local.secure-storage.v1` |

本地签名包没有 provisioning profile，用不了共享钥匙串组，所以 `MF_LOCAL_SIGNING=1` 时 SecureStorage 改用登录钥匙串，条目 ACL 只信任 App 和 Helper。普通 Xcode 构建保持原行为。

## 构建

需要 Xcode、Python 3 和钥匙串里的 `andysun Local Code Signing` 证书（指纹在 `build.py` 的 `LOCAL`，换证书时改这里）。

```sh
bash tools/local-signing/build.sh --output "$HOME/Downloads/MMF-local"
```

在源码副本中构建（Release 构建号自增不影响工作区），关闭 Hardened Runtime（自签名 framework 没有 TeamID，否则 library validation 会拒绝加载），从内到外签名。

## 测试

```sh
bash tools/local-signing/test.sh
sh Tests/Logitech/run.sh
```
