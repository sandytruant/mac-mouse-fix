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

## 来源

遵循 [MMF License](../License)。HID++ 传输层基于 lcandy2 的 PR #1995，报文解析参考 PR #2094。
