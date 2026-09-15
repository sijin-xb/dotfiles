pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

/**
 * Provides access to some Hyprland data not available in Quickshell.Hyprland.
 */
Singleton {
    id: root
    property var windowList: []
    property var addresses: []
    property var windowByAddress: ({})
    property var workspaces: []
    property var workspaceIds: []
    property var workspaceById: ({})
    property var activeWorkspace: null
    property var monitors: []
    property var layers: ({})

    // Convenient stuff

    function toplevelsForWorkspace(workspace) {
        return ToplevelManager.toplevels.values.filter(toplevel => {
            const address = `0x${toplevel.HyprlandToplevel?.address}`;
            var win = HyprlandData.windowByAddress[address];
            return win?.workspace?.id === workspace;
        })
    }

    function hyprlandClientsForWorkspace(workspace) {
        return root.windowList.filter(win => win.workspace.id === workspace);
    }

    function clientForToplevel(toplevel) {
        if (!toplevel || !toplevel.HyprlandToplevel) {
            return null;
        }
        const address = `0x${toplevel?.HyprlandToplevel?.address}`;
        return root.windowByAddress[address];
    }

    // Internals

    function updateWindowList() {
        if (WM.compositor !== "hyprland") return;
        getClients.running = true;
    }

    function updateLayers() {
        if (WM.compositor !== "hyprland") return;
        getLayers.running = true;
    }

    function updateMonitors() {
        if (WM.compositor !== "hyprland") return;
        getMonitors.running = true;
    }

    function updateWorkspaces() {
        if (WM.compositor !== "hyprland") return;
        getWorkspaces.running = true;
        getActiveWorkspace.running = true;
    }

    function updateAll() {
        if (WM.compositor !== "hyprland") return;
        updateWindowList();
        updateMonitors();
        updateLayers();
        updateWorkspaces();
    }

    // 事件 → 需要刷新的数据。原先每个事件都跑 updateAll()，而一轮 updateAll 要起
    // 5 个 hyprctl 子进程（实测每个 3~5ms CPU，合计约 20ms）。一次工作区切换就会
    // 收到近十个事件，滚轮连切时成倍——主线程被进程创建拖住，壁纸视差动画就会
    // 明显掉帧 / 慢半拍。这里按事件类型只刷该刷的，并用定时器把同一波事件合并成一次。
    property var pendingRefresh: ({})
    function requestRefresh(kind) {
        pendingRefresh[kind] = true;
        refreshDebounce.restart();
    }
    function flushRefresh() {
        const pending = pendingRefresh;
        pendingRefresh = ({});
        if (pending.windows) updateWindowList();
        if (pending.layers) updateLayers();
        if (pending.monitors) updateMonitors();
        if (pending.workspaces) updateWorkspaces();
        if (pending.all) updateAll();
    }
    function refreshForEvent(name) {
        if (!name) {
            requestRefresh("all");
            return;
        }
        if (name.startsWith("workspace") || name === "focusedmon" || name === "focusedmonv2"
            || name === "activespecial" || name === "activewindow" || name === "activewindowv2") {
            // 工作区/焦点变化同时影响栏上的工作区与活动窗口
            requestRefresh("workspaces");
            requestRefresh("windows");
            return;
        }
        if (name === "openwindow" || name === "closewindow" || name === "movewindow"
            || name === "changefloatingmode" || name === "fullscreen" || name === "minimize"
            || name === "urgent" || name === "togglegroup" || name === "moveintogroup"
            || name === "moveoutofgroup" || name === "pin") {
            requestRefresh("windows");
            return;
        }
        if (name.startsWith("monitor")) {
            requestRefresh("monitors");
            return;
        }
        // 图层开关过于频繁，且 shell 不依赖它做实时判断；screencast 同理
        if (name === "openlayer" || name === "closelayer" || name === "screencast") return;
        // 未知事件：保守全刷
        requestRefresh("all");
    }

    Timer {
        id: refreshDebounce
        // 把同一波事件（一次切换往往连着好几个）合并成一次刷新
        interval: 40
        onTriggered: root.flushRefresh()
    }

    function biggestWindowForWorkspace(workspaceId) {
        const windowsInThisWorkspace = HyprlandData.windowList.filter(w => w.workspace.id == workspaceId);
        return windowsInThisWorkspace.reduce((maxWin, win) => {
            const maxArea = (maxWin?.size?.[0] ?? 0) * (maxWin?.size?.[1] ?? 0);
            const winArea = (win?.size?.[0] ?? 0) * (win?.size?.[1] ?? 0);
            return winArea > maxArea ? win : maxWin;
        }, null);
    }

    Component.onCompleted: {
        updateAll();
    }

    Connections {
        target: Hyprland
        enabled: WM.compositor === "hyprland"

        function onRawEvent(event) {
            root.refreshForEvent(event.name);
        }
    }

    Process {
        id: getClients
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            id: clientsCollector
            onStreamFinished: {
                root.windowList = JSON.parse(clientsCollector.text)
                let tempWinByAddress = {};
                for (var i = 0; i < root.windowList.length; ++i) {
                    var win = root.windowList[i];
                    tempWinByAddress[win.address] = win;
                }
                root.windowByAddress = tempWinByAddress;
                root.addresses = root.windowList.map(win => win.address);
            }
        }
    }

    Process {
        id: getMonitors
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            id: monitorsCollector
            onStreamFinished: {
                root.monitors = JSON.parse(monitorsCollector.text);
            }
        }
    }

    Process {
        id: getLayers
        command: ["hyprctl", "layers", "-j"]
        stdout: StdioCollector {
            id: layersCollector
            onStreamFinished: {
                root.layers = JSON.parse(layersCollector.text);
            }
        }
    }

    Process {
        id: getWorkspaces
        command: ["hyprctl", "workspaces", "-j"]
        stdout: StdioCollector {
            id: workspacesCollector
            onStreamFinished: {
                var rawWorkspaces = JSON.parse(workspacesCollector.text);
                root.workspaces = rawWorkspaces.filter(ws => ws.id >= 1 && ws.id <= 100);
                let tempWorkspaceById = {};
                for (var i = 0; i < root.workspaces.length; ++i) {
                    var ws = root.workspaces[i];
                    tempWorkspaceById[ws.id] = ws;
                }
                root.workspaceById = tempWorkspaceById;
                root.workspaceIds = root.workspaces.map(ws => ws.id);
            }
        }
    }

    Process {
        id: getActiveWorkspace
        command: ["hyprctl", "activeworkspace", "-j"]
        stdout: StdioCollector {
            id: activeWorkspaceCollector
            onStreamFinished: {
                root.activeWorkspace = JSON.parse(activeWorkspaceCollector.text);
            }
        }
    }
}