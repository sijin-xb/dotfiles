# ============================================================
# 帮助打印（原 §5）
# ============================================================
# ============================================================
# 5. 帮助打印（CLI 层）
# ============================================================
print_help() {
    cat <<EOF
sijin-xb's dotfiles 自部署脚本 —— Rice 版本: ${RICE_VERSION}

核心特性：桌面歌词逐字卡拉OK ·
         拼音搜索启动器 · SUPER+T 终端召唤 · matugen Material 3 全局取色

用法：
  $0                    进入 TUI 二级菜单（推荐新手）
  $0 --tui              同上
  $0 install            一键安装（7 步）
                          默认不滚动系统；FULL_UPGRADE=1 $0 install 则执行 pacman -Syu
  $0 update             增量升级（见下）
  $0 rollback / restore / archive / uninstall   见下
  $0 status             当前部署状态一览：会话 / 清单 / 版本 / 快照 / 占用（只读）
  $0 doctor             环境体检：缺哪些包、配置在不在、QML 模块齐不齐（只读）
  $0 deps [--missing]   列出当前会话需要的依赖包；--missing 只看缺口（只读）
  $0 theme              图标 / 光标 / GTK 主题在 9 个 sink 里的取值与一致性（只读）
  $0 clean [--all]      清理临时残留；--all 连自举缓存、旧快照、旧备份一起清

单文件运行（自举）：
  只把 install.sh 这一个文件捞下来也能跑 —— 它会自己 clone 仓库到
  ~/.local/share/dotfiles-src，然后用仓库里那份（更新的）脚本重跑自己：

    curl -fsSL https://raw.githubusercontent.com/sijin-xb/dotfiles/main/install.sh \
        | bash -s -- update

  · 想换仓库地址：DOTFILES_REPO_URL=... 或改仓库缓存位置 DOTFILES_SRC_DIR=...
  · 想彻底重置自举缓存：rm -rf ~/.local/share/dotfiles-src
  · 在仓库里正常执行时这一步是 0 开销（只做一次文件存在性判断）。

环境变量：
  SESSION=end4pc|caelestia|dms
                             选择要安装的会话（合成器 + 桌面 Shell），三选一：
                             · end4pc   → Hyprland + quickshell（end4-PC 底盘）
                                          默认；配置入口 ~/.config/hypr/hyprland.lua
                                          + ~/.config/quickshell/end4-pC
                             · caelestia → Hyprland + caelestia shell
                                          shell clone 到 ~/.config/quickshell/caelestia
                             ⚠ end4pc 与 caelestia 都会把 Caelestia QML 插件
                             编译到 ~/src/caelestia-build（end4-PC 的锁屏硬依赖
                             import Caelestia.Config），dms 不需要。
                             · dms      → niri + DankMaterialShell（DMS）
                                          配置入口 ~/.config/niri/config.kdl
                             设定后跳过交互提问，适合脚本/无人值守重装。
                             例：SESSION=caelestia ./install.sh install
                             未设置时会在 [1/7] 步交互询问。
                             ⚠ 只部署**选中的那套**：合成器与 shell 的另一套
                             都不碰，避免覆盖机器上已有的配置。
  COMPOSITOR=niri|hyprland   [兼容旧写法] 等价于 SESSION=dms / SESSION=end4pc。
  INSTALL_BOTH_COMPOSITORS=1 两套合成器配置都部署（默认只部署选中的那套）。
                              机器上同时用 Hyprland 和 niri 时用它。
  FONTS=0|1                   是否安装推荐字体（pacman 字体包 + AUR 字体链 +
                              霞鹜臻楷 GB 下载 + 移除 65-wqy-zenhei.conf）。
                              · 不设置：执行到时交互询问 [Y/n]
                              · FONTS=0：一个字体包都不碰，适合已有字体方案的机器
                              · FONTS=1：跳过询问直接装（等价旧行为）
                              · 非交互执行（管道 / 重定向）时无法询问，兜底为 1
                              TUI 的「执行安装」页按 f 可随时切换。
  FULL_UPGRADE=1             安装时执行 pacman -Syu 全系统升级（默认只装缺失项）
  $0 update [选项]       升级：只做**文件层**的增量同步，不重装包、不重拉底盘
                          默认在仓库里跑（先 git pull 再 update 即可拿到新版配置）
                          --dry-run         只打印会改什么，一个字节都不写
                          --pull            先 git pull 拉最新提交再同步
                          --with-packages   顺便补齐新增的依赖包（只补不卸）
                          --no-prune        不做「仓库已删除文件」的清理
                          --force           版本号没变也照跑
                          --yes, -y         不交互确认
                          依赖部署清单区分「新增 / 更新 / 删除」：
                            ~/.local/state/dotfiles-backup/state/deployed-<shell>-<comp>.tsv
                          删除项一律**移到备份**（$BACKUP_ROOT/update-<时间戳>/removed/），
                          不 rm；升级前自动快照，出问题 $0 rollback 一条命令还原。
  $0 rollback           回档：还原到最近一次 install 之前的状态
                           （执行前会自动保存 pre-rollback 快照供 restore 用）
  $0 restore            恢复：回档后，还原回 rollback 之前的 rice 状态
  $0 archive [-o TAR.GZ] [--delete]
                        打包存档 rice 所有配置/数据/状态文件到 ~/dotfiles-archive-<时间戳>.tar.gz
                          -o PATH     自定义输出路径
                          --delete     打包成功后清理源文件（可用于彻底卸载前备份）
  $0 uninstall          卸载 rice（询问是否先存档 → 删除源路径）
  $0 -h, --help         显示本帮助

环境要求：
  · Arch Linux 系（/etc/arch-release 必须存在）
  · Wayland 会话；安装目标为 Hyprland 或 niri + 对应桌面 Shell
    （Hyprland + quickshell end4-PC / Hyprland + caelestia / niri + DMS）
  · 普通用户执行（不要 root），需有 sudo 权限用于 pacman

目录说明：
  · ~/.config/hypr/hyprland.lua     Hyprland 配置入口
  ·     custom/general.lua          用户差异层（blur / 阴影等高级参数放这里）
  ·     hyprland/shellOverrides/    quickshell 设置面板写入的值（优先级最高）
  · ~/.config/quickshell/end4-pC/   quickshell 底盘 + 本仓库的差异层（end4pc）
  · ~/.config/quickshell/caelestia/ caelestia shell 本体（caelestia）
  · ~/.config/niri/config.kdl       niri 配置入口（dms）
  · ~/.local/state/dotfiles-backup/  回档 / 卸载存档 / 备份目录

FAQ：
  1) 回档后想回到 rice？ → 运行 $0 restore
  2) 存档默认位置？       → ~/dotfiles-archive-YYYYMMDD-HHMMSS.tar.gz
  3) 面板模糊太浓？       → quickshell 设置 → Hyprland：模糊半径 10→8，活动不透明度 82→88

EOF
}

