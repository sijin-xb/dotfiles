import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.ii.overlay
// Translation.tr：界面文案走统一翻译表（translations/*.json）
import qs.services

StyledOverlayWidget {
    id: root
    title: Translation.tr("MangoHud FPS")
    minimumWidth: 275
    minimumHeight: 100
    contentItem: FpsLimiterContent {
        radius: root.contentRadius
    }
}
