pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Shapes
import Quickshell.Io

/**
 * bongo cat 本体：纯 QML 手绘的小白猫，是 Shell 的一部分（无素材、无 Live2D）。
 * 毛色固定白色，道具（zzz、箱子、键盘、耳机…）用 matugen 主题色。
 *
 * 玩法：
 * - 点它 = 摸摸（爱心 + bong bong ♪）
 * - 拖它 = 拎起来：耳朵后倒、爪子随速度摆、身体朝移动方向倾斜，喵喵抗议
 * - 甩它 = 飞出去：惯性滑行、屏幕边缘反弹、落地压扁 + 扬尘；摔狠了眼冒圈圈
 * - 落哪住哪：位置持久化，`ipc call pet home` 回老家
 * - 唱歌：听歌时接桌面歌词的逐字 KRC 时间戳，每个字张一次嘴，
 *   点头频率跟随这一行的字密度；没有逐字数据的播放器退化为哼歌模式
 *
 * 心情来自 PetState。motion: 0=rest 1=held 2=flying
 */
Item {
    id: root

    property var vitals
    property var lyricsProvider: null
    property bool active: true // 由 PetWindow 绑定到 petEnabled
    property alias interactionRoot: creatureWrap
    readonly property string mood: vitals?.mood ?? "sleep"
    readonly property bool sleeping: mood === "sleep"
    property bool blinking: false

    // ——— 运动状态 ———
    property int motion: 0 // 0=rest 1=held 2=flying
    readonly property bool grabbed: motion === 1
    readonly property bool airborne: motion === 2
    property real catX: -1
    property real catY: -1
    property real vx: 0
    property real vy: 0
    property real sVx: 0 // 平滑后的速度（驱动姿态）
    property real sVy: 0
    property real pawSwing: 0
    property bool dizzy: false
    property bool positionLoaded: false
    property bool settling: false // 落地/扔出后还在回弹，物理循环保持运行

    // ——— 唱歌 ———
    property real singOpen: 0 // 0..1 张嘴程度
    property int singBobPeriod: 620

    readonly property bool petted: pettedTimer.running
    property string sayText: ""

    // ——— 固定猫猫配色（不随深浅色主题变化）———
    readonly property color furColor: "#FDFDFD"
    readonly property color furBorder: ColorUtils.transparentize("#544F5B", 0.78)
    readonly property color faceColor: "#4A4550"
    readonly property color earPink: "#F5AFC0"
    readonly property color nosePink: "#F09DB2"
    readonly property color blushPink: ColorUtils.transparentize("#F5AFC0", 0.45)
    // Shell 侧的道具（zzz、键盘、耳机…）沿用主题强调色
    readonly property color accentColor: Appearance.colors.colPrimary

    readonly property bool bubbleVisible: petArea.containsMouse || sayTimer.running
    readonly property string bubbleLabel: sayText.length > 0 ? sayText : (vitals?.moodLabel ?? "")
    readonly property string bubbleDetail: sayText.length > 0 ? "" : (vitals?.moodDetail ?? "")

    // 呼吸幅度/周期随心情变化
    readonly property real breathAmp: sleeping ? 0.05 : (mood === "busy" ? 0.045 : 0.03)
    readonly property int breathPeriod: sleeping ? 2600 : (mood === "busy" ? 1100 : 1700)
    // 尾巴：睡着不动，忙碌/焦虑时烦躁地快甩
    readonly property int tailPeriod: sleeping ? 0 : (mood === "busy" || mood === "anxious" ? 500 : (mood === "music" ? 700 : 1500))
    // 拍爪：醒着、没被拎/飞、没有专门动作（打字/举箱）时拍
    readonly property bool pawTapActive: !sleeping && motion === 0 && mood !== "typing" && mood !== "carry"
    readonly property int pawTapPeriod: mood === "music" ? 640 : 1700

    // 耳朵：焦虑耷拉 + 被拎/飞行时往后倒
    property real earDroopL: mood === "anxious" ? -18 : 0
    Behavior on earDroopL {
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutCubic
        }
    }
    property real earDroopR: mood === "anxious" ? 18 : 0
    Behavior on earDroopR {
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutCubic
        }
    }
    property real earFlyL: (grabbed || airborne) ? -24 : 0
    Behavior on earFlyL {
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }
    }
    property real earFlyR: (grabbed || airborne) ? 24 : 0
    Behavior on earFlyR {
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }
    }

    function clamp(v, a, b) {
        return Math.max(a, Math.min(b, v));
    }

    function say(text, ms) {
        sayText = text;
        sayTimer.interval = ms;
        sayTimer.restart();
    }

    function pet() {
        pettedTimer.restart();
        heartAnim.restart();
        wiggleAnim.restart();
        say("bong bong ♪", 2200);
    }

    onMoodChanged: {
        // 心情动画可能被打断在半路；把位移归零
        body.x = 0;
        body.rotation = 0;
        pawLRot.angle = 0;
        pawRRot.angle = 0;
    }

    // ——— 位置与物理 ———
    function clampCat() {
        const maxX = Math.max(8, width - creatureWrap.width - 8);
        const maxY = Math.max(8, height - creatureWrap.height - 8);
        catX = clamp(catX, 8, maxX);
        catY = clamp(catY, 8, maxY);
    }

    function moveCatTo(x, y) {
        catX = x;
        catY = y;
        clampCat();
    }

    function defaultX() {
        return width - creatureWrap.width - 14;
    }
    function defaultY() {
        return height - creatureWrap.height - 10;
    }

    function applyDefaultPosition() {
        if (width > 0 && height > 0) {
            catX = defaultX();
            catY = defaultY();
        }
    }

    Component.onCompleted: fallbackPositionTimer.restart()

    // 文件不存在时 loadFailed 在部分路径下不可靠：超时兜底直接用默认位
    Timer {
        id: fallbackPositionTimer
        interval: 400
        onTriggered: {
            if (!root.positionLoaded) {
                root.applyDefaultPosition();
                root.positionLoaded = true;
            }
        }
    }

    FileView {
        id: positionFile
        path: `${Directories.state}/pet-position.json`
        watchChanges: false
        onLoaded: {
            if (adapter.x >= 0 && adapter.y >= 0 && root.width > 0) {
                root.catX = adapter.x;
                root.catY = adapter.y;
                root.clampCat();
            } else {
                root.applyDefaultPosition();
            }
            root.positionLoaded = true;
        }
        onLoadFailed: {
            root.applyDefaultPosition();
            root.positionLoaded = true;
        }
        onSaveFailed: error => console.warn("[Pet] position save failed:", error)
        JsonAdapter {
            id: adapter
            property real x: -1
            property real y: -1
        }
    }

    function savePosition() {
        if (!positionLoaded)
            return;
        adapter.x = catX;
        adapter.y = catY;
        positionFile.writeAdapter();
    }
    Timer {
        id: saveTimer
        interval: 700
        onTriggered: root.savePosition()
    }

    function startHold() {
        if (motion === 1)
            return;
        motion = 1;
        vx = 0;
        vy = 0;
        singOpen = 0.15;
        say("喵呜——放我下来！", 1800);
    }

    function releaseWithVelocity(ivx, ivy) {
        const speed = Math.hypot(ivx, ivy);
        if (speed > 260) {
            startFly(ivx, ivy);
        } else {
            landSoft();
        }
    }

    function startFly(ivx, ivy) {
        const speed = Math.hypot(ivx, ivy);
        const cap = 2800;
        const scale = speed > cap ? cap / speed : 1;
        vx = ivx * scale;
        vy = ivy * scale;
        sVx = vx;
        sVy = vy;
        motion = 2;
        say("喵啊啊!!", 900);
    }

    function toss(dx, dy) {
        if (motion === 1)
            return;
        if (dx === 0 && dy === 0) {
            startFly((Math.random() * 2 - 1) * 1500, -(700 + Math.random() * 900));
        } else {
            startFly(dx, dy);
        }
    }

    function landSoft() {
        motion = 0;
        stretchS.xScale = 1.12;
        stretchS.yScale = 0.9;
        pawLRot.angle = 0;
        pawRRot.angle = 0;
        body.x = 0;
        settling = true;
        saveTimer.restart();
    }

    function impact(strength, x, y) {
        // 落地/撞墙：压扁 + 扬尘 + (狠了)眩晕
        settling = true;
        stretchS.xScale = clamp(1 + strength / 5200, 1, 1.28);
        stretchS.yScale = 1 / stretchS.xScale;
        if (strength > 420)
            dustAnim.restart();
        if (strength > 1100 && !dizzy) {
            dizzy = true;
            dizzyTimer.restart();
            say("摔晕了…嗝", 1500);
        }
    }

    Timer {
        id: dizzyTimer
        interval: 1100
        onTriggered: root.dizzy = false
    }

    function land() {
        motion = 0;
        settling = true;
        pawLRot.angle = 0;
        pawRRot.angle = 0;
        body.x = 0;
        saveTimer.restart();
    }

    function bounce() {
        const pad = 8;
        let hit = 0;
        if (catX <= pad && vx < 0) {
            catX = pad;
            hit = Math.abs(vx);
            vx = -vx * 0.55;
        } else if (catX >= width - creatureWrap.width - pad && vx > 0) {
            catX = width - creatureWrap.width - pad;
            hit = Math.abs(vx);
            vx = -vx * 0.55;
        }
        if (catY <= pad && vy < 0) {
            catY = pad;
            hit = Math.max(hit, Math.abs(vy));
            vy = -vy * 0.55;
        } else if (catY >= height - creatureWrap.height - pad && vy > 0) {
            catY = height - creatureWrap.height - pad;
            hit = Math.max(hit, Math.abs(vy));
            vy = -vy * 0.55;
        }
        if (hit > 0)
            impact(hit, catX, catY);
    }

    function goHome() {
        motion = 0;
        settling = true;
        homeAnimX.to = defaultX();
        homeAnimY.to = defaultY();
        homeAnim.restart();
    }
    SequentialAnimation {
        id: homeAnim
        running: false
        onStopped: root.savePosition()
        NumberAnimation {
            id: homeAnimX
            target: root
            property: "catX"
            duration: 650
            easing.type: Easing.InOutBack
        }
        NumberAnimation {
            id: homeAnimY
            target: root
            property: "catY"
            duration: 650
            easing.type: Easing.InOutBack
        }
    }

    // 每帧积分：飞行物理 + 姿态（倾斜/摆爪/挤压拉伸）
    FrameAnimation {
        running: root.active && root.positionLoaded && (root.motion !== 0 || root.settling)
        onTriggered: root.stepPhysics(frameTime)
    }

    function stepPhysics(dt) {
        const k = Math.min(1, dt * 10);
        // 速度平滑（驱动姿态）
        sVx += (vx - sVx) * Math.min(1, dt * 9);
        sVy += (vy - sVy) * Math.min(1, dt * 9);

        if (motion === 2) {
            const drag = Math.exp(-1.5 * dt);
            vx *= drag;
            vy *= drag;
            catX += vx * dt;
            catY += vy * dt;
            clampCat();
            bounce();
            if (Math.hypot(vx, vy) < 26)
                land();
        }

        // 挤压拉伸：被拎/飞行时沿速度方向拉长，静止时弹回
        const speed = Math.hypot(sVx, sVy);
        const targetSx = (motion !== 0) ? 1 + Math.min(0.16, speed / 5200) : 1;
        stretchS.xScale += (targetSx - stretchS.xScale) * k;
        stretchS.yScale += ((1 / targetSx) - stretchS.yScale) * k;

        // 身体朝移动方向倾斜
        const tiltTarget = (motion !== 0) ? clamp(sVx * 0.045, -18, 18) : 0;
        poseTilt.angle += (tiltTarget - poseTilt.angle) * k;

        // 爪子随速度摆动（拎起来时像钟摆）
        const swingTarget = (motion !== 0) ? clamp(-sVx * 0.07, -30, 30) : 0;
        pawSwing += (swingTarget - pawSwing) * Math.min(1, dt * 9);
        if (motion !== 0) {
            pawLRot.angle = pawSwing;
            pawRRot.angle = pawSwing * 0.75;
        }

        // 静止且回弹结束 → 物理循环歇菜
        if (motion === 0 && Math.abs(stretchS.xScale - 1) < 0.004 && Math.abs(poseTilt.angle) < 0.2 && Math.abs(pawSwing) < 0.4)
            settling = false;
    }

    // ——— 唱歌 ———
    Timer {
        id: singTimer
        interval: 33
        running: root.active && root.mood === "music"
        repeat: true
        onTriggered: root.updateSing()
    }

    function updateSing() {
        if (motion !== 0) { // 被拎着时吓得不唱了
            singOpen += (0.12 - singOpen) * 0.5;
            return;
        }
        if (mood !== "music") {
            singOpen += (0 - singOpen) * 0.5;
            return;
        }
        const prov = root.lyricsProvider;
        const hasKrc = prov && prov.shouldShow && prov.lyricLines && prov.lyricLines.length > 0;
        if (hasKrc) {
            const t = prov.currentTime + prov.lyricOffset;
            const line = prov.lyricLines[prov.currentLineIndex];
            if (!line) {
                singOpen += (0.08 - singOpen) * 0.5;
                return;
            }
            const words = line.words;
            if (words && words.length > 0) {
                // 这一行的字密度 = 歌的节奏 → 点头周期
                let sum = 0;
                for (const w of words)
                    sum += w.dur;
                singBobPeriod = clamp((sum / words.length) * 2000, 300, 760);
                let open = 0.06;
                for (const w of words) {
                    if (t >= w.start && t < w.start + w.dur) {
                        open = w.dur < 0.16 ? 0.65 : 1;
                        break;
                    }
                }
                singOpen += (open - singOpen) * 0.55;
            } else {
                // LRC 兜底：固定频率张合
                singOpen += ((Math.sin(t * Math.PI * 2 * 1.3) > 0 ? 0.85 : 0.1) - singOpen) * 0.5;
                singBobPeriod = 560;
            }
        } else {
            // 哼歌模式：别的播放器在放但没有逐字数据
            singOpen += ((Math.sin(Date.now() / 1000 * Math.PI * 2 * 1.2) > 0 ? 0.55 : 0.12) - singOpen) * 0.4;
            singBobPeriod = 620;
        }
    }

    // ——— 摸摸 / 说话 ———
    Timer { // 摸摸反应特效
        id: pettedTimer
        interval: 2200
    }
    Timer {
        id: sayTimer
        onTriggered: root.sayText = ""
    }

    Timer {
        id: blinkStart
        interval: 2600 + Math.random() * 2400
        running: root.visible && !root.sleeping
        onTriggered: {
            root.blinking = true;
            blinkEnd.start();
        }
    }
    Timer {
        id: blinkEnd
        interval: 140
        onTriggered: {
            root.blinking = false;
            blinkStart.interval = 2600 + Math.random() * 2400;
            blinkStart.restart();
        }
    }
    Timer { // 猫猫 random 耳朵抽动
        id: earTwitchTimer
        interval: 3200 + Math.random() * 4200
        running: root.visible && !root.sleeping && root.motion === 0
        onTriggered: {
            if (Math.random() < 0.5)
                earTwitchL.restart();
            else
                earTwitchR.restart();
            interval = 3200 + Math.random() * 4200;
            restart();
        }
    }

    onWidthChanged: {
        if (!positionLoaded)
            applyDefaultPosition();
        else
            clampCat();
    }
    onHeightChanged: {
        if (!positionLoaded)
            applyDefaultPosition();
        else
            clampCat();
    }

    // ——— 气泡 ———
    Rectangle {
        id: bubble
        x: creatureWrap.x + (creatureWrap.width - width) / 2
        y: creatureWrap.y - height - 10 < 8 ? creatureWrap.y + creatureWrap.height + 10 : creatureWrap.y - height - 10
        width: bubbleColumn.implicitWidth + 22
        height: bubbleColumn.implicitHeight + 14
        radius: 11
        color: Appearance.colors.colLayer3
        border.width: 1
        border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.72)
        opacity: root.bubbleVisible ? 1 : 0
        scale: root.bubbleVisible ? 1 : 0.75
        transformOrigin: Item.Bottom
        Behavior on opacity {
            NumberAnimation {
                duration: 180
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutBack
            }
        }

        Column {
            id: bubbleColumn
            anchors.centerIn: parent
            spacing: 2

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.bubbleLabel
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer3
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.bubbleDetail.length > 0
                width: Math.min(implicitWidth, 170)
                elide: Text.ElideRight
                text: root.bubbleDetail
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer1
            }
        }
        Rectangle { // 气泡尾巴
            width: 10
            height: 10
            rotation: 45
            color: parent.color
            border.width: 1
            border.color: parent.border.color
            anchors {
                top: parent.bottom
                topMargin: -6
                horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // ——— 猫猫 ———
    Item {
        id: creatureWrap
        x: root.catX
        y: root.catY
        width: 150
        height: 160

        StyledRectangularShadow {
            target: body
        }

        Rectangle {
            id: body
            width: 92
            height: 70
            radius: 34
            anchors {
                bottom: parent.bottom
                bottomMargin: 6
                horizontalCenter: parent.horizontalCenter
            }
            color: root.furColor
            border.width: 1.5
            border.color: root.furBorder
            transform: [
                Scale {
                    id: breathTransform
                    origin.x: 46
                    origin.y: 70
                    yScale: 1
                },
                Scale {
                    id: stretchS
                    origin.x: 46
                    origin.y: 35
                    xScale: 1
                    yScale: 1
                },
                Rotation {
                    id: poseTilt
                    origin.x: 46
                    origin.y: 55
                    angle: 0
                }
            ]

            SequentialAnimation {
                running: true
                loops: Animation.Infinite
                NumberAnimation {
                    target: breathTransform
                    property: "yScale"
                    to: 1 + root.breathAmp
                    duration: root.breathPeriod
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: breathTransform
                    property: "yScale"
                    to: 1
                    duration: root.breathPeriod
                    easing.type: Easing.InOutSine
                }
            }

            SequentialAnimation { // 忙碌发抖
                running: root.mood === "busy" && root.motion === 0
                loops: Animation.Infinite
                NumberAnimation {
                    target: body
                    property: "x"
                    to: 1.4
                    duration: 90
                }
                NumberAnimation {
                    target: body
                    property: "x"
                    to: -1.4
                    duration: 180
                }
                NumberAnimation {
                    target: body
                    property: "x"
                    to: 0
                    duration: 90
                }
            }
            SequentialAnimation { // 焦虑颤抖
                running: root.mood === "anxious" && root.motion === 0
                loops: Animation.Infinite
                NumberAnimation {
                    target: body
                    property: "x"
                    to: 1
                    duration: 70
                }
                NumberAnimation {
                    target: body
                    property: "x"
                    to: -1
                    duration: 140
                }
                NumberAnimation {
                    target: body
                    property: "x"
                    to: 0
                    duration: 70
                }
            }
            SequentialAnimation { // 找网络时踱步
                running: root.mood === "lost" && root.motion === 0
                loops: Animation.Infinite
                NumberAnimation {
                    target: body
                    property: "x"
                    to: -14
                    duration: 900
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: body
                    property: "x"
                    to: 14
                    duration: 1800
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: body
                    property: "x"
                    to: 0
                    duration: 900
                    easing.type: Easing.InOutSine
                }
            }
            SequentialAnimation { // 听歌点头（周期跟随歌词字密度）
                running: root.mood === "music" && !root.petted && root.motion === 0
                loops: Animation.Infinite
                NumberAnimation {
                    target: body
                    property: "rotation"
                    to: 4
                    duration: root.singBobPeriod * 0.5
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: body
                    property: "rotation"
                    to: -4
                    duration: root.singBobPeriod
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: body
                    property: "rotation"
                    to: 0
                    duration: root.singBobPeriod * 0.5
                    easing.type: Easing.InOutSine
                }
            }

            // ——— 尾巴 ———
            Shape {
                anchors.fill: parent
                transform: Rotation {
                    id: tailSway
                    origin.x: 68
                    origin.y: 62
                    angle: root.sleeping ? 6 : 0
                }
                ShapePath {
                    strokeColor: root.furBorder
                    strokeWidth: 10
                    capStyle: ShapePath.RoundCap
                    fillColor: "transparent"
                    PathSvg {
                        path: "M 66 62 C 86 60 96 46 90 26"
                    }
                }
                ShapePath {
                    strokeColor: root.furColor
                    strokeWidth: 6.5
                    capStyle: ShapePath.RoundCap
                    fillColor: "transparent"
                    PathSvg {
                        path: "M 66 62 C 86 60 96 46 90 26"
                    }
                }
                SequentialAnimation {
                    running: root.tailPeriod > 0
                    loops: Animation.Infinite
                    NumberAnimation {
                        target: tailSway
                        property: "angle"
                        to: 9
                        duration: root.tailPeriod
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        target: tailSway
                        property: "angle"
                        to: -3
                        duration: root.tailPeriod
                        easing.type: Easing.InOutSine
                    }
                }
            }

            // ——— 耳朵 ———
            Shape {
                anchors.fill: parent
                transform: Rotation {
                    id: earLRot
                    origin.x: 27
                    origin.y: 10
                    property real twitchAngle: 0
                    angle: root.earDroopL + root.earFlyL + earLRot.twitchAngle
                }
                ShapePath {
                    strokeColor: root.furBorder
                    strokeWidth: 1.5
                    fillColor: root.furColor
                    PathSvg {
                        path: "M 14 12 L 18 -12 L 40 6"
                    }
                }
                ShapePath {
                    fillColor: root.earPink
                    PathSvg {
                        path: "M 19 7 L 21.5 -6 L 33 3"
                    }
                }
            }
            Shape {
                anchors.fill: parent
                transform: Rotation {
                    id: earRRot
                    origin.x: 65
                    origin.y: 10
                    property real twitchAngle: 0
                    angle: root.earDroopR + root.earFlyR + earRRot.twitchAngle
                }
                ShapePath {
                    strokeColor: root.furBorder
                    strokeWidth: 1.5
                    fillColor: root.furColor
                    PathSvg {
                        path: "M 78 12 L 74 -12 L 52 6"
                    }
                }
                ShapePath {
                    fillColor: root.earPink
                    PathSvg {
                        path: "M 73 7 L 70.5 -6 L 59 3"
                    }
                }
            }

            // ——— 脸 ———
            Rectangle {
                x: 24
                y: root.mood === "anxious" ? 18 : 20
                width: root.mood === "anxious" ? 13 : 11
                height: width
                radius: width / 2
                color: root.faceColor
                visible: (!root.sleeping && !root.blinking || root.motion !== 0) && !root.dizzy
            }
            Rectangle {
                x: 57
                y: root.mood === "anxious" ? 18 : 20
                width: root.mood === "anxious" ? 13 : 11
                height: width
                radius: width / 2
                color: root.faceColor
                visible: (!root.sleeping && !root.blinking || root.motion !== 0) && !root.dizzy
            }
            Rectangle { // 眼睛高光
                x: 26.5
                y: root.mood === "anxious" ? 20.5 : 22.5
                width: 3.5
                height: 3.5
                radius: 1.75
                color: "#FFFFFF"
                visible: (!root.sleeping && !root.blinking || root.motion !== 0) && !root.dizzy
            }
            Rectangle {
                x: 59.5
                y: root.mood === "anxious" ? 20.5 : 22.5
                width: 3.5
                height: 3.5
                radius: 1.75
                color: "#FFFFFF"
                visible: (!root.sleeping && !root.blinking || root.motion !== 0) && !root.dizzy
            }
            Shape { // 睡着/眨眼：⌒ ⌒
                anchors.fill: parent
                visible: (root.sleeping || root.blinking) && root.motion === 0
                ShapePath {
                    strokeColor: root.faceColor
                    strokeWidth: 2.6
                    capStyle: ShapePath.RoundCap
                    fillColor: "transparent"
                    PathSvg {
                        path: "M 23 30 Q 29 24 35 30"
                    }
                }
                ShapePath {
                    strokeColor: root.faceColor
                    strokeWidth: 2.6
                    capStyle: ShapePath.RoundCap
                    fillColor: "transparent"
                    PathSvg {
                        path: "M 57 30 Q 63 24 69 30"
                    }
                }
            }
            Rectangle { // 摔晕的圈圈眼
                x: 23
                y: 19
                width: 13
                height: 13
                radius: 6.5
                color: "transparent"
                border.width: 2.4
                border.color: root.faceColor
                visible: root.dizzy
                transform: Rotation {
                    origin.x: 6.5
                    origin.y: 6.5
                }
                SequentialAnimation on rotation {
                    running: root.dizzy
                    loops: Animation.Infinite
                    NumberAnimation {
                        from: 0
                        to: 360
                        duration: 700
                    }
                }
            }
            Rectangle {
                x: 56
                y: 19
                width: 13
                height: 13
                radius: 6.5
                color: "transparent"
                border.width: 2.4
                border.color: root.faceColor
                visible: root.dizzy
                transform: Rotation {
                    origin.x: 6.5
                    origin.y: 6.5
                }
                SequentialAnimation on rotation {
                    running: root.dizzy
                    loops: Animation.Infinite
                    NumberAnimation {
                        from: 0
                        to: -360
                        duration: 700
                    }
                }
            }

            Rectangle { // 腮红
                x: 10
                y: 39
                width: 13
                height: 7
                radius: 3.5
                color: root.blushPink
                opacity: root.sleeping ? 0.6 : 1
            }
            Rectangle {
                x: 69
                y: 39
                width: 13
                height: 7
                radius: 3.5
                color: root.blushPink
                opacity: root.sleeping ? 0.6 : 1
            }

            Shape { // 猫鼻子
                anchors.fill: parent
                ShapePath {
                    fillColor: root.nosePink
                    PathSvg {
                        path: "M 43 31 L 49 31 L 46 35 Z"
                    }
                }
            }

            Shape { // "ω" 猫嘴（不唱歌时）
                anchors.fill: parent
                visible: root.mood !== "sleep" && root.mood !== "busy" && root.mood !== "anxious" && root.mood !== "music" && root.motion === 0
                ShapePath {
                    strokeColor: root.faceColor
                    strokeWidth: 2.2
                    capStyle: ShapePath.RoundCap
                    fillColor: "transparent"
                    PathSvg {
                        path: "M 38 39 Q 42 44 46 40 Q 50 44 54 39"
                    }
                }
            }
            Rectangle { // 唱歌的嘴（高度跟 singOpen 走，逐字张合）
                x: 40
                y: 34
                width: 12
                height: 3 + root.singOpen * 10
                radius: 5
                color: root.faceColor
                visible: root.mood === "music" && root.motion === 0
                Rectangle { // 小舌头
                    anchors {
                        bottom: parent.bottom
                        bottomMargin: 1
                        horizontalCenter: parent.horizontalCenter
                    }
                    width: 6
                    height: Math.min(4, parent.height - 2)
                    radius: 2
                    color: root.nosePink
                    visible: parent.height > 6
                }
            }
            Rectangle { // 被拎/飞行吓到的 "O" 嘴
                x: 41
                y: 37
                width: 10
                height: 11
                radius: 5
                color: "transparent"
                border.width: 2.2
                border.color: root.faceColor
                visible: root.motion !== 0
            }
            Shape { // 认真抿嘴
                anchors.fill: parent
                visible: root.mood === "busy" && root.motion === 0
                ShapePath {
                    strokeColor: root.faceColor
                    strokeWidth: 2.4
                    capStyle: ShapePath.RoundCap
                    fillColor: "transparent"
                    PathSvg {
                        path: "M 40 41 L 52 41"
                    }
                }
            }
            Shape { // 担心波浪嘴
                anchors.fill: parent
                visible: root.mood === "anxious" && root.motion === 0
                ShapePath {
                    strokeColor: root.faceColor
                    strokeWidth: 2.4
                    capStyle: ShapePath.RoundCap
                    fillColor: "transparent"
                    PathSvg {
                        path: "M 38 42 Q 41 38.5 44 42 T 50 42 T 56 42"
                    }
                }
            }
            Rectangle { // 睡觉 "o" 嘴
                x: 42
                y: 38
                width: 8
                height: 8
                radius: 4
                color: "transparent"
                border.width: 2
                border.color: root.faceColor
                visible: root.sleeping && root.motion === 0
            }

            // ——— 前爪（趴着的 bongo 爪）———
            Rectangle {
                id: pawFrontL
                x: 17
                y: 57
                width: 24
                height: 13
                radius: 6.5
                color: root.furColor
                border.width: 1.5
                border.color: root.furBorder
                visible: root.mood !== "typing" && root.mood !== "carry"
                transform: Rotation {
                    id: pawLRot
                    origin.x: 12
                    origin.y: 13
                    angle: 0
                }
                Rectangle { // 趾缝
                    x: 9
                    y: 8.5
                    width: 1.5
                    height: 4
                    radius: 0.75
                    color: ColorUtils.transparentize(root.furBorder, 0.25)
                }
                Rectangle {
                    x: 14.5
                    y: 8.5
                    width: 1.5
                    height: 4
                    radius: 0.75
                    color: ColorUtils.transparentize(root.furBorder, 0.25)
                }
                SequentialAnimation {
                    running: root.pawTapActive
                    loops: Animation.Infinite
                    PauseAnimation {
                        duration: root.pawTapPeriod - 330
                    }
                    NumberAnimation {
                        target: pawLRot
                        property: "angle"
                        to: 12
                        duration: 120
                        easing.type: Easing.InQuad
                    }
                    NumberAnimation {
                        target: pawLRot
                        property: "angle"
                        to: 0
                        duration: 150
                        easing.type: Easing.OutQuad
                    }
                }
            }
            Rectangle {
                id: pawFrontR
                x: 51
                y: 57
                width: 24
                height: 13
                radius: 6.5
                color: root.furColor
                border.width: 1.5
                border.color: root.furBorder
                visible: root.mood !== "typing" && root.mood !== "carry"
                transform: Rotation {
                    id: pawRRot
                    origin.x: 12
                    origin.y: 13
                    angle: 0
                }
                Rectangle {
                    x: 9
                    y: 8.5
                    width: 1.5
                    height: 4
                    radius: 0.75
                    color: ColorUtils.transparentize(root.furBorder, 0.25)
                }
                Rectangle {
                    x: 14.5
                    y: 8.5
                    width: 1.5
                    height: 4
                    radius: 0.75
                    color: ColorUtils.transparentize(root.furBorder, 0.25)
                }
                SequentialAnimation {
                    running: root.pawTapActive
                    loops: Animation.Infinite
                    PauseAnimation {
                        duration: root.pawTapPeriod / 2
                    }
                    PauseAnimation {
                        duration: Math.max(0, root.pawTapPeriod / 2 - 330)
                    }
                    NumberAnimation {
                        target: pawRRot
                        property: "angle"
                        to: -12
                        duration: 120
                        easing.type: Easing.InQuad
                    }
                    NumberAnimation {
                        target: pawRRot
                        property: "angle"
                        to: 0
                        duration: 150
                        easing.type: Easing.OutQuad
                    }
                }
            }

            // ——— 落地扬尘 ———
            Item {
                id: dustGroup
                anchors {
                    top: body.bottom
                    topMargin: -10
                    horizontalCenter: parent.horizontalCenter
                }
                width: 70
                height: 14
                Rectangle {
                    id: dustA
                    x: 30
                    y: 6
                    width: 8
                    height: 8
                    radius: 4
                    color: ColorUtils.transparentize("#BEB7C9", 0.35)
                    opacity: 0
                }
                Rectangle {
                    id: dustB
                    x: 33
                    y: 4
                    width: 6
                    height: 6
                    radius: 3
                    color: ColorUtils.transparentize("#BEB7C9", 0.45)
                    opacity: 0
                }
                Rectangle {
                    id: dustC
                    x: 36
                    y: 6
                    width: 5
                    height: 5
                    radius: 2.5
                    color: ColorUtils.transparentize("#BEB7C9", 0.45)
                    opacity: 0
                }
                SequentialAnimation {
                    id: dustAnim
                    running: false
                    ParallelAnimation {
                        NumberAnimation {
                            target: dustA
                            property: "x"
                            from: 35
                            to: 2
                            duration: 420
                            easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            target: dustA
                            property: "opacity"
                            to: 0
                            duration: 420
                        }
                    }
                    ParallelAnimation {
                        NumberAnimation {
                            target: dustB
                            property: "x"
                            from: 35
                            to: 58
                            duration: 380
                            easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            target: dustB
                            property: "opacity"
                            from: 0.9
                            to: 0
                            duration: 380
                        }
                    }
                    ParallelAnimation {
                        NumberAnimation {
                            target: dustC
                            property: "x"
                            from: 35
                            to: 66
                            duration: 440
                            easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            target: dustC
                            property: "opacity"
                            from: 0.9
                            to: 0
                            duration: 440
                        }
                    }
                }
            }

            MouseArea {
                id: petArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                preventStealing: true
                property point pressGlobal
                property point grabOffset
                property var velSamples: []
                property bool moved: false

                onPressed: mouse => {
                    moved = false;
                    velSamples = [];
                    const g = mapToItem(root, mouse.x, mouse.y);
                    pressGlobal = g;
                    grabOffset = Qt.point(g.x - creatureWrap.x, g.y - creatureWrap.y);
                }
                onPositionChanged: mouse => {
                    if (!pressed)
                        return;
                    const g = mapToItem(root, mouse.x, mouse.y);
                    if (!moved && Math.hypot(g.x - pressGlobal.x, g.y - pressGlobal.y) > 7) {
                        moved = true;
                        root.startHold();
                    }
                    if (moved) {
                        velSamples.push({
                            t: Date.now(),
                            x: g.x,
                            y: g.y
                        });
                        if (velSamples.length > 6)
                            velSamples.shift();
                        root.moveCatTo(g.x - grabOffset.x, g.y - grabOffset.y);
                    }
                }
                onReleased: mouse => {
                    if (moved && root.motion === 1) {
                        // 用最近 ~120ms 的采样算出手速
                        let ivx = 0, ivy = 0;
                        const now = Date.now();
                        const old = velSamples.find(s => now - s.t <= 130) ?? velSamples[0];
                        const last = velSamples[velSamples.length - 1];
                        if (old && last && last.t > old.t) {
                            const dt = (last.t - old.t) / 1000;
                            ivx = (last.x - old.x) / dt;
                            ivy = (last.y - old.y) / dt;
                        }
                        root.releaseWithVelocity(ivx, ivy);
                    } else if (!moved) {
                        root.pet();
                    }
                    moved = false;
                }
            }
        }

        // ——— 道具 ———
        Item { // 睡觉的 zzz
            id: zzzGroup
            visible: root.sleeping && root.motion === 0
            anchors {
                bottom: body.top
                bottomMargin: 6
                left: body.right
                leftMargin: -10
            }
            width: 46
            height: 34

            Repeater {
                model: 3
                StyledText {
                    id: zzzText
                    required property int index
                    text: "z"
                    font.family: Appearance.font.family.expressive
                    font.pixelSize: 13 + zzzText.index * 6
                    font.weight: Font.DemiBold
                    color: root.accentColor
                    opacity: 0
                    x: zzzText.index * 11
                    y: -zzzText.index * 9
                    SequentialAnimation {
                        running: root.sleeping && root.motion === 0
                        loops: Animation.Infinite
                        PauseAnimation {
                            duration: zzzText.index * 500
                        }
                        ParallelAnimation {
                            NumberAnimation {
                                target: zzzText
                                property: "y"
                                from: -zzzText.index * 9
                                to: -zzzText.index * 9 - 22
                                duration: 2400
                                easing.type: Easing.OutSine
                            }
                            SequentialAnimation {
                                NumberAnimation {
                                    target: zzzText
                                    property: "opacity"
                                    to: 0.9
                                    duration: 400
                                }
                                PauseAnimation {
                                    duration: 1400
                                }
                                NumberAnimation {
                                    target: zzzText
                                    property: "opacity"
                                    to: 0
                                    duration: 600
                                }
                            }
                        }
                    }
                }
            }
        }

        Item { // 下载时双手举箱
            id: boxGroup
            visible: root.mood === "carry"
            anchors.fill: body

            Rectangle { // 举起的左臂（画在箱子后面）
                x: 30
                y: -10
                width: 11
                height: 32
                radius: 5.5
                color: root.furColor
                border.width: 1.5
                border.color: root.furBorder
                transform: Rotation {
                    origin.x: 5.5
                    origin.y: 32
                    angle: 16
                }
            }
            Rectangle { // 举起的右臂
                x: 51
                y: -10
                width: 11
                height: 32
                radius: 5.5
                color: root.furColor
                border.width: 1.5
                border.color: root.furBorder
                transform: Rotation {
                    origin.x: 5.5
                    origin.y: 32
                    angle: -16
                }
            }
            Rectangle { // 箱子
                width: 36
                height: 24
                radius: 4
                anchors {
                    bottom: parent.top
                    bottomMargin: 10
                    horizontalCenter: parent.horizontalCenter
                }
                color: Appearance.colors.colTertiaryContainer
                border.width: 1
                border.color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.6)
                transform: Translate {
                    id: boxBob
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 7
                    height: parent.height
                    color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.7)
                }
                SequentialAnimation {
                    running: root.mood === "carry"
                    loops: Animation.Infinite
                    NumberAnimation {
                        target: boxBob
                        property: "y"
                        to: -3
                        duration: 480
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        target: boxBob
                        property: "y"
                        to: 0
                        duration: 480
                        easing.type: Easing.InOutSine
                    }
                }
            }
        }

        Item { // 编译时在迷你键盘上敲敲敲（bongo 招牌动作）
            id: keyboardGroup
            visible: root.mood === "typing"
            anchors {
                top: body.bottom
                topMargin: -7
                horizontalCenter: body.horizontalCenter
            }
            width: 64
            height: 24

            Rectangle { // 键盘面板（画在爪子后面）
                anchors.bottom: parent.bottom
                width: parent.width
                height: 15
                radius: 4
                color: Appearance.colors.colLayer3
                border.width: 1
                border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.6)
                Row {
                    anchors.centerIn: parent
                    spacing: 4
                    Repeater {
                        model: 5
                        Rectangle {
                            width: 6
                            height: 6
                            radius: 2
                            color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.55)
                        }
                    }
                }
            }
            Rectangle {
                id: typePawL
                x: 8
                y: 2
                width: 20
                height: 12
                radius: 6
                color: root.furColor
                border.width: 1.5
                border.color: root.furBorder
                Rectangle { // 粉粉的肉垫
                    anchors {
                        bottom: parent.bottom
                        bottomMargin: 1.5
                        horizontalCenter: parent.horizontalCenter
                    }
                    width: 7
                    height: 5
                    radius: 2.5
                    color: root.earPink
                }
                SequentialAnimation {
                    running: root.mood === "typing"
                    loops: Animation.Infinite
                    NumberAnimation {
                        target: typePawL
                        property: "y"
                        to: 7
                        duration: 110
                        easing.type: Easing.InQuad
                    }
                    NumberAnimation {
                        target: typePawL
                        property: "y"
                        to: 2
                        duration: 110
                        easing.type: Easing.OutQuad
                    }
                }
            }
            Rectangle {
                id: typePawR
                x: 36
                y: 2
                width: 20
                height: 12
                radius: 6
                color: root.furColor
                border.width: 1.5
                border.color: root.furBorder
                Rectangle {
                    anchors {
                        bottom: parent.bottom
                        bottomMargin: 1.5
                        horizontalCenter: parent.horizontalCenter
                    }
                    width: 7
                    height: 5
                    radius: 2.5
                    color: root.earPink
                }
                SequentialAnimation {
                    running: root.mood === "typing"
                    loops: Animation.Infinite
                    PauseAnimation {
                        duration: 110
                    }
                    NumberAnimation {
                        target: typePawR
                        property: "y"
                        to: 7
                        duration: 110
                        easing.type: Easing.InQuad
                    }
                    NumberAnimation {
                        target: typePawR
                        property: "y"
                        to: 2
                        duration: 110
                        easing.type: Easing.OutQuad
                    }
                }
            }
        }

        Item { // 听歌戴耳机
            id: headphoneGroup
            visible: root.mood === "music"
            anchors.fill: body
            Shape {
                anchors.fill: parent
                ShapePath {
                    strokeColor: root.accentColor
                    strokeWidth: 3.5
                    capStyle: ShapePath.RoundCap
                    fillColor: "transparent"
                    PathSvg {
                        path: "M 14 30 C 14 6 78 6 78 30"
                    }
                }
            }
            Rectangle {
                x: 9
                y: 24
                width: 12
                height: 19
                radius: 6
                color: root.accentColor
            }
            Rectangle {
                x: 71
                y: 24
                width: 12
                height: 19
                radius: 6
                color: root.accentColor
            }
        }

        MaterialSymbol { // 飘着的音符
            id: noteA
            visible: root.mood === "music"
            text: "music_note"
            iconSize: 15
            fill: 1
            color: Appearance.colors.colSecondary
            anchors {
                bottom: body.top
                bottomMargin: 8
                left: body.right
                leftMargin: -18
            }
            opacity: 0
            transform: Translate {
                id: noteAMove
            }
            SequentialAnimation {
                running: root.mood === "music"
                loops: Animation.Infinite
                PauseAnimation {
                    duration: 400
                }
                ParallelAnimation {
                    NumberAnimation {
                        target: noteAMove
                        property: "x"
                        to: 10
                        duration: 1600
                    }
                    NumberAnimation {
                        target: noteAMove
                        property: "y"
                        to: -26
                        duration: 1600
                        easing.type: Easing.OutSine
                    }
                    SequentialAnimation {
                        NumberAnimation {
                            target: noteA
                            property: "opacity"
                            to: 0.9
                            duration: 300
                        }
                        NumberAnimation {
                            target: noteA
                            property: "opacity"
                            to: 0
                            duration: 1300
                        }
                    }
                }
            }
        }
        MaterialSymbol { // 第二个音符，错开
            id: noteB
            visible: root.mood === "music"
            text: "graphic_eq"
            iconSize: 14
            fill: 1
            color: Appearance.colors.colSecondary
            anchors {
                bottom: body.top
                bottomMargin: 4
                right: body.left
                rightMargin: -8
            }
            opacity: 0
            transform: Translate {
                id: noteBMove
            }
            SequentialAnimation {
                running: root.mood === "music"
                loops: Animation.Infinite
                PauseAnimation {
                    duration: 1200
                }
                ParallelAnimation {
                    NumberAnimation {
                        target: noteBMove
                        property: "x"
                        to: -10
                        duration: 1600
                    }
                    NumberAnimation {
                        target: noteBMove
                        property: "y"
                        to: -24
                        duration: 1600
                        easing.type: Easing.OutSine
                    }
                    SequentialAnimation {
                        NumberAnimation {
                            target: noteB
                            property: "opacity"
                            to: 0.9
                            duration: 300
                        }
                        NumberAnimation {
                            target: noteB
                            property: "opacity"
                            to: 0
                            duration: 1300
                        }
                    }
                }
            }
        }

        MaterialSymbol { // 忙碌的汗滴
            id: sweat
            visible: root.mood === "busy"
            text: "water_drop"
            iconSize: 14
            fill: 1
            color: Appearance.colors.colSecondary
            anchors {
                top: body.top
                topMargin: 6
                left: body.right
                leftMargin: -12
            }
            opacity: 0
            transform: Translate {
                id: sweatMove
            }
            SequentialAnimation {
                running: root.mood === "busy"
                loops: Animation.Infinite
                PauseAnimation {
                    duration: 700
                }
                ParallelAnimation {
                    NumberAnimation {
                        target: sweatMove
                        property: "y"
                        from: 0
                        to: 16
                        duration: 700
                        easing.type: Easing.InQuad
                    }
                    SequentialAnimation {
                        NumberAnimation {
                            target: sweat
                            property: "opacity"
                            to: 0.95
                            duration: 150
                        }
                        NumberAnimation {
                            target: sweat
                            property: "opacity"
                            to: 0
                            duration: 550
                        }
                    }
                }
            }
        }

        StyledText { // 找网络时的 "?"
            id: questionMark
            visible: root.mood === "lost"
            text: "?"
            font.family: Appearance.font.family.expressive
            font.pixelSize: 22
            font.weight: Font.DemiBold
            color: Appearance.colors.colSecondary
            anchors {
                bottom: body.top
                bottomMargin: 14
                horizontalCenter: body.horizontalCenter
            }
            transform: Translate {
                id: questionBob
            }
            SequentialAnimation {
                running: root.mood === "lost"
                loops: Animation.Infinite
                NumberAnimation {
                    target: questionBob
                    property: "y"
                    to: -5
                    duration: 500
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: questionBob
                    property: "y"
                    to: 0
                    duration: 500
                    easing.type: Easing.InOutSine
                }
            }
        }

        MaterialSymbol { // 低电量警告
            id: batteryWarn
            visible: root.mood === "anxious"
            text: "battery_alert"
            iconSize: 17
            fill: 1
            color: Appearance.colors.colError
            anchors {
                bottom: body.top
                bottomMargin: 14
                horizontalCenter: body.horizontalCenter
            }
            opacity: 0.9
            SequentialAnimation {
                running: root.mood === "anxious"
                loops: Animation.Infinite
                NumberAnimation {
                    target: batteryWarn
                    property: "opacity"
                    to: 0.25
                    duration: 450
                }
                NumberAnimation {
                    target: batteryWarn
                    property: "opacity"
                    to: 0.9
                    duration: 450
                }
            }
        }

        // ——— 摸摸时的爱心 ———
        Item {
            id: heartsGroup
            anchors {
                bottom: body.top
                bottomMargin: 8
                horizontalCenter: body.horizontalCenter
            }
            width: 44
            height: 44

            MaterialSymbol {
                id: heartA
                text: "favorite"
                iconSize: 15
                fill: 1
                color: Appearance.colors.colError
                anchors.bottom: parent.bottom
                x: 6
                opacity: 0
                transform: Translate {
                    id: heartAMove
                }
            }
            MaterialSymbol {
                id: heartB
                text: "favorite"
                iconSize: 12
                fill: 1
                color: Appearance.colors.colError
                anchors.bottom: parent.bottom
                x: 24
                opacity: 0
                transform: Translate {
                    id: heartBMove
                }
            }
        }

        SequentialAnimation {
            id: heartAnim
            running: false
            ParallelAnimation {
                NumberAnimation {
                    target: heartAMove
                    property: "y"
                    from: 0
                    to: -34
                    duration: 900
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: heartAMove
                    property: "x"
                    from: 0
                    to: 8
                    duration: 900
                }
                SequentialAnimation {
                    NumberAnimation {
                        target: heartA
                        property: "opacity"
                        to: 1
                        duration: 150
                    }
                    PauseAnimation {
                        duration: 300
                    }
                    NumberAnimation {
                        target: heartA
                        property: "opacity"
                        to: 0
                        duration: 400
                    }
                }
            }
            ParallelAnimation {
                NumberAnimation {
                    target: heartBMove
                    property: "y"
                    from: 0
                    to: -40
                    duration: 900
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: heartBMove
                    property: "x"
                    from: 0
                    to: 14
                    duration: 900
                }
                SequentialAnimation {
                    NumberAnimation {
                        target: heartB
                        property: "opacity"
                        to: 1
                        duration: 150
                    }
                    PauseAnimation {
                        duration: 300
                    }
                    NumberAnimation {
                        target: heartB
                        property: "opacity"
                        to: 0
                        duration: 400
                    }
                }
            }
        }
        SequentialAnimation {
            id: wiggleAnim
            running: false
            NumberAnimation {
                target: body
                property: "rotation"
                to: 8
                duration: 90
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: body
                property: "rotation"
                to: -8
                duration: 140
                easing.type: Easing.InOutQuad
            }
            NumberAnimation {
                target: body
                property: "rotation"
                to: 5
                duration: 110
            }
            NumberAnimation {
                target: body
                property: "rotation"
                to: 0
                duration: 120
            }
        }
        SequentialAnimation { // 耳朵抽动（左）
            id: earTwitchL
            running: false
            NumberAnimation {
                target: earLRot
                property: "twitchAngle"
                to: 10
                duration: 80
            }
            NumberAnimation {
                target: earLRot
                property: "twitchAngle"
                to: 0
                duration: 140
            }
        }
        SequentialAnimation { // 耳朵抽动（右）
            id: earTwitchR
            running: false
            NumberAnimation {
                target: earRRot
                property: "twitchAngle"
                to: -10
                duration: 80
            }
            NumberAnimation {
                target: earRRot
                property: "twitchAngle"
                to: 0
                duration: 140
            }
        }
    }
}
