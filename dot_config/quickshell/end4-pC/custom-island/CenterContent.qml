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

	width:  Theme.cNotchMinWidth
	height: 30

	// ── Required notch width for the current carousel item ────────────────────
	// TopBar.cWidth reads this so the notch always matches what is visible.
	readonly property int fw: Theme.notchRadius
	readonly property int requiredWidth: Theme.cNotchMinWidth

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

				width:  Theme.cNotchMinWidth
				height: 30

				// ── Clock ──────────────────────────────────────────────────────
				// 默认项：日期 + 时间（HH:MM:SS）。**不带日历图标**（按需求）。
				// 上游这里是"当前窗口标题"，换成时间是因为 Bar 左侧的
				// activeWindow 组件已经在显示窗口标题了。
				Text {
					anchors.fill: parent
					visible:      modelData === "clock"
					// 日期取秒级 SystemClock 的 date —— 跨零点会自动跳到新的一天。
					// 格式按需求用中文「年月日」；汉字不是 Qt 的格式字符（y/M/d/H…），
					// 所以直接写在格式串里就会原样输出，不需要单引号转义。
					text:         Qt.locale().toString(secondClock.date, "yyyy年M月d日")
					              + "  " + DateTime.hourStr + ":" + DateTime.minuteStr + ":" + root.secondStr
					color:        Theme.text
					font.pixelSize: 14
					// 收起态时钟单独用 Theme.clockFontFamily（默认 Google Sans
					// Display）。跟 Bar 上其它组件不共享 main —— 这段文字以数字
					// 为主，换一个数字字形更漂亮的字体观感提升最大；要切回和
					// 邻居一致，把 Theme.clockFontFamily 改成 mainFontFamily 即可。
					// tnum 保证秒数跳动时数字宽度不抖（字体不支持时会被忽略）。
					font.family:  Theme.clockFontFamily
					font.features: { "tnum": 1 }
					verticalAlignment:   Text.AlignVCenter
					horizontalAlignment: Text.AlignHCenter
					elide:        Text.ElideRight
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
