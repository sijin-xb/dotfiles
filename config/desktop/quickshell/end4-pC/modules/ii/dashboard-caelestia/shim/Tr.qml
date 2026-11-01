pragma Singleton

import QtQuick
import Quickshell
import qs.services

/**
 * Caelestia `Caelestia.I18n.Tr` 的本地代理。
 *
 * 上游 Tr 走 Caelestia 插件的 translator（读 Caelestia 自己的翻译文件），
 * 本仓库的翻译在 services/Translation.qml（读 translations/*.json，
 * 1314 条键，覆盖了 dashboard 大部分常用词）。这里做同形转发。
 *
 * 语义差异：
 *   - trCtx / trCtxN 忽略 context（本仓库 Translation 不带 context 概念）
 *   - trN / trCtxN 忽略复数（中文没有复数变化），只做 %n 替换
 *   - trMarked 退化为 tr
 */
Singleton {
    id: root

    function tr(text) {
        return Translation.tr(text);
    }

    function trCtx(text, context) {
        return Translation.tr(text);
    }

    function trN(text, plural, n) {
        return Translation.tr(text).replace("%n", n);
    }

    function trCtxN(text, plural, n, context) {
        return Translation.tr(text).replace("%n", n);
    }

    function trMarked(text) {
        return Translation.tr(text);
    }
}
