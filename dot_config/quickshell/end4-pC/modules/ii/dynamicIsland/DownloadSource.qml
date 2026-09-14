import QtQuick

// 下载任务源。
//
// 进度上报方式（按精度排序）：
//  1. fish 包装函数自动上报：终端里跑 curl / wget 时，
//     ~/.config/fish/functions/ 下的包装函数解析输出百分比，
//     自动调用 task_begin / task_progress / task_end，进度条精确。
//  2. 手动 IPC 上报：
//     qs -c end4-pC ipc call island task_begin download "下载 foo.iso"
//     qs -c end4-pC ipc call island task_progress download 42
//     qs -c end4-pC ipc call island task_end download
//
// 注意：不自动探测 curl / wget 进程。壁纸切换、AI 请求等后台脚本
// 也会跑 curl，自动探测会让下载胶囊乱闪，噪音大于价值；
// 交互式下载已由包装函数覆盖。aria2c 几乎只在真实下载时出现，保留探测。
TaskSource {
    taskId: "download"
    processNames: ["aria2c"]
    priority: 7
    defaultLabel: "下载"
    icon: "download"
}
