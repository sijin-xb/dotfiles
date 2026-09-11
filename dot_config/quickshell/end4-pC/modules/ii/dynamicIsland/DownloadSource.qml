import QtQuick

// 下载任务源：curl / wget / aria2c 在跑时显示在右侧副岛。
//
// 大文件下载想让进度准确，在脚本里上报即可：
//   qs -c end4-pC ipc call island task_begin download "下载 foo.iso"
//   qs -c end4-pC ipc call island task_progress download 42
//   qs -c end4-pC ipc call island task_end download
//
// curl 可以这样喂进度：
//   curl -L --progress-bar -o foo.iso URL 2>&1 \
//     | tr '\r' '\n' | while read -r l; do
//         p=$(echo "$l" | grep -oP '\d+(?=%)' | head -1)
//         [ -n "$p" ] && qs -c end4-pC ipc call island task_progress download "$p"
//       done
TaskSource {
    taskId: "download"
    processNames: ["curl", "wget", "aria2c"]
    priority: 7
    defaultLabel: "下载"
    icon: "download"
}
