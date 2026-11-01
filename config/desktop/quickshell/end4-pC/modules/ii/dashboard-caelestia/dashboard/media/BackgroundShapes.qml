pragma ComponentBehavior: Bound

import QtQuick
import M3Shapes
import "../../components"
import "../../shim"

Item {
    id: root

    readonly property list<int> shapePool: [MaterialShape.Circle, MaterialShape.Cookie4Sided, MaterialShape.Cookie6Sided, MaterialShape.Cookie7Sided, MaterialShape.Cookie9Sided, MaterialShape.Cookie12Sided, MaterialShape.Sunny, MaterialShape.VerySunny, MaterialShape.SoftBurst, MaterialShape.Pentagon, MaterialShape.Gem, MaterialShape.Arch, MaterialShape.Arrow, MaterialShape.Pill, MaterialShape.Triangle, MaterialShape.Fan, MaterialShape.Oval]

    property int count: 14
    property real minSize: 36
    property real maxSize: 124
    property real minSpeed: 4
    property real maxSpeed: 18
    property real minRotSpeed: -12
    property real maxRotSpeed: 12
    property list<real> lightOpacities: [0.34, 0.34, 0.08, 0.2]
    property list<real> darkOpacities: [0.16, 0.16, 0.04, 0.16]

    function rand(min: real, max: real): real {
        return min + Math.random() * (max - min);
    }

    function signedRand(min: real, max: real): real {
        return rand(min, max) * (Math.random() < 0.5 ? -1 : 1);
    }

    // 漂移行程：固定值，**不能**绑定 root.width / root.height。
    // 面板开合时宽度每帧都在变，duration 跟着变会让每个动画每帧重启，
    // 形状会原地抖动而不是漂移。
    // 取值比面板略宽/略高，保证循环的两端都在画面外，回环时看不见跳变。
    readonly property real spanX: 2400
    readonly property real spanY: 900

    readonly property bool animating: root.visible && root.width > 0 && root.height > 0
        && (Players.active?.isPlaying ?? false)

    clip: true
    Component.onCompleted: shapes.model = count

    Repeater {
        id: shapes

        DriftingShape {}
    }

    // 漂移原本由这里的 FrameAnimation + JS 循环驱动：每帧 itemAt(i) 取 14 个对象、
    // 再逐个写 x / y / rotation 三个属性，全部在 JS 里执行；同时它让整个岛窗口
    // 每帧都必须重绘，岛一旦展开就再也不会空闲。
    // 现在改成每个形状自己挂 QML 动画（C++ 侧驱动，无逐帧 JS），
    // 位移/旋转的观感、速度区间、随机分布都保持不变。

    component DriftingShape: MaterialShape {
        id: shapeItem

        required property int index

        // 速度与方向：与原 JS 循环里的 vx / vy / vr 同分布，只是不再逐帧累加
        readonly property real vx: root.signedRand(root.minSpeed, root.maxSpeed)
        readonly property real vy: root.signedRand(root.minSpeed, root.maxSpeed)
        // 旋转速度可能随机到接近 0，会让 duration 发散，夹一个下限
        readonly property real vr: {
            const v = root.rand(root.minRotSpeed, root.maxRotSpeed);
            return Math.abs(v) < 0.5 ? (v < 0 ? -0.5 : 0.5) : v;
        }
        readonly property int colourIdx: Math.floor(Math.random() * 4)
        readonly property bool goingRight: shapeItem.vx >= 0
        readonly property bool goingDown: shapeItem.vy >= 0
        readonly property real baseRotation: root.rand(0, 360)
        // 初始散布：与原实现 Component.onCompleted 里的随机位置等价，
        // 保证面板刚打开时形状就已经铺满，而不是从边缘慢慢飘进来
        readonly property real initialX: root.rand(0, 1000)
        readonly property real initialY: root.rand(0, 420)

        implicitSize: root.minSize + (index / root.count) * (root.maxSize - root.minSize)
        shape: root.shapePool[Math.floor(Math.random() * root.shapePool.length)]
        color: [Colours.palette.m3primaryContainer, Colours.palette.m3secondaryContainer, Colours.palette.m3tertiaryContainer, Colours.palette.m3outlineVariant][colourIdx]
        opacity: Colours.light ? root.lightOpacities[colourIdx] : root.darkOpacities[colourIdx]

        // x / y / rotation 不在声明处绑值 —— 那会和下面的动画抢同一个属性。
        // 首帧位置在这里落定，动画只负责此后的漂移。
        Component.onCompleted: {
            x = initialX;
            y = initialY;
            rotation = baseRotation;
        }

        // ── 漂移：QML 动画取代逐帧 JS 循环 ──
        // 分两段：① 从随机初始位置漂到出屏（只跑一次，保住原来的随机分布）；
        // ② 出屏 → 另一侧出屏，无限循环 —— 两端都在画面外，回环时看不到跳变。
        // 第二段的 from/to 是常量表达式，不依赖面板尺寸，所以开合动画期间不会重启。
        SequentialAnimation on x {
            running: root.animating

            NumberAnimation {
                to: shapeItem.goingRight ? root.spanX : -shapeItem.implicitSize
                duration: Math.max(1, Math.abs(to - shapeItem.initialX) / Math.abs(shapeItem.vx) * 1000)
            }
            NumberAnimation {
                from: shapeItem.goingRight ? -shapeItem.implicitSize : root.spanX
                to: shapeItem.goingRight ? root.spanX : -shapeItem.implicitSize
                duration: Math.max(1, Math.abs(to - from) / Math.abs(shapeItem.vx) * 1000)
                loops: Animation.Infinite
            }
        }

        SequentialAnimation on y {
            running: root.animating

            NumberAnimation {
                to: shapeItem.goingDown ? root.spanY : -shapeItem.implicitSize
                duration: Math.max(1, Math.abs(to - shapeItem.initialY) / Math.abs(shapeItem.vy) * 1000)
            }
            NumberAnimation {
                from: shapeItem.goingDown ? -shapeItem.implicitSize : root.spanY
                to: shapeItem.goingDown ? root.spanY : -shapeItem.implicitSize
                duration: Math.max(1, Math.abs(to - from) / Math.abs(shapeItem.vy) * 1000)
                loops: Animation.Infinite
            }
        }

        // 旋转本来就是周期运动，一段就够；起止角差 360°，回环处角度等价
        NumberAnimation on rotation {
            running: root.animating
            from: shapeItem.baseRotation
            to: shapeItem.baseRotation + (shapeItem.vr >= 0 ? 360 : -360)
            duration: 360 / Math.abs(shapeItem.vr) * 1000
            loops: Animation.Infinite
        }

        Behavior on color {
            CAnim {}
        }

        Behavior on opacity {
            Anim {
                type: Anim.SlowEffects
            }
        }
    }
}
