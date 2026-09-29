import QtQuick
import Quickshell

/**
 * 运行时探测 Caelestia QML 插件（QML 模块 Caelestia.Config）是否可用。
 *
 * ── 为什么需要它 ────────────────────────────────────────────────────
 * end4-PC 的锁屏（modules/ii/lock/caelestia/**）与仪表盘（modules/ii/
 * dashboard-caelestia/**）是从 caelestia-dots/shell vendor 过来的，其中 132 个
 * 文件写着 `import Caelestia.Config`。
 *
 * QML 的 `import <模块>` 是**编译期硬依赖**：模块解析不到时，那些文件里的类型
 * 全部 unavailable，错误沿
 *     Sidebar → FileDialog → IslandHost → IllogicalImpulseFamily → shell.qml
 * 一路上抛，`qs -c end4-pC` 直接 "Failed to load configuration"，表现就是
 * 登录后桌面残缺或只剩鼠标光标。
 *
 * 面板族里真正构成硬依赖的只有两处：Lock（锁屏）与 IslandHost（岛屿+仪表盘）。
 * 所以 IllogicalImpulseFamily.qml 把它们改成 `PanelLoader { source: ... }` 的
 * **运行时**创建，并用本探针决定要不要创建：
 *   · 插件在位 → 行为与以前完全一致（两个面板都挂上）
 *   · 插件缺失 → 只少锁屏与灵动岛，其余面板照常起来，不再整个桌面起不来
 *
 * 插件产物由 install.sh 的 [4a/7] 编译到 ~/src/caelestia-build/qml，
 * 再由 start_quickshell.sh（会话自启）与 fish config.fish（手动跑 qs）注入
 * QML2_IMPORT_PATH。
 *
 * ── 为什么用 Qt.createQmlObject 探测 ────────────────────────────────
 * 这是唯一能在**运行时**问出「某个 QML 模块装没装」的办法：模块缺失时
 * createQmlObject 抛异常，可以 catch；而静态 import 一旦失败就是加载期错误，
 * 没法拦。探针本身不 import Caelestia.*，所以插件缺失时它自己仍能编译。
 */
QtObject {
    /**
     * 探测结果：true = Caelestia.Config 可解析。
     *
     * 绑定只在第一次求值时执行一次（不依赖任何可变属性），探测有副作用
     * （createQmlObject 会在 this 下挂一个临时 QtObject），不做重复探测。
     */
    readonly property bool available: {
        try {
            Qt.createQmlObject("import Caelestia.Config; QtObject {}", this);
            console.warn("[end4-pC] Caelestia QML 插件就绪：锁屏与灵动岛已挂载。");
            return true;
        } catch (e) {
            console.warn("[end4-pC] Caelestia QML 插件不可用（import Caelestia.Config 失败）：" + e);
            console.warn("[end4-pC]   → 本次只跳过「锁屏」与「灵动岛」，其余面板不受影响。");
            console.warn("[end4-pC]   → 修复：重跑 install.sh（[4a/7] 会把插件编译到 ~/src/caelestia-build/qml）；");
            console.warn("[end4-pC]     或在 fish 里 `set -gx QML2_IMPORT_PATH ~/src/caelestia-build/qml` 后重启 qs。");
            return false;
        }
    }
}
