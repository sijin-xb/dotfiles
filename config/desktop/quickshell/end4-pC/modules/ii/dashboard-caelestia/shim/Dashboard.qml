pragma Singleton

import QtQuick
import Quickshell

/**
 * 替代 Caelestia `ScreenState` 里 dashboard 相关的三个成员。
 *
 * 上游的 ScreenState 是 PersistentProperties（带 required ShellScreen），
 * 语义是「一块屏幕上的所有抽屉状态」。dashboard 只用到其中两项：
 *   - dashboardTab   当前激活的 tab 索引
 *   - dashboardDate  日历当前展示的月份
 * 加上「用户点头像要求关面板」这个意图 → closeRequested() 信号。
 *
 * 用单例而不是 per-screen 实例：end4-pC 这边 dashboard 只有一份
 * （IslandHost 是单例 PanelWindow），没有 per-screen 的必要。
 */
Singleton {
    id: root

    /// 当前激活的 dashboard tab 索引（0 = Dashboard，1 = Media，…）。
    property int dashboardTab: 0

    /// 日历当前展示的月份。点月份标题或中间键会回到当前月。
    property date dashboardDate: new Date()

    /// 面板内组件请求关闭时发出（例如点击头像触发选择器）。
    signal closeRequested()
}
