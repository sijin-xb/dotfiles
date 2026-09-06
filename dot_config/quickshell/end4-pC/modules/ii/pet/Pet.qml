pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Shapes

/**
 * 桌宠本尊：一只 bongo cat 风格的小白猫，纯 QML 手绘（无素材、无 Live2D，
 * 它就是 Shell 的一部分）。毛色固定为白色，让"猫"的身份稳定；道具
 * （zzz、箱子、键盘、耳机…）用 matugen 主题色，跟桌面融为一体。
 *
 * 心情来自 PetState。招牌动作是交替拍爪（bong bong）：
 * 打字时在键盘上快拍、听歌时跟节拍拍、平时慢悠悠地拍。
 */
Item {
    id: root

    property var vitals
    property alias interactionRoot: creatureWrap
    readonly property string mood: vitals?.mood ?? "sleep"
    readonly property bool sleeping: mood === "sleep"
    property bool blinking: false
    readonly property bool petted: pettedTimer.running

    // ——— 固定猫猫配色（不随深浅色主题变化）———
    readonly property color furColor: "#FDFDFD"
    readonly property color furBorder: ColorUtils.transparentize("#544F5B", 0.78)
    readonly property color faceColor: "#4A4550"
    readonly property color earPink: "#F5AFC0"
    readonly property color nosePink: "#F09DB2"
    readonly property color blushPink: ColorUtils.transparentize("#F5AFC0", 0.45)
    // Shell 侧的道具（zzz、键盘、耳机…）沿用主题强调色
    readonly property color accentColor: Appearance.colors.colPrimary

    readonly property bool bubbleVisible: petArea.containsMouse || petted
    readonly property string bubbleLabel: petted ? "bong bong ♪" : (vitals?.moodLabel ?? "")
    readonly property string bubbleDetail: petted ? "" : (vitals?.moodDetail ?? "")

    // 呼吸幅度/周期随心情变化
    readonly property real breathAmp: sleeping ? 0.05 : (mood === "busy" ? 0.045 : 0.03)
    readonly property int breathPeriod: sleeping ? 2600 : (mood === "busy" ? 1100 : 1700)
    // 尾巴：睡着不动，忙碌/焦虑时烦躁地快甩
    readonly property int tailPeriod: sleeping ? 0 : (mood === "busy" || mood === "anxious" ? 500 : (mood === "music" ? 700 : 1500))
    // 拍爪：打字/搬货时不拍（有专门动作），醒着就拍，听歌跟节拍
    readonly property bool pawTapActive: !sleeping && mood !== "typing" && mood !== "carry"
    readonly property int pawTapPeriod: mood === "music" ? 640 : 1700

    function pet() {
        pettedTimer.restart();
        heartAnim.restart();
        wiggleAnim.restart();
    }

    onMoodChanged: {
        // 动画可能被打断在半路；把位移归零
        body.x = 0;
        body.rotation = 0;
        pawLRot.angle = 0;
        pawRRot.angle = 0;
    }

    Timer { // 摸摸反应
        id: pettedTimer
        interval: 2200
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
        running: root.visible && !root.sleeping
        onTriggered: {
            if (Math.random() < 0.5)
                earTwitchL.restart();
            else
                earTwitchR.restart();
            interval = 3200 + Math.random() * 4200;
            restart();
        }
    }

    // ——— 气泡 ———
    Rectangle {
        id: bubble
        anchors {
            bottom: creatureWrap.top
            bottomMargin: 10
            horizontalCenter: creatureWrap.horizontalCenter
        }
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
        anchors {
            bottom: parent.bottom
            bottomMargin: 20
            horizontalCenter: parent.horizontalCenter
        }
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
                running: root.mood === "busy"
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
                running: root.mood === "anxious"
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
                running: root.mood === "lost"
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
            SequentialAnimation { // 听歌点头
                running: root.mood === "music" && !root.petted
                loops: Animation.Infinite
                NumberAnimation {
                    target: body
                    property: "rotation"
                    to: 4
                    duration: 300
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: body
                    property: "rotation"
                    to: -4
                    duration: 600
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: body
                    property: "rotation"
                    to: 0
                    duration: 300
                    easing.type: Easing.InOutSine
                }
            }

            // ——— 尾巴：身体右后方的描边曲线，会摇 ———
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

            // ——— 耳朵：不闭合路径（fill 自动闭合，底边不描边藏在身体里），
            //      可以抽动、焦虑时耷拉 ———
            Shape {
                anchors.fill: parent
                transform: Rotation {
                    id: earLRot
                    origin.x: 27
                    origin.y: 10
                    property real twitchAngle: 0
                    angle: root.earDroopL + earLRot.twitchAngle
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
                    angle: root.earDroopR + earRRot.twitchAngle
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
                visible: !root.sleeping && !root.blinking
            }
            Rectangle {
                x: 57
                y: root.mood === "anxious" ? 18 : 20
                width: root.mood === "anxious" ? 13 : 11
                height: width
                radius: width / 2
                color: root.faceColor
                visible: !root.sleeping && !root.blinking
            }
            Rectangle { // 眼睛高光
                x: 26.5
                y: root.mood === "anxious" ? 20.5 : 22.5
                width: 3.5
                height: 3.5
                radius: 1.75
                color: "#FFFFFF"
                visible: !root.sleeping && !root.blinking
            }
            Rectangle {
                x: 59.5
                y: root.mood === "anxious" ? 20.5 : 22.5
                width: 3.5
                height: 3.5
                radius: 1.75
                color: "#FFFFFF"
                visible: !root.sleeping && !root.blinking
            }
            Shape { // 睡着/眨眼：⌒ ⌒
                anchors.fill: parent
                visible: root.sleeping || root.blinking
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

            Shape { // "ω" 猫嘴
                anchors.fill: parent
                visible: root.mood !== "sleep" && root.mood !== "busy" && root.mood !== "anxious"
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
            Shape { // 认真抿嘴
                anchors.fill: parent
                visible: root.mood === "busy"
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
                visible: root.mood === "anxious"
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
                visible: root.sleeping
            }

            // ——— 前爪（趴着的 bongo 爪）：打字/举箱时会换专门动作 ———
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

            MouseArea {
                id: petArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pet()
            }
        }

        // ——— 道具 ———
        Item { // 睡觉的 zzz
            id: zzzGroup
            visible: root.sleeping
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
                        running: root.sleeping
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

    // 焦虑时耳朵耷拉
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
}
