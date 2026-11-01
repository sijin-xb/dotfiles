// ─────────────────────────────────────────────────────────────────────────────
// 从 Brain_Shell 移植：src/modules/Center/CenterContent.qml
//
// 这是 Bar 中间那段 notch 的**收起态内容** —— 一个可滚轮切换的轮播：
//   clock（纯时间 HH:MM:SS，默认） / music / timer / stopwatch / record_setup
//
// 改动：
//   1. 删掉相对 import（"../../"、"../../services/home/."），
//      扁平化到 custom-island/ 后靠同目录隐式导入解析 Theme 等单例；
//   2. 给 Nerd Font 字形的 Text 补 font.family: Theme.nerdFontFamily
//      （end4-pC 主字体不含 Nerd 字形，不补会渲染成豆腐块）；
//   3. 默认项 "title"（窗口标题）→ "clock"（纯时间 HH:MM:SS，无图标无日期），
//      并删掉配套的 hyprctl 标题抓取 Process 与 Hyprland RawEvent 监听；
//   4. 去掉展开仪表盘时整层淡出（岛屿的胶囊宽度固定，内容应保持可见）；
//   5. MPRIS 改走 MprisController.activePlayer，过滤浏览器播放；
//   6. 时间精确到秒，用自起的秒级 SystemClock 驱动（不依赖全局秒精度开关），
//      字体从等宽换成主题的数字字体（appearance.fonts.numbers）；
//   7. 移除收起态的「录制中」状态（record_active：秒数计时 / 丢弃 / 停止）：
//      录制中不再劫持收起态轮播。录屏设置条（record_setup）与录屏功能本身
//      保留，供其它灵动岛共用。
// ─────────────────────────────────────────────────────────────────────────────

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Io
// MprisController：用它替代裸 Mpris.players，才能过滤掉浏览器播放（见下方说明）
// DateTime：收起态默认项要显示纯时间
import qs.services
// StyledText：Bar 上所有文字都用它 —— 收起态时钟也走同一个组件，
// 字体族/字号/variableAxes 才会和邻居完全同源（见下面 Clock 那段的说明）
import qs.modules.common.widgets
// Appearance：clockMeasure / clockText 的字号令牌（pixelSize.smaller）要用。
// 之前漏了这条 import，字号绑定 ReferenceError 静默失败，字号实际没降下来。
import qs.modules.common

// CenterContent — scrollable dynamic island carousel.
//
// Active item order:
//   "clock"     — always present (default, 纯时间 HH:MM)
//   "music"     — MPRIS player present
//   "timer"     — ClockState.timerRunning
//   "stopwatch" — ClockState.swRunning
//
// CenterNotchMonitor (internal QtObject) watches ClockState and
// handles urgent transitions:
//   • timer <= 30s remaining → force-scroll to timer, text blinks red
//   • stopwatch active → appears in carousel, scrolls if on clock
//
// Cava bars: single Rectangle per bar, anchors.centerIn — grows
// symmetrically. No center rounding artefact. 5px wide.

