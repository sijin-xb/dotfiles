pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Caelestia.Config
// ⚠ 这里**不能** import Caelestia.Services：那个 C++ 模块导出的单例也叫
// Lyrics，会盖掉 ../../shim 里的同名 QML 单例（实测本页的 Lyrics 解析到的是
// caelestia::services::Lyrics，缺 subtitleFor 时报
// "Property 'subtitleFor' ... is not a function"）。
// 后果是这一页读 Caelestia 自己的取词后端，而不是本仓库的 LyricsService，
// 与桌面歌词浮层各显示各的。去掉该 import，Lyrics 才会落到 shim 上。
import "../../components"
import "../../components/containers"
import "../../components/controls"
import "../../components/effects"
import "../../shim"

Item {
    id: root

    // Funny binding hack to make lyrics update
    readonly property var _: {
        const p = Players.active;
        if (p)
            Lyrics.setTrack(p.trackArtist, p.trackTitle, p.trackAlbum, p.length);
        else
            Lyrics.clearTrack();
    }

    readonly property real fadeAmount: 0.1
    property bool flag
    property list<string> lyricList: Lyrics.lyrics

    layer.enabled: true
    layer.effect: Mask {
        maskSource: mask

        Rectangle {
            id: mask

            layer.enabled: true
            visible: false
            implicitWidth: root.width
            implicitHeight: root.height

            gradient: Gradient {
                orientation: Gradient.Vertical

                GradientStop {
                    color: Qt.alpha("black", 0)
                    position: 0
                }
                GradientStop {
                    color: Qt.alpha("black", 1)
                    position: root.fadeAmount
                }
                GradientStop {
                    color: Qt.alpha("black", 1)
                    position: 1 - root.fadeAmount
                }
                GradientStop {
                    color: Qt.alpha("black", 0)
                    position: 1
                }
            }
        }
    }

    state: {
        flag; // For some reason it doesn't update sometimes, so use this to force an update
        if (Lyrics.hasLyrics)
            return "hasLyrics";
        if (Lyrics.loading)
            return "loading";
        return "noLyrics";
    }

    states: [
        State {
            name: "loading"

            PropertyChanges {
                loadingIndicator.opacity: 1
                lyrics.opacity: 0
                noLyrics.opacity: 0
            }
        },
        State {
            name: "hasLyrics"

            PropertyChanges {
                loadingIndicator.opacity: 0
                lyrics.opacity: 1
                noLyrics.opacity: 0
            }
        },
        State {
            name: "noLyrics"

            PropertyChanges {
                loadingIndicator.opacity: 0
                lyrics.opacity: 0
                noLyrics.opacity: 1
            }
        }
    ]

    transitions: [
        Transition {
            from: "loading"

            SequentialAnimation {
                Anim {
                    target: loadingIndicator
                    property: "opacity"
                    type: Anim.DefaultEffects
                }
                Anim {
                    targets: [lyrics, noLyrics]
                    property: "opacity"
                    type: Anim.SlowEffects
                }
            }
        },
        Transition {
            from: "hasLyrics"

            SequentialAnimation {
                Anim {
                    target: lyrics
                    property: "opacity"
                    type: Anim.DefaultEffects
                }
                Anim {
                    targets: [loadingIndicator, noLyrics]
                    property: "opacity"
                    type: Anim.SlowEffects
                }
            }
        },
        Transition {
            from: "noLyrics"

            SequentialAnimation {
                Anim {
                    target: noLyrics
                    property: "opacity"
                    type: Anim.DefaultEffects
                }
                Anim {
                    targets: [loadingIndicator, lyrics]
                    property: "opacity"
                    type: Anim.SlowEffects
                }
            }
        }
    ]

    Connections {
        function onHasLyricsChanged() {
            root.flag = !root.flag;
        }

        target: Lyrics
    }

    Loader {
        id: loadingIndicator

        anchors.centerIn: parent
        asynchronous: true
        active: opacity > 0
        opacity: 0

        sourceComponent: ColumnLayout {
            spacing: Tokens.spacing.large

            StyledRect {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: shape.implicitSize + Tokens.padding.medium * 2
                implicitHeight: shape.implicitSize + Tokens.padding.medium * 2
                color: Colours.palette.m3primaryContainer
                radius: Tokens.rounding.full

                LoadingIndicator {
                    id: shape

                    anchors.centerIn: parent
                    implicitSize: Math.round(Tokens.sizes.dashboard.mediaSectionWidth / 5)
                    containsIcon: true // This removes the pentagon, which is not centered
                }
            }

            StyledText {
                text: Tr.tr("Loading lyrics...")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.title.medium
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    Loader {
        id: noLyrics

        anchors.centerIn: parent
        asynchronous: true
        active: opacity > 0
        opacity: 0

        sourceComponent: ColumnLayout {
            spacing: Tokens.spacing.small

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: "sentiment_sad"
                fontStyle: Tokens.font.icon.builders.large.scale(2).build()
                color: Colours.palette.m3outline
            }

            StyledText {
                text: Tr.tr("No lyrics found")
                color: Colours.palette.m3outline
                font: Tokens.font.title.medium
            }
        }
    }

    StyledListView {
        id: lyrics

        anchors.fill: parent
        anchors.topMargin: parent.height * root.fadeAmount / 2
        anchors.bottomMargin: parent.height * root.fadeAmount / 2

        displayMarginBeginning: anchors.topMargin
        displayMarginEnd: anchors.bottomMargin

        model: root.lyricList
        Component.onCompleted: {
            currentIndex = Qt.binding(() => {
                model; // Force update when lyrics change
                return Lyrics.indexForTime(Players.active?.position ?? 0);
            });
            positionViewAtIndex(currentIndex, ListView.Center);
        }
        onModelChanged: Qt.callLater(() => positionViewAtIndex(currentIndex, ListView.Center))

        highlightRangeMode: ListView.ApplyRange
        highlightMoveDuration: Tokens.anim.durations.large
        highlightMoveVelocity: -1
        preferredHighlightBegin: (height - (currentItem?.implicitHeight ?? 0)) / 2
        preferredHighlightEnd: (height + (currentItem?.implicitHeight ?? 0)) / 2

        spacing: Tokens.spacing.small
        opacity: 0
        enabled: opacity > 0

        // 原文 + 副标题（翻译 / 音译）两行一组。
        // 外层用 Item 而不是 Column：MouseArea 要是 Column 的子项，会被当作
        // 一个布局项参与排布，跟 anchors.fill 打架。
        delegate: Item {
            id: lyric

            required property string modelData
            required property int index

            // ListView.isCurrentItem 只在 delegate 根项上可靠，
            // 子项统一经 isCurrent 读，不要各自再取一次。
            readonly property bool isCurrent: ListView.isCurrentItem
            property real effectScale: isCurrent ? 1 : 0

            // 只给当前行取副标题：非当前行直接短路成空串，
            // 避免为几百行歌词各建一个字符串绑定（那才是真正的滚动开销）。
            readonly property string subtitle: isCurrent ? (Lyrics.subtitleFor(index) ?? "") : ""

            anchors.left: lyrics.contentItem.left
            anchors.right: lyrics.contentItem.right
            height: col.implicitHeight
            implicitHeight: col.implicitHeight

            Column {
                id: col

                width: parent.width
                spacing: 2

                StyledText {
                    id: lyricText

                    width: parent.width
                    text: lyric.modelData || ". . ."
                    color: lyric.isCurrent ? Colours.palette.m3primary : mouse.containsMouse ? Colours.palette.m3onSurface : Colours.palette.m3outline
                    font: Tokens.font.body.medium
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere

                    layer.enabled: lyric.effectScale > 0
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: Colours.palette.m3primary
                        shadowOpacity: 0.5 * lyric.effectScale
                        shadowBlur: 0.6 * lyric.effectScale
                        blur: 0.4 * lyric.effectScale
                    }
                }

                // 翻译 / 音译 —— 与桌面歌词浮层的 trans / roman 接轨
                StyledText {
                    width: parent.width
                    visible: lyric.subtitle !== ""
                    text: lyric.subtitle
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    opacity: lyric.isCurrent ? 0.9 : 0

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }
            }

            Behavior on effectScale {
                Anim {
                    type: Anim.SlowEffects
                }
            }

            MouseArea {
                id: mouse

                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: {
                    const p = Players.active;
                    if (p)
                        p.position = Lyrics.timeForIndex(lyric.index);
                }
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.SlowEffects
            }
        }
    }

    Behavior on lyricList {
        SequentialAnimation {
            Anim {
                target: lyrics
                property: "opacity"
                to: 0
                type: Anim.DefaultEffects
            }
            PropertyAction {}
            Anim {
                target: lyrics
                property: "opacity"
                to: 1
                type: Anim.SlowEffects
            }
        }
    }
}
