import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    required property var screenRef
    required property string monitor
    required property string framePath

    property int revealDelayMs: 32
    property int fadeDurationMs: 180
    property bool armed: false

    signal covered()
    signal finished()
    signal failed()

    screen: screenRef
    color: "transparent"

    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    mask: Region {}

    WlrLayershell.namespace: "dms:plugins:mpvpaper:transition"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    function reveal() {
        if (!armed || guardFrame.status !== Image.Ready) {
            finished()
            return
        }
        revealDelay.restart()
    }

    Image {
        id: guardFrame
        anchors.fill: parent
        source: root.framePath ? "file://" + root.framePath : ""
        fillMode: Image.Stretch
        asynchronous: false
        cache: false
        smooth: false
        opacity: 1

        onStatusChanged: {
            if (status === Image.Ready && !root.armed) {
                root.armed = true
                Qt.callLater(() => root.covered())
            } else if (status === Image.Error) {
                root.failed()
            }
        }
    }

    Timer {
        id: revealDelay
        interval: root.revealDelayMs
        repeat: false
        onTriggered: fadeOut.restart()
    }

    NumberAnimation {
        id: fadeOut
        target: guardFrame
        property: "opacity"
        from: 1
        to: 0
        duration: root.fadeDurationMs
        easing.type: Easing.InOutCubic
        onFinished: root.finished()
    }
}
