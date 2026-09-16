# 键盘按键显示

> **范围**：`scripts/keyboard/`、`services/KeycapDisplay.qml`、
> `modules/ii/keycapDisplay/`
> **历史变更**：[CHANGELOG.md](../CHANGELOG.md)

在屏幕上显示两样东西，对应两种完全不同的需求：

| 显示 | 内容 | 用途 |
|---|---|---|
| **键帽** | 修饰键（Ctrl/Shift/Alt/Super）、`Ctrl+Alt+Del` 这类组合键、方向键 / F 键等不可打印键 | 看快捷键 |
| **文本** | 打出来的可见字符累积成一行可读文本 | **看自己打了什么** |

可打印字符**只走文本、不进键帽** —— 否则打一个单词会变成一堆单独闪过的键帽，
永远读不出内容。修饰键与组合键反过来只走键帽，因为那是快捷键而不是输入。

开关在 **设置 → 桌面 → 按键显示**，默认关闭。其中「显示已输入的文本（可读）」
可以单独关掉，那样就退化成纯键帽模式（看快捷键用）。

## 为什么需要额外权限

按键事件的唯一来源是 `/dev/input/event*`，而它的属主是 `root:input`
（`crw-rw----`）。所以要么把用户加进 `input` 组，要么写 udev 规则：

~~~bash
sudo usermod -aG input "$USER"   # 之后需要重新登录
id -nG                            # 确认 input 已在组列表里
~~~

没加组也能装、也能开开关，只是守护读不到设备，此时设置页会直接把原因显示出来
（读取守护 stderr 的错误码并翻译），不用去猜为什么没反应。

## 实现

~~~
/dev/input/event*
  └─ scripts/keyboard/keycap-reader.py     （常驻，单线程 select，只读不 grab）
       └─ stdout 逐行 {"keys": ["Ctrl","Shift"], "text": "hello wor"}
            └─ services/KeycapDisplay.qml   （Process + SplitParser）
                 └─ modules/ii/keycapDisplay/KeycapOverlay.qml  （layer-shell 浮层）
~~~

守护每行输出一个**状态快照**（不是事件流），界面因此不需要维护任何状态机：
`keys` 是要画成键帽的键，`text` 是已输入的文本。

几个刻意的选择：

- **只读，绝不 `EVIOCGRAB`**。抓设备会让按键不再进到应用里，那是键盘重映射工具的
  活。这里只旁观，所以对输入毫无影响，也不会和其它键盘工具打架。
- **单线程 `select` 多路复用**。没有轮询：只有「屏幕上还有文本」时才用 0.5 秒的
  select 超时去检查该不该清空文本，没有文本时完全睡着。设备列表每 5 秒重扫一次，
  插拔外接键盘不用重启守护。
- **松开字母不会回退文本**。文本是「已经打出来的历史」，如果松开就删掉，
  边打边消失，还是读不出单词。
- **两种时长分开**。键帽松开后停留 `timeout`（默认 1600ms，看一眼就够）；
  文本在停止输入 `textTimeout`（默认 5000ms）后才清空 —— 文本是要读的，需要更长。
  两个超时都由守护掌握，界面不做第二套计时，否则两边时间对不上会出现
  「界面清空了、下次按键又冒出旧文本」。
- **组合键优先于文本**。按住 Ctrl/Alt/Super 时，其余按键一律当组合键显示成键帽，
  不追加进文本 —— `Ctrl+A` 是快捷键，不是打了字母 a。
- **Caps Lock 只影响大小写**，本身不作为「按住」展示（它是锁，不是按住）。
- **自动重复（`value == 2`）不追加**，按住不放不会刷出一串 aaaa。
- **过滤鼠标按键**。`BTN_*` 与 `KEY_*` 的码值区间是**重叠**的
  （`BTN_TRIGGER_HAPPY` 在 `0x2c0`，而 `KEY_*` 一直用到 `0x2ff`），
  所以不能用「码值 ≥ 256 就是鼠标键」这种区间判断，而是用从内核头文件生成的
  `BTN_CODES` 集合精确排除。
- **浮层不吃输入**。`mask` 只覆盖内容本身、里面没有 `MouseArea`，
  点击会穿透到下面的窗口。
- **逐字符渲染文本**。每个字符是独立 delegate，新字符弹入 —— 比整块文本一起闪
  更有「正在打字」的感觉。

## 键名表与字符映射

`scripts/keyboard/keynames.py` 是**自动生成**的（387 个键码 + 110 个 `BTN_*`），
不要手改：

~~~bash
./scripts/keyboard/gen-keynames.py
~~~

来源是 `/usr/include/linux/input-event-codes.h`。手写键名表很容易漏掉多媒体键、
小键盘、国际键盘的键位；生成物随仓库提交，所以运行时不再依赖那个头文件。

**字符映射（键码 → 实际字符）是按 US 布局写死的**，在 `keycap-reader.py` 的
`US_MAP` 里。evdev 只给键码不给字符，要还原「打了什么字」必须有一张布局表；
本机 `kb_layout = us`，所以直接按 US 映射。**换成别的布局时字符会不对**，
那种情况请关掉「显示已输入的文本」，只保留键帽模式（或自行扩展 `US_MAP`）。

## 测试

按键没法在测试里合成（`ydotool` 需要额外装，`uinput` 需要 root），所以逻辑被抽成
`Session` / `parse_buffer`，测试直接伪造 `input_event` 字节：

~~~bash
./scripts/keyboard/test-keycap-reader.py
~~~

33 项，覆盖：打 hello 的可读性、空格断词、退格、Esc 清空、Shift / Caps 的大小写、
`Ctrl+a` 走键帽而不进文本、`Super+Shift+;` 同理、方向键走键帽、Enter 断词、
自动重复不刷屏、鼠标按键过滤、文本长度上限、闲置超时清空、`--no-text` 退化模式、
一包多事件、截断数据、快照 JSON 格式。

## 相关配置

~~~json
{
  "keycapDisplay": {
    "enable": false,
    "showTypedText": true,
    "timeout": 1600,
    "textTimeout": 5000,
    "maxTextLength": 48,
    "position": "bottom"
  }
}
~~~

- `showTypedText`：关掉就只显示键帽（快捷键模式，也适用于非 US 布局）。
- `timeout`：键帽松开后停留多久（毫秒）。
- `textTimeout`：停止输入多久后清空文本（毫秒）。
- `maxTextLength`：文本缓冲区上限，超出丢最老的，避免浮层无限变宽。
- `position`：`bottom`（默认）或 `top`。
