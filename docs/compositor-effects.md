# 合成器层模糊与窗口透明度（niri ↔ Hyprland 参数对照）

> 范围：**合成器自己**做的背景模糊与窗口透明度。
> 不含 QML 自绘模糊（那部分见 [backdrop-blur.md](backdrop-blur.md)）。
> 目标：两个合成器下观感一致 —— **以 niri 的数值为准，移植到 Hyprland**。

## 1. 参数对照表

| 概念 | niri | Hyprland | 说明 |
|---|---|---|---|
| 模糊强度 | `blur { offset 3 }` | `decoration.blur.size = 3` | 见下方「⚠ 语义不同」 |
| 迭代次数 | `blur { passes 3 }` | `decoration.blur.passes = 3` | 两边同名同义 ✓ |
| 噪点 | `blur { noise 0.02 }` | `decoration.blur.noise = 0.02` | 消除色带，两边同义 ✓ |
| 饱和度 | `blur { saturation 1.5 }` | **无对应项** | 见下方「⚠ 无法移植」 |
| 透底采样 | `background-effect { xray true }` | `decoration.blur.xray = true` | 两边都有，语义一致 |
| 窗口透明度 | `window-rule { opacity 0.97 }` | `decoration.active_opacity` / `inactive_opacity` | 见下方「⚠ 活跃/非活跃」 |

### ⚠ 语义不同：`offset` 不是模糊半径

niri 用的是 **dual kawase** 模糊，`offset` 是**每 pass 的像素偏移乘数**，不是半径：

> `offset` is the pixel offset multiplier for each pass. Offset `1` is the original
> dual kawase blur. Larger values produce a smoother blur, at no additional GPU cost.

而 Hyprland 的 `size` 是模糊半径。两者算法不同，**数值取相同值（3）只是让强度量级接近**，
不会像素级一致。想更精确，在 niri 里微调 `offset` 试出来（官方建议：先加 `offset`
直到出现伪影，再 +1 `passes`）。

### ⚠ 无法移植：`saturation`

niri 的 `saturation 1.5` 是**模糊背景的饱和度倍率**（>1 增艳）。
Hyprland 没有这个参数；最接近的是 `vibrancy`（背景色**渗透强度**，0~1），
语义不同 —— 一个是饱和度倍率，一个是渗透量。**不要硬套数值**。

### ⚠ 活跃 / 非活跃

- **niri 没有 active/inactive 之分**：`opacity` 是全局的，所有窗口都是 0.97，
  不管是否聚焦。
- **Hyprland 有** `active_opacity` 和 `inactive_opacity` 两个值。

为了和 niri 一致，Hyprland 两侧**都设为 0.97**。代价：失去「失焦窗口变淡」的
视觉区分 —— 但 niri 本来就没有这个区分。

如果你更想要失焦区分，把 `inactive_opacity` 单独调淡（如 0.85），只让活跃窗口
对齐 niri 的 0.97。

## 2. 值在哪里改

### niri（源，直接改）
```
~/.config/niri/blur.kdl      # blur { passes / offset / noise / saturation }
~/.config/niri/rule.kdl      # 全局 window-rule { opacity }
```

### Hyprland（目标，分两处）

| 参数 | 文件 | 能否直接改 |
|---|---|---|
| `noise` | `~/.config/hypr/custom/general.lua` | ✅ 可以 |
| `xray` / `vibrancy` / `brightness` / `contrast` | 同上 | ✅ 可以 |
| `size` / `passes` / `active_opacity` / `inactive_opacity` | `~/.config/hypr/hyprland/shellOverrides/main.lua` | ⚠️ 见下 |

**`shellOverrides/main.lua` 是 DMS 生成的文件**（头部写着 "DO NOT EDIT. MANAGED
BY THE SHELL"），且它在加载顺序的**最后一步**被 require —— 所以 `custom/general.lua`
里写 `size` 是**覆盖不掉**它的。

两种正规改法：
1. **Quickshell 设置 → 「配置文件」→「Hyprland」面板的滑条**（会重写该文件）；
2. 直接编辑该文件（见效快，但 DMS 下次写设置时会覆盖回去）。

## 3. SUPER + A 为什么删了

原绑定（`hyprland/keybinds.lua`）：

```lua
hl.bind("SUPER + A", function()
    -- active_opacity 在 0.65 ↔ 1.0 之间切换
end, { description = "Shell: Toggle active window opacity" })
```

它用 `hl.config()` 直接写 `decoration.active_opacity`（因为 `setprop` 对该属性无效）。
透明度对齐到 0.97 之后，**一按这个键就会把 0.97 覆盖成 0.65 或 1.0**，破坏对齐。

→ 已移除。临时改透明度请用 `hyprctl` 或设置面板。

保留的相邻绑定（**没有**被误删）：
- `SUPER + ALT + A` — 左侧边栏 detach
- `SUPER + SHIFT + A` — Google Lens / snip to search

残留：`hyprland/scripts/toggle_window_opacity.sh` 现在没有任何调用者（孤儿脚本），
暂时保留，确认不用后可删。

## 4. 改完怎么生效

```bash
# Hyprland
hyprctl reload

# niri
niri msg action do-screen-transition   # 或直接重启会话
```
