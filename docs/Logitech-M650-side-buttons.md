# M650 L 侧键按住实验

这是默认开启的 HID++ 输入修复，尚未完成全部实机验证。仅接管可 diversion 的 Back `0053 → 按钮4`、Forward `0056 → 按钮5`；不修改中键、MX 手势、DPI、滚轮、pressure 判断或授权/付费逻辑。

## 使用 / 关闭

1. 默认开启，无需配置。建议退出 Options+、Solaar 等会争用侧键的程序。
2. 在按钮页面给 4/5 绑定动作（如“点按+拖移”）即可使用。
3. 如需关闭：退出 helper 后，在 `~/Library/Application Support/com.andysun.mac-mouse-fix.dev/config.plist` 的 `General` 字典内加入下列内容，再重启 helper：
   ```xml
   <key>logitechSideButtons</key><false/>
   ```
   开关仅在启动后于 IOThread 读取一次；缺失视为开启。不修改默认配置，也不自动写用户配置。
4. 崩溃、SIGKILL 后无需给鼠标断电：下次启动会接管残留的临时 diversion，正常退出时再清除。

## 边界与安全取舍

- **能力限制**：当前不扩展 `Device.nOfButtons` 或 SwitchMaster 能力掩码。HID 描述已包含按钮 1–5 时没有此限制；若所有已附加设备只声明少于5键，4/5 的映射可能不会被监听，本实验尚不支持该描述布局。不要通过“所有 Logitech 至少五键”绕过；后续应仅发布已成功接管的能力，并处理异步撤销与 held 的顺序。
- 匹配 Logitech vendor collection，直接蓝牙，以及 PR1995 的已知接收器 PID `C52B/C532/C534/C548/C547` 的槽位1–6。启用后作用于这些接口上所有符合条件的侧键，不只 M650。`C53F` 等未知 USB 布局和 USB 直连暂不探测，不能仅凭产品名称推断槽位协议。
- **没有进行 M650/Bolt/多接收器实机验证**。IORegistry 中出现接收器不等于协议验证通过。测试不会打开 HID manager、发设备报告、投递鼠标事件或修改配置。
- Sender ID：直接蓝牙接口同时声明 mouse collection 时使用其 registry ID。接收器使用同一 USB 设备（VendorID/ProductID/`LocationID` 相同）下唯一声明 mouse collection `(1,2)` 的兄弟接口的 registry ID，与该接收器原生鼠标事件解析到的设备一致（例：C548 vendor 接口 `0x…efe` → 鼠标接口 `0x…f03`），两个同型号接收器也能区分。接收器先出现 HID++ 接口时，后续核验会补解析。找不到或不唯一时显式使用0，回退到 `NO_FILTER` 的 StrangeDevice。同一接收器上的多只鼠标与原生行为一样共用接收器身份。不按 PID 匹配 DeviceManager。
- 保存原 reporting flags/remap，写入仅设置临时 divert 的 valid 位；remap参数0表示不改变。**启动时发现的临时 diversion 视为自己崩溃残留并接管**，原始状态记为“未 divert”，退出时清除；持久 diversion 位不动。代价：若 Options+ 正在运行并已 divert 侧键，会被抢走，因此建议不要同时运行。运行期间观察到其他客户端修改 flags/remap 后放弃该控制，直到重新连接才重试，避免反复争抢。ACK 与完整 CID/readback 匹配后才开始合成输入；丢 ACK 的写入保留清理责任并尝试回退。
- 没有硬件原子 ownership/lease：另一程序若写出完全相同的状态无法识别。接收器槽位断连（HID++1 `0x41`，byte 4 bit 6）后丢弃旧 ownership，防止恢复到换入的另一只鼠标。
- 每30秒核验**每个**接管控制，重试初始睡眠/缺失控制；系统唤醒、接收器连接通知、`0x1D4B` 重连通知会立即核验，并在1秒、3秒后各再核验一次；新出现的接口（如蓝牙重连）同样在1秒、3秒后补核验，覆盖鼠标刚连上还不应答的情况。日志会注明接管发生在 receiver/direct、PID 和槽位。正常保持 diversion 或仅查询超时不会释放长按。确认 diversion 已消失时仅释放该控制；断连/正常退出释放全部 held。无法区分丢失 release 报告和真实长按，不使用超时强行抬起。唤醒鼠标的那次按键发生在重新接管之前，仍是原生点击。
- 所有命令和清理串行运行在独立 IOHIDLib worker；请求等待仅泵该线程 run loop。worker 不读取 Config/DeviceManager，也不等待 main/IOThread。SIGTERM/SIGINT 经 dispatch signal source 在普通上下文清理，**不是 signal-safe ObjC 调用**。正常退出最多等4秒，先释放全部 held，再逐控制恢复；多设备/离线超时可能无法在退出前完成硬件恢复，下次启动会接管并清理。
- 合成事件保持原输入路径，整数 pressure 为 down=1/up=0，时间戳使用 `CLOCK_UPTIME_RAW` 纳秒而非 `mach_absolute_time()` 原始 ticks。

## 自动测试

```sh
sh Tests/Logitech/run.sh
plutil -lint 'Mouse Fix.xcodeproj/project.pbxproj'
git diff --check
```

需 macOS/Xcode 命令行工具。ASan/UBSan 纯协议测试覆盖 framing、槽位/命令/CID、接收器连接 link 标志、侧键过滤、64种状态转换；fake transport 编译生产实现，覆盖原 remap 保留、崩溃残留接管与清除（保留持久位）、运行期 foreign diversion、丢 ACK 回退、短包/错误CID、第二个控制丢 diversion、长按跨多次核验/超时、睡眠初始重试、串行清理及幂等退出。CGEventPost 被截获，只检查按钮号、pressure、sender、时间戳。

实机待测：单侧键持续超过90秒且不断拖移；双侧键两种释放顺序；只让第二侧键丢 diversion；按住时断开/重连；鼠标休眠唤醒后多久恢复；kill -9 helper 后重启是否直接可用；正常停用/SIGTERM 后原生点击恢复；其他按钮/指针/滚轮不变；多个接收器不发生错误 sender 归属。硬件验证仍待测试者执行。

## 来源

保留 [MMF License](../License)。IOHIDLib worker、串行 run-loop transport 与发现流程基于 **lcandy2 的 PR #1995**（commit `a874b40130ba0ab9bbea9e3eab57b5fa5de12f34`）。framing、响应长度/CID 检查、ACK/readback、ownership 及 fake transport 测试思路借鉴 PR #2094；没有引入其 MX 手势/DPI/UI 变更，也不继承其硬件测试结论。
