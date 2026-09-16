# 键盘按键显示

> **范围**：`scripts/keyboard/`、`services/KeycapDisplay.qml`、
> `modules/ii/keycapDisplay/`
> **历史变更**：[CHANGELOG.md](../CHANGELOG.md)

在屏幕上实时显示当前按下的按键，组合键按顺序排开，全部松开后延迟淡出。
开关在 **设置 → 桌面 → 按键显示**，默认关闭。

## 为什么需要额外权限

按键事件的唯一来源是 `/dev/input/event*`，而它的属主是 `root:input`
（`crw-rw----`）。所以要么把用户加进 `input` 组，要么写 udev 规则：

~~~bash
sudo usermod -aG input "$USER"   # 之后需要重新登录
id -nG                            # 确认 input 已在组列表里
~~~

没加组也能装、也能开开关，只是守护读不到设备，此时设置页会直接把原因显示出来
（读取守护 stderr 的报错），不用去猜为什么没反应。

## 实现

~~~
/dev/input/event*
  └─ scripts/keyboard/keycap-reader.py     （常驻，单线程 select，只读不 grab）
       └─ stdout 逐行 {"keys": ["Ctrl","A"]}
            └─ services/KeycapDisplay.qml   （Process + SplitParser）
                 └─ modules/ii/keycapDisplay/KeycapOverlay.qml  （layer-shell 浮层）
~~~

几个刻意的选择：

- **只读，绝不 `EVIOCGRAB`**。抓设备会让按键不再进到应用里，那是键盘重映射工具的
  活。这里只旁观，所以对输入毫无影响，也不会和其它键盘工具打架。
- **单线程 `select` 多路复用**。没有轮询、没有定时唤醒，空闲时进程完全睡着；
  设备列表每 5 秒重扫一次，插拔外接键盘不用重启守护。
- **状态分两层**。`heldKeys` 是守护上报的真实按住集合（松手即空），
  `shownKeys` 是界面要画的东西 —— 按下立刻跟上，全部松开后再留
  `timeout` 毫秒才淡出，否则快速点一下根本来不及看见。
- **过滤鼠标按键**。`BTN_*` 与 `KEY_*` 的码值区间是**重叠**的
  （`BTN_TRIGGER_HAPPY` 在 `0x2c0`，而 `KEY_*` 一直用到 `0x2ff`），
  所以不能用「码值 ≥ 256 就是鼠标键」这种区间判断，而是用从内核头文件生成的
  `BTN_CODES` 集合精确排除。自动重复（`value == 2`）也跳过，按住不放不会刷屏。
- **浮层不吃输入**。`mask` 只覆盖键帽本身、键帽上没有 `MouseArea`，
  点击会穿透到下面的窗口。
- **修饰键单独着色**。Ctrl / Shift / Alt / Super 用主色描边，组合键一眼能看出
  哪个是修饰键。

## 键名表

`scripts/keyboard/keynames.py` 是**自动生成**的（387 个键码 + 110 个 `BTN_*`），
不要手改：

~~~bash
./scripts/keyboard/gen-keynames.py
~~~

来源是 `/usr/include/linux/input-event-codes.h`。手写键名表很容易漏掉多媒体键、
小键盘、国际键盘的键位；生成物随仓库提交，所以运行时不再依赖那个头文件。

## 测试

按键没法在测试里合成（`ydotool` 需要额外装，`uinput` 需要 root），所以解析逻辑
被抽成了 `parse_buffer()`，测试直接伪造 `input_event` 字节：

~~~bash
./scripts/keyboard/test-keycap-reader.py
~~~

覆盖组合键顺序、自动重复、鼠标按键过滤、非按键事件、重复松开、未知键码兜底、
一包多事件、截断数据等情况。

## 相关配置

~~~json
{
  "keycapDisplay": {
    "enable": false,
    "timeout": 1200,
    "position": "bottom"
  }
}
~~~

- `timeout`：全部松开后键帽再停留多久（毫秒）。
- `position`：`bottom`（默认）或 `top`。