Item {
	id: root

	// ── 宽度：跟随当前轮播项的内容，不再写死 300 ──────────────────────────
	// 旧实现固定 Theme.cNotchMinWidth(300)，屏幕实测岛屿胶囊 300px 而时钟文字
	// 只有约 135px → 左右各空 82px，与同一条栏上内容自适应的邻居（media 101 /
	// sysTray 93 / resources 80）并排就是「又胖又空」。
	//
	// ⚠⚠ v3：clock 的宽度测量改用隐藏 StyledText（clockMeasure）直读。
	// 之前（52cb1f9）走的是 statusList.itemAtIndex(index) 读 delegate 上报——
	// **itemAtIndex() 不是响应式绑定**：冷启动首帧求值时 delegate 尚未实例化，
	// 返回 null → 永远退回 300，之后绑定不再重算。于是「自适应」只在编辑器
	// 触发热重载（delegate 已在）时碰巧生效，每次重启 qs 都打回 300 原形。
	// 隐藏 Text 与显示的 clockText 同源（同 StyledText / 同令牌 / 同 tnum），
	// implicitWidth 恒可用且绑定恒响应式，彻底摆脱 ListView 的实例化时机。
	// clockNaturalWidth 的计算见下方隐藏测量区（rowMaterial 组合测量）

	// ── 多形态宽度（对齐「其他组件各有各的宽」的体系）────────────────────────
	// 每个轮播项有自己的形态宽：clock 贴内容、timer/stopwatch 跟随计时文本、
	// music 给 cava 一个舒适的下限、record_setup 维持基准宽（三按钮 + 弹性
	// spacer 的固定布局，收窄会挤爆）。切换时宽度走 Island.qml 的标准曲线动画。
	readonly property real currentContentWidth: {
		switch (root._items[root._carouselIndex]) {
		case "clock":     return root.clockNaturalWidth
		case "timer":     return Math.max(180, root.timerNaturalWidth + 115)
		case "stopwatch": return Math.max(180, root.swNaturalWidth + 115)
		case "music":     return 150
		default:          return Theme.cNotchMinWidth  // record_setup
		}
	}

	readonly property int requiredWidth: IslandState.capsuleWidthFor(root.currentContentWidth)

	width:  requiredWidth
	height: 30

	// ── 隐藏测量 Text（不参与布局与渲染，只当尺子用）────────────────────────
	// ⚠ 每把尺子都必须与显示端逐属性同源（同组件/同字号/同字重/同字体族），
	//   显示端改样式时这里必须同步，否则测量失真。
	// clock 尺（rowMaterial 形态）：日期尺 + 时间尺，组合出总宽 ——
	//   日期宽 + leftPadding 5 + Row spacing 4 + 药丸(时间宽 + 16)
	//   （AM/PM / 图标药丸随可见性另行累加，与显示端 Row 的布局规则一致）
	StyledText {
		id: clockDateMeasure
		visible: false
		text: DateTime.longDate
		font.pixelSize: Appearance.font.pixelSize.small
	}
	StyledText {
		id: clockTimeMeasure
		visible: false
		text: (Config.options.bar.clock.showSeconds
		       ? DateTime.hourStr + ":" + DateTime.minuteStr + ":" + root.secondStr
		       : DateTime.hourStr + ":" + DateTime.minuteStr)
		font.pixelSize: Appearance.font.pixelSize.smallie
		font.weight: Font.Bold
		font.features: { "tnum": 1 }
		font.letterSpacing: -0.4
	}
	readonly property real clockNaturalWidth: {
		let w = 0
		if (Config.options.bar.clock.showDate)
			w += clockDateMeasure.implicitWidth + 5      // leftPadding 5
		w += 4 + clockTimeMeasure.implicitWidth + 16      // Row spacing + 药丸 padding
		if (DateTime.use12HourFormat && Config.options.bar.clock.showAmPm)
			w += 4 + 8                                   // AM/PM 小药丸（近似，短文本）
		if (Config.options.bar.clock.showIcon)
			w += 4 + 25
		return w
	}
	// timer / stopwatch 尺：与显示端同参（15 bold mono）。
	// +115 的常数 = 结构留白：左图标 15+16、文本侧隙 8+8、右按钮区 47+15。
	Text {
		id: timerMeasure
		visible: false
		text: ClockState.timerDisplay
		font.pixelSize: 15
		font.weight: Font.Bold
		font.family: Theme.monoFontFamily
	}
	Text {
		id: swMeasure
		visible: false
		text: ClockState.swDisplay
		font.pixelSize: 15
		font.weight: Font.Bold
		font.family: Theme.monoFontFamily
	}
	readonly property real timerNaturalWidth: timerMeasure.implicitWidth
	readonly property real swNaturalWidth: swMeasure.implicitWidth

	// ── Required notch width for the current carousel item ────────────────────
	// TopBar.cWidth reads this so the notch always matches what is visible.
	readonly property int fw: Theme.notchRadius

	// ── 秒级时钟 ─────────────────────────────────────────────────────────────
	// ⚠ 与上游的差异（按需求新增）：
	// DateTime.clock 的 precision 由 Config.options.time.secondPrecision 决定，
	// 没开时是分钟级 —— 直接拿它取秒会得到一个静止不动的数字。
	// 这里自起一个秒级 SystemClock 专供收起态显示：既保证秒一定在走，
	// 又不必为了一个胶囊去打开全局的秒精度开关（那会连带 Bar / 侧栏的时钟一起变秒级）。
	SystemClock {
		id: secondClock
		precision: SystemClock.Seconds
	}

	readonly property string secondStr: Qt.locale().toString(secondClock.date, "ss")
	// ── MPRIS ─────────────────────────────────────────────────────────────────
	// ⚠ 与上游的差异（必要修复）：
	// Brain_Shell 直接取 Mpris.players.values[0]，只要系统里存在任何 MPRIS
	// 播放器就当作"正在播放"——浏览器（Chrome/Brave/Firefox）通过
	// plasma-browser-integration 之类的桥也会注册成 MPRIS 播放器，
	// 于是随便开个网页都会在岛上显示成音乐。
	// end4-pC 有现成的 MprisController.activePlayer，它按
	// Config.options.media.ignoreBrowserPlayers（用户已开）过滤浏览器桥，
	// 所以这里改用它，语义变成"只识别真正的媒体播放器"。
	readonly property var    player:    MprisController.activePlayer
	readonly property bool   isPlaying: player?.playbackState === MprisPlaybackState.Playing
	?? false
	readonly property string artUrl:    player?.trackArtUrl ?? ""

	// ── 已移除：上游的「窗口标题」抓取 ────────────────────────────────────────
	// 上游这里有一个 Process 调 `hyprctl activewindow -j` 取 initialTitle，
	// 再挂 Hyprland 的 RawEvent 在每次切窗口/工作区时重跑一次，把结果写进
	// activeTitle 给 title 轮播项显示。
	// 现在默认项换成时间（见下方 _items），activeTitle 没有任何地方再读，
	// 整块（含 import Quickshell.Hyprland）一并删除 —— 否则每次切窗口都会
	// 白 spawn 一个 hyprctl 进程。

	// ── Dynamic item list ─────────────────────────────────────────────────────
	// ⚠ 与上游的差异（按需求改）：
	// 上游的默认项是 "title"（当前窗口标题）。这里换成 "clock"（纯时间）。
	// 窗口标题在 Bar 上没什么用（左侧 activeWindow 组件已经在显示了），
	// 而时间是这个位置原本就该有的东西。
	property var  _items:         ["clock"]
	property int  _carouselIndex: 0
	readonly property real _itemStride: 45  // 30px height + 15px spacing

	function _rebuildItems(autoScrollType) {
		var currentType = (_items.length > _carouselIndex)
		? _items[_carouselIndex] : "clock"

		var list = ["clock"]
		if (root.player                    !== null) list.push("music")
		if (ClockState.timerStarted)                   list.push("timer")
		if (ClockState.swStarted)                      list.push("stopwatch")
		if (ShellState.screenRecord && !ScreenRecService.recording) list.push("record_setup")

		root._items = list

		var idx = list.indexOf(currentType)
		if (idx < 0) idx = 0

		if (autoScrollType) {
			var nIdx = list.indexOf(autoScrollType)
			if (nIdx >= 0) {
				// 录屏设置条（record_setup）总是抢占滚动；
				// 其它项只在当前项是 clock（默认项）时才自动滚过去。
				if (autoScrollType === "record_setup" || currentType === "clock")
				idx = nIdx
			}
		}

		root._carouselIndex = idx
		statusList.contentY = idx * root._itemStride
	}

	// Force-scroll to a specific type regardless of where the user is
	function _forceScrollTo(type) {
		var idx = root._items.indexOf(type)
		if (idx < 0) return
		root._carouselIndex = idx
		statusList.contentY = idx * root._itemStride
	}

	onPlayerChanged: _rebuildItems(player !== null ? "music" : null)

	// ── State monitor — timer urgency + carousel transitions ─────────────────
	readonly property bool timerUrgent:
	ClockState.timerRunning && ClockState.timerLeft <= 30 && ClockState.timerLeft > 0

	Connections {
		target: ClockState

		function onTimerRunningChanged() {
			root._rebuildItems(ClockState.timerRunning ? "timer" : null)
		}

		function onSwStartedChanged() {
			root._rebuildItems(ClockState.swStarted ? "stopwatch" : null)
			root._forceScrollTo("stopwatch")
		}

		function onTimerLeftChanged() {
			if (ClockState.timerRunning && ClockState.timerLeft === 30 || ClockState.timerRunning && ClockState.timerLeft === 10)
			root._forceScrollTo("timer")
		}
		
		function onTimerStartedChanged() {
			root._rebuildItems(ClockState.timerStarted ? "timer" : null)
			root._forceScrollTo("timer")
		}
	}

	Connections {
		target: ShellState
		function onScreenRecordChanged() {
			if (ShellState.screenRecord && !ScreenRecService.recording)
			root._rebuildItems("record_setup")
			else if (!ShellState.screenRecord)
			root._rebuildItems(null)
		}
	}

	// 录制开始/结束时刷新列表：record_setup 只在「未录制」时出现，
	// 录制中收起态不显示任何录屏内容（原来的 record_active 已移除）。
	Connections {
		target: ScreenRecService
		function onRecordingChanged() {
			root._rebuildItems(null)
		}
	}

	// ── Scroll debounce ───────────────────────────────────────────────────────
	property bool _scrollBusy: false
	Timer {
		id: scrollCooldown
		interval: 250
		onTriggered: root._scrollBusy = false
	}

	// ── Cava — shared via CavaService singleton ─────────────────────────────
	readonly property int _cavaBars: CavaService.barCount
	readonly property var _bars:     CavaService.bars

	// ── Carousel ──────────────────────────────────────────────────────────────
	Item {
		anchors.fill: parent

		// ⚠ 与上游的差异（按需求改）：
		// 上游这里写的是 opacity: Popups.dashboardOpen ? 0 : 1 —— 展开仪表盘时
		// 把收起态内容整个淡出。那是因为上游的 notch 会撑大成面板、内容留在
		// 里面会显得奇怪。
		// 岛屿的胶囊宽度固定 300（Bar 中间区是 anchors.centerIn，中间组件变宽
		// 会盖住左右两组），面板是在胶囊下方独立展开的，所以胶囊内容应当保持
		// 可见 —— 否则展开时 Bar 中间会留一个空胶囊。
		opacity: 1

		WheelHandler {
			acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
			onWheel: function(event) {
				// Block scroll only during setup (not during active recording)
				if (ShellState.screenRecord && !ScreenRecService.recording) return
				if (root._scrollBusy) return
				root._scrollBusy = true
				scrollCooldown.restart()

				var maxIdx = root._items.length - 1
				if (event.angleDelta.y < 0)
				root._carouselIndex = Math.min(maxIdx, root._carouselIndex + 1)
				else
				root._carouselIndex = Math.max(0, root._carouselIndex - 1)

				statusList.contentY = root._carouselIndex * root._itemStride
			}
		}

		ListView {
			id: statusList
			anchors.fill: parent
			orientation:  ListView.Vertical
			spacing:      15
			clip:         true
			snapMode:     ListView.SnapOneItem
			interactive:  false

			Behavior on contentY {
				NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
			}

			model: root._items

			delegate: Item {
				required property string modelData
				required property int    index

				// 跟随容器宽度（容器由根上的 currentContentWidth 反推出来；
				// clock 的测量已改走根上的隐藏 Text，见 clockNaturalWidth 注释）
				width:  root.requiredWidth
				height: 30

				// ── Clock ──────────────────────────────────────────────────────
				// 默认项：日期 + 时间（HH:MM:SS）。**不带日历图标**（按需求）。
				// 上游这里是"当前窗口标题"，换成时间是因为 Bar 左侧的
				// activeWindow 组件已经在显示窗口标题了。
				//
				// ── 字体：走 StyledText，与 Bar 上其它文字**同一条逻辑** ────────
				// 以前这里写死 font.family: Theme.clockFontFamily（"Space Grotesk"）
				// + font.pixelSize: 14，结果：设置面板里改字体对它无效，而且它和
				// 邻居的字形/字号都不一致 —— 同一排胶囊里两套字体，一眼就能看出。
				//
				// 现在用 StyledText，它自带的那套判定就是 Bar 其它组件的判定：
				//   shouldUseNumberFont = /^\d+$/.test(text)
				//   → 纯数字用 appearance.fonts.numbers，否则用 appearance.fonts.main
				//   → 字号 appearance.font.pixelSize.small
				//   → variableAxes 取 main 的字重/字宽
				// ── 2026-10-04 收起态照搬 ClockWidget 的 rowMaterial 分支 ──────
				// 溯源：middleLayout = [island, clockWidget]，cornerStyle 3 →
				// BarWidgetSwitcher 选 rowMaterial。此处逐属性复刻该分支，
				// 并与右侧时钟读同一份 Config.options.bar.clock（显示项联动）：
				//   [日期 longDate · small · colOnPrimaryContainer]
				//   [时间药丸 colPrimary 底 · 高 24 · full 圆角 · smallie Bold
				//    onPrimary · tnum · letterSpacing -0.4]
				//   [AM/PM 小药丸 colTertiaryContainer · colPrimary 字 · 叠 -10]
				//   [日历图标药丸 colPrimary · showIcon 时]
				// 24 小时制（time.format 不含 ap）时 AM/PM 药丸自动隐藏。
				Row {
					anchors.centerIn: parent
					visible:      modelData === "clock"
					spacing:      4

					// 日期（rowMaterial 同款：leftPadding 5）
					StyledText {
						anchors.verticalCenter: parent.verticalCenter
						visible:    Config.options.bar.clock.showDate
						text:       DateTime.longDate
						font.pixelSize: Appearance.font.pixelSize.small
						color:      Appearance.colors.colOnPrimaryContainer
						leftPadding: 5
					}

					// 时间药丸（rowMaterial 同款）
					Rectangle {
						anchors.verticalCenter: parent.verticalCenter
						implicitWidth: timePillText.implicitWidth + 16
						implicitHeight: 24
						radius: Appearance.rounding.full
						color: Appearance.colors.colPrimary

						StyledText {
							id: timePillText
							anchors.centerIn: parent
							font.pixelSize: Appearance.font.pixelSize.smallie
							font.weight:    Font.Bold
							color:          Appearance.colors.colOnPrimary
							font.features:  { "tnum": 1 }
							font.letterSpacing: -0.4
							// 时间源与右侧时钟完全同源（DateTime 单例，
							// secondPrecision 已开，秒级跳动节奏一致）
							text: (Config.options.bar.clock.showSeconds
							       ? DateTime.hourStr + ":" + DateTime.minuteStr + ":" + root.secondStr
							       : DateTime.hourStr + ":" + DateTime.minuteStr)
						}
					}

					// AM/PM 小药丸（rowMaterial 同款：叠在时间药丸上 -10）
					Rectangle {
						visible:    DateTime.use12HourFormat && Config.options.bar.clock.showAmPm
						anchors.verticalCenter: parent.verticalCenter
						anchors.leftMargin: -10
						implicitWidth: ampmPillText.implicitWidth + 8
						implicitHeight: 24
						radius: Appearance.rounding.full
						color: Appearance.colors.colTertiaryContainer

						StyledText {
							id: ampmPillText
							anchors.centerIn: parent
							font.pixelSize: Appearance.font.pixelSize.smaller
							color:          Appearance.colors.colPrimary
							text:           DateTime.use12HourFormat
							                  ? Qt.locale().toString(secondClock.date, "ap") : ""
						}
					}

					// 日历图标（rowMaterial 同款：showIcon 时显示）
					Rectangle {
						visible:    Config.options.bar.clock.showIcon
						anchors.verticalCenter: parent.verticalCenter
						width: 25
						height: 25
						radius: Appearance.rounding.full
						color: Appearance.colors.colPrimary

						MaterialSymbol {
							anchors.centerIn: parent
							fill: 0
							text: "calendar_month"
							iconSize: Appearance.font.pixelSize.normal
							color: Appearance.colors.colOnPrimary
						}
					}
				}

				// ── Music ──────────────────────────────────────────────────────
				Item {
					anchors.fill: parent
					anchors.leftMargin: root.fw/2
					anchors.rightMargin: root.fw/2
					visible:      modelData === "music"

					readonly property int artSize: 20
					readonly property int artPad:   7

					Item {
						x:    parent.artPad
						anchors.verticalCenter: parent.verticalCenter
						width:  parent.artSize
						height: parent.artSize

						Rectangle {
							anchors.fill:  parent
							radius:        width / 2
							color:         Qt.rgba(Theme.active.r, Theme.active.g, Theme.active.b, 0.18)
							border.color:  Qt.rgba(Theme.active.r, Theme.active.g, Theme.active.b, 0.38)
							border.width:  1
							visible:       root.artUrl === ""
							Text {
								anchors.centerIn: parent
								text:           "♪"
								font.family:    Theme.nerdFontFamily
								font.pixelSize: 9
								color:          Theme.active
							}
						}

						Rectangle {
							id:            artMask
							anchors.fill:  parent
							radius:        width / 2
							visible:       false
							layer.enabled: true
						}

						Image {
							anchors.fill:  parent
							source:        root.artUrl
							fillMode:      Image.PreserveAspectCrop
							smooth:        true
							cache:         true
							visible:       root.artUrl !== ""
							layer.enabled: true
							layer.effect: MultiEffect {
								maskEnabled:      true
								maskSource:       artMask
								maskThresholdMin: 0.5
								maskSpreadAtMin:  1.0
							}
						}
					}

					Item {
						id: barsArea
						anchors {
							left:        parent.left
							leftMargin:  parent.artPad + parent.artSize + 5
							right:       parent.right
							rightMargin: 5
							top:         parent.top
							bottom:      parent.bottom
						}

						readonly property real _barW:       5
						readonly property real _barSpacing: Math.max(
							1,
							(width - _barW * root._cavaBars) / Math.max(1, root._cavaBars - 1))
							readonly property real _maxBarH:    height / 2

							Row {
								anchors.fill: parent
								spacing:      barsArea._barSpacing

								Repeater {
									model: root._bars
									delegate: Item {
										required property int modelData
										width:  barsArea._barW
										height: barsArea.height
										readonly property real _amp: modelData / 100.0
										Rectangle {
											anchors.centerIn: parent
											width:  barsArea._barW
											height: Math.max(2, _amp * barsArea._maxBarH * 2)
											radius: width / 2
											color:  Qt.rgba(
												Theme.active.r, Theme.active.g, Theme.active.b,
												0.28 + _amp * 0.72)
												Behavior on height {
													NumberAnimation { duration: 50; easing.type: Easing.OutCubic }
												}
											}
										}
									}
								}
							}
						}

						// ── Timer ──────────────────────────────────────────────────────
						Item {
							anchors.fill: parent
							visible:      modelData === "timer"

							// Icon — left edge of notch
							Text {
								anchors {
									left:           parent.left
									leftMargin:     root.fw
									verticalCenter: parent.verticalCenter
								}
								text:           "󰔟"
								font.family:    Theme.nerdFontFamily
								font.pixelSize: 16
								color:          root.timerUrgent ? "#ff5555" : Theme.active
								Behavior on color { ColorAnimation { duration: 200 } }
							}

							// Time display — centered in remaining space
							Text {
								id: timerText
								anchors {
									left:           parent.left
									leftMargin:     8
									right:          parent.right
									rightMargin:    8
									verticalCenter: parent.verticalCenter
								}
								text:           ClockState.timerDisplay
								font.pixelSize: 15
								font.weight:    Font.Bold
								font.family: Theme.monoFontFamily
								horizontalAlignment: Text.AlignHCenter
								color:          root.timerUrgent ? "#ff5555" : Theme.text
								Behavior on color { ColorAnimation { duration: 200 } }

								// Blink when urgent — opacity pulses 1 → 0.25 → 1
								SequentialAnimation on opacity {
									id: timerBlink
									running:  root.timerUrgent
									loops:    Animation.Infinite
									NumberAnimation { to: 0.25; duration: 500; easing.type: Easing.InOutSine }
									NumberAnimation { to: 1.0;  duration: 500; easing.type: Easing.InOutSine }
								}

								// Snap back to full opacity when blink stops
								Connections {
									target: timerBlink
									function onRunningChanged() {
										if (!timerBlink.running) timerText.opacity = 1.0
									}
								}
							}
							// Icon — right edge of notch
							Row{
								anchors {
									right:          parent.right
									rightMargin:    root.fw
									verticalCenter: parent.verticalCenter
								}
								spacing: root.fw

								Text {
									anchors {
										verticalCenter: parent.verticalCenter
									}
									text:           ClockState.timerRunning ? "󱫟" : "󱫡"
									font.family:    Theme.nerdFontFamily
									font.pixelSize: 16
									color:          _timerPauseHov.hovered ? Theme.active : Theme.text
									HoverHandler { id: _timerPauseHov;  }
									MouseArea {
										anchors.fill: parent
										cursorShape: Qt.PointingHandCursor
										onClicked: ClockState.timerRunning = !ClockState.timerRunning
									}
								}
								Text {
									anchors {
										verticalCenter: parent.verticalCenter
									}
									text:			"󱫥"
									font.family:    Theme.nerdFontFamily
									font.pixelSize: 16
									color:			_timerResetHov.hovered ? Theme.active : Theme.text
									HoverHandler { id: _timerResetHov; cursorShape: Qt.PointingHandCursor }
									MouseArea {
										anchors.fill: parent
										cursorShape: Qt.PointingHandCursor
										onClicked: {
											ClockState.requestTimerReset()
										}
									}
								}
							}
						}
						// ── Stopwatch ──────────────────────────────────────────────────
						Item {
							anchors.fill: parent
							visible:      modelData === "stopwatch"

							// Icon — left edge of notch
							Text {
								anchors {
									left:           parent.left
									leftMargin:     root.fw
									verticalCenter: parent.verticalCenter
								}
								text:           ""
								font.family:    Theme.nerdFontFamily
								font.pixelSize: 16
								color:          Theme.active
							}

							// Running time — centered in remaining space
							Text {
								anchors {
									left:           parent.left
									leftMargin:     8
									right:          parent.right
									rightMargin:    8
									verticalCenter: parent.verticalCenter
								}
								text:           ClockState.swDisplay
								font.pixelSize: 15
								font.weight:    Font.Bold
								font.family: Theme.monoFontFamily
								horizontalAlignment: Text.AlignHCenter
								color:          Theme.text
							}
							// Icon — right edge of notch
							Row{
								anchors {
									right:          parent.right
									rightMargin:    root.fw
									verticalCenter: parent.verticalCenter
								}
								spacing: root.fw
								
								Text {
									anchors {
										verticalCenter: parent.verticalCenter
									}
									text:           ClockState.swRunning ? "󱫟" : "󱫡"
									font.family:    Theme.nerdFontFamily
									font.pixelSize: 16
									color:          _pauseHov.hovered ? Theme.active : Theme.text
									HoverHandler { id: _pauseHov;  }
									MouseArea {
										anchors.fill: parent
										cursorShape: Qt.PointingHandCursor
										onClicked: {
										ClockState.swRunning = !ClockState.swRunning
										}
									}
								}
								Text {
									anchors {
										verticalCenter: parent.verticalCenter
									}
									text:			"󱫥"
									font.family:    Theme.nerdFontFamily
									font.pixelSize: 16
									color:			_notchResetHov.hovered ? Theme.active : Theme.text
										
									HoverHandler { id: _notchResetHov; cursorShape: Qt.PointingHandCursor }
									MouseArea {
											anchors.fill: parent
											cursorShape: Qt.PointingHandCursor
											onClicked: {
												ClockState.requestStopwatchReset()
											}
										}
									}
							}
						}

						// ── Record setup — strip buttons + Record button ───────────────
						Item {
							anchors{
								fill: parent
								leftMargin: root.fw/2
								rightMargin: root.fw/2
							}
							
							visible:      modelData === "record_setup"

							Row {
								anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
								spacing: 6

								// ── Capture strip button ───────────────────────────────
								Item {
									anchors.verticalCenter: parent.verticalCenter
									width:  csRow.implicitWidth + 14
									height: 22

									Rectangle {
										anchors.fill: parent
										radius:       height / 2
										color: ScreenRecService.openStrip === "capture"
										? Qt.rgba(Theme.active.r, Theme.active.g, Theme.active.b, 0.15)
										: csH.hovered ? Qt.rgba(1,1,1,0.08) : Qt.rgba(1,1,1,0.04)
										border.color: ScreenRecService.openStrip === "capture"
										? Qt.rgba(Theme.active.r, Theme.active.g, Theme.active.b, 0.3)
										: Qt.rgba(1,1,1,0.1)
										border.width: 1
										Behavior on color        { ColorAnimation { duration: 100 } }
										Behavior on border.color { ColorAnimation { duration: 100 } }
									}
									Row {
										id: csRow
										anchors.centerIn: parent
										spacing: 5
										Text {
											text: ScreenRecService.captureIcon
											font.pixelSize: 13
											color: ScreenRecService.openStrip === "capture"
											? Theme.active : Qt.rgba(1,1,1,0.7)
											anchors.verticalCenter: parent.verticalCenter
											Behavior on color { ColorAnimation { duration: 100 } }
										}
										Text {
											text: ScreenRecService.captureLabel()
											font.pixelSize: 11
											color: ScreenRecService.openStrip === "capture"
											? Theme.active : Qt.rgba(1,1,1,0.7)
											anchors.verticalCenter: parent.verticalCenter
											Behavior on color { ColorAnimation { duration: 100 } }
										}
										Text {
											text: "▾"; font.pixelSize: 8
											color: Qt.rgba(1,1,1,0.35)
											anchors.verticalCenter: parent.verticalCenter
										}
									}
									// 点击循环切换录制目标。
									// 上游这里挂的是一个 hover 展开的下拉弹层，移植时弹层没做，
									// 所以按钮悬停只会变色、点下去毫无反应（见 ScreenRecService 的
									// _captureOrder 注释）。循环切换在只有三项时更快，也不需要浮层定位。
									MouseArea {
										anchors.fill: parent
										cursorShape: Qt.PointingHandCursor
										onClicked: ScreenRecService.cycleCaptureTarget()
									}
									HoverHandler {
										id: csH
										onHoveredChanged: {
											if (hovered) {
												var pos = parent.mapToItem(null, 0, 0)
												ScreenRecService.popupTargetX = pos.x
												ScreenRecService.popupTargetWidth = parent.width

												ScreenRecService.openStrip = "capture"
												ScreenRecService.keepStripOpen()
											} else {
												ScreenRecService.scheduleStripClose()
											}
										}
									}
								}

								// ── Audio strip button ─────────────────────────────────
								Item {
									anchors.verticalCenter: parent.verticalCenter
									width:  asRow.implicitWidth + 14
									height: 22

									Rectangle {
										anchors.fill: parent
										radius:       height / 2
										color: ScreenRecService.openStrip === "audio"
										? Qt.rgba(Theme.active.r, Theme.active.g, Theme.active.b, 0.15)
										: asH.hovered ? Qt.rgba(1,1,1,0.08) : Qt.rgba(1,1,1,0.04)
										border.color: ScreenRecService.openStrip === "audio"
										? Qt.rgba(Theme.active.r, Theme.active.g, Theme.active.b, 0.3)
										: Qt.rgba(1,1,1,0.1)
										border.width: 1
										Behavior on color        { ColorAnimation { duration: 100 } }
										Behavior on border.color { ColorAnimation { duration: 100 } }
									}
									Row {
										id: asRow
										anchors.centerIn: parent
										spacing: 5
										Text {
											text: "🎙"; font.pixelSize: 12
											anchors.verticalCenter: parent.verticalCenter
										}
										Text {
											text: ScreenRecService.audioLabel()
											font.pixelSize: 11
											color: ScreenRecService.openStrip === "audio"
											? Theme.active : Qt.rgba(1,1,1,0.7)
											anchors.verticalCenter: parent.verticalCenter
											Behavior on color { ColorAnimation { duration: 100 } }
										}
										Text {
											text: "▾"; font.pixelSize: 8
											color: Qt.rgba(1,1,1,0.35)
											anchors.verticalCenter: parent.verticalCenter
										}
									}
									// 点击循环切换音频：无 → 系统声 → 麦克风 → 无
									// （同上，上游的下拉弹层没有移植）
									MouseArea {
										anchors.fill: parent
										cursorShape: Qt.PointingHandCursor
										onClicked: ScreenRecService.cycleAudio()
									}
									HoverHandler {
										id: asH
										onHoveredChanged: {
											if (hovered) {
												var pos = parent.mapToItem(null, 0, 0)
												ScreenRecService.popupTargetX = pos.x
												ScreenRecService.popupTargetWidth = parent.width

												ScreenRecService.openStrip = "audio"
												ScreenRecService.keepStripOpen()
											} else {
												ScreenRecService.scheduleStripClose()
											}
										}
									}
								}

								// Flexible spacer
								Item {
									anchors.verticalCenter: parent.verticalCenter
									height: 1
									width: parent.width
									- csRow.implicitWidth - 14
									- asRow.implicitWidth - 14
									- recBtnLabel.implicitWidth - 24
									- parent.spacing * 3
								}

								// ── Record button ──────────────────────────────────────
								Rectangle {
									anchors.verticalCenter: parent.verticalCenter
									width:  recBtnLabel.implicitWidth + 24
									height: 22
									radius: height / 2
									color:  recBtnH.hovered
									? Qt.rgba(0.9, 0.2, 0.2, 0.85)
									: Qt.rgba(0.8, 0.1, 0.1, 0.7)
									Behavior on color { ColorAnimation { duration: 100 } }
									Row {
										anchors.centerIn: parent
										spacing: 5
										Rectangle {
											width: 7; height: 7; radius: 4
											color: "#ffffff"
											anchors.verticalCenter: parent.verticalCenter
										}
										Text {
											id: recBtnLabel
											text: Translation.tr("Record")
											font.pixelSize: 11; font.weight: Font.Medium
											color: "#ffffff"
											anchors.verticalCenter: parent.verticalCenter
										}
									}
									HoverHandler { id: recBtnH}
									MouseArea { anchors.fill: parent;cursorShape: Qt.PointingHandCursor; onClicked: ScreenRecService.startRecording() }
								}
							}
						}

					} // delegate
				}
			}

			// ── Click to toggle dashboard ─────────────────────────────────────────────
			// TapHandler has lower implicit grab priority than child MouseAreas
			// (record_setup / timer / stopwatch 的按钮会先吃掉点击)，
			// 落在胶囊空白处才开面板。
			TapHandler {
				onTapped: {
					// Do nothing during screen rec setup — ESC / cancel button handles it
					if (ShellState.screenRecord && !ScreenRecService.recording) return
					var next = !Popups.dashboardOpen
					Popups.closeAll()
					Popups.dashboardOpen = next
				}
			}
		}
