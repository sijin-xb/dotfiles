-- ============================================================
-- Hyprland 配置入口文件 (hyprland.lua)
-- ------------------------------------------------------------
-- 这是整个配置的总入口，Hyprland 启动时会加载这一个文件，
-- 它再通过 require(...) 依次引入 `hyprland/` 和 `custom/` 目录
-- 下的各个模块，最终拼成完整配置。
--
-- 使用原则（重要）：
--   `hyprland/` 目录 = 默认/模板配置，不建议直接改动
--     （方便以后同步上游模板更新，不容易和你自己的改动冲突）
--   `custom/`    目录 = 你自己的个性化配置，写在这里
--     只要 custom/ 下存在对应文件名（execs.lua / general.lua /
--     rules.lua / keybinds.lua / env.lua），就会在对应的默认
--     模块**之后**被加载 —— 后加载的规则会覆盖/追加同名配置，
--     所以想覆盖默认行为，直接在 custom/ 里写同名规则即可，
--     不需要动 hyprland/ 里的原文件。
--
-- 加载顺序（从上到下）：
--   1. 内部库/服务
--   2. 环境变量（默认 env → 自定义 env，如果存在）
--   3. 默认配置（execs → general → rules → colors → keybinds）
--   4. 自定义配置（execs → general → rules → keybinds，各自
--      仅在 custom/ 下存在对应文件时才加载）
--   5. nwg-displays 多显示器布局支持（workspaces.lua / monitors.lua）
--   6. Shell overrides（放在最后，用于覆盖 shell 相关的默认行为）
-- ============================================================

-- 本文件负责把 `hyprland` 和 `custom` 两个文件夹里的配置串起来
-- 想加自己的个性化配置，去 `custom` 文件夹里写，不要改这里

-- ---- 内部逻辑（库函数 / 后台服务），一般不需要动 ----
require("hyprland.lib")
require("hyprland.services")

-- ---- 环境变量 ----
require("hyprland.env")                          -- 默认环境变量
if is_file_exists(HOME .. "/.config/hypr/custom/env.lua") then
    require("custom.env")                        -- 如果你写了自定义环境变量，加载它（会覆盖/追加默认值）
    end

    -- ---- 默认配置（模板自带，不建议直接改）----
    require("hyprland.execs")                        -- 开机自启动的程序
    require("hyprland.general")                      -- 通用设置：圆角、边框、间距、模糊(blur)参数等
    require("hyprland.rules")                        -- 窗口规则 / 图层规则（悬浮、模糊、动画等）
    require("hyprland.colors")                       -- 配色方案
    require("hyprland.keybinds")                     -- 默认快捷键

    -- ---- 自定义配置（你自己的个性化设置，写在 custom/ 下对应文件即可）----
    -- 每一块都先判断文件是否存在，不存在就跳过，避免报错
    if is_file_exists(HOME .. "/.config/hypr/custom/execs.lua") then
        require("custom.execs")                      -- 自定义自启动程序
        end
        if is_file_exists(HOME .. "/.config/hypr/custom/general.lua") then
            require("custom.general")                    -- 自定义通用设置（如覆盖 blur 的 size/passes）
            end
            if is_file_exists(HOME .. "/.config/hypr/custom/rules.lua") then
                require("custom.rules")                      -- 自定义窗口/图层规则（如覆盖 no_blur 全局开关）
                end
                if is_file_exists(HOME .. "/.config/hypr/custom/keybinds.lua") then
                    require("custom.keybinds")                   -- 自定义快捷键
                    end

                    -- ---- nwg-displays 多显示器布局支持 ----
                    -- 如果用 nwg-displays 生成过显示器/工作区布局文件，这里会自动加载
                    if is_file_exists(HOME .. "/.config/hypr/workspaces.lua") then
                        require("workspaces")                        -- 工作区与显示器的绑定关系
                        end
                        if is_file_exists(HOME .. "/.config/hypr/monitors.lua") then
                            require("monitors")                          -- 显示器分辨率/位置/缩放等
                            end

                            -- ---- Shell 覆盖项 ----
                            -- 放在最后加载，用于覆盖桌面 shell（如 Quickshell/Caelestia）相关的默认行为
                            require("hyprland.shellOverrides.main")
