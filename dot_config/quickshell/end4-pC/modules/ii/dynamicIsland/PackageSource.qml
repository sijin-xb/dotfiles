import QtQuick

// 包管理任务源：pacman / yay / paru / makepkg 的下载与 AUR 构建。
//
// 自动探测：进程在跑就显示（不确定态动画）。
// 主动上报：
//   qs -c end4-pC ipc call island task_begin package "安装 foo"
//   qs -c end4-pC ipc call island task_progress package 45
//   qs -c end4-pC ipc call island task_end package
// （task_* 的旧别名 pkg_* 仍然可用）
TaskSource {
    taskId: "package"
    processNames: ["pacman", "yay", "paru", "pikaur", "makepkg"]
    priority: 8
    defaultLabel: "软件包"
    icon: "download"
}
