import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * GitHub 仓库卡片（设置 → GitHub 的仓库列表里用）。
 *
 * 显示：名称（+ 私有 / fork / 归档徽标）、描述、语言、Star、Fork、最后更新。
 * 点击整卡触发 `activated(html_url)`，由调用方负责在浏览器打开。
 */
Rectangle {
    id: card
    property var repo: ({})
    signal activated(url: string)

    readonly property bool hovered: cardMouse.containsMouse

    radius: Appearance.rounding.normal
    color: card.hovered
        ? Appearance.colors.colLayer1Hover
        : Appearance.colors.colLayer1
    border.width: 1
    border.color: Appearance.colors.colLayer0Border

    Behavior on color {
        ColorAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    function relativeDate(iso) {
        if (!iso)
            return "";
        const then = new Date(iso).getTime();
        if (isNaN(then))
            return "";
        const days = Math.floor((Date.now() - then) / 86400000);
        if (days <= 0) return Translation.tr("today");
        if (days === 1) return Translation.tr("yesterday");
        if (days < 30) return `${days} ` + Translation.tr("days ago");
        if (days < 365) return `${Math.floor(days / 30)} ` + Translation.tr("months ago");
        return `${Math.floor(days / 365)} ` + Translation.tr("years ago");
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: 10
        }
        spacing: 4

        // 名称 + 徽标
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            MaterialSymbol {
                text: card.repo.private ? "lock" : "book"
                iconSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colPrimary
            }

            StyledText {
                Layout.fillWidth: true
                text: card.repo.name ?? ""
                elide: Text.ElideRight
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
            }

            StyledText {
                visible: card.repo.fork === true
                text: Translation.tr("fork")
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.smallest
            }

            StyledText {
                visible: card.repo.archived === true
                text: Translation.tr("archived")
                color: Appearance.colors.colError
                font.pixelSize: Appearance.font.pixelSize.smallest
            }
        }

        // 描述
        StyledText {
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: card.repo.description ?? ""
            visible: (card.repo.description ?? "").length > 0
            elide: Text.ElideRight
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            color: Appearance.colors.colOnSurfaceVariant
            font.pixelSize: Appearance.font.pixelSize.smaller
        }

        // 元信息
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            RowLayout {
                spacing: 3
                visible: (card.repo.language ?? "").length > 0
                Rectangle {
                    implicitWidth: 8
                    implicitHeight: 8
                    radius: 4
                    color: Appearance.colors.colTertiary
                }
                StyledText {
                    text: card.repo.language ?? ""
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.smallest
                }
            }

            RowLayout {
                spacing: 3
                MaterialSymbol {
                    text: "star"
                    iconSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnSurfaceVariant
                }
                StyledText {
                    text: `${card.repo.stargazers_count ?? 0}`
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.features: { "tnum": 1 }
                }
            }

            RowLayout {
                spacing: 3
                MaterialSymbol {
                    text: "fork_right"
                    iconSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnSurfaceVariant
                }
                StyledText {
                    text: `${card.repo.forks_count ?? 0}`
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.features: { "tnum": 1 }
                }
            }

            Item {
                Layout.fillWidth: true
            }

            StyledText {
                text: card.relativeDate(card.repo.updated_at)
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.smallest
            }
        }
    }

    MouseArea {
        id: cardMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: card.activated(card.repo.html_url ?? "")
    }
}
