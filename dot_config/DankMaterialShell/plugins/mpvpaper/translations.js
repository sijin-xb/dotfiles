/**
 * MpvPaper Plugin Translations
 * This file is dynamically injected into the global I18n singleton at runtime.
 */

const translations = {
    "zh_CN": {
        "mpvpaper": {
            "MpvPaper Plugin": "MpvPaper 插件",
            "General": "基本设置",
            "Language": "语言",
            "Simplified Chinese": "简体中文",
            "English": "English",
            "Monitor": "当前控制显示器",
            "No Monitors": "未检测到显示器",
            "Same on all monitors": "所有显示器使用相同壁纸",
            "All": "全部",
            "All Monitors": "所有显示器",
            "Video List (%1 videos)": "视频库 (共 %1 个视频)",
            "Video List (Empty)": "视频库 (暂无视频)",
            "Add Video": "添加视频",
            "Add Folder": "添加文件夹",
            "Clear List": "清空视频库",
            "Video Settings": "画面设置",
            "Hardware Decoding": "GPU 硬件加速",
            "Tiling Mode": "画面填充方式",
            "Fill Screen (Crop)": "全屏填充 (裁剪)",
            "Fit Screen (Letterbox)": "比例优先 (留黑边)",
            "Stretch Fill": "拉伸填充 (铺满)",
            "Volume": "播放音量",
            "Playback & Power": "播放与省电",
            "Lock Screen Behavior": "锁屏行为",
            "Close Player": "关闭播放器",
            "Pause Playback": "暂停播放",
            "Pause on Fullscreen": "全屏时暂停播放",
            "Scheduled Restart Interval": "自动重载间隔",
            "Disabled": "已禁用",
            "10 Minutes": "10 分钟",
            "30 Minutes": "30 分钟",
            "1 Hour": "1 小时",
            "2 Hours": "2 小时",
            "Periodically restart mpv process to prevent potential memory leaks": "定时重启 mpvpaper，避免长时间运行后内存占用持续增长。",
            "Advanced MPV Settings": "高级 MPV 设置",
            "Disable user MPV scripts": "禁止加载用户 MPV 脚本",
            "Prevent mpv-mpris, uosc, and other local MPV scripts from loading in wallpaper processes. Recommended.": "阻止 mpv-mpris、uosc 等用户 MPV 脚本在壁纸进程中加载。",
            "Custom MPV Options": "自定义 MPV 参数",
            "These options are appended after the plugin-generated MPV options.": "追加到插件生成的 MPV 参数之后。",
            "Select Video Files": "选择视频文件",
            "Video Files": "视频文件",
            "All Files": "所有文件",
            "Video Added": "视频已添加",
            "Successfully added %1 videos": "成功添加了 %1 个视频",
            "Select Video Folder": "选择视频文件夹",
            "Folder Added": "文件夹已添加",
            "Added %1 videos from directory": "从目录中导入了 %1 个视频",
            "No Videos Found": "未找到视频",
            "No supported video files found in selected folder": "所选文件夹中没有支持的视频格式",
            "Video Wallpaper": "视频壁纸",
            "%1 wallpapers": "%1 个壁纸",
            "MpvPaper Error": "播放器异常",
            "Video playback failed on %1": "显示器 %1 上的视频播放失败"
        }
    }
}

function tr(language, term) {
    if (language !== "zh_CN") return term;
    const table = translations.zh_CN.mpvpaper;
    return table[term] || term;
}
