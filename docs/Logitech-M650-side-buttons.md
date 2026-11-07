# Logitech 侧键按住（M650 L 等）

新款 Logitech 鼠标在没有 Options+ 时，侧键只会发出瞬间点击，没有“按住”状态，所以点按+拖移、点按+滚动用不了。Helper 通过 HID++ `0x1B04` 临时接管 Back `0053` 和 Forward `0056`，再把真实的按下/松开作为按钮 4/5 发出。

支持 Bolt/Unifying 接收器（`C52B/C532/C534/C548/C547`）和蓝牙直连，已在 M650 L + Bolt 上实测。

## 使用

- 默认开启。在按钮页面给 4/5 绑定动作即可。
- 不要同时运行 Options+、Solaar 或官方版 Mac Mouse Fix，它们会争用侧键。
- 唤醒鼠标的那一下侧键仍是原生点击（接管在鼠标连上后约 1 秒内恢复）。
- 退出 Helper 时恢复原生行为；崩溃后无需给鼠标断电，下次启动会自动重新接管。

关闭：退出 Helper，在 `~/Library/Application Support/com.andysun.mac-mouse-fix.dev/config.plist` 的 `General` 里加入 `<key>logitechSideButtons</key><false/>`，再启动。

## 测试

```sh
sh Tests/Logitech/run.sh
```

## 侧键重复录入修复

接管与移除按 IORegistry interface ID 匹配，避免同一 HID 接口的不同 `IOHIDDeviceRef` 包装对象各自维护按键状态、重复发送事件。`ClickCycle` 同时忽略尚未松开的按钮的重复按下，并在替换长按定时器前取消旧定时器；正常双击仍由按下／松开交替计数。

`Tests/Logitech/run.sh` 也会编译生产版 `ClickCycle.swift`，测试重复事件、正常双击、长按和双击长按。

当前保留 `MMFDiag` 诊断日志及合成事件标记（`kCGEventSourceUserData = 0x4D4D464C4F474931`），供实机验证；仅记录接口、按钮、状态和时间戳，不记录指针位置。可用以下命令捕获：

```sh
/usr/bin/log stream --level debug --style compact --predicate 'process == "Mac Mouse Fix Helper" AND eventMessage CONTAINS "MMFDiag"'
```

## 来源

遵循 [MMF License](../License)。HID++ 传输层基于 lcandy2 的 PR #1995，报文解析参考 PR #2094。
